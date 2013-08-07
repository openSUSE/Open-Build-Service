include MaintenanceHelper
include ValidationHelper

require 'builder/xchar'

class SourceController < ApplicationController

  class IllegalRequestError < APIException
    setup 'illegal_request', 404, "Illegal request"
  end

  validate_action :index => {:method => :get, :response => :directory}
  validate_action :projectlist => {:method => :get, :response => :directory}
  validate_action :packagelist => {:method => :get, :response => :directory}
  validate_action :filelist => {:method => :get, :response => :directory}
  validate_action :project_meta => {:method => :get, :response => :project}
  validate_action :package_meta => {:method => :get, :response => :package}

  validate_action :project_meta => {:method => :put, :request => :project, :response => :status}
  validate_action :package_meta => {:method => :put, :request => :package, :response => :status}

  skip_before_filter :validate_xml_request, :only => [:file]
  skip_before_filter :extract_user, only: [:lastevents_public]

  # /source
  #########
  def index
    # init and validation
    #--------------------
    deleted = params.has_key? :deleted
    admin_user = @http_user.is_admin?

    # access checks
    #--------------

    # GET /source
    #------------
    if request.get?
      if deleted
        if admin_user
          pass_to_backend
          return
        else
          render_error :status => 403, :errorcode => 'no_permission_for_deleted',
                       :message => "only admins can see deleted projects"
          return
        end
      else
        projectlist
      end
    # /if request.get?

    # POST /source
    #-------------
    elsif request.post?
      dispatch_command

    end
  end

  def projectlist
    # list all projects (visible to user)
    dir = Project.pluck(:name).sort
    output = String.new
    output << "<?xml version='1.0' encoding='UTF-8'?>\n"
    output << "<directory>\n"
    output << dir.map { |item| "  <entry name=\"#{::Builder::XChar.encode(item)}\"/>\n" }.join
    output << "</directory>\n"
    render :text => output, :content_type => "text/xml"
  end

  # /source/:project
  #-----------------
  def index_project

    # init and validation
    #--------------------
    valid_commands=["undelete", "showlinked", "remove_flag", "set_flag", "createpatchinfo", "createkey", "extendkey", "copy", "createmaintenanceincident", "unlock", "release"]
    raise IllegalRequestError.new "invalid_project_name" unless valid_project_name?(params[:project])
    if params[:cmd]
      raise IllegalRequestError.new "invalid_command" unless valid_commands.include?(params[:cmd])
      command = params[:cmd]
    end
    project_name = params[:project]
    #admin_user = @http_user.is_admin?

    # GET /source/:project
    #---------------------
    if request.get?
      if params.has_key? :deleted
        unless Project.find_by_name project_name
          # project is deleted or not accessable
          validate_visibility_of_deleted_project(project_name)
        end
        pass_to_backend
      else
        if Project.is_remote_project?(project_name)
          # not a local project, hand over to backend
          pass_to_backend
	else
          pro = Project.find_by_name!(project_name)
          # we let the backend list the packages after we verified the project is visible
          if params.has_key? :view
            if params["view"] == "issues"
              render :text => pro.render_issues_axml(params), :content_type => 'text/xml'
              return
            end
            pass_to_backend
	  else
            packages=nil
            if params.has_key? :expand
              packages = pro.expand_all_packages
            else
              packages = pro.packages.pluck(:name, :db_project_id)
            end
            packages = packages.sort{|a,b| a[0]<=>b[0] }
            prj_names = Hash.new
            Project.where(id: packages.map {|a| a[1]}.uniq).pluck(:id, :name).each do |id, name|
              prj_names[id] = name
            end 
            output = String.new
            output << "<directory count='#{packages.length}'>\n"
            output << packages.map { |p| p[1]==pro.id ? "  <entry name=\"#{p[0]}\"/>\n" : "  <entry name=\"#{p[0]}\" originproject=\"#{prj_names[p[1]]}\"/>\n" }.join
            output << "</directory>\n"
            render :text => output, :content_type => "text/xml"
          end
        end
      end
      return
    # /request.get?

    # DELETE /source/:project
    #------------------------
    elsif request.delete?
      pro = Project.get_by_name project_name

      # checks
      unless @http_user.can_modify_project?(pro)
        logger.debug "No permission to delete project #{project_name}"
        render_error :status => 403, :errorcode => 'delete_project_no_permission',
          :message => "Permission denied (delete project #{project_name})"
        return
      end
      pro.can_be_deleted?

      # find linking repos
      private_check_and_remove_repositories(params, pro.repositories) or return

      # Find open requests with 'pro' as source or target and decline/revoke them.
      # Revoke if source or decline if target went away, pick the first action that matches to decide...
      # Note: As requests are a backend matter, it's pointless to include them into the transaction below
      pro.open_requests_with_project_as_source_or_target.each do |request|
        request.bs_request_actions.each do |action|
          if action.source_project == pro.name
            request.change_state('revoked', :comment => "The source project '#{pro.name}' was removed")
            break
          end
          if action.target_project == pro.name
            request.change_state('declined', :comment => "The target project '#{pro.name}' was removed")
            break
          end
        end
      end

      # Find open requests which have a review involving this project (or it's packages) and remove those reviews
      # but leave the requests otherwise untouched.
      pro.open_requests_with_by_project_review.each do |request|
        request.remove_reviews(:by_project => pro.name)
      end


      Project.transaction do
        logger.info "destroying project object #{pro.name}"
        pro.destroy

        params[:user] = @http_user.login
        path = "/source/#{pro.name}"
        path << build_query_from_hash(params, [:user, :comment])
        Suse::Backend.delete path
        logger.debug "delete request to backend: #{path}"
      end

      render_ok
      return
    # /if request.delete?

    # POST /source/:project
    #----------------------
    elsif request.post?
      params[:user] = @http_user.login

      # command: undelete
      if 'undelete' == command
        unless @http_user.can_create_project?(project_name) and pro.nil?
          render_error :status => 403, :errorcode => "cmd_execution_no_permission",
            :message => "no permission to execute command '#{command}'"
          return
        end
        dispatch_command
        return
      elsif 'release' == command
        pro = Project.get_by_name project_name, {:includeallpackages => 1}
        repo_matches=nil
        pro.repositories.each do |repo|
          next if params[:repository] and params[:repository] != repo.name
          repo.release_targets.each do |releasetarget|
            unless @http_user.can_modify_project?(releasetarget.target_repository.project)
              render_error :status => 403, :errorcode => "cmd_execution_no_permission",
                :message => "no permission to write in project #{releasetarget.target_repository.project.name}"
              return
            end
            unless releasetarget.trigger == "manual"
              render_error :status => 400, :errorcode => "cmd_execution_no_permission",
                :message => "Trigger is not set to manual in repository #{releasetarget.repository.project.name}/#{releasetarget.repository.name}"
              return
            end
            repo_matches=true
          end
        end
        unless repo_matches
          render_error :status => 404, :errorcode => "no_matching_release_target",
            :message => "No defined or matching release target"
          return
        end
        # any package read protected?
       
        dispatch_command
        return
      elsif 'copy' == command
        prj = Project.find_by_name(project_name)
        unless (prj and @http_user.can_modify_project?(prj)) or @http_user.can_create_project?(project_name)
          render_error :status => 403, :errorcode => "cmd_execution_no_permission",
            :message => "no permission to execute command '#{command}'"
          return
        end
        oproject = Project.get_by_name(params[:oproject], {:includeallpackages => 1})
        if params.has_key?(:makeolder)
          unless @http_user.can_modify_project?(oproject)
            render_error :status => 403, :errorcode => "cmd_execution_no_permission",
              :message => "no permission to execute command '#{command}', requires modification permission in oproject"
            return
          end
        end
        dispatch_command
        return
      end

      pro = Project.get_by_name project_name
      # unlock
      if command == "unlock" and @http_user.can_modify_project?(pro, true)
        dispatch_command
      elsif command == "showlinked" or @http_user.can_modify_project?(pro)
        # command: showlinked, set_flag, remove_flag, ...?
        dispatch_command
      else
        render_error :status => 403, :errorcode => "cmd_execution_no_permission",
          :message => "no permission to execute command '#{command}'"
        return
      end

    end
  end

  # FIXME: for OBS 3, api of branch and copy calls have target and source in the opossite place
  # /source/:project/:package
  #--------------------------
  def index_package
    # init and validation
    #--------------------
    #admin_user = @http_user.is_admin?
    deleted_package = params.has_key? :deleted
    # valid post commands
    valid_commands=['diff', 'branch', 'servicediff', 'linkdiff', 'showlinked', 'copy', 'remove_flag', 'set_flag', 
                    'rebuild', 'undelete', 'wipe', 'runservice', 'commit', 'commitfilelist', 
                    'createSpecFileTemplate', 'deleteuploadrev', 'linktobranch', 'updatepatchinfo',
                    'getprojectservices', 'unlock', 'release']
    # list of commands which are allowed even when the project has the package only via a project link
    read_commands = ['branch', 'diff', 'linkdiff', 'servicediff', 'showlinked', 'getprojectservices']
    source_untouched_commands = ['branch', 'diff', 'linkdiff', 'servicediff', 'showlinked', 'rebuild', 'wipe', 'remove_flag', 'set_flag', 'getprojectservices']
    # list of cammands which create the target package
    package_creating_commands = ['branch', 'copy', 'undelete']

    raise IllegalRequestError.new "invalid_project_name" unless valid_project_name?(params[:project])
    if params[:cmd]
      raise IllegalRequestError.new "invalid_command" unless valid_commands.include?(params[:cmd])
      raise IllegalRequestError.new "invalid_command_not_post" unless request.post?
      command = params[:cmd]
    elsif request.post?
      raise MissingParameterError.new "POST request without given cmd parameter"
    end
    # find out about source and target dependening on command   - FIXME: ugly! sync calls
    if command == 'release'
      origin_project_name = params[:project]
      origin_package_name = params[:package]
    elsif command == 'branch'
      origin_project_name = params[:project]
      target_package_name = origin_package_name = params[:package]
      target_project_name = params[:target_project] if params[:target_project]
      target_package_name = params[:target_package] if params[:target_package]
    else
      target_project_name = params[:project]
      target_package_name = params[:package]
      origin_project_name = params[:oproject] if params[:oproject]
      origin_package_name = params[:opackage] if params[:opackage]
    end
    #
    if origin_package_name and not origin_project_name
      render_error :status => 404, :errorcode => "missing_argument",
                   :message => "origin package name is specified, but no origin project"
      return
    end

    # Check for existens/access of origin package when specified
    spkg = nil
    Project.get_by_name origin_project_name if origin_project_name
    if origin_package_name && ![ '_project', '_pattern' ].include?(origin_package_name) && !(params[:missingok] && command == 'branch')
      spkg = Package.get_by_project_and_name(origin_project_name, origin_package_name) if origin_package_name && ![ '_project', '_pattern' ].include?(origin_package_name)
    end
    if spkg
      # use real source in case we followed project link
      params[:oproject] = origin_project_name = spkg.project.name
      params[:opackage] = origin_package_name = spkg.name
    end

    tprj = nil
    tpkg = nil
    # The target must exist, except for following cases
    if (request.post? and command == 'release')
      repo_matches=nil
      spkg.project.repositories.each do |repo|
        next if params[:repository] and params[:repository] != repo.name
        repo.release_targets.each do |releasetarget|
          unless @http_user.can_modify_project?(releasetarget.target_repository.project)
            render_error :status => 403, :errorcode => "cmd_execution_no_permission",
              :message => "no permission to write in project #{releasetarget.target_repository.project.name}"
            return
          end
          unless releasetarget.trigger == "manual"
            render_error :status => 400, :errorcode => "cmd_execution_no_permission",
              :message => "Trigger is not set to manual in repository #{releasetarget.repository.project.name}/#{releasetarget.repository.name}"
            return
          end
          repo_matches=true
        end
      end
      unless repo_matches
        render_error :status => 404, :errorcode => "no_matching_release_target",
          :message => "No defined or matching release target"
        return
      end
    elsif (request.post? and command == 'undelete') or (request.get? and deleted_package)
      tprj = Project.get_by_name(target_project_name)
      if Package.exists_by_project_and_name(target_project_name, target_package_name, follow_project_links: false)
        render_error :status => 404, :errorcode => "package_exists",
          :message => "the package exists already #{tprj.name} #{target_package_name}"
        return
      end
      if command == 'undelete' and request.post?
        tprj = Project.get_by_name(target_project_name)
        unless @http_user.can_create_package_in?(tprj)
          render_error :status => 403, :errorcode => "cmd_execution_no_permission",
            :message => "no permission to create package in project #{target_project_name}"
          return
        end
      end
    elsif request.post? and package_creating_commands.include?(command)  # branch/copy
      # The branch command may be used just for simulation
      unless params[:dryrun]
        # we require a target, but are we allowed to modify the existing target ?
        if Project.exists_by_name(target_project_name) and Package.exists_by_project_and_name(target_project_name, target_package_name, follow_project_links: false)
          tpkg = Package.get_by_project_and_name(target_project_name, target_package_name, use_source: false, follow_project_links: false)
          unless @http_user.can_modify_package?(tpkg)
            render_error :status => 403, :errorcode => "cmd_execution_no_permission",
              :message => "no permission to execute command '#{command}' for package #{tpkg.name} in project #{tpkg.project.name}"
            return
          end
        else
          # branch command may find out target project itself later and checks permission
          exists = Project.exists_by_name(target_project_name)
          if command == 'branch' and not exists and target_project_name and not @http_user.can_create_project?(target_project_name)
            render_error :status => 403, :errorcode => "cmd_execution_no_permission",
              :message => "no permission to create project #{target_project_name}"
            return
          end
          if exists 
            tprj = Project.get_by_name(target_project_name)
            unless @http_user.can_create_package_in?(tprj)
              render_error :status => 403, :errorcode => "cmd_execution_no_permission",
                :message => "no permission to create package in project #{target_project_name}"
              return
            end
          end
        end
      end
    else
      follow_project_links = false
      follow_project_links = true if request.get? or (source_untouched_commands.include? command)

      if [ '_project', '_pattern' ].include? target_package_name and not request.delete?
        tprj = Project.get_by_name target_project_name
      else
        use_source = true
        use_source = false if command == "showlinked"
        tpkg = Package.get_by_project_and_name(target_project_name, target_package_name, use_source: use_source, follow_project_links: follow_project_links)
        tprj = tpkg.project unless tpkg.nil? # for remote package case
        if request.delete? or (request.post? and not read_commands.include? command)
          # unlock
          if command == "unlock" 
            unless @http_user.can_modify_package?(tpkg, true)
              render_error :status => 403, :errorcode => "cmd_execution_no_permission",
                :message => "no permission to unlock package #{tpkg.name} in project #{tpkg.project.name}"
              return
            end
          elsif not @http_user.can_modify_package?(tpkg)
            if request.delete? or (request.post? and not read_commands.include? command)
              render_error :status => 403, :errorcode => "delete_package_no_permission",
                :message => "no permission to delete package #{tpkg.name} in project #{tpkg.project.name}"
              return
            end
            render_error :status => 403, :errorcode => "cmd_execution_no_permission",
              :message => "no permission to modify package #{tpkg.name} in project #{tpkg.project.name}"
            return
          end
        end
      end

    end

    # check read access rights when the package does not exist anymore
    if tpkg.nil? and deleted_package
      validate_read_access_of_deleted_package(target_project_name, target_package_name)
    end
    
    # GET /source/:project/:package
    #------------------------------
    if request.get?
      if params["view"] == "issues"
        unless tpkg
          render_error :status => 400, :errorcode => "no_local_package",
            :message => "Issues can only be shown for local packages"
          return
        end
        render :text => tpkg.render_issues_axml(params), :content_type => 'text/xml'
        return
      end

      # exec
      path = request.path
      path << build_query_from_hash(params, [:rev, :linkrev, :emptylink, :expand, :view, :extension, :lastworking, :withlinked, :meta, :deleted, :parse, :arch, :repository])
      pass_to_backend path
      return

    # /request.get?

    # DELETE /source/:project/:package
    #---------------------------------
    elsif request.delete?

      # checks
      if target_package_name == "_project"
        render_error :status => 403, :errorcode => "delete_package_no_permission",
          :message => "_project package can not be deleted."
        return
      end

      # deny deleting if other packages use this as develpackage
      # Shall we offer a --force option here as well ?
      # Shall we ask the other package owner accepting to be a devel package ?
      tpkg.can_be_deleted?

      # Find open requests with 'tpkg' as source or target and decline/revoke them.
      # Revoke if source or decline if target went away, pick the first action that matches to decide...
      # Note: As requests are a backend matter, it's pointless to include them into the transaction below
      tpkg.open_requests_with_package_as_source_or_target.each do |request|
        request.bs_request_actions.each do |action|
          if action.source_project == tpkg.project.name and action.source_package == tpkg.name
            request.change_state('revoked', :comment => "The source package '#{tpkg.project.name} / #{tpkg.name}' was removed")
            break
          end
          if action.target_project == tpkg.project.name and action.target_package == tpkg.name
            request.change_state('declined', :comment => "The target package '#{tpkg.project.name} / #{tpkg.name}' was removed")
            break
          end
        end
      end

      # Find open requests which have a review involving this package and remove those reviews
      # but leave the requests otherwise untouched.
      tpkg.open_requests_with_by_package_review.each do |request|
        request.remove_reviews(:by_project => tpkg.project.name, :by_package => tpkg.name)
      end

      # exec
      Package.transaction do
        tpkg.destroy

        params[:user] = @http_user.login
        path = "/source/#{target_project_name}/#{target_package_name}"
        path << build_query_from_hash(params, [:user, :comment])
        Suse::Backend.delete path
    
        if target_package_name == "_product"
          Project.find_by_name!(params[:project]).update_product_autopackages
        end
      end
      render_ok
      return
    # /request.delete?

    # POST /source/:project/:package
    #-------------------------------
    elsif request.post?

      dispatch_command

    end
  end

  # /source/:project/_attribute/:attribute
  # /source/:project/:package/_attribute/:attribute
  # /source/:project/:package/:binary/_attribute/:attribute
  #--------------------------------------------------------
  def attribute_meta
    # init and validation
    #--------------------
    required_parameters :project
    params[:user] = @http_user.login if @http_user
    binary=nil
    binary=params[:binary] if params[:binary]
    # valid post commands
    raise IllegalRequestError.new "invalid_project_name" unless valid_project_name?(params[:project])
    if params[:package] and params[:package] != "_project"
      @attribute_container = Package.get_by_project_and_name(params[:project], params[:package], use_source: false)
    else
      # project
      if Project.is_remote_project?(params[:project])
        render_error :status => 400, :errorcode => "remote_project",
          :message => "Attribute access to remote project is not yet supported"
        return
      end
      @attribute_container = Project.get_by_name(params[:project])
    end

    if @attribute_container.nil?
      render_error :status => 404, :errorcode => "not_existing_attribute",
                   :message => "Attribute is not defined in system"
      return
    end

    # is the attribute type defined at all ?
    if params[:attribute]
      # Valid attribute
      aname = params[:attribute]
      name_parts = aname.split(/:/)
      if name_parts.length != 2
        render_error :status => 400, :errorcode => "invalid_attribute",
          :message => "attribute '#{aname}' must be in the $NAMESPACE:$NAME style"
        return
      end
      # existing ?
      at = AttribType.find_by_name(params[:attribute])
      unless at
        render_error :status => 404, :errorcode => "not_existing_attribute",
          :message => "Attribute is not defined in system"
        return
      end
      # only needed for a get request
      params[:namespace] = name_parts[0]
      params[:name] = name_parts[1]
    end


    # GET
    # /source/:project/_attribute/:attribute
    # /source/:project/:package/_attribute/:attribute
    # /source/:project/:package/:binary/_attribute/:attribute
    #--------------------------------------------------------
    if request.get?

      # init
      # checks
      # exec
      if params[:rev]
        path = "/source/#{URI.escape(params[:project])}/#{URI.escape(params[:package]||'_project')}/_attribute?meta=1&rev=#{CGI.escape(params[:rev])}"
        answer = Suse::Backend.get(path)
        render :text => answer.body.to_s, :content_type => 'text/xml'
      else
        render :text => @attribute_container.render_attribute_axml(params), :content_type => 'text/xml'
      end
      return

    # /request.get?

    # DELETE
    # /source/:project/_attribute/:attribute
    # /source/:project/:package/_attribute/:attribute
    # /source/:project/:package/:binary/_attribute/:attribute
    #--------------------------------------------------------
    elsif request.delete?
      # init
      if params[:namespace].blank? or params[:name].blank?
        render_error :status => 400, :errorcode => "missing_attribute",
          :message => "No attribute got specified for delete"
        return
      end
      ac = @attribute_container.find_attribute(params[:namespace], params[:name], binary)

      # checks
      unless ac
          render_error :status => 404, :errorcode => "not_found",
            :message => "Attribute #{aname} does not exist" and return
      end
      if params[:attribute]
        unless @http_user.can_create_attribute_in? @attribute_container, :namespace => name_parts[0], :name => name_parts[1]
          render_error :status => 403, :errorcode => "change_attribute_no_permission",
            :message => "user #{user.login} has no permission to change attribute"
          return
        end
      end

      # exec
      ac.destroy
      @attribute_container.write_attributes(params[:comment])
      render_ok

    # /request.delete?

    # POST
    # /source/:project/_attribute/:attribute
    # /source/:project/:package/_attribute/:attribute
    # /source/:project/:package/:binary/_attribute/:attribute
    #--------------------------------------------------------
    elsif request.post?

      # init
      begin
        req = ActiveXML::Node.new(request.body.read)
        req.element_name # trigger XML parsing
      rescue ActiveXML::ParseError => e
        render_error :message => "Invalid XML",
          :status => 400, :errorcode => "invalid_xml"
        return
      end

      # checks
      if params[:attribute]
        unless @http_user.can_create_attribute_in? @attribute_container, :namespace => name_parts[0], :name => name_parts[1]
          render_error :status => 403, :errorcode => "change_attribute_no_permission",
            :message => "user #{user.login} has no permission to change attribute"
          return
        end
      else
          req.each_attribute do |attr|
            begin
              can_create = @http_user.can_create_attribute_in? @attribute_container, :namespace => attr.namespace, :name => attr.name
            rescue ActiveRecord::RecordNotFound => e
              render_error :status => 404, :errorcode => "not_found",
                :message => e.message
              return
            rescue ArgumentError => e
              render_error :status => 400, :errorcode => "change_attribute_attribute_error",
                :message => e.message
              return
            end
            unless can_create
              render_error :status => 403, :errorcode => "change_attribute_no_permission",
                :message => "user #{user.login} has no permission to change attribute"
              return
            end
          end
      end

      # exec
      changed = false
      req.each_attribute do |attr|
        begin
          changed = true if @attribute_container.store_attribute_axml(attr, binary)
        rescue Project::SaveError => e
          render_error :status => 403, :errorcode => "save_error", :message => e.message
          return
        rescue Package::SaveError => e
          render_error :status => 403, :errorcode => "save_error", :message => e.message
          return
        end
      end
      @attribute_container.write_attributes(params[:comment]) if changed
      render_ok

    # /request.post?

    # bad request
    #------------
    else
      raise IllegalRequestError.new
    end
  end

  # /source/:project/_meta
  def project_meta
    # init and validation
    #--------------------
    required_parameters :project
    unless valid_project_name?(params[:project])
      render_error :status => 400, :errorcode => "invalid_project_name",
        :message => "invalid project name '#{params[:project]}'"
      return
    end

    project_name = params[:project]
    params[:user] = @http_user.login

    # GET /source/:project/_meta
    #---------------------------
    if request.get?
      if Project.find_remote_project project_name
        # project from remote buildservice, get metadata from backend
	if params[:view]
	  render_error :status => 404, :errorcode => "invalid_project_parameters"
	  return
	end
        pass_to_backend
      else
        # access check
        prj = Project.get_by_name(project_name)

        render :text => prj.to_axml(params[:view]), :content_type => 'text/xml'
      end
      return

    # PUT /source/:project/_meta
    #----------------------------
    elsif request.put?
      # init
      # assemble path for backend
      path = request.path
      path += build_query_from_hash(params, [:user, :comment, :rev])
      #allowed = false
      request_data = request.raw_post

      # permission check
      rdata = Xmlhash.parse(request_data)
      if rdata['name'] != project_name 
        render_error :status => 400, :errorcode => 'project_name_mismatch',
                     :message => "project name in xml data ('#{rdata['name']}) does not match resource path component ('#{project_name}')"
        return
      end
      begin
        prj = Project.get_by_name rdata['name']
      rescue Project::UnknownObjectError
        prj = nil
      end

      # remote url project must be edited by the admin
      unless @http_user.is_admin?
        if rdata.has_key? 'remoteurl' or rdata.has_key? 'remoteproject'
          render_error :status => 403, :errorcode => "change_project_no_permission",
            :message => "admin rights are required to change remoteurl or remoteproject"
          return
        end
      end

      # Need permission
      logger.debug "Checking permission for the put"
      if prj
        # is lock explicit set to disable ? allow the un-freeze of the project in that case ...
        ignoreLock = nil
        # do not support unlock via meta data, just via command or request revoke for now
        # ignoreLock = true if rdata.has_key?("lock/disable")

        # project exists, change it
        unless @http_user.can_modify_project?(prj, ignoreLock)
          if prj.is_locked?
            logger.debug "no permission to modify LOCKED project #{prj.name}"
            render_error :status => 403, :errorcode => "change_project_no_permission", 
              :message => "The project #{prj.name} is locked"
            return
          end
          logger.debug "user #{user.login} has no permission to modify project #{prj.name}"
          render_error :status => 403, :errorcode => "change_project_no_permission", 
            :message => "no permission to change project"
          return
        end

       else
        # project is new
        unless @http_user.can_create_project? project_name
          logger.debug "Not allowed to create new project"
          render_error :status => 403, :errorcode => 'create_project_no_permission',
            :message => "not allowed to create new project '#{project_name}'"
          return
        end
      end

      # the following code checks if the target project of a linked project exists or is not readable by user
      rdata.elements('link') do |e|
        # permissions check
        tproject_name = e.value("project")
        tprj = Project.get_by_name(tproject_name)

        # The read access protection for own and linked project must be the same.
        # ignore this for remote targets
        if tprj.class == Project and tprj.disabled_for?('access', nil, nil) and 
            !FlagHelper.xml_disabled_for?(rdata, 'access')
          render_error :status => 404, :errorcode => "project_read_access_failure" ,
                       :message => "project links work only when both projects have same read access protection level: #{project_name} -> #{tproject_name}"
          return
        end

        logger.debug "project #{project_name} link checked against #{tproject_name} projects permission"
      end

      new_repo_names = {}
      # Check used repo pathes for existens and read access permissions
      rdata.elements('repository') do |r|
        new_repo_names[r['name']] = 1
        r.elements('path') do |e|
          # permissions check
          tproject_name = e.value("project")
          tprj = Project.get_by_name(tproject_name)
          if tprj.class == Project and tprj.disabled_for?('access', nil, nil) # user can access tprj, but backend would refuse to take binaries from there
            render_error :status => 404, :errorcode => "repository_access_failure" ,
            :message => "The current backend implementation is not using binaries from read access protected projects #{tproject_name}"
            return
          end
          
          logger.debug "project #{project_name} repository path checked against #{tproject_name} projects permission"
        end
      end

      if prj
        removedRepositories = Array.new
        prj.repositories.each do |repo|
          if !new_repo_names[repo.name] and not repo.remote_project_name
            # collect repositories to remove
            removedRepositories << repo
          end
        end
        private_check_and_remove_repositories(params, removedRepositories) or return
      end

      Project.transaction do
        # exec
        unless prj
          prj = Project.new(name: project_name)
          prj.update_from_xml(rdata)
	  # failure is ok
          prj.add_user(@http_user.login, 'maintainer')
        else
          prj.update_from_xml(rdata)
        end
        prj.store
      end
      render_ok

    # bad request
    #------------
    else
      raise IllegalRequestError.new
    end
  end

  # /source/:project/_config
  def project_config
    # check for project
    prj = Project.get_by_name(params[:project])

    # assemble path for backend
    params[:user] = @http_user.login

    # GET /source/:project/_config
    if request.get?
      path = request.path
      path += build_query_from_hash(params, [:rev])
      pass_to_backend path
      return
    end

    # assemble path for backend
    path = request.path
    path += build_query_from_hash(params, [:user, :comment])

    # PUT /source/:project/_config
    if request.put?
      unless @http_user.can_modify_project?(prj)
        render_error :status => 403, :errorcode => 'put_project_config_no_permission',
          :message => "No permission to write build configuration for project '#{params[:project]}'"
        return
      end

      pass_to_backend path
      return
    end
    render_error :status => 400, :errorcode => 'illegal_request',
        :message => "Illegal request: #{request.path}"
  end

  # /source/:project/_pubkey
  def project_pubkey
    # check for project
    prj = Project.get_by_name(params[:project])

    # assemble path for backend
    params[:user] = @http_user.login if request.delete?
    path = request.path
    path += build_query_from_hash(params, [:user, :comment, :rev])

    # GET /source/:project/_pubkey
    if request.get?
      pass_to_backend path

    # DELETE /source/:project/_pubkey
    elsif request.delete?
      #check for permissions
      upperProject = prj.name.gsub(/:[^:]*$/,"")
      while upperProject != prj.name and not upperProject.blank?
        if Project.exists_by_name(upperProject) and @http_user.can_modify_project?(Project.get_by_name(upperProject))
          pass_to_backend path
          return
        end
        upperProject = upperProject.gsub(/:[^:]*$/,"")
      end

      if @http_user.is_admin?
        pass_to_backend path
      else
        render_error :status => 403, :errorcode => 'delete_project_pubkey_no_permission',
          :message => "No permission to delete public key for project '#{params[:project]}'. Either maintainer permissions by upper project or admin permissions is needed."
      end
      return
    end
  end


  # /source/:project/:package/_meta
  def package_meta
    required_parameters :project, :package
   
    project_name = params[:project]
    package_name = params[:package]

    valid_package_name! package_name

    if request.get?
      # GET /source/:project/:package/_meta
      pack = Package.get_by_project_and_name( project_name, package_name, use_source: false )

      if params.has_key?(:rev) or pack.nil? # and not pro_name 
        # check if this comes from a remote project, also true for _project package
        # or if rev it specified we need to fetch the meta from the backend
        answer = Suse::Backend.get(request.path)
        if answer
          render :text => answer.body.to_s, :content_type => 'text/xml'
        else
          render_error :status => 404, :errorcode => "unknown_package",
            :message => "Unknown package '#{package_name}'"
        end
        return
      end

      render :text => pack.to_axml(params[:view]), :content_type => 'text/xml'

    else
      # PUT /source/:project/:package/_meta

      rdata = Xmlhash.parse(request.raw_post)
      
      if rdata['project'] && rdata['project'] != project_name
        render_error :status => 400, :errorcode => 'project_name_mismatch',
                     :message => "project name in xml data does not match resource path component"
        return
      end

      if rdata['name'] && rdata['name'] != package_name
        render_error :status => 400, :errorcode => 'package_name_mismatch',
                     :message => "package name in xml data does not match resource path component"
        return
      end

      # check for project
      if Package.exists_by_project_and_name( project_name, package_name, follow_project_links: false )
        # is lock explicit set to disable ? allow the un-freeze of the project in that case ...
        ignoreLock = nil
