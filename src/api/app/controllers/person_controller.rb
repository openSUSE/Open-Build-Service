require 'xmlhash'

class PersonController < ApplicationController
  validate_action userinfo: {method: :get, response: :user}
  validate_action userinfo: {method: :put, request: :user, response: :status}
  validate_action grouplist: {method: :get, response: :directory}
  validate_action register: {method: :put, response: :status}
  validate_action register: {method: :post, response: :status}

  skip_before_action :extract_user, only: [:command, :register]
  skip_before_action :require_login, only: [:command, :register]

  def show
    if params[:prefix]
      @list = User.where("login LIKE ?", params[:prefix] + '%')
    else
      @list = User.all
    end
  end

  def login
    render_ok # just a dummy check for the webui to call (for now)
  end

  # Returns a list of all users (that optionally start with a prefix)
  def command
    if params[:cmd] == "register"
      internal_register
      return
    end
    raise UnknownCommandError.new "Allowed commands are 'change_password'"
  end

  def get_userinfo
    user = User.find_by_login!(params[:login])

    if user.login != @http_user.login
      logger.debug "Generating for user from parameter #{user.login}"
      render xml: user.render_axml(@http_user.is_admin?)
    else
      logger.debug "Generating user info for logged in user #{@http_user.login}"
      render xml: @http_user.render_axml(true)
    end
  end

  def post_userinfo
    login = params[:login]
    # just for permission checking
    User.find_by_login!(login)

    if params[:cmd] == "change_password"
      login ||= @http_user.login
      password = request.raw_post.to_s.chomp
      if login != @http_user.login && !@http_user.is_admin?
        render_error status: 403, errorcode: "change_password_no_permission",
                     message: "No permission to change password for user #{login}"
        return
      end
      if password.blank?
        render_error status: 404, errorcode: "password_empty",
                     message: "No new password given in first line of the body"
        return
      end
      change_password(login, password)
      render_ok
      return
    end
    if params[:cmd] == "lock"
      return unless require_admin
      user = User.find_by_login!(params[:login])
      user.lock!
      render_ok
      return
    end
    if params[:cmd] == "delete"
      # maybe we should allow the users to delete themself?
      return unless require_admin
      user = User.find_by_login!(params[:login])
      user.delete!
      render_ok
      return
    end
    raise UnknownCommandError.new "Allowed commands are 'change_password', 'lock' or 'delete', got #{params[:cmd]}"
  end

  def put_userinfo
    login = params[:login]
    user = User.find_by_login(login) if login

    if user
      unless user.login == User.current.login || User.current.is_admin?
        logger.debug "User has no permission to change userinfo"
        render_error(status: 403, errorcode: 'change_userinfo_no_permission',
          message: "no permission to change userinfo for user #{user.login}") && return
      end
    elsif User.current.is_admin?
      user = User.create!(login: login, password: "notset", email: "TEMP")
      user.state = "locked"
    else
      logger.debug "Tried to create non-existing user without admin rights"
      @errorcode = 404
      @summary = "Requested non-existing user"
      render_error(status: @errorcode) && return
    end

    xml = Xmlhash.parse(request.raw_post)
    logger.debug("XML: #{request.raw_post}")
    user.email = xml.value('email') || ''
    user.realname = xml.value('realname') || ''
    if User.current.is_admin?
      # only admin is allowed to change these, ignore for others
      user.state = xml.value('state')
      update_globalroles(user, xml)

      if xml['owner']
        user.state = :subaccount
        user.owner = User.find_by_login! xml['owner']['userid']
        if user.owner.owner
          render_error(status: 400, errorcode: 'subaccount_chaining',
            message: "A subaccount can not be assigned to subaccount #{user.owner.login}") && return
        end
      end
    end
    update_watchlist(user, xml)
    user.save!
    render_ok
  end

  class NoPermissionToGroupList < APIException
    setup 401, "No user logged in, permission to grouplist denied"
  end

  def grouplist
    raise NoPermissionToGroupList.new unless User.current

    user = User.find_by_login! params[:login]
    @list = User.lookup_strategy.groups(user)
  end

  def register
    # FIXME 3.0, to be removed
    internal_register
  end

  class ErrRegisterSave < APIException
  end

  class NoPermission < APIException
  end

  def internal_register
    xml = REXML::Document.new( request.raw_post )

    logger.debug( "register XML: #{request.raw_post}" )

    login = xml.elements["/unregisteredperson/login"].text
    realname = xml.elements["/unregisteredperson/realname"].text
    email = xml.elements["/unregisteredperson/email"].text
    password = xml.elements["/unregisteredperson/password"].text
    note = xml.elements["/unregisteredperson/note"].text if xml.elements["/unregisteredperson/note"]
    status = xml.elements["/unregisteredperson/state"].text if xml.elements["/unregisteredperson/status"]

    if auth_method == :proxy
      if request.env['HTTP_X_USERNAME'].blank?
        raise ErrRegisterSave.new "Missing iChain header"
      end
      login = request.env['HTTP_X_USERNAME']
      email = request.env['HTTP_X_EMAIL'] unless request.env['HTTP_X_EMAIL'].blank?
      realname = request.env['HTTP_X_FIRSTNAME'] + " " + request.env['HTTP_X_LASTNAME'] unless request.env['HTTP_X_LASTNAME'].blank?
    end

    UnregisteredUser.register(login: login, realname: realname, email:
        email, password: password, note: note, status: status)

    # This may fail when no notification is configured. Not important, so no exception handling for now
    # IchainNotifier.deliver_approval(newuser)
    render_ok
  rescue Exception => e
    # Strip passwords from request environment and re-raise exception
    request.env["RAW_POST_DATA"] = request.env["RAW_POST_DATA"].sub(/<password>(.*)<\/password>/, "<password>STRIPPED<password>")
    raise e
  end

  def update_watchlist( user, xml )
    new_watchlist = []
    xml.get('watchlist').elements("project") do |e|
      new_watchlist << e['name']
    end

    new_watchlist.map! do |name|
      WatchedProject.find_or_create_by(project: Project.find_by_name!(name), user: user)
    end
    user.watched_projects.replace(new_watchlist)
    Rails.cache.delete(["watched_project_names", user])
  end
  private :update_watchlist

  def update_globalroles( user, xml )
    new_globalroles = []
    xml.elements("globalrole") do |e|
      new_globalroles << e.to_s
    end

    user.update_globalroles( new_globalroles )
  end

  private :update_globalroles

  def change_my_password
    # FIXME3.0: remove this function
    xml = REXML::Document.new( request.raw_post )

    logger.debug( "changepasswd XML: #{request.raw_post}" )

    login = xml.elements["/userchangepasswd/login"].text
    password = xml.elements["/userchangepasswd/password"].text
    login = URI.unescape(login)

    change_password(login, URI.unescape(password))
    render_ok
  end

  def change_password(login, password)
    unless User.current
      logger.debug "No user logged in, permission to changing password denied"
      @errorcode = 401
      @summary = "No user logged in, permission to changing password denied"
      render template: 'error', status: 401
    end

    if login.blank? || password.blank?
      render_error status: 404, errorcode: 'failed to change password',
            message: "Failed to change password: missing parameter"
      return
    end
    user = User.get_by_login(login)

    # change password to LDAP if LDAP is enabled
    if CONFIG['ldap_mode'] == :on
      ldap_password = Base64.decode64(password)
      if CONFIG['ldap_ssl'] == :on
        require 'base64'
        begin
          logger.debug( "Using LDAP to change password for #{login}" )
          result = UserLdapStrategy.change_password_ldap(login, ldap_password)
        rescue Exception
          logger.debug "CONFIG['ldap_mode'] selected but 'ruby-ldap' module not installed."
        end
        if result
          render_error status: 404, errorcode: 'change_passwd_failure', message: "Failed to change password to ldap: #{result}"
          return
        end
      else
        render_error status: 404, errorcode: 'change_passwd_no_security', message: "LDAP mode enabled, the user password can only" +
                                                                                            " be changed with CONFIG['ldap_ssl'] enabling."
        return
      end
    end

    # update password in users db
    user.update_password( password )
    user.save!
  end
  private :change_password

  # GET /person/<login>/token
  def tokenlist
    user = User.get_by_login(params[:login])
    @list = user.tokens
  end

  # POST /person/<login>/token
  def command_token
    user = User.get_by_login(params[:login])

    unless params[:cmd] == "create"
      raise UnknownCommandError.new "Allowed commands are 'create'"
    end
    pkg = nil
    if params[:project] || params[:package]
      pkg = Package.get_by_project_and_name( params[:project], params[:package] )
    end
    @token = Token.create( user: user, package: pkg )
  end

  class TokenNotFound < APIException
    setup 404
  end

  # DELETE /person/<login>/token/<id>
  def delete_token
    user = User.get_by_login(params[:login])

    token = Token.where( user_id: user.id, id: params[:id] ).first
    raise TokenNotFound.new "Specified token \"#{params[:id]}\" got not found" unless token
    token.destroy!
    render_ok
  end
end
