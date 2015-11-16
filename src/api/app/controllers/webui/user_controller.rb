require 'base64'
require 'event'

class Webui::UserController < Webui::WebuiController

  include Webui::WebuiHelper
  include Webui::NotificationSettings

  before_filter :check_display_user, :only => [:show, :edit, :requests, :list_my, :delete, :save, :confirm, :admin, :lock]
  before_filter :require_login, :only => [:edit, :save, :notifications, :update_notifications, :index]
  before_filter :require_admin, :only => [:edit, :delete, :lock, :confirm, :admin, :index]

  skip_before_action :check_anonymous, only: [:do_login]

  def index
    @users = User.all_without_nobody
  end

  def logout
    logger.info "Logging out: #{session[:login]}"
    reset_session
    User.current = nil
    if CONFIG['proxy_auth_mode'] == :on
      redirect_to CONFIG['proxy_auth_logout_page']
    else
      redirect_to root_path
    end
  end

  def login
  end

  def do_login
    mode = CONFIG['proxy_auth_mode'] || CONFIG['ichain_mode'] || :basic
    logger.debug "do_login: with #{mode}"

    case mode
    when :on
      user = User.find_by(login: request.env['HTTP_X_USERNAME'])
    when :basic, :off
      user = User.find_with_credentials(params[:username], params[:password])
    end

    if user.nil? || (user.state == User::STATES['ichainrequest'] || user.state == User::STATES['unconfirmed'])
      redirect_to(user_login_path, error: 'Authentication failed')
      return
    end

    logger.debug "USER found: #{user.login}"
    User.current = user

    session[:login] = User.current.login
    session[:password] = params[:password]

    redirect_back_or_to root_path
  end

  def show
    @iprojects = @displayed_user.involved_projects.pluck(:name, :title)
    @ipackages = @displayed_user.involved_packages.joins(:project).pluck(:name, 'projects.name as pname')
    @owned = @displayed_user.owned_packages

    if User.current == @displayed_user
        @reviews = @displayed_user.involved_reviews
        @patchinfos = @displayed_user.involved_patchinfos
        @requests_in = @displayed_user.incoming_requests
        @requests_out = @displayed_user.outgouing_requests
        @declined_requests = @displayed_user.declined_requests
        @user_have_requests = @displayed_user.requests?
    end
  end

  def home
    if params[:user].present?
      redirect_to :action => :show, user: params[:user]
    else
      redirect_to :action => :show, user: User.current
    end
  end

  # Request from the user
  def requests
    sortable_fields = {
        0 => :created_at,
        3 => :creator,
        5 => :priority
      }
    sorting_field = sortable_fields[params[:iSortCol_0].to_i]
    sorting_field ||= :created_at
    sorting_dir = params[:sSortDir_0].try(:to_sym)
    sorting_dir = :asc unless ["asc", "desc"].include?(params[:sSortDir_0])
    @requests = @displayed_user.requests(params[:sSearch])
    @requests_count = @requests.count
    @requests = @requests.offset(params[:iDisplayStart].to_i).limit(params[:iDisplayLength].to_i).reorder(sorting_field => sorting_dir)
    respond_to do |format|
      # For jquery dataTable
      format.json {
        render_json_response_for_dataTable(
          echo_next_count: params[:sEcho].to_i + 1,
          total_records_count: @displayed_user.requests.count,
          total_filtered_records_count: @requests_count,
          records: @requests
        ) do |request|
          render_to_string(:partial => "shared/single_request.json", locals: { req: request, no_target: true, hide_state: true }).to_s.split(',')
        end
      }
    end
  end

  def save
    unless User.current.is_admin?
      if User.current != @displayed_user
        flash[:error] = "Can't edit #{@displayed_user.login}"
        redirect_to(:back) and return
      end
    end
    @displayed_user.realname = params[:realname]
    @displayed_user.email = params[:email]
    if User.current.is_admin?
      @displayed_user.state = User::STATES[params[:state]] if params[:state]
      @displayed_user.update_globalroles([params[:globalrole]]) if params[:globalrole]
    end
    @displayed_user.save!

    flash[:success] = "User data for user '#{@displayed_user.login}' successfully updated."
    redirect_back_or_to :action => 'show', user: @displayed_user
  end

  def edit
    @roles = Role.global_roles
    @states = %w(confirmed unconfirmed deleted locked)
  end

  def delete
    @displayed_user.state = User::STATES['deleted']
    @displayed_user.save
    redirect_back_or_to :action => 'show', user: @displayed_user
  end

  def confirm
    @displayed_user.state = User::STATES['confirmed']
    @displayed_user.save
    redirect_back_or_to :action => 'show', user: @displayed_user
  end

  def lock
    @displayed_user.state = User::STATES['locked']
    @displayed_user.save
    redirect_back_or_to :action => 'show', user: @displayed_user
  end

  def admin
    @displayed_user.update_globalroles(%w(Admin))
    @displayed_user.save
    redirect_back_or_to :action => 'show', user: @displayed_user
  end

  def save_dialog
    @roles = Role.global_roles
    render_dialog
  end

  def user_icon
    required_parameters :icon
    params[:user] = params[:icon].gsub(/.png$/, '')
    icon
  end

  def icon
    required_parameters :user
    size = params[:size].to_i || '20'
    user = User.find_by_login(params[:user])
    if user.nil? or (content = user.gravatar_image(size)) == :none
      redirect_to ActionController::Base.helpers.asset_path('default_face.png')
      return
    end

    expires_in 5.hours, public: true
    if stale?(etag: Digest::MD5.hexdigest(content))
      render text: content, layout: false, content_type: 'image/png'
    end
  end

  def register
    opts = { login:    params[:login],
             email:    params[:email],
             realname: params[:realname],
             password: params[:password],
             state:    params[:state] }
    begin
      UnregisteredUser.register(opts)
    rescue APIException => e
      flash[:error] = e.message
      redirect_back_or_to :controller => 'main', :action => 'index' and return
    end

    flash[:success] = "The account '#{params[:login]}' is now active."

    if User.current.is_admin?
      redirect_to :controller => :user, :action => :index
    else
      session[:login] = opts[:login]
      User.current = User.find_by_login(session[:login])
      if Project.where(name: User.current.home_project_name).exists?
        redirect_to project_show_path(User.current.home_project_name)
      else
        redirect_to :controller => :main, :action => :index
      end
    end
  end

  def register_user
  end

  def password_dialog
    render_dialog
  end

  def change_password
    # check the valid of the params
    unless User.current.password_equals?(params[:password])
      errmsg = 'The value of current password does not match your current password. Please enter the password and try again.'
    end
    if not params[:new_password] == params[:repeat_password]
      errmsg = 'The passwords do not match, please try again.'
    end
    if params[:password] == params[:new_password]
      errmsg = 'The new password is the same as your current password. Please enter a new password.'
    end
    if errmsg
      flash[:error] = errmsg
      redirect_to :action => :show, user: User.current
      return
    end

    user = User.current
    user.update_password params[:new_password]
    user.save!

    flash[:success] = 'Your password has been changed successfully.'
    redirect_to :action => :show, user: User.current
  end

  def autocomplete
    required_parameters :term
    render json: list_users(params[:term])
  end

  def tokens
    required_parameters :q
    render json: list_users(params[:q], true)
  end

  def notifications
    @notifications = notifications_for_user(User.current)
  end

  def update_notifications
    User.current.groups_users.each do |gu|
      gu.email = params[gu.group.title] == '1'
      gu.save
    end

    update_notifications_for_user(params, User.current)

    flash[:notice] = 'Notifications settings updated'
    redirect_to action: :notifications
  end

  protected

  def list_users(prefix = nil, hash = nil)
    names = []
    users = User.arel_table
    User.where(users[:login].matches("#{prefix}%")).pluck(:login).each do |user|
      if hash
        names << { 'name' => user }
      else
        names << user
      end
    end
    names
  end
end