# unlock only via command for now
#        ignoreLock = 1 if Xmlhash.parse(request.raw_post).get("lock")["disable"]

        pkg = Package.get_by_project_and_name( project_name, package_name, use_source: false )
        unless @http_user.can_modify_package?(pkg, ignoreLock)
          render_error :status => 403, :errorcode => "change_package_no_permission",
            :message => "no permission to modify package '#{pkg.project.name}'/#{pkg.name}"
          return
        end

        if pkg and not pkg.disabled_for?('sourceaccess', nil, nil)
          if FlagHelper.xml_disabled_for?(rdata, 'sourceaccess')
             render_error :status => 403, :errorcode => "change_package_protection_level",
               :message => "admin rights are required to raise the protection level of a package"
             return
          end
        end
      else
        prj = Project.get_by_name(project_name)
        unless @http_user.can_create_package_in?(prj)
          render_error :status => 403, :errorcode => "create_package_no_permission",
            :message => "no permission to create a package in project '#{project_name}'"
          return
        end
        pkg = prj.packages.new(name: package_name)
      end
        
      begin
        Package.transaction do
          pkg.update_from_xml(rdata)
          pkg.store
        end
      rescue Package::CycleError => e
        render_error :status => 400, :errorcode => 'devel_cycle', :message => e.message
        return
      end

      render_ok
    end
  end

  # /source/:project/:package/:filename
  def file
    project_name = params[:project]
    package_name = params[:package]
    file = params[:filename]
    if file.blank?
	return index_package
    end
    path = "/source/#{URI.escape(project_name)}/#{URI.escape(package_name)}/#{URI.escape(file)}"

    #authenticate
    return unless @http_user
    params[:user] = @http_user.login

    if params.has_key?(:deleted) and request.get? 
      if Project.exists_by_name(project_name)
        validate_read_access_of_deleted_package(project_name, package_name)
        pass_to_backend
        return
      elsif package_name == "_project"
        validate_visibility_of_deleted_project(project_name)
        pass_to_backend
        return
      end
    end

    prj = Project.get_by_name(project_name)
    pack = nil
    allowed = false

    if package_name == "_project" or package_name == "_pattern"
      allowed = permissions.project_change? prj
    else
      if request.get? 
        # a readable package, even on remote instance is enough here
        begin
          pack = Package.get_by_project_and_name(project_name, package_name)
        rescue Package::UnknownObjectError
        end
      else
        # we need a local package here in any case for modifications
        pack = Package.get_by_project_and_name(project_name, package_name)
        allowed = permissions.package_change? pack
      end

      if pack.nil? and request.get?
        # Check if this is a package on a remote OBS instance
        answer = Suse::Backend.get(request.path)
        if answer
          pass_to_backend
          return
        end
      end
    end

    # GET /source/:project/:package/:filename
    if request.get?
      if pack # local package
        path = "/source/#{URI.escape(pack.project.name)}/#{URI.escape(pack.name)}/#{URI.escape(file)}"
      end
      path += build_query_from_hash(params, [:rev, :meta, :deleted, :limit, :expand])
      pass_to_backend path
      return
    end

    # PUT /source/:project/:package/:filename
    if request.put?
      unless allowed
        render_error :status => 403, :errorcode => 'put_file_no_permission',
          :message => "Insufficient permissions to store file in package #{package_name}, project #{project_name}"
        return
      end

      path += build_query_from_hash(params, [:user, :comment, :rev, :linkrev, :keeplink, :meta])

      # file validation where possible
      if params[:filename] == "_aggregate"
         validator = Suse::Validator.validate( "aggregate", request.raw_post.to_s)
      elsif params[:filename] == "_constraints"
         validator = Suse::Validator.validate( "constraints", request.raw_post.to_s)
      elsif params[:filename] == "_link"
         validator = Suse::Validator.validate( "link", request.raw_post.to_s)
      elsif params[:filename] == "_service"
         validator = Suse::Validator.validate( "service", request.raw_post.to_s)
      elsif params[:filename] == "_patchinfo"
         validator = Suse::Validator.validate( "patchinfo", request.raw_post.to_s)
      elsif params[:package] == "_pattern"
         validator = Suse::Validator.validate( "pattern", request.raw_post.to_s)
      end

      # verify link
      if params[:filename] == "_link"
        data = ActiveXML::Node.new(request.raw_post.to_s)
        if data
          tproject_name = data.value("project") || project_name
          tpackage_name = data.value("package") || package_name
          if data.has_attribute? 'missingok'
            Project.get_by_name(tproject_name) # permission check
            if Package.exists_by_project_and_name(tproject_name, tpackage_name, follow_project_links: true, allow_remote_packages: true)
              render_error :status => 400, :errorcode => 'not_missing',
                :message => "Link contains a missingok statement but link target (#{tproject_name}/#{tpackage_name}) exists."
              return
            end
          else
            Package.get_by_project_and_name(tproject_name, tpackage_name)
          end
        end
      end

      # verify patchinfo data
      if params[:filename] == "_patchinfo"
        Patchinfo.new.verify_data(prj, request.raw_post.to_s)
      end

      # _pattern was not a real package in former OBS 2.0 and before, so we need to create the
      # package here implicit to stay api compatible.
      # FIXME3.0: to be revisited
      if package_name == "_pattern" and not Package.exists_by_project_and_name( project_name, package_name, follow_project_links: false )
        pack = Package.new(:name => "_pattern", :title => "Patterns", :description => "Package Patterns")
        prj.packages << pack
        pack.save
      end

      pass_to_backend path

      # update package timestamp, kind and issues
      pack.sources_changed unless params[:rev] == 'repository' or [ "_project", "_pattern" ].include? package_name

      if package_name == "_product"
        Project.find_by_name!(params[:project]).update_product_autopackages
      end

    # DELETE /source/:project/:package/:filename
    elsif request.delete?
      path += build_query_from_hash(params, [:user, :comment, :rev, :linkrev, :keeplink])

      unless allowed
        render_error :status => 403, :errorcode => 'delete_file_no_permission',
          :message => "Insufficient permissions to delete file"
        return
      end

      Suse::Backend.delete path
      unless package_name == "_pattern" or package_name == "_project"
        # _pattern was not a real package in old times
        pack.sources_changed
      end
      if package_name == "_product"
        Project.find_by_name!(params[:project]).update_product_autopackages
      end
      render_ok
    end
  end

  # POST, GET /public/lastevents
  # GET /lastevents
  def lastevents_public
    lastevents
  end

  # POST /lastevents
  def lastevents
    path = get_request_path

    # map to a GET, so we can X-forward it
    forward_from_backend path
  end

  private

  # POST /source?cmd=createmaintenanceincident
  def index_createmaintenanceincident
    # set defaults
    unless params[:attribute]
      params[:attribute] = "OBS:MaintenanceProject"
    end
    noaccess = false
    noaccess = true if params[:noaccess]

    # find maintenance project via attribute
    at = AttribType.find_by_name(params[:attribute])
    unless at
      render_error :status => 403, :errorcode => 'not_found',
        :message => "The given attribute #{params[:attribute]} does not exist"
      return
    end
    prj = Project.find_by_attribute_type( at ).first()
    unless @http_user.can_modify_project?(prj)
      render_error :status => 403, :errorcode => "modify_project_no_permission",
        :message => "no permission to modify project '#{prj.name}'"
      return
    end
    
    # check for correct project kind
    unless prj and prj.project_type == "maintenance"
      render_error :status => 400, :errorcode => "incident_has_no_maintenance_project",
        :message => "incident projects shall only create below maintenance projects"
      return
    end

    # create incident project
    incident = create_new_maintenance_incident(prj, nil, nil, noaccess)
    render_ok :data => {:targetproject => incident.project.name}
  end

  def private_check_and_remove_repositories( params, removeRepositories )
    # find linking repos which get deleted
    linkingRepositories = Array.new
    linkingTargetRepositories = Array.new
    removeRepositories.each do |repo|
      linkingRepositories += repo.linking_repositories
      linkingTargetRepositories += repo.linking_target_repositories
    end
    unless params[:force] and not params[:force].empty?
      if linkingRepositories.length > 0
        lrepstr = linkingRepositories.map{|l| l.project.name+'/'+l.name}.join "\n"
        render_error :status => 400, :errorcode => "repo_dependency",
          :message => "Unable to delete repository; following repositories depend on this project:\n#{lrepstr}\n"
        return false
      end
      if linkingTargetRepositories.length > 0
        lrepstr = linkingTargetRepositories.map{|l| l.project.name+'/'+l.name}.join "\n"
        render_error :status => 400, :errorcode => "repo_dependency",
          :message => "Unable to delete repository; following target repositories depend on this project:\n#{lrepstr}\n"
        return false
      end
    end
    if removeRepositories.length > 0
      # do remove
      private_remove_repositories( removeRepositories, (params[:remove_linking_repositories] and not params[:remove_linking_repositories].empty?) )
    end
    return true
  end

  def private_remove_repositories( repositories, full_remove = false )
    del_repo = Project.find_by_name("deleted").repositories[0]

    repositories.each do |repo|
      linking_repos = repo.linking_repositories
      prj = repo.project

      # full remove, otherwise the model will take care of the cleanup
      if full_remove == true
        # recursive for INDIRECT linked repositories
        unless linking_repos.length < 1
          private_remove_repositories( linking_repos, true )
        end

        # try to remove the repository 
        # but never remove the special repository named "deleted"
        unless repo == del_repo
          # permission check
          unless @http_user.can_modify_project?(prj)
            render_error :status => 403, :errorcode => 'change_project_no_permission',
              :message => "No permission to remove a repository in project '#{prj.name}'"
            return
          end
        end
      end

      # remove this repository, but be careful, because we may have done it already.
      if Repository.exists?(repo) and r=prj.repositories.find(repo)
        logger.info "destroy repo #{r.name} in '#{prj.name}'"
        r.destroy
        prj.store({:lowprio => true}) # low prio storage
      end
    end
  end

  # POST /source?cmd=branch (aka osc mbranch)
  def index_branch
    ret = do_branch params
    if ret[:status] == 200
      if ret[:text]
        render ret
      else
        render_ok ret
      end
      return
    end
    render_error ret
  end

  # create a id collection of all projects doing a project link to this one
  # POST /source/<project>?cmd=showlinked
  def index_project_showlinked
    valid_http_methods :post
    required_parameters :project
    project_name = params[:project]

    # FIXME2.4 implement test case for hidden projects and hidden links
    pro = Project.find_by_name(project_name)

    builder = Builder::XmlMarkup.new( :indent => 2 )
    xml = builder.collection() do |c|
      pro.find_linking_projects.each do |l|
        p={}
        p[:name] = l.name
        c.project(p)
      end
    end
    render :text => xml, :content_type => "text/xml"
  end

  # unlock a project
  # POST /source/<project>?cmd=unlock
  def index_project_unlock
    valid_http_methods :post
    project_name = params[:project]

    if params[:comment].blank?
      render_error :status => 400, :errorcode => "no_comment",
        :message => "Unlock command requires a comment"
      return
    end

    pro = Project.get_by_name(project_name)
    if pro.project_type == "maintenance_incident"
      rel = BsRequest.where(state: [:new, :review, :declined]).joins(:bs_request_actions)
      rel = rel.where(bs_request_actions: { type: 'maintenance_release', source_project: pro.name})
      if rel.exists?
        render_error :status => 403, :errorcode => "open_release_request",
          :message => "Unlock of maintenance incident #{} is not possible, because there is a running release request: #{rel.first.id}"
        return
      end
    end

    p = { :comment => params[:comment] }

    f = pro.flags.find_by_flag_and_status("lock", "enable")
    unless f
      render_error :status => 400, :errorcode => "not_locked",
        :message => "project '#{pro.name}' is not locked"
      return
    end
   
    Project.transaction do 
      pro.flags.delete(f)
      pro.store(p)

      # maintenance incidents need special treatment
      if pro.project_type == "maintenance_incident"
        # reopen all release targets
        pro.repositories.each do |repo|
          repo.release_targets.each do |releasetarget|
            releasetarget.trigger = "maintenance"
            releasetarget.save!
          end
        end
        pro.store(p)

        # ensure higher build numbers for re-release
        Suse::Backend.post "/build/#{URI.escape(pro.name)}?cmd=wipe", nil
      end
    end

    render_ok
  end

  # POST /source/<project>?cmd=extendkey
  def index_project_extendkey
    valid_http_methods :post
    project_name = params[:project]

    Project.find_by_name project_name

    path = request.path
    path << build_query_from_hash(params, [:cmd, :user, :comment])
    pass_to_backend path
  end

  # POST /source/<project>?cmd=createkey
  def index_project_createkey
    valid_http_methods :post
    project_name = params[:project]

    Project.find_by_name project_name

    path = request.path
    path << build_query_from_hash(params, [:cmd, :user, :comment])
    pass_to_backend path
  end

  # POST /source/<project>?cmd=createmaintenanceincident
  def index_project_createmaintenanceincident
    valid_http_methods :post

    noaccess = false
    noaccess = true if params[:noaccess]

    prj = Project.get_by_name( params[:project] )
    unless @http_user.can_modify_project?(prj)
      render_error :status => 403, :errorcode => "modify_project_no_permission",
        :message => "no permission to modify project '#{prj.name}'"
      return
    end

    # check for correct project kind
    unless prj and prj.project_type == "maintenance"
      render_error :status => 400, :errorcode => "incident_has_no_maintenance_project",
        :message => "incident projects shall only create below maintenance projects"
      return
    end

    # create incident project
    incident = create_new_maintenance_incident(prj, nil, nil, noaccess)
    render_ok :data => {:targetproject => incident.project.name}
  end

  # POST /source/<project>?cmd=undelete
  def index_project_undelete
    valid_http_methods :post
    project_name = params[:project]

    path = request.path
    path << build_query_from_hash(params, [:cmd, :user, :comment])
    pass_to_backend path

    # read meta data from backend to restore database object
    path = request.path + "/_meta"
    prj = Project.new(name: params[:project])
    Project.transaction do
      prj.update_from_xml(Xmlhash.parse(backend_get(path)))
      prj.store
    end

    # restore all package meta data objects in DB
    backend_pkgs = Collection.find :package, :match => "@project='#{project_name}'"
    backend_pkgs.each_package do |package|
      Package.transaction do
        path = request.path + "/" + package.name + "/_meta"
        p = Xmlhash.parse(backend_get(path))
        pkg = prj.packages.new(name: p['name'])
        pkg.update_from_xml(p)
        pkg.store
      end
    end
  end

  # POST /source/<project>?cmd=release
  def index_project_release
    valid_http_methods :post
    params[:user] = @http_user.login

    p = Project.get_by_name(params[:project])
    if p.class == String # remote project
      render_error :status => 404, :errorcode => "remote_project",
        :message => "The release from remote projects is currently not supported"
      return
    end

    if params.has_key? :nodelay
      p.do_project_release(params)
      render_ok
    else
      # inject as job
      p.delay.do_project_release(params)
      render_invoked
    end
  end

  # POST /source/<project>?cmd=copy
  def index_project_copy
    valid_http_methods :post
    project_name = params[:project]
    oproject = params[:oproject]

    oprj = Project.get_by_name( oproject )

    if oprj.class == String # remote project
      render_error :status => 404, :errorcode => "remote_project",
        :message => "The copy from remote projects is currently not supported"
      return
    end

    unless @http_user.is_admin?
      if params[:withbinaries]
        render_error :status => 403, :errorcode => "project_copy_no_permission",
          :message => "no permission to copy project with binaries for non admins"
        return
      end

      unless oprj.class == String
        oprj.packages.each do |pkg|
          if pkg.disabled_for?('sourceaccess', nil, nil)
            render_error :status => 403, :errorcode => "project_copy_no_permission",
              :message => "no permission to copy project due to source protected package #{pkg.name}"
            return
          end
        end
      end
    end

    # create new project object based on oproject
    p = Project.find_by_name(project_name)
    Project.transaction do
      if oprj.class == String # remote project
        rdata = Xmlhash.parse(backend_get("/source/#{URI.escape(oprj)}/_meta"))
        p = Project.new :name => project_name, :title => rdata["title"], :description => rdata["description"]
      else # local project
        p = Project.new :name => project_name, :title => oprj.title, :description => oprj.description
        p.save
        oprj.flags.each do |f|
          p.flags.create(:status => f.status, :flag => f.flag, :architecture => f.architecture, :repo => f.repo) unless f.flag == 'lock'
        end
        oprj.repositories.each do |repo|
          r = p.repositories.create :name => repo.name
          repo.repository_architectures.each do |ra|
            r.repository_architectures.create! :architecture => ra.architecture, :position => ra.position
          end
          position = 0
          repo.path_elements.each do |pe|
            position += 1
            r.path_elements << PathElement.new(:link => pe.link, :position => position)
          end
        end
      end
      p.add_user @http_user, "maintainer"
      p.store
    end unless p

    if params.has_key? :nodelay
      p.do_project_copy(params)
      render_ok
    else
      # inject as job
      p.delay.do_project_copy(params)
      render_invoked
    end
  end
  
  # POST /source/<project>?cmd=createpatchinfo
  def index_project_createpatchinfo
    #project_name = params[:project]
    # a new_format argument may be given but we don't support the old (and experimental marked) format
    # anymore

    render_ok data: Patchinfo.new.create_patchinfo(params[:project], params[:name],
                                                   comment: params[:comment], force: params[:force])
  end

  # POST /source/<project>/<package>?cmd=updatepatchinfo
  def index_package_updatepatchinfo

    Patchinfo.new.cmd_update_patchinfo(params[:project], params[:package])
    render_ok
  end

  # unlock a package
  # POST /source/<project>/<package>?cmd=unlock
  def index_package_unlock
    valid_http_methods :post

    if params[:comment].blank?
      render_error :status => 400, :errorcode => "no_comment",
        :message => "Unlock command requires a comment"
      return
    end

    p = { :comment => params[:comment] }

    pkg = Package.get_by_project_and_name(params[:project], params[:package])
    f = pkg.flags.find_by_flag_and_status("lock", "enable")
    unless f
      render_error :status => 400, :errorcode => "not_locked",
        :message => "package '#{pkg.project.name}/#{pkg.name}' is not locked"
      return
    end
    pkg.flags.delete(f)
    pkg.store(p)

    render_ok
  end

  # Collect all project source services for a package
  # POST /source/<project>/<package>?cmd=getprojectservices
  def index_package_getprojectservices
    valid_http_methods :post

    path = request.path
    path << build_query_from_hash(params, [:cmd])
    pass_to_backend path
  end

  # create a id collection of all packages doing a package source link to this one
  # POST /source/<project>/<package>?cmd=showlinked
  def index_package_showlinked
    valid_http_methods :post
    project_name = params[:project]
    package_name = params[:package]

    pack = Package.find_by_project_and_name( project_name, package_name )

    unless pack
      # package comes from remote instance or is hidden

      # FIXME: return an empty list for now
      # we could request the links on remote instance via that: but we would need to search also localy and merge ...

