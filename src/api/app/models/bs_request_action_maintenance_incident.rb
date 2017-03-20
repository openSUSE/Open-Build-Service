#
class BsRequestActionMaintenanceIncident < BsRequestAction
  #### Includes and extends
  include RequestSourceDiff

  #### Constants

  #### Self config
  class NoMaintenanceReleaseTarget < APIException
    setup 'no_maintenance_release_target'
  end

  #### Attributes
  #### Associations macros (Belongs to, Has one, Has many)
  #### Callbacks macros: before_save, after_save, etc.
  #### Scopes (first the default_scope macro if is used)
  #### Validations macros

  #### Class methods using self. (public and then private)
  def self.sti_name
    :maintenance_incident
  end

  #### To define class methods as private use private_class_method
  #### private
  #### Instance methods (public and then protected/private)
  def is_maintenance_incident?
    true
  end

  def get_releaseproject(pkg, tprj)
    return if pkg.is_patchinfo?

    releaseproject = target_releaseproject ? Project.get_by_name(target_releaseproject) : tprj
    if releaseproject.try(:name).blank?
      raise NoMaintenanceReleaseTarget.new "Maintenance incident request contains no defined release" +
                                           " target project for package #{pkg.name}"
    end

    # Automatically switch to update project
    releaseproject = releaseproject.update_instance
    unless releaseproject.is_maintenance_release?
      raise NoMaintenanceReleaseTarget.new "Maintenance incident request contains release target " +
                                           "project #{releaseproject.name} with invalid project" +
                                           "kind \"#{releaseproject.kind}\" for package #{pkg.name}"
    end
    releaseproject
  end

  def sourcediff(opts = {})
    unless opts[:view] == "xml"
      # skip local links
      hash = Directory.hashed(project: source_project, package: source_package)
      return '' if hash['linkinfo'] && hash['linkinfo']['project'] == source_project
    end
    super(opts)
  end

  def _merge_pkg_into_maintenance_incident(incidentProject)
    # recreate package based on link target and throw everything away, except source changes
    # silently as maintenance teams requests ...
    new_pkg = nil

    # find link target
    dir_hash = Directory.hashed(project: source_project, package: source_package)
    linkinfo = dir_hash['linkinfo']
    if linkinfo && linkinfo['project'] == source_project
      # local link, skip it, it will come via branch command
      return
    end
    kinds = Package.detect_package_kinds(dir_hash)
    pkg_title = ""
    pkg_description = ""

    # patchinfos are handled as new packages
    if kinds.include? 'patchinfo'
      if Package.exists_by_project_and_name(incidentProject.name, source_package, follow_project_links: false)
        new_pkg = Package.get_by_project_and_name(incidentProject.name, source_package, use_source: false, follow_project_links: false)
      else
        new_pkg = incidentProject.packages.create!(name: source_package, title: pkg_title, description: pkg_description)
        new_pkg.flags.create!(status: 'enable', flag: 'build')
        new_pkg.flags.create(status: 'enable', flag: 'publish') unless incidentProject.flags.find_by_flag_and_status('access', 'disable')
        new_pkg.store(comment: "maintenance_incident request #{bs_request.number}", request: bs_request)
      end

      # use specified release project if defined
    elsif target_releaseproject
      package_name = source_package
      package_name = linkinfo['package'] if linkinfo

      branch_params = {target_project: incidentProject.name,
                       olinkrev: 'base',
                       requestid: bs_request.number,
                       maintenance: 1,
                       force: 1,
                       comment: 'Initial new branch from specified release project',
                       project: target_releaseproject, package: package_name}
      # accept branching from former update incidents or GM (for kgraft case)
      linkprj = Project.find_by_name(linkinfo['project']) if linkinfo
      if defined?(linkprj) && linkprj
        if linkprj.is_maintenance_incident? || linkprj != linkprj.update_instance || kinds.include?('channel')
          branch_params[:project] = linkinfo['project']
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
    elsif linkinfo && !linkinfo['missingok']
      # linked to an existing package in an external project
      linked_project = linkinfo['project']
      linked_package = linkinfo['package']

      branch_params = {target_project: incidentProject.name,
                       olinkrev: 'base',
                       requestid: bs_request.number,
                       maintenance: 1,
                       force: 1,
                       comment: 'Initial new branch',
                       project: linked_project, package: linked_package}
      ret = BranchPackage.new(branch_params).branch
      new_pkg = Package.get_by_project_and_name(ret[:data][:targetproject], ret[:data][:targetpackage])
    elsif linkinfo && linkinfo['package'] # a new package for all targets
      if Package.exists_by_project_and_name(incidentProject.name, source_package, follow_project_links: false)
        new_pkg = Package.get_by_project_and_name(incidentProject.name, source_package, use_source: false, follow_project_links: false)
      else
        new_pkg = Package.new(name: source_package, title: pkg.title, description: pkg.description)
        incidentProject.packages << new_pkg
        new_pkg.store(comment: "maintenance_incident request #{bs_request.number}", request: bs_request)
      end
    else
      # no link and not a patchinfo
      return # error out instead ?
    end

    # backend copy of submitted sources, but keep link
    cp_params = {
      cmd:            "copy",
      user:           User.current.login,
      oproject:       source_project,
      opackage:       source_package,
      requestid:      bs_request.number,
      keeplink:       1,
      expand:         1,
      withacceptinfo: 1,
      comment:        "Maintenance incident copy from project #{source_project}"
    }
    cp_params[:orev] = source_rev if source_rev
    cp_path = "/source/#{CGI.escape(incidentProject.name)}/#{CGI.escape(new_pkg.name)}"
    cp_path << Suse::Backend.build_query_from_hash(cp_params, [:cmd, :user, :oproject, :opackage,
                                                               :orev, :keeplink, :expand, :comment,
                                                               :requestid, :withacceptinfo])
    result = Suse::Backend.post cp_path
    result = Xmlhash.parse(result.body)
    set_acceptinfo(result["acceptinfo"])

    new_pkg.sources_changed
    new_pkg
  end

  def merge_into_maintenance_incident(incidentProject)
    # copy all or selected packages and project source files from base project
    # we don't branch from it to keep the link target.
    pkg = _merge_pkg_into_maintenance_incident(incidentProject)

    incidentProject.save!
    incidentProject.store(comment: "maintenance_incident request #{bs_request.number}", request: bs_request)
    pkg
  end

  def execute_accept(opts)
    # create or merge into incident project
    incident_project = Project.get_by_name(target_project)

    # the incident got created before
    self.target_package = merge_into_maintenance_incident(incident_project)

    # update action with real target project
    self.target_project = incident_project.name

    if sourceupdate == 'cleanup'
      source_cleanup
    end

    # create a patchinfo if missing and incident has just been created
    if opts[:check_for_patchinfo] && !incident_project.packages.joins(:package_kinds).where("kind = 'patchinfo'").exists?
      Patchinfo.new.create_patchinfo_from_request(incident_project, bs_request)
    end

    save
  end

  def expand_targets(ignore_build_state)
    # find maintenance project
    maintenanceProject = nil
    if target_project
      maintenanceProject = Project.get_by_name target_project
    else
      maintenanceProject = Project.get_maintenance_project
      self.target_project = maintenanceProject.name
    end
    unless maintenanceProject.is_maintenance_incident? || maintenanceProject.is_maintenance?
      raise NoMaintenanceProject.new 'Maintenance incident requests have to go to projects of type maintenance or maintenance_incident'
    end
    raise IllegalRequest.new 'Target package must not be specified in maintenance_incident actions' if target_package
    super(ignore_build_state)
  end

  #### Alias of methods
end

# == Schema Information
#
# Table name: bs_request_actions
#
#  id                    :integer          not null, primary key
#  bs_request_id         :integer          indexed
#  type                  :string(255)
#  target_project        :string(255)      indexed
#  target_package        :string(255)      indexed
#  target_releaseproject :string(255)
#  source_project        :string(255)      indexed
#  source_package        :string(255)      indexed
#  source_rev            :string(255)
#  sourceupdate          :string(255)
#  updatelink            :boolean          default(FALSE)
#  person_name           :string(255)
#  group_name            :string(255)
#  role                  :string(255)
#  created_at            :datetime
#  target_repository     :string(255)
#  makeoriginolder       :boolean          default(FALSE)
#
# Indexes
#
#  bs_request_id                               (bs_request_id)
#  index_bs_request_actions_on_source_package  (source_package)
#  index_bs_request_actions_on_source_project  (source_project)
#  index_bs_request_actions_on_target_package  (target_package)
#  index_bs_request_actions_on_target_project  (target_project)
#
# Foreign Keys
#
#  bs_request_actions_ibfk_1  (bs_request_id => bs_requests.id)
#
