include ValidationHelper

module MaintenanceHelper
  class MissingAction < APIException
    setup 400, 'The request contains no actions. Submit requests without source changes may have skipped!'
  end

  class MultipleUpdateInfoTemplate < APIException; end

  def _release_product(source_package, target_project, action)
    product_package = Package.find_by_project_and_name source_package.project.name, "_product"
    # create package container, if missing
    tpkg = create_package_container_if_missing(product_package, "_product", target_project)
    # copy sources
    release_package_copy_sources(action, product_package, "_product", target_project)
    tpkg.project.update_product_autopackages
    tpkg.sources_changed
  end

  def _release_package(source_package, target_project, target_package_name, action, relink)
    # create package container, if missing
    tpkg = create_package_container_if_missing(source_package, target_package_name, target_project)

    link = nil
    if relink
      # detect local links
      begin
        link = source_package.source_file('_link')
        link = ActiveXML::Node.new(link)
      rescue ActiveXML::Transport::Error
        link = nil
      end
    end
    if link && (link.value(:project).nil? || link.value(:project) == source_package.project.name)
      release_package_relink(link, action, target_package_name, target_project, tpkg)
    else
      # copy sources
      release_package_copy_sources(action, source_package, target_package_name, target_project)
      tpkg.sources_changed
    end
  end

  def release_package(source_package, target, target_package_name,
                      filter_source_repository = nil, multibuild_container = nil, action = nil,
                      setrelease = nil, manual = nil)
    if target.kind_of? Repository
      target_project = target.project
    else
      # project
      target_project = target
    end
    target_project.check_write_access!
    # lock the scheduler
    target_project.suspend_scheduler

    if source_package.name.starts_with?("_product:") && target_project.packages.where(name: "_product").count > 0
      # a master _product container exists, so we need to copy all sources
      _release_product(source_package, target_project, action)
    else
      _release_package(source_package, target_project, target_package_name, action, manual ? nil : true)
    end

    # copy binaries
    if target.kind_of? Repository
      u_ids = copy_binaries_to_repository(filter_source_repository, source_package, target, target_package_name, multibuild_container, setrelease)
    else
      u_ids = copy_binaries(filter_source_repository, source_package, target_package_name, target_project, multibuild_container, setrelease)
    end

    # create or update main package linking to incident package
    unless source_package.is_patchinfo? || manual
      release_package_create_main_package(action.bs_request, source_package, target_package_name, target_project)
    end

    # publish incident if source is read protect, but release target is not. assuming it got public now.
    f = source_package.project.flags.find_by_flag_and_status('access', 'disable')
    if f
      unless target_project.flags.find_by_flag_and_status('access', 'disable')
        source_package.project.flags.delete(f)
        source_package.project.store({ comment: 'project becomes public on release action' })
        # patchinfos stay unpublished, it is anyway too late to test them now ...
      end
    end

    # release the scheduler lock
    target_project.resume_scheduler

    u_ids
  end

  def release_package_relink(link, action, target_package_name, target_project, tpkg)
    link.delete_attribute('project') # its a local link, project name not needed
    link.set_attribute('package', link.value(:package).gsub(/\..*/, '') + target_package_name.gsub(/.*\./, '.')) # adapt link target with suffix
    link_xml = link.dump_xml
    # rubocop:disable Metrics/LineLength
    Backend::Connection.put "/source/#{URI.escape(target_project.name)}/#{URI.escape(target_package_name)}/_link?rev=repository&user=#{CGI.escape(User.current.login)}", link_xml
    # rubocop:enable Metrics/LineLength
    md5 = Digest::MD5.hexdigest(link_xml)
    # commit with noservice parameter
    upload_params = {
      user:      User.current.login,
      cmd:       "commitfilelist",
      noservice: "1",
      comment:   "Set local link to #{target_package_name} via maintenance_release request"
    }
    upload_params[:requestid] = action.bs_request.number if action
    upload_path = "/source/#{URI.escape(target_project.name)}/#{URI.escape(target_package_name)}"
    upload_path << Backend::Connection.build_query_from_hash(upload_params, [:user, :comment, :cmd, :noservice, :requestid])
    answer = Backend::Connection.post upload_path, "<directory> <entry name=\"_link\" md5=\"#{md5}\" /> </directory>"
    tpkg.sources_changed(dir_xml: answer)
  end

  def release_package_create_main_package(request, source_package, target_package_name, target_project)
    base_package_name = target_package_name.gsub(/\.[^\.]*$/, '')

    # only if package does not contain a _patchinfo file
    lpkg = nil
    if Package.exists_by_project_and_name(target_project.name, base_package_name, follow_project_links: false)
      lpkg = Package.get_by_project_and_name(target_project.name, base_package_name, use_source: false, follow_project_links: false)
    else
      lpkg = Package.new(name: base_package_name, title: source_package.title, description: source_package.description)
      target_project.packages << lpkg
      lpkg.store
    end
    upload_params = {
      user:    User.current.login,
      rev:     "repository",
      comment: "Set link to #{target_package_name} via maintenance_release request"
    }
    upload_path = "/source/#{URI.escape(target_project.name)}/#{URI.escape(base_package_name)}/_link"
    upload_path << Backend::Connection.build_query_from_hash(upload_params, [:user, :rev])
    link = "<link package='#{target_package_name}' cicount='copy' />\n"
    md5 = Digest::MD5.hexdigest(link)
    Backend::Connection.put upload_path, link
    # commit
    upload_params[:cmd] = 'commitfilelist'
    upload_params[:noservice] = '1'
    upload_params[:requestid] = request.number if request
    upload_path = "/source/#{URI.escape(target_project.name)}/#{URI.escape(base_package_name)}"
    upload_path << Backend::Connection.build_query_from_hash(upload_params, [:user, :comment, :cmd, :noservice, :requestid])
    answer = Backend::Connection.post upload_path, "<directory> <entry name=\"_link\" md5=\"#{md5}\" /> </directory>"
    lpkg.sources_changed(dir_xml: answer)
  end

  def release_package_copy_sources(action, source_package, target_package_name, target_project)
    # backend copy of current sources as full copy
    # that means the xsrcmd5 is different, but we keep the incident project anyway.
    cp_params = {
      cmd:            "copy",
      user:           User.current.login,
      oproject:       source_package.project.name,
      opackage:       source_package.name,
      comment:        "Release from #{source_package.project.name} / #{source_package.name}",
      expand:         "1",
      withvrev:       "1",
      noservice:      "1",
      withacceptinfo: "1"
    }
    cp_params[:requestid] = action.bs_request.number if action
    if target_project.is_maintenance_release? && source_package.is_link?
      # no permission check here on purpose
      if source_package.linkinfo['project'] == target_project.name &&
         source_package.linkinfo['package'] == target_package_name.gsub(/\.[^\.]*$/, '')
        # link target is equal to release target. So we freeze our link.
        cp_params[:freezelink] = 1
      end
    end
    cp_path = "/source/#{CGI.escape(target_project.name)}/#{CGI.escape(target_package_name)}"
    cp_path << Backend::Connection.build_query_from_hash(cp_params, [:cmd, :user, :oproject,
                                                                     :opackage, :comment, :requestid,
                                                                     :expand, :withvrev, :noservice,
                                                                     :freezelink, :withacceptinfo])
    result = Backend::Connection.post(cp_path)
    result = Xmlhash.parse(result.body)
    action.set_acceptinfo(result["acceptinfo"]) if action
  end

  def copy_binaries(filter_source_repository, source_package, target_package_name, target_project,
                    multibuild_container, setrelease)
    update_ids = []
    source_package.project.repositories.each do |source_repo|
      next if filter_source_repository && filter_source_repository != source_repo
      source_repo.release_targets.each do |releasetarget|
        # FIXME: filter given release and/or target repos here
        if releasetarget.target_repository.project == target_project
          u_id = copy_binaries_to_repository(source_repo, source_package, releasetarget.target_repository,
                                             target_package_name, multibuild_container, setrelease)
          update_ids << u_id if u_id
        end
        # remove maintenance release trigger in source
        if releasetarget.trigger == 'maintenance'
          releasetarget.trigger = nil
          releasetarget.save!
          source_repo.project.store
        end
      end
    end
    update_ids
  end

  def copy_binaries_to_repository(source_repository, source_package, target_repo, target_package_name,
                                  multibuild_container, setrelease)
    u_id = get_updateinfo_id(source_package, target_repo)
    source_package_name = source_package.name
    if multibuild_container.present?
      source_package_name << ":" << multibuild_container
      target_package_name = target_package_name.gsub(/:.*/, '') << ":" << multibuild_container
    end
    source_repository.architectures.each do |arch|
      # get updateinfo id in case the source package comes from a maintenance project
      copy_single_binary(arch, target_repo, source_package.project.name, source_package_name,
                         source_repository, target_package_name, u_id, setrelease)
    end
    u_id
  end

  def copy_single_binary(arch, target_repository, source_project_name, source_package_name, source_repo,
                         target_package_name, update_info_id, setrelease)
    cp_params = {
      cmd:         "copy",
      oproject:    source_project_name,
      opackage:    source_package_name,
      orepository: source_repo.name,
      user:        User.current.login,
      resign:      "1"
    }
    cp_params[:setupdateinfoid] = update_info_id if update_info_id
    cp_params[:setrelease] = setrelease if setrelease
    cp_params[:multibuild] = "1" unless source_package_name.include? ':'
    # rubocop:disable Metrics/LineLength
    cp_path = "/build/#{CGI.escape(target_repository.project.name)}/#{URI.escape(target_repository.name)}/#{URI.escape(arch.name)}/#{URI.escape(target_package_name)}"
    # rubocop:enable Metrics/LineLength
    cp_path << Backend::Connection.build_query_from_hash(cp_params, [:cmd, :oproject, :opackage,
                                                                     :orepository, :setupdateinfoid,
                                                                     :resign, :setrelease, :multibuild])
    Backend::Connection.post cp_path
  end

  def get_updateinfo_id(source_package, target_repo)
    return unless source_package.is_patchinfo?

    # check for patch name inside of _patchinfo file
    xml = Patchinfo.new.read_patchinfo_xmlhash(source_package)
    e = xml.elements("name")
    patch_name = e ? e.first : ""

    mi = MaintenanceIncident.find_by_db_project_id(source_package.project_id)
    return unless mi

    id_template = "%Y-%C"
    # check for a definition in maintenance project
    a = mi.maintenance_db_project.find_attribute('OBS', 'MaintenanceIdTemplate')
    if a
      id_template = a.values[0].value
    end

    # expand a possible defined update info template in release target of channel
    project_filter = nil
    prj = source_package.project.parent
    if prj && prj.is_maintenance?
      project_filter = prj.maintained_projects.map(&:project)
    end
    # prefer a channel in the source project to avoid double hits exceptions
    cts = ChannelTarget.find_by_repo(target_repo, [source_package.project])
    cts = ChannelTarget.find_by_repo(target_repo, project_filter) unless cts.any?
    first_ct = cts.first
    unless cts.all? { |c| c.id_template == first_ct.id_template }
      msg = cts.map { |cti| "#{cti.channel.package.project.name}/#{cti.channel.package.name}" }.join(", ")
      raise MultipleUpdateInfoTemplate, "Multiple channel targets found in #{msg} for repository #{target_repo.project.name}/#{target_repo.name}"
    end
    id_template = cts.first.id_template if cts.first && cts.first.id_template

    u_id = mi.getUpdateinfoId(id_template, patch_name)
    u_id
  end

  def create_package_container_if_missing(source_package, target_package_name, target_project)
    tpkg = nil
    if Package.exists_by_project_and_name(target_project.name, target_package_name, follow_project_links: false)
      tpkg = Package.get_by_project_and_name(target_project.name, target_package_name, use_source: false, follow_project_links: false)
    else
      tpkg = Package.new(name: target_package_name,
                         releasename: source_package.releasename,
                         title: source_package.title,
                         description: source_package.description)
      target_project.packages << tpkg
      if source_package.is_patchinfo?
        # publish patchinfos only
        tpkg.flags.create(flag: 'publish', status: 'enable')
      end
      tpkg.store
    end
    tpkg
  end

  def import_channel(channel, pkg, target_repo = nil)
    channel = REXML::Document.new(channel)

    if target_repo
      channel.elements['/channel'].add_element 'target', {
        "project"    => target_repo.project.name,
        "repository" => target_repo.name
      }
    end

    # replace all project definitions with update projects, if they are defined
    ['//binaries', '//binary'].each do |bin|
      channel.get_elements(bin).each do |b|
        attrib = b.attributes.get_attribute('project')
        prj = Project.get_by_name(attrib.to_s) if attrib
        if defined?(prj) && prj
          a = prj.find_attribute('OBS', 'UpdateProject')
          if a && a.values[0]
            b.attributes["project"] = a.values[0]
          end
        end
      end
    end

    query = { user: User.current_login }
    query[:comment] = "channel import function"
    Backend::Connection.put(pkg.source_path('_channel', query), channel.to_s)

    pkg.sources_changed
    # enforce updated channel list in database:
    pkg.update_backendinfo
  end

  def instantiate_container(project, opackage, opts = {})
    opkg = opackage.origin_container
    pkg_name = opkg.name
    if opkg.is_a?(Package) && opkg.project.is_maintenance_release?
      # strip incident suffix
      pkg_name = opkg.name.gsub(/\.[^\.]*$/, '')
    end

    # target packages must not exist yet
    if Package.exists_by_project_and_name(project.name, pkg_name, follow_project_links: false)
      raise PackageAlreadyExists, "package #{opkg.name} already exists"
    end
    opkg.find_project_local_linking_packages.each do |p|
      lpkg_name = p.name
      if p.is_a?(Package) && p.project.is_maintenance_release?
        # strip incident suffix
        lpkg_name = p.name.gsub(/\.[^\.]*$/, '')
      end
      if Package.exists_by_project_and_name(project.name, lpkg_name, follow_project_links: false)
        raise PackageAlreadyExists, "package #{p.name} already exists"
      end
    end

    pkg = project.packages.create(name: pkg_name, title: opkg.title, description: opkg.description)
    pkg.store

    arguments = "&noservice=1"
    arguments << "&requestid=" << opts[:request].number.to_s if opts[:request]
    arguments << "&comment=" << CGI.escape(opts[:comment]) if opts[:comment]
    if opts[:makeoriginolder]
      # rubocop:disable Metrics/LineLength
      # versioned copy
      path = pkg.source_path + "?cmd=copy&withvrev=1&oproject=#{CGI.escape(opkg.project.name)}&opackage=#{CGI.escape(opkg.name)}#{arguments}&user=#{CGI.escape(User.current.login)}&comment=initialize+package"
      # rubocop:enable Metrics/LineLength
      if Package.exists_by_project_and_name(project.name, opkg.name, allow_remote_packages: true)
        # a package exists via project link, make it older in any case
        path << "+and+make+source+instance+older&makeoriginolder=1"
      end
      Backend::Connection.post path
    else
      # rubocop:disable Metrics/LineLength
      # simple branch
      Backend::Connection.post pkg.source_path + "?cmd=branch&oproject=#{CGI.escape(opkg.project.name)}&opackage=#{CGI.escape(opkg.name)}#{arguments}&user=#{CGI.escape(User.current.login)}&comment=initialize+package+as+branch"
      # rubocop:enable Metrics/LineLength
    end
    pkg.sources_changed

    # and create the needed local links
    opkg.find_project_local_linking_packages.each do |p|
      lpkg_name = p.name
      if p.is_a?(Package) && p.project.is_maintenance_release?
        # strip incident suffix
        lpkg_name = p.name.gsub(/\.[^\.]*$/, '')
        # skip the base links
        next if lpkg_name == p.name
      end
      # create container
      unless project.packages.where(name: lpkg_name).exists?
        lpkg = project.packages.create(name: lpkg_name, title: p.title, description: p.description)
        lpkg.store
      end

      # rubocop:disable Metrics/LineLength
      # copy project local linked packages
      Backend::Connection.post "/source/#{pkg.project.name}/#{lpkg.name}?cmd=copy&oproject=#{CGI.escape(p.project.name)}&opackage=#{CGI.escape(p.name)}#{arguments}&user=#{CGI.escape(User.current.login)}"
      # rubocop:enable Metrics/LineLength
      # and fix the link
      ret = ActiveXML::Node.new(lpkg.source_file('_link'))
      ret.delete_attribute('project') # its a local link, project name not needed
      ret.set_attribute('package', pkg.name)
      Backend::Connection.put lpkg.source_path('_link', user: User.current.login), ret.dump_xml
      lpkg.sources_changed
    end
  end
end
