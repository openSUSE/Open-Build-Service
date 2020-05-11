# Filters added to this controller will be run for all controllers in the application.
# Likewise, all the methods added will be available for all controllers.

require_dependency 'authenticator'

class Webui::WebuiController < ActionController::Base
  layout 'webui/webui'

  helper_method :valid_xml_id

  Rails.cache.set_domain if Rails.cache.respond_to?('set_domain')

  include Pundit
  include FlipperFeature
  protect_from_forgery

  before_action :set_influxdb_data
  before_action :setup_view_path
  before_action :check_user
  before_action :check_anonymous
  before_action :set_influxdb_additional_tags
  before_action :require_configuration
  before_action :set_pending_announcement
  after_action :clean_cache

  # :notice and :alert are default, we add :success and :error
  add_flash_types :success, :error

  rescue_from Pundit::NotAuthorizedError do |exception|
    pundit_action = case exception.try(:query).to_s
                    when 'index?' then 'list'
                    when 'show?' then 'view'
                    when 'create?' then 'create'
                    when 'new?' then 'create'
                    when 'update?' then 'update'
                    when 'edit?' then 'edit'
                    when 'destroy?' then 'delete'
                    when 'branch?' then 'branch'
                    else exception.try(:query)
    end
    if pundit_action && exception.record
      message = "Sorry, you are not authorized to #{pundit_action} this #{exception.record.class}."
    else
      message = 'Sorry, you are not authorized to perform this action.'
    end
    if request.xhr?
      render json: { error: message }, status: 400
    else
      flash[:error] = message
      redirect_back(fallback_location: root_path)
    end
  end

  rescue_from Backend::Error, Timeout::Error do |exception|
    Airbrake.notify(exception)
    message = if exception.is_a?(Backend::Error)
                'There has been an internal error. Please try again.'
              elsif exception.is_a?(Timeout::Error)
                'The request timed out. Please try again.'
              end

    if request.xhr?
      render json: { error: message }, status: 400
    else
      flash[:error] = message
      redirect_back(fallback_location: root_path)
    end
  end

  # FIXME: This is more than stupid. Why do we tell the user that something isn't found
  # just because there is some data missing to compute the request? Someone needs to read
  # http://guides.rubyonrails.org/active_record_validations.html
  class MissingParameterError < RuntimeError; end
  rescue_from MissingParameterError do |exception|
    logger.debug "#{exception.class.name} #{exception.message} #{exception.backtrace.join('\n')}"
    render file: Rails.root.join('public/404'), status: 404, layout: false, formats: [:html]
  end

  def valid_xml_id(rawid)
    rawid = "_#{rawid}" if rawid !~ /^[A-Za-z_]/ # xs:ID elements have to start with character or '_'
    CGI.escapeHTML(rawid.gsub(/[+&: .\/\~\(\)@#]/, '_'))
  end

  def home
    if params[:login].present?
      redirect_to user_path(params[:login])
    else
      redirect_to user_path(User.possibly_nobody)
    end
  end

  protected

  # We execute both strategies here. The default rails strategy (resetting the session)
  # and throwing an exception if the session is handled elswhere (e.g. proxy_auth_mode: :on)
  def handle_unverified_request
    super
    raise ActionController::InvalidAuthenticityToken
  end

  def set_project
    # We've started to use project_name for new routes...
    @project = ::Project.find_by(name: params[:project_name] || params[:project])
    raise ActiveRecord::RecordNotFound unless @project
  end

  def require_login
    if CONFIG['kerberos_mode']
      kerberos_auth
    else
      unless User.session
        render(text: 'Please login') && (return false) if request.xhr?

        flash[:error] = 'Please login to access the requested page.'
        mode = CONFIG['proxy_auth_mode'] || :off
        if mode == :off
          redirect_to new_session_path
        else
          redirect_to root_path
        end
        return false
      end
      true
    end
  end

  def required_parameters(*parameters)
    parameters.each do |parameter|
      unless params.include?(parameter.to_s)
        raise MissingParameterError, "Required Parameter #{parameter} missing"
      end
    end
  end

  def lockout_spiders
    @spider_bot = request.bot?
    if @spider_bot
      head :ok
      return true
    end
    false
  end

  def kerberos_auth
    return true unless CONFIG['kerberos_mode'] && !User.session

    authorization = authenticator.authorization_infos || []
    if authorization[0].to_s != 'Negotiate'
      # Demand kerberos negotiation
      response.headers['WWW-Authenticate'] = 'Negotiate'
      render :new, status: 401
      return
    else
      begin
        authenticator.extract_user
      rescue Authenticator::AuthenticationRequiredError => e
        logger.info "Authentication via kerberos failed '#{e.message}'"
        flash[:error] = "Authentication failed: '#{e.message}'"
        redirect_back(fallback_location: root_path)
        return
      end
      if User.session
        logger.info "User '#{User.session!}' has logged in via kerberos"
        session[:login] = User.session!.login
        redirect_back(fallback_location: root_path)
        return true
      end
    end
  end

  def check_user
    @spider_bot = request.bot?
    previous_user = User.possibly_nobody.login
    User.session = nil # reset old users hanging around

    user_checker = WebuiControllerService::UserChecker.new(http_request: request, config: CONFIG)

    if user_checker.proxy_enabled?
      if user_checker.user_login.blank?
        User.session = User.find_nobody!
        return
      end

      User.session = user_checker.find_or_create_user!

      if User.session!.is_active?
        User.session!.update_login_values(request.env)
      else
        User.session!.count_login_failure
        session[:login] = nil
        User.session = User.find_nobody!
        send_login_information_rabbitmq(:disabled) if previous_user != User.possibly_nobody.login
        redirect_to(CONFIG['proxy_auth_logout_page'], error: 'Your account is disabled. Please contact the administrator for details.')
        return
      end
    end

    User.session = User.find_by_login(session[:login]) if session[:login]

    User.session ||= User.possibly_nobody

    if !User.session
      send_login_information_rabbitmq(:unauthenticated)
    elsif previous_user != User.possibly_nobody.login
      send_login_information_rabbitmq(:success)
    end
  end

  def check_displayed_user
    param_login = params[:login] || params[:user_login]
    if param_login.present?
      begin
        @displayed_user = User.find_by_login!(param_login)
      rescue NotFoundError
        # admins can see deleted users
        @displayed_user = User.find_by_login(param_login) if User.admin_session?
        redirect_back(fallback_location: root_path, error: "User not found #{param_login}") unless @displayed_user
      end
    else
      @displayed_user = User.possibly_nobody
    end
    @is_displayed_user = (User.session == @displayed_user)
  end

  # Don't show performance of database queries to users
  def peek_enabled?
    return false if CONFIG['peek_enabled'] != 'true'
    User.admin_session? || User.possibly_nobody.is_staff?
  end

  def require_package
    required_parameters :package
    params[:rev], params[:package] = params[:pkgrev].split('-', 2) if params[:pkgrev]
    @project ||= params[:project]

    return if params[:package].blank?

    begin
      @package = Package.get_by_project_and_name(@project.to_param, params[:package],
                                                 follow_project_links: true, follow_multibuild: true)
    rescue APIError => e
      if [Package::Errors::ReadSourceAccessError, Authenticator::AnonymousUser].include?(e.class)
        flash[:error] = "You don't have access to the sources of this package: \"#{params[:package]}\""
        redirect_back(fallback_location: project_show_path(@project))
        return
      end

      raise(ActiveRecord::RecordNotFound, 'Not Found') unless request.xhr?
      render nothing: true, status: :not_found
    end
  end

  private

  def send_login_information_rabbitmq(msg)
    message = case msg
              when :success
                'login,access_point=webui value=1'
              when :disabled
                'login,access_point=webui,failure=disabled value=1'
              when :logout
                'logout,access_point=webui value=1'
              when :unauthenticated
                'login,access_point=webui,failure=unauthenticated value=1'
    end
    RabbitmqBus.send_to_bus('metrics', message)
  end

  def authenticator
    @authenticator ||= Authenticator.new(request, session, response)
  end

  def require_configuration
    @configuration = ::Configuration.first
  end

  # Before filter to check if current user is administrator
  def require_admin
    return if User.admin_session?
    flash[:error] = 'Requires admin privileges'
    redirect_back(fallback_location: { controller: 'main', action: 'index' })
  end

  # before filter to only show the frontpage to anonymous users
  def check_anonymous
    if !User.session
      unless ::Configuration.anonymous
        flash[:error] = 'No anonymous access. Please log in!'
        redirect_back(fallback_location: root_path)
      end
    else
      false
    end
  end

  # After filter to clean up caches
  def clean_cache; end

  def setup_view_path
    return unless CONFIG['theme']

    theme_path = Rails.root.join('app', 'views', 'webui', 'theme', CONFIG['theme'])
    prepend_view_path(theme_path)
  end

  def check_ajax
    raise ActionController::RoutingError, 'Expected AJAX call' unless request.xhr?
  end

  def pundit_user
    User.possibly_nobody
  end

  def set_pending_announcement
    return if Announcement.last.in?(User.possibly_nobody.announcements)
    @pending_announcement = Announcement.last
  end

  def add_arrays(arr1, arr2)
    # we assert that both have the same size
    ret = []
    if arr1
      arr1.length.times do |i|
        time1, value1 = arr1[i]
        time2, value2 = arr2[i]
        value2 ||= 0
        value1 ||= 0
        time1 ||= 0
        time2 ||= 0
        ret << [(time1 + time2) / 2, value1 + value2]
      end
    end
    ret << 0 if ret.length.zero?
    ret
  end

  def set_influxdb_data
    InfluxDB::Rails.current.tags = {
      interface: :webui
    }
  end

  def set_influxdb_additional_tags
    tags = {
      beta: User.possibly_nobody.in_beta?,
      anonymous: !User.session
    }

    InfluxDB::Rails.current.tags = InfluxDB::Rails.current.tags.merge(tags)
  end
end
