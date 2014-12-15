class BsRequestActionMaintenanceIncident < BsRequestAction

  include SubmitRequestSourceDiff

  def is_maintenance_incident?
    true
  end

  def self.sti_name
    return :maintenance_incident
  end

  class NoMaintenanceReleaseTarget < APIException
    setup 'no_maintenance_release_target'
  end

  def get_releaseproject(pkg, tprj)
    return nil if pkg.is_patchinfo?
    releaseproject = nil
    if self.target_releaseproject
      releaseproject = Project.get_by_name self.target_releaseproject
    else
      if !tprj
        raise NoMaintenanceReleaseTarget.new "Maintenance incident request contains no defined release target project for package #{pkg.name}"
      end
      releaseproject = tprj
    end
    # Automatically switch to update project
    releaseproject = releaseproject.update_instance
    unless releaseproject.is_maintenance_release?
      raise NoMaintenanceReleaseTarget.new "Maintenance incident request contains release target project #{releaseproject.name} with invalid project kind \"#{releaseproject.project_type}\" for package #{pkg.name}"
    end
    return releaseproject
  end


  def merge_into_maintenance_incident(incidentProject, base, releaseproject=nil, request=nil)

    # copy all or selected packages and project source files from base project
    # we don't branch from it to keep the link target.
    packages = nil
    if base.class == Project
      packages = base.packages
    else
      packages = [base]
    end

    packages.each do |pkg|
      # recreate package based on link target and throw everything away, except source changes
      # silently as maintenance teams requests ...
      new_pkg = nil

      # find link target
      data = REXML::Document.new(Suse::Backend.get("/source/#{CGI.escape(pkg.project.name)}/#{CGI.escape(pkg.name)}").body)
      e = data.elements['directory/linkinfo']
      if e and e.attributes['project'] == pkg.project.name
        # local link, skip it, it will come via branch command
        next
      end
      # patchinfos are handled as new packages
      if pkg.is_patchinfo?
        if Package.exists_by_project_and_name(incidentProject.name, pkg.name, follow_project_links: false)
          new_pkg = Package.get_by_project_and_name(incidentProject.name, pkg.name, use_source: false, follow_project_links: false)
        else
          new_pkg = incidentProject.packages.create(:name => pkg.name, :title => pkg.title, :description => pkg.description)
          new_pkg.flags.create(:status => 'enable', :flag => 'build')
          new_pkg.flags.create(:status => 'enable', :flag => 'publish') unless incidentProject.flags.find_by_flag_and_status('access', 'disable')
          new_pkg.store
        end

        # use specified release project if defined
      elsif releaseproject
        package_name = pkg.name
        package_name = e.attributes['package'] if e

        branch_params = {:target_project => incidentProject.name,
                         :maintenance => 1,
                         :force => 1,
                         :comment => 'Initial new branch',
                         :project => releaseproject, :package => package_name}
        branch_params[:requestid] = request.id if request
        # accept branching from former update incidents or GM (for kgraft case)
        if e and linkprj = Project.find_by_name(e.attributes['project'])
          if linkprj.is_maintenance_incident? or linkprj != linkprj.update_instance or pkg.is_channel?
            branch_params[:project] = e.attributes['project']
            branch_params[:ignoredevel] = "1"
          end
        end
        # it is fine to have new packages
        unless Package.exists_by_project_and_name(branch_params[:project], package_name, follow_project_links: true)
          branch_params[:missingok] = 1
        end
        ret = BranchPackage.new(branch_params).branch
        new_pkg = Package.get_by_project_and_name(ret[:data][:targetproject], ret[:data][:targetpackage])

        # use link target as fallback
      elsif e and not e.attributes['missingok']
        # linked to an existing package in an external project 
        linked_project = e.attributes['project']
        linked_package = e.attributes['package']

        branch_params = {:target_project => incidentProject.name,
                         :maintenance => 1,
                         :force => 1,
                         :project => linked_project, :package => linked_package}
        branch_params[:requestid] = request.id if request
        ret = BranchPackage.new(branch_params).branch
        new_pkg = Package.get_by_project_and_name(ret[:data][:targetproject], ret[:data][:targetpackage])
      else

        # a new package for all targets
        if e and e.attributes['package']
          if Package.exists_by_project_and_name(incidentProject.name, pkg.name, follow_project_links: false)
            new_pkg = Package.get_by_project_and_name(incidentProject.name, pkg.name, use_source: false, follow_project_links: false)
          else
            new_pkg = Package.new(:name => pkg.name, :title => pkg.title, :description => pkg.description)
            incidentProject.packages << new_pkg
            new_pkg.store
          end
        else
          # no link and not a patchinfo
          next # error out instead ?
        end
      end

      # backend copy of current sources, but keep link
      cp_params = {
          :cmd => 'copy',
          :user => User.current.login,
          :oproject => pkg.project.name,
          :opackage => pkg.name,
          :keeplink => 1,
          :expand => 1,
          :comment => 'Maintenance incident copy from project ' + pkg.project.name
      }
      cp_params[:requestid] = request.id if request
      cp_path = "/source/#{CGI.escape(incidentProject.name)}/#{CGI.escape(new_pkg.name)}"
      cp_path << Suse::Backend.build_query_from_hash(cp_params, [:cmd, :user, :oproject, :opackage, :keeplink, :expand, :comment, :requestid])
      Suse::Backend.post cp_path, nil

      new_pkg.sources_changed
    end

    incidentProject.save!
    incidentProject.store
  end

  def execute_accept(opts)
    # create or merge into incident project
    source = nil
    if self.source_package
      source = Package.get_by_project_and_name(self.source_project, self.source_package)
    else
      source = Project.get_by_name(self.source_project)
    end

    incident_project = Project.get_by_name(self.target_project)

    # the incident got created before
    merge_into_maintenance_incident(incident_project, source, self.target_releaseproject, self.bs_request)

    # update action with real target project
    self.target_project = incident_project.name

    if self.sourceupdate == 'cleanup'
      self.source_cleanup
    end

    # create a patchinfo if missing and incident has just been created
    if opts[:check_for_patchinfo] and !incident_project.packages.joins(:package_kinds).where("kind = 'patchinfo'").exists?
      Patchinfo.new.create_patchinfo_from_request(incident_project, self.bs_request)
    end

  end

  def expand_targets(ignore_build_state)
    # find maintenance project
    maintenanceProject = nil
    if self.target_project
      maintenanceProject = Project.get_by_name self.target_project
    else
      maintenanceProject = Project.get_maintenance_project
      self.target_project = maintenanceProject.name
    end
    unless maintenanceProject.is_maintenance_incident? or maintenanceProject.is_maintenance?
      raise NoMaintenanceProject.new 'Maintenance incident requests have to go to projects of type maintenance or maintenance_incident'
    end
    super(ignore_build_state)
  end

end