#      path = "/search/package/id?match=(@linkinfo/package=\"#{CGI.escape(package_name)}\"+and+@linkinfo/project=\"#{CGI.escape(project_name)}\")"
#      answer = Suse::Backend.post path, nil
#      render :text => answer.body, :content_type => 'text/xml'
      render :text => "<collection/>", :content_type => 'text/xml'
      return
    end

    builder = Builder::XmlMarkup.new( :indent => 2 )
    xml = builder.collection() do |c|
      pack.find_linking_packages.each do |l|
        p={}
        p[:project] = l.project.name
        p[:name] = l.name
        c.package(p)
      end
    end
    render :text => xml, :content_type => "text/xml"
  end

  # POST /source/<project>/<package>?cmd=undelete
  def index_package_undelete
    valid_http_methods :post
    params[:user] = @http_user.login

    path = request.path
    path << build_query_from_hash(params, [:cmd, :user, :comment])
    pass_to_backend path

    # read meta data from backend to restore database object
    path = request.path + "/_meta"
    prj = Project.find_by_name!(params[:project])
    pkg = prj.packages.new(name: params[:package])
    pkg.update_from_xml(Xmlhash.parse(backend_get(path)))
    pkg.store
  end

  # FIXME: obsolete this for 3.0
  # POST /source/<project>/<package>?cmd=createSpecFileTemplate
  def index_package_createSpecFileTemplate
    specfile_path = "#{request.path}/#{params[:package]}.spec"
    begin
      backend_get( specfile_path )
      render_error :status => 400, :errorcode => "spec_file_exists",
        :message => "SPEC file already exists."
      return
    rescue ActiveXML::Transport::NotFoundError
      specfile = File.read "#{Rails.root}/files/specfiletemplate"
      Suse::Backend.put( specfile_path, specfile )
    end
    render_ok
  end

  # OBS 3.0: this should be obsoleted, we have /build/ controller for this
  # POST /source/<project>/<package>?cmd=rebuild
  def index_package_rebuild
    project_name = params[:project]
    package_name = params[:package]
    repo_name = params[:repo]
    arch_name = params[:arch]

    # check for sources in this or linked project
    pkg = Package.find_by_project_and_name(project_name, package_name)
    unless pkg
      # check if this is a package on a remote OBS instance
      answer = Suse::Backend.get(request.path)
      unless answer
        render_error :status => 400, :errorcode => 'unknown_package',
          :message => "Unknown package '#{package_name}'"
        return
      end
    end

    path = "/build/#{project_name}?cmd=rebuild&package=#{package_name}"
    if repo_name
      if p.repositories.find_by_name(repo_name).nil?
        render_error :status => 400, :errorcode => 'unknown_repository',
          :message=> "Unknown repository '#{repo_name}'"
        return
      end
      path += "&repository=#{repo_name}"
    end
    if arch_name
      path += "&arch=#{arch_name}"
    end

    backend.direct_http( URI(path), :method => "POST", :data => "" )

    render_ok
  end

  # POST /source/<project>/<package>?cmd=commit
  def index_package_commit
    valid_http_methods :post
    params[:user] = @http_user.login

    path = request.path
    path << build_query_from_hash(params, [:cmd, :user, :comment, :rev, :linkrev, :keeplink, :repairlink])
    pass_to_backend path

    pack = Package.find_by_project_and_name( params[:project], params[:package] )
    pack.sources_changed if pack # in case of _project package

    if params[:package] == "_product"
      Project.find_by_name!(params[:project]).update_product_autopackages
    end
  end

  # POST /source/<project>/<package>?cmd=commitfilelist
  def index_package_commitfilelist
    valid_http_methods :post
    params[:user] = @http_user.login
    #project_name = params[:project]
    #package_name = params[:package]

    path = request.path
    path << build_query_from_hash(params, [:cmd, :user, :comment, :rev, :linkrev, :keeplink, :repairlink])
    answer = pass_to_backend path
    
    pack = Package.find_by_project_and_name( params[:project], params[:package] )
    if pack # in case of _project package
      pack.set_package_kind_from_commit(answer)
      pack.sources_changed
    end

    if params[:package] == "_product"
      Project.find_by_name!(params[:project]).update_product_autopackages
    end
  end

  # POST /source/<project>/<package>?cmd=diff
  def index_package_diff
    valid_http_methods :post
    #oproject_name = params[:oproject]
    #opackage_name = params[:opackage]
 
    path = request.path
    path << build_query_from_hash(params, [:cmd, :rev, :orev, :oproject, :opackage, :expand ,:linkrev, :olinkrev, :unified ,:missingok, :meta, :file, :filelimit, :tarlimit, :view, :withissues, :onlyissues])
    pass_to_backend path
  end

  # POST /source/<project>/<package>?cmd=linkdiff
  def index_package_linkdiff
    valid_http_methods :post

    path = request.path
    path << build_query_from_hash(params, [:cmd, :rev, :unified, :linkrev, :file, :filelimit, :tarlimit, :view, :withissues, :onlyissues])
    pass_to_backend path
  end

  # POST /source/<project>/<package>?cmd=servicediff
  def index_package_servicediff
    valid_http_methods :post

    path = request.path
    path << build_query_from_hash(params, [:cmd, :rev, :unified, :file, :filelimit, :tarlimit, :view, :withissues, :onlyissues])
    pass_to_backend path
  end

  # POST /source/<project>/<package>?cmd=copy
  def index_package_copy
    valid_http_methods :post
    params[:user] = @http_user.login

    sproject = params[:project]
    sproject = params[:oproject] if params[:oproject]
    spackage = params[:package]
    spackage = params[:opackage] if params[:opackage]

    # create target package, if it does not exist
    tpkg = Package.find_by_project_and_name(params[:project], params[:package])
    if tpkg.nil?
      prj = Project.find_by_name!(params[:project])
      answer = Suse::Backend.get("/source/#{CGI.escape(sproject)}/#{CGI.escape(spackage)}/_meta")
      if answer
        Package.transaction do
          adata = Xmlhash.parse(answer.body)
          adata['name'] = params[:package]
          p = prj.packages.new(name: params[:package])
          p.update_from_xml(adata)
          p.remove_all_persons
          p.remove_all_groups
          p.develpackage = nil
          p.store
        end
        tpkg = Package.find_by_project_and_name(params[:project], params[:package])
      else
        render_error :status => 404, :errorcode => 'unknown_package',
          :message => "Unknown package #{spackage} in project #{sproject}"
        return
      end
    end

    # We need to use the project name of package object, since it might come via a project linked project
    path = "/source/#{CGI.escape(tpkg.project.name)}/#{CGI.escape(tpkg.name)}"
    path << build_query_from_hash(params, [:cmd, :rev, :user, :comment, :oproject, :opackage, :orev, :expand, :keeplink, :repairlink, :linkrev, :olinkrev, :requestid, :dontupdatesource, :withhistory])
    pass_to_backend path

    tpkg.sources_changed
  end

  # POST /source/<project>/<package>?cmd=release
  def index_package_release
    valid_http_methods :post
    params[:user] = @http_user.login

    pkg = Package.get_by_project_and_name params[:project], params[:package], use_source: true, follow_project_links: false
    pkg.project.repositories.each do |repo|
      next if params[:repository] and params[:repository] != repo.name
      repo.release_targets.each do |releasetarget|
        # find md5sum and release source and binaries
        release_package(pkg, releasetarget.target_repository.project.name, pkg.name, repo)
      end
    end

    render_ok
  end

  # POST /source/<project>/<package>?cmd=runservice
  def index_package_runservice
    valid_http_methods :post
    params[:user] = @http_user.login

    pack = Package.find_by_project_and_name( params[:project], params[:package] )

    path = request.path
    path << build_query_from_hash(params, [:cmd, :comment, :user])
    pass_to_backend path

    pack.sources_changed
  end

  # POST /source/<project>/<package>?cmd=deleteuploadrev
  def index_package_deleteuploadrev
    valid_http_methods :post
    params[:user] = @http_user.login

    path = request.path
    path << build_query_from_hash(params, [:cmd])
    pass_to_backend path
  end

  # POST /source/<project>/<package>?cmd=linktobranch
  def index_package_linktobranch
    valid_http_methods :post
    params[:user] = @http_user.login
    prj_name = params[:project]
    pkg_name = params[:package]
    pkg_rev = params[:rev]
    pkg_linkrev = params[:linkrev]

    pkg = Package.get_by_project_and_name prj_name, pkg_name, use_source: true, follow_project_links: false

    #convert link to branch
    rev = ""
    if not pkg_rev.nil? and not pkg_rev.empty?
      rev = "&orev=#{pkg_rev}"
    end
    linkrev = ""
    if not pkg_linkrev.nil? and not pkg_linkrev.empty?
      linkrev = "&linkrev=#{pkg_linkrev}"
    end
    Suse::Backend.post "/source/#{prj_name}/#{pkg_name}?cmd=linktobranch&user=#{CGI.escape(params[:user])}#{rev}#{linkrev}", nil

    pkg.sources_changed
    render_ok
  end

  # POST /source/<project>/<package>?cmd=branch&target_project="optional_project"&target_package="optional_package"&update_project_attribute="alternative_attribute"&comment="message"
  def index_package_branch
    ret = Package.transaction do
      do_branch params
    end
    if ret[:status] == 200
      if ret[:text]
        render ret
      else
        render_ok ret
      end
      return
    end
    render_error ret
  end

  # POST /source/<project>/<package>?cmd=set_flag&repository=:opt&arch=:opt&flag=flag&status=status
  def index_package_set_flag
    valid_http_methods :post

    required_parameters :project, :package, :flag, :status

    prj_name = params[:project]
    pkg_name = params[:package]

    pkg = Package.get_by_project_and_name prj_name, pkg_name, use_source: true, follow_project_links: false

    pkg.transaction do
      # first remove former flags of the same class
      begin
        pkg.remove_flag(params[:flag], params[:repository], params[:arch])
        pkg.add_flag(params[:flag], params[:status], params[:repository], params[:arch])
      rescue ArgumentError => e
        render_error :status => 400, :errorcode => 'invalid_flag', :message => e.message
        return
      end
      pkg.store
    end
    render_ok
  end

  # POST /source/<project>?cmd=set_flag&repository=:opt&arch=:opt&flag=flag&status=status
  def index_project_set_flag
    valid_http_methods :post

    required_parameters :project, :flag, :status
    prj_name = params[:project]
    prj = Project.get_by_name prj_name

    # Raising permissions afterwards is not secure. Do not allow this by default.
    unless @http_user.is_admin?
      if params[:flag] == "access" and params[:status] == "enable" and not prj.enabled_for?('access', params[:repository], params[:arch])
        raise Project::ForbiddenError.new
      end
      if params[:flag] == "sourceaccess" and params[:status] == "enable" and
          !prj.enabled_for?('sourceaccess', params[:repository], params[:arch])
        raise Project::ForbiddenError.new
      end
    end

    prj.transaction do
      begin
        # first remove former flags of the same class
        prj.remove_flag(params[:flag], params[:repository], params[:arch])
        prj.add_flag(params[:flag], params[:status], params[:repository], params[:arch])
      rescue ArgumentError => e
        render_error :status => 400, :errorcode => 'invalid_flag', :message => e.message
        return
      end
      
      prj.store
    end
    render_ok
  end

  # POST /source/<project>/<package>?cmd=remove_flag&repository=:opt&arch=:opt&flag=flag
  def index_package_remove_flag
    valid_http_methods :post

    required_parameters :project, :package, :flag
    
    pkg = Package.get_by_project_and_name( params[:project], params[:package] )
    
    pkg.transaction do
      pkg.remove_flag(params[:flag], params[:repository], params[:arch])
      pkg.store
    end
    render_ok
  end

  # POST /source/<project>?cmd=remove_flag&repository=:opt&arch=:opt&flag=flag
  def index_project_remove_flag
    valid_http_methods :post
    required_parameters :project, :flag

    prj_name = params[:project]

    prj = Project.get_by_name prj_name

    prj.transaction do
      prj.remove_flag(params[:flag], params[:repository], params[:arch])
      prj.store
    end
    render_ok
  end

end
