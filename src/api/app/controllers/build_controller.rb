class BuildController < ApplicationController
  def index
    # for read access and visibility permission check
    if params[:package] && !%w(_repository _jobhistory).include?(params[:package])
      Package.get_by_project_and_name( params[:project], params[:package], use_source: false, follow_multibuild: true )
    else
      Project.get_by_name params[:project]
    end

    if request.get?
      pass_to_backend
      return
    end

    if @http_user.is_admin?
      # check for a local package instance
      Package.get_by_project_and_name( params[:project], params[:package], use_source: false, follow_project_links: false )
      pass_to_backend
    else
      render_error status: 403, errorcode: "execute_cmd_no_permission",
        message: "Upload of binaries is only permitted for administrators"
    end
  end

  def project_index
    prj = nil
    unless params[:project] == "_dispatchprios"
      prj = Project.get_by_name params[:project]
    end

    if request.get?
      pass_to_backend
      return
    elsif request.post?
      # check if user has project modify rights
      allowed = false
      allowed = true if permissions.global_project_change
      allowed = true if permissions.project_change? prj

      # check for cmd parameter
      if params[:cmd].nil?
        raise MissingParameterError.new "Missing parameter 'cmd'"
      end

      unless %w(wipe restartbuild killbuild abortbuild rebuild unpublish).include? params[:cmd]
        render_error status: 400, errorcode: "illegal_request",
          message: "unsupported POST command #{params[:cmd]} to #{request.url}"
        return
      end

      unless prj.class == Project
        render_error status: 403, errorcode: "readonly_error",
          message: "The project #{params[:project]} is a remote project and therefore readonly."
        return
      end

      if !allowed && !params[:package].nil?
        package_names = nil
        if params[:package].kind_of? Array
          package_names = params[:package]
        else
          package_names = [params[:package]]
        end
        package_names.each do |pack_name|
          pkg = Package.find_by_project_and_name( prj.name, pack_name )
          if pkg.nil?
            allowed = permissions.project_change? prj
            unless allowed
              render_error status: 403, errorcode: "execute_cmd_no_permission",
                message: "No permission to execute command on package #{pack_name} in project #{prj.name}"
              return
            end
          else
            allowed = permissions.package_change? pkg
            unless allowed
              render_error status: 403, errorcode: "execute_cmd_no_permission",
                message: "No permission to execute command on package #{pack_name}"
              return
            end
          end
        end
      end

      unless allowed
        render_error status: 403, errorcode: "execute_cmd_no_permission",
          message: "No permission to execute command on project #{params[:project]}"
        return
      end

      pass_to_backend
      return
    elsif request.put?
      if @http_user.is_admin?
        pass_to_backend
      else
        render_error status: 403, errorcode: "execute_cmd_no_permission",
          message: "No permission to execute command on project #{params[:project]}"
      end
      return
    else
      render_error status: 400, errorcode: 'illegal_request',
        message: "Illegal request: #{request.method.to_s.upcase} #{request.path}"
      return
    end
  end

  def buildinfo
    required_parameters :project, :repository, :arch, :package
    # just for permission checking
    if request.post? && params[:package] == "_repository"
      # for osc local package build in this repository
      Project.get_by_name params[:project]
    else
      Package.get_by_project_and_name params[:project], params[:package], use_source: false, follow_multibuild: true
    end

    path = "/build/#{params[:project]}/#{params[:repository]}/#{params[:arch]}/#{params[:package]}/_buildinfo"
    unless request.query_string.empty?
      path += '?' + request.query_string
    end

    pass_to_backend path
  end

  # /build/:project/:repository/:arch/_builddepinfo
  def builddepinfo
    required_parameters :project, :repository, :arch

    # just for permission checking
    Project.get_by_name params[:project]

    path = "/build/#{params[:project]}/#{params[:repository]}/#{params[:arch]}/_builddepinfo"
    unless request.query_string.empty?
      path += '?' + request.query_string
    end

    pass_to_backend path
  end

  # /build/:project/:repository/:arch/:package/:filename
  def file
    required_parameters :project, :repository, :arch, :package, :filename

    # read access permission check
    prj = nil
    if params[:package] == "_repository"
      prj = Project.get_by_name params[:project]
    else
      pkg = Package.get_by_project_and_name params[:project], params[:package], use_source: false, follow_multibuild: true
      prj = pkg.project if pkg.class == Package
    end

    if prj.class == Project && prj.disabled_for?('binarydownload', params[:repository], params[:arch]) && !@http_user.can_download_binaries?(prj)
      render_error status: 403, errorcode: "download_binary_no_permission",
        message: "No permission to download binaries from package #{params[:package]}, project #{params[:project]}"
      return
    end

    path = request.path_info + "?" + request.query_string

    if request.delete?
      unless permissions.project_change? params[:project]
        render_error status: 403, errorcode: "delete_binary_no_permission",
          message: "No permission to delete binaries from project #{params[:project]}"
        return
      end

      if params[:package] == "_repository"
        pass_to_backend
      else
        render_error status: 400, errorcode: "invalid_operation",
          message: "Delete operation of build results is not allowed"
      end

      return
    end

    regexp = nil
    # if there is a query, we can't assume it's a simple download, so better leave out the logic (e.g. view=fileinfo)
    unless request.query_string
      # check if binary exists and for size
      fpath = "/build/" + [:project, :repository, :arch, :package].map {|x| params[x]}.join("/")
      file_list = Suse::Backend.get(fpath)
      regexp = file_list.body.match(/name=["']#{Regexp.quote params[:filename]}["'].*size=["']([^"']*)["']/)
    end
    if regexp
      fsize = regexp[1]
      logger.info "streaming #{path}"

      # rubocop:disable Lint/EndAlignment
      c_type = case params[:filename].split(/\./)[-1]
               when "rpm"
                 "application/x-rpm"
               when "deb"
                 "application/x-deb"
               when "iso"
                 "application/x-cd-image"
               else
                 "application/octet-stream"
               end
      # rubocop:enable Lint/EndAlignment

      headers.update!(
        'Content-Disposition' => %(attachment; filename="#{params[:filename]}"),
        'Content-Type' => c_type,
        'Transfer-Encoding' => 'binary',
        'Content-Length' => fsize
      )

      render status: 200, text: Proc.new {|_, output|
        backend_request = Net::HTTP::Get.new(path)
        Net::HTTP.start(CONFIG['source_host'], CONFIG['source_port']) do |http|
          http.request(backend_request) do |response|
            response.read_body do |chunk|
              output.write(chunk)
            end
          end
        end
      }
    else
      if request.put?
        unless @http_user.is_admin?
          # this route can be used publish binaries without history changes in sources
          render_error status: 403, errorcode: "upload_binary_no_permission",
            message: "No permission to upload binaries."
          return
        end
      end
      pass_to_backend path
    end
  end

  def logfile
    # for permission check
    pkg = Package.get_by_project_and_name params[:project], params[:package], use_source: true, follow_project_links: true, follow_multibuild: true

    if pkg.class == Package && pkg.project.disabled_for?('binarydownload', params[:repository], params[:arch]) &&
        !@http_user.can_download_binaries?(pkg.project)
      render_error status: 403, errorcode: "download_binary_no_permission",
                   message: "No permission to download binaries from package #{params[:package]}, project #{params[:project]}"
      return
    end

    pass_to_backend
  end

  def result
    required_parameters :project

    # this route is mainly for checking submissions to a target project
    if params.has_key? :lastsuccess
      return result_lastsuccess
    end

    # for permission check
    Project.get_by_name params[:project]

    pass_to_backend
  end

  def result_lastsuccess
    required_parameters :package, :pathproject

    pkg = Package.get_by_project_and_name(params[:project], params[:package],
                                          {use_source: false, follow_project_links: true})
    raise RemoteProjectError.new 'The package lifes in a remote project, this is not supported atm' unless pkg

    tprj = Project.get_by_name params[:pathproject]
    bs = PackageBuildStatus.new(pkg).result(target_project: tprj, srcmd5: params[:srcmd5])
    @result = []
    bs.each do |repo, status|
      archs = []
      status.each do |arch, archstat|
        oneline = [arch, archstat[:result]]
        if archstat[:missing].blank?
          oneline << nil
        else
          oneline << archstat[:missing].join(",")
        end
        archs << oneline
      end
      @result << [repo, archs]
    end
    render xml: render_to_string(partial: "lastsuccess")
  end
end
