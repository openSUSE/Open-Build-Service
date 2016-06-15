require 'api_exception'

class BsRequestAction < ActiveRecord::Base
  #### Includes and extends
  include ParsePackageDiff

  #### Constants
  VALID_SOURCEUPDATE_OPTIONS = ['update', 'noupdate', 'cleanup']

  #### Self config
  class DiffError < APIException; setup 404; end  # a diff error can have many reasons, but most likely something within us
  class RemoteSource < APIException; end
  class RemoteTarget < APIException; end
  class InvalidReleaseTarget < APIException; end
  class LackingMaintainership < APIException
    setup 'lacking_maintainership', 403, 'Creating a submit request action with options requires maintainership in source package'
  end
  class NoMaintenanceProject < APIException; end
  class UnknownAttribute < APIException; setup 404; end
  class IncidentHasNoMaintenanceProject < APIException; end
  class NotSupported < APIException; end
  class SubmitRequestRejected < APIException; end
  class RequestRejected < APIException; setup 403; end
  class UnknownProject < APIException; setup 404; end
  class UnknownRole < APIException; setup 404; end
  class IllegalRequest < APIException; end
  class BuildNotFinished < APIException; end
  class UnknownTargetProject < APIException; end
  class UnknownTargetPackage < APIException; end
  class WrongLinkedPackageSource < APIException; end
  class MissingPatchinfo < APIException; end
  class VersionReleaseDiffers < APIException; end

  #### Attributes

  #### Associations macros (Belongs to, Has one, Has many)
  belongs_to :bs_request
  has_one :bs_request_action_accept_info, :dependent => :delete

  #### Callbacks macros: before_save, after_save, etc.
  #### Scopes (first the default_scope macro if is used)

  #### Validations macros
  validates_inclusion_of :sourceupdate, :in => VALID_SOURCEUPDATE_OPTIONS, :allow_nil => true
  validate :check_sanity

  #### Class methods using self. (public and then private)

  def self.get_package_diff(path, query)
    path += "?#{query.to_query}"
    begin
      Suse::Backend.post(path, '', 'Timeout' => 30).body
    rescue Timeout::Error
      raise DiffError.new("Timeout while diffing #{path}")
    rescue ActiveXML::Transport::Error => e
      raise DiffError.new("The diff call for #{path} failed: #{e.summary}")
    end
  end

  def self.type_to_class_name(type_name)
    case type_name
    when :submit then
      BsRequestActionSubmit
    when :delete then
      BsRequestActionDelete
    when :change_devel then
      BsRequestActionChangeDevel
    when :add_role then
      BsRequestActionAddRole
    when :set_bugowner then
      BsRequestActionSetBugowner
    when :maintenance_incident then
      BsRequestActionMaintenanceIncident
    when :maintenance_release then
      BsRequestActionMaintenanceRelease
    when :group then
      BsRequestActionGroup
    end
  end

  def self.find_sti_class(type_name)
    return super if type_name.nil?
    type_to_class_name(type_name.to_sym) || super
  end

  def self.new_from_xml_hash(hash)
    classname = type_to_class_name(hash.delete('type').to_sym)

    # request actions of type group were official never supported
    # but there is build.opensuse.org which contains quite some of these
    # requests. However, it is not used there anymore, so dis-allow to create
    # new requests. But we do validate that the code is still working.
    # FIXME3.0: drop this code and drop these actions from database.
    raise ArgumentError, "request actions of type group can not be created anymore" if classname == BsRequestActionGroup and not Rails.env.test?

    if classname
      a = classname.new
    else
      raise ArgumentError, 'unknown type'
    end

    # now remove things from hash
    a.store_from_xml(hash)

    raise ArgumentError, "too much information #{hash.inspect}" unless hash.blank?

    a
  end

  #### To define class methods as private use private_class_method
  #### private

  #### Instance methods (public and then protected/private)
  def minimum_priority
    nil
  end

  def check_sanity
    if [:submit, :maintenance_incident, :maintenance_release, :change_devel].include? action_type
      errors.add(:source_project, "should not be empty for #{action_type} requests") if source_project.blank?
      if !is_maintenance_incident?
        errors.add(:source_package, "should not be empty for #{action_type} requests") if source_package.blank?
      end
      errors.add(:target_project, "should not be empty for #{action_type} requests") if target_project.blank?
      if source_package == target_package and source_project == target_project
        if self.sourceupdate or self.updatelink
          errors.add(:target_package, 'No source changes are allowed, if source and target is identical')
        end
      end
    end
    errors.add(:target_package, 'is invalid package name') if target_package && !Package.valid_name?(target_package)
    errors.add(:source_package, 'is invalid package name') if source_package && !Package.valid_name?(source_package)
    errors.add(:target_project, 'is invalid project name') if target_project && !Project.valid_name?(target_project)
    errors.add(:source_project, 'is invalid project name') if source_project && !Project.valid_name?(source_project)

    # TODO to be continued
  end

  def action_type
    self.class.sti_name
  end

  # convenience functions to check types
  def is_submit?
    false
  end

  def is_maintenance_release?
    false
  end

  def is_maintenance_incident?
    false
  end

  def matches_package?(source_or_target, pkg)
    (self.send("#{source_or_target}_project") == pkg.project.name) and
        (self.send("#{source_or_target}_package") == pkg.name)
  end

  def store_from_xml(hash)
    source = hash.delete('source')
    if source
      self.source_package = source.delete('package')
      self.source_project = source.delete('project')
      self.source_rev = source.delete('rev')

      raise ArgumentError, "too much information #{source.inspect}" unless source.blank?
    end

    target = hash.delete('target')
    if target
      self.target_package = target.delete('package')
      self.target_project = target.delete('project')
      self.target_releaseproject = target.delete('releaseproject')
      self.target_repository = target.delete('repository')

      raise ArgumentError, "too much information #{target.inspect}" unless target.blank?
    end

    ai = hash.delete('acceptinfo')
    if ai
      self.bs_request_action_accept_info = BsRequestActionAcceptInfo.new
      self.bs_request_action_accept_info.rev = ai.delete('rev')
      self.bs_request_action_accept_info.srcmd5 = ai.delete('srcmd5')
      self.bs_request_action_accept_info.osrcmd5 = ai.delete('osrcmd5')
      self.bs_request_action_accept_info.xsrcmd5 = ai.delete('xsrcmd5')
      self.bs_request_action_accept_info.oxsrcmd5 = ai.delete('oxsrcmd5')

      raise ArgumentError, "too much information #{ai.inspect}" unless ai.blank?
    end

    o = hash.delete('options')
    if o
      self.sourceupdate = o.delete('sourceupdate')
      # old form
      self.sourceupdate = 'update' if self.sourceupdate == '1'
      # there is mess in old data ;(
      self.sourceupdate = nil unless VALID_SOURCEUPDATE_OPTIONS.include? self.sourceupdate

      self.updatelink = true if o.delete('updatelink') == 'true'
      self.makeoriginolder = o.delete('makeoriginolder')
      raise ArgumentError, "too much information #{s.inspect}" unless o.blank?
    end

    p = hash.delete('person')
    if p
      self.person_name = p.delete('name') { raise ArgumentError, 'a person without name' }
      self.role = p.delete('role')
      raise ArgumentError, "too much information #{p.inspect}" unless p.blank?
    end

    g = hash.delete('group')
    if g
      self.group_name = g.delete('name') { raise ArgumentError, 'a group without name' }
      raise ArgumentError, 'role already taken' if self.role
      self.role = g.delete('role')
      raise ArgumentError, "too much information #{g.inspect}" unless g.blank?
    end
  end

  def xml_package_attributes(source_or_target)
    attributes = {}
    value = self.send "#{source_or_target}_project"
    attributes[:project] = value unless value.blank?
    value = self.send "#{source_or_target}_package"
    attributes[:package] = value unless value.blank?
    attributes
  end

  def render_xml_source(node)
    attributes = xml_package_attributes('source')
    attributes[:rev] = self.source_rev unless self.source_rev.blank?
    node.source attributes
  end

  def render_xml_target(node)
    attributes = xml_package_attributes('target')
    attributes[:releaseproject] = self.target_releaseproject unless self.target_releaseproject.blank?
    node.target attributes
  end

  def render_xml_attributes(node)
    if [:submit, :maintenance_incident, :maintenance_release, :change_devel].include? self.action_type
      render_xml_source(node)
      render_xml_target(node)
    end
  end

  def render_xml(builder)
    builder.action :type => self.action_type do |action|
      render_xml_attributes(action)
      if self.sourceupdate || self.updatelink || self.makeoriginolder
        action.options do
          action.sourceupdate self.sourceupdate if self.sourceupdate
          action.updatelink 'true' if self.updatelink
          action.makeoriginolder 'true' if self.makeoriginolder
        end
      end
      bs_request_action_accept_info.render_xml(builder) unless bs_request_action_accept_info.nil?
    end
  end

  def set_acceptinfo(ai)
    self.bs_request_action_accept_info = BsRequestActionAcceptInfo.create(ai)
  end

  def notify_params(ret = {})
    ret[:action_id] = self.id
    ret[:type] = self.action_type.to_s
    ret[:sourceproject] = self.source_project
    ret[:sourcepackage] = self.source_package
    ret[:sourcerevision] = self.source_rev
    ret[:person] = self.person_name
    ret[:group] = self.group_name
    ret[:role] = self.role
    ret[:targetproject] = self.target_project
    ret[:targetpackage] = self.target_package
    ret[:targetrepository] = self.target_repository
    ret[:target_releaseproject] = self.target_releaseproject
    ret[:sourceupdate] = self.sourceupdate
    ret[:makeoriginolder] = self.makeoriginolder

    if self.action_type == :change_devel
      ret[:targetpackage] ||= self.source_package
    end

    ret.keys.each do |k|
      ret.delete(k) if ret[k].nil?
    end
    ret
  end

  def contains_change?
    begin
      return !sourcediff().blank?
    rescue BsRequestAction::DiffError
      # if the diff can'be created we can't say
      # but let's assume the reason for the problem lies in the change
      return true
    end
  end

  def sourcediff(_opts = {})
    ''
  end

  def webui_infos
    begin
      sd = self.sourcediff(view: 'xml', withissues: true)
    rescue DiffError, Project::UnknownObjectError, Package::UnknownObjectError => e
      return [{ error: e.message }]
    end
    diff = sorted_filenames_from_sourcediff(sd)
    if diff[0].empty?
      nil
    else
      diff
    end
  end

  def default_reviewers
    reviews = []
    return reviews unless self.target_project

    tprj = Project.get_by_name self.target_project
    if tprj.class == String
      raise RemoteTarget.new 'No support to target to remote projects. Create a request in remote instance instead.'
    end
    tpkg = nil
    if self.target_package
      if self.is_maintenance_release?
        # use orignal/stripped name and also GA projects for maintenance packages.
        # But do not follow project links, if we have a branch target project, like in Evergreen case
        if tprj.find_attribute('OBS', 'BranchTarget')
          tpkg = tprj.packages.find_by_name self.target_package.gsub(/\.[^\.]*$/, '')
        else
          tpkg = tprj.find_package self.target_package.gsub(/\.[^\.]*$/, '')
        end
      elsif [:set_bugowner, :add_role, :change_devel, :delete].include? self.action_type
        # target must exists
        tpkg = tprj.packages.find_by_name! self.target_package
      else
        # just the direct affected target
        tpkg = tprj.packages.find_by_name self.target_package
      end
    else
      if self.source_package
        tpkg = tprj.packages.find_by_name self.source_package
      end
    end

    if self.source_project
      # if the user is not a maintainer if current devel package, the current maintainer gets added as reviewer of this request
      if self.action_type == :change_devel and tpkg.develpackage and not User.current.can_modify_package?(tpkg.develpackage, 1)
        reviews.push(tpkg.develpackage)
      end

      if !self.is_maintenance_release?
        # Creating requests from packages where no maintainer right exists will enforce a maintainer review
        # to avoid that random people can submit versions without talking to the maintainers
        # projects may skip this by setting OBS:ApprovedRequestSource attributes
        if self.source_package
          spkg = Package.find_by_project_and_name self.source_project, self.source_package
          if spkg and not User.current.can_modify_package? spkg
            if self.action_type == :submit
              if self.sourceupdate or self.updatelink
                # FIXME: completely misplaced in this function
                raise LackingMaintainership.new
              end
            end
            if  not spkg.project.find_attribute('OBS', 'ApprovedRequestSource') and
                not spkg.find_attribute('OBS', 'ApprovedRequestSource')
              reviews.push(spkg)
            end
          end
        else
          sprj = Project.find_by_name self.source_project
          if sprj and not User.current.can_modify_project? sprj and not sprj.find_attribute('OBS', 'ApprovedRequestSource')
            if self.action_type == :submit
              if self.sourceupdate or self.updatelink
                raise LackingMaintainership.new
              end
            end
            if  not sprj.find_attribute('OBS', 'ApprovedRequestSource')
              reviews.push(sprj)
            end
          end
        end
      end
    end

    # find reviewers in target package
    if tpkg
      reviews += find_reviewers(tpkg)
    end
    # project reviewers get added additionaly - might be dups
    if tprj
      reviews += find_reviewers(tprj)
    end

    return reviews.uniq
  end

  #
  # find default reviewers of a project/package via role
  #
  def find_reviewers(obj)
    # obj can be a project or package object
    reviewers = []

    reviewer_id = Role.rolecache['reviewer'].id

    # check for reviewers in a package first
    if obj.class == Project
      obj.relationships.users.where(role_id: reviewer_id).pluck(:user_id).each do |r|
        reviewers << User.find(r)
      end
      obj.relationships.groups.where(role_id: reviewer_id).pluck(:group_id).each do |r|
        reviewers << Group.find(r)
      end
    elsif obj.class == Package
      obj.relationships.users.where(role_id: reviewer_id).pluck(:user_id).each do |r|
        reviewers << User.find(r)
      end
      obj.relationships.groups.where(role_id: reviewer_id).pluck(:group_id).each do |r|
        reviewers << Group.find(r)
      end
      reviewers += find_reviewers(obj.project)
    end

    return reviewers
  end

  def request_changes_state(_state)
    # only groups care for now
  end

  def get_releaseproject(_pkg, _tprj)
    # only needed for maintenance incidents
    nil
  end

  def execute_accept(_opts)
    raise 'Needs to be reimplemented in subclass'
  end

  # after all actions are executed, the controller calls into every action a cleanup
  # the actions can "cache" in the opts their state to avoid duplicated work
  def per_request_cleanup(_opts)
    # does nothing by default
  end

  # this is called per action once it's verified that all actions in a request are
  # permitted.
  def create_post_permissions_hook(_opts)
    # does nothing by default
  end

  # general source cleanup, used in submit and maintenance_incident actions
  def source_cleanup
    source_project = Project.find_by_name(self.source_project)
    return unless source_project
    if (source_project.packages.count == 1 and ::Configuration.cleanup_empty_projects) or !self.source_package

      # remove source project, if this is the only package and not a user's home project
      splits = self.source_project.split(':')
      return nil if splits.count == 2 && splits[0] == 'home'

      source_project.commit_opts = { comment: self.bs_request.description, request: self.bs_request }
      source_project.destroy
      return "/source/#{self.source_project}"
    end
    # just remove one package
    source_package = source_project.packages.find_by_name!(self.source_package)
    source_package.commit_opts = { comment: self.bs_request.description, request: self.bs_request }
    source_package.destroy
    return Package.source_path(self.source_project, self.source_package)
  end

  def check_maintenance_release(pkg, repo, arch)
    # rubocop:disable Metrics/LineLength
    binaries = Xmlhash.parse(Suse::Backend.get("/build/#{URI.escape(pkg.project.name)}/#{URI.escape(repo.name)}/#{URI.escape(arch.name)}/#{URI.escape(pkg.name)}").body)
    # rubocop:enable Metrics/LineLength
    l = binaries.elements('binary')
    unless l and l.count > 0
      raise BuildNotFinished.new "patchinfo #{pkg.name} is not yet build for repository '#{repo.name}'"
    end

    # check that we did not skip a source change of patchinfo
    data = Directory.hashed(project: pkg.project.name, package: pkg.name, expand: 1)
    verifymd5 = data['srcmd5']
    # rubocop:disable Metrics/LineLength
    history = Xmlhash.parse(Suse::Backend.get("/build/#{URI.escape(pkg.project.name)}/#{URI.escape(repo.name)}/#{URI.escape(arch.name)}/#{URI.escape(pkg.name)}/_history").body)
    # rubocop:enable Metrics/LineLength
    last = history.elements('entry').last
    unless last and last['srcmd5'].to_s == verifymd5.to_s
      raise BuildNotFinished.new "last patchinfo #{pkg.name} is not yet build for repository '#{repo.name}'"
    end
  end

  def create_expand_package(packages, opts = {})
    newactions = Array.new
    incident_suffix = ''
    if self.is_maintenance_release?
      # The maintenance ID is always the sub project name of the maintenance project
      incident_suffix = '.' + self.source_project.gsub(/.*:/, '')
    end

    found_patchinfo = false
    newPackages = Array.new
    newTargets = Array.new

    packages.each do |pkg|
      unless pkg.kind_of? Package
        raise RemoteSource.new 'No support for auto expanding from remote instance. You need to submit a full specified request in that case.'
      end
      # find target via linkinfo or submit to all.
      # FIXME: this is currently handling local project links for packages with multiple spec files.
      #        This can be removed when we handle this as shadow packages in the backend.
      tpkg = ltpkg    = pkg.name
      rev             = self.source_rev
      data            = nil
      missing_ok_link = false
      suffix          = ''
      tprj            = pkg.project
      while tprj == pkg.project
        data = Directory.hashed(project: tprj.name, package: ltpkg)
        e = data['linkinfo']
        if e
          suffix = ltpkg.gsub(/^#{Regexp.escape(e['package'])}/, '')
          ltpkg = e['package']
          tprj = Project.get_by_name(e['project'])
          missing_ok_link=true if e['missingok']
        else
          tprj = nil
        end
      end
      tpkg = tpkg.gsub(/#{Regexp.escape(suffix)}$/, '') # strip distro specific extension
      tpkg = self.target_package if self.target_package # already given

      # maintenance incident actions need a releasetarget
      releaseproject = self.get_releaseproject(pkg, tprj)

      # overwrite target if defined
      tprj = Project.get_by_name(self.target_project) if self.target_project
      raise UnknownTargetProject.new 'target project does not exist' unless tprj or self.is_maintenance_release?

      # do not allow release requests without binaries
      if self.is_maintenance_release? and pkg.is_patchinfo? and data and !opts[:ignore_build_state]
        # check for build state and binaries
        state = REXML::Document.new(Suse::Backend.get("/build/#{URI.escape(pkg.project.name)}/_result?view=versrel").body)
        results = state.get_elements("/resultlist/result[@project='#{pkg.project.name}'')]")
        unless results
          raise BuildNotFinished.new "The project'#{pkg.project.name}' has no building repositories"
        end
        versrel={}
        results.each do |result|
          repo = result.attributes['repository']
          arch = result.attributes['arch']
          if result.attributes['dirty']
            raise BuildNotFinished.new "The repository '#{pkg.project.name}' / '#{repo}' / #{arch} " +
                                       "needs recalculation by the schedulers"
          end
          if %w(finished publishing).include? result.attributes['state']
            raise BuildNotFinished.new "The repository '#{pkg.project.name}' / '#{repo}' / #{arch}" +
                                       "did not finish the publish yet"
          end
          unless %w(published unpublished).include? result.attributes['state']
            raise BuildNotFinished.new "The repository '#{pkg.project.name}' / '#{repo}' / #{arch} " +
                                       "did not finish the build yet"
          end

          # all versrel are the same
          versrel[repo] ||= {}
          result.get_elements("status").each do |status|
            package = status.attributes['package']
            vrel = status.attributes['versrel']
            next unless vrel
            if versrel[repo][package] and versrel[repo][package] != vrel
              raise VersionReleaseDiffers.new "#{package} has a different version release in same repository"
            end
            versrel[repo][package] ||= vrel
          end
        end

        pkg.project.repositories.each do |repo|
          next unless repo
          firstarch=repo.architectures.first
          next unless firstarch

          # skip excluded patchinfos
          status = state.get_elements("/resultlist/result[@repository='#{repo.name}' and @arch='#{firstarch.name}']").first
          next if status and (s=status.get_elements("status[@package='#{pkg.name}']").first) and s.attributes['code'] == 'excluded'
          raise BuildNotFinished.new "patchinfo #{pkg.name} is broken" if s.attributes['code'] == 'broken'

          check_maintenance_release(pkg, repo, firstarch)

          found_patchinfo = true
        end

      end

      # re-route (for the kgraft case building against GM or former incident)
      if self.is_maintenance_release? and tprj
        tprj = tprj.update_instance
        if tprj.is_maintenance_incident?
          release_target = nil
          pkg.project.repositories.includes(:release_targets).each do |repo|
            repo.release_targets.each do |rt|
              next if rt.trigger != "maintenance"
              next unless rt.target_repository.project.is_maintenance_release?
              if release_target && release_target != rt.target_repository.project
                raise InvalidReleaseTarget.new "Multiple release target projects are not supported"
              end
              release_target = rt.target_repository.project
            end
          end
          raise InvalidReleaseTarget.new "Can not release to a maintenance incident project" unless release_target
          tprj = release_target
        end
      end

      # Will this be a new package ?
      unless missing_ok_link
        unless e and tprj and tprj.exists_package?(tpkg, follow_project_links: true, allow_remote_packages: false)
          if self.is_maintenance_release?
            pkg.project.repositories.includes(:release_targets).each do |repo|
              repo.release_targets.each do |rt|
                newTargets << rt.target_repository.project.name
              end
            end
            newPackages << pkg
            next
          elsif !is_maintenance_incident? and !is_submit?
            raise UnknownTargetPackage.new 'target package does not exist'
          end
        end
      end

      newAction = self.dup
      newAction.source_package = pkg.name
      if self.is_maintenance_incident?
        newTargets << tprj.name if tprj
        newAction.target_releaseproject = releaseproject.name if releaseproject
      elsif not pkg.is_channel?
        newTargets << tprj.name
        newAction.target_project = tprj.name
        newAction.target_package = tpkg + incident_suffix
      end
      newAction.source_rev = rev if rev
      if self.is_maintenance_release?
        if pkg.is_channel?
          # create submit request for possible changes in the _channel file
          submitAction = BsRequestActionSubmit.new
          submitAction.source_project = newAction.source_project
          submitAction.source_package = newAction.source_package
          submitAction.source_rev = newAction.source_rev
          submitAction.target_project = tprj.name
          submitAction.target_package = tpkg
          # replace the new action
          newAction.destroy
          newAction = submitAction
        else # non-channel package
          next if ReleaseTarget.where(repository: pkg.project.repositories, target_repository: tprj.repositories, trigger: "maintenance").count < 1
          unless pkg.project.can_be_released_to_project?(tprj)
            raise WrongLinkedPackageSource.new "According to the source link of package " +
                                               "#{pkg.project.name}/#{pkg.name} it would go to project" +
                                               "#{tprj.name} which is not specified as release target."
          end
        end
      end
      # no action, nothing to do
      next unless newAction
      # check if the source contains really a diff or we can skip the entire action
      if [:submit, :maintenance_incident].include? newAction.action_type and !newAction.contains_change?
        # submit contains no diff, drop it again
        newAction.destroy
      else
        newactions << newAction
      end
    end
    if self.is_maintenance_release? and !found_patchinfo and !opts[:ignore_build_state]
      raise MissingPatchinfo.new 'maintenance release request without patchinfo would release no binaries'
    end

    # new packages (eg patchinfos) go to all target projects by default in maintenance requests
    newTargets.uniq!
    newPackages.uniq!
    newPackages.each do |pkg|
      releaseTargets=nil
      if pkg.is_patchinfo?
        releaseTargets = Patchinfo.new.fetch_release_targets(pkg)
      end
      newTargets.each do |p|
        unless releaseTargets.blank?
          found=false
          releaseTargets.each do |rt|
            if rt['project'] == p
              found=true
              break
            end
          end
          next unless found
        end

        # rubocop:disable Metrics/LineLength
        # skip if there is no active maintenance trigger for this package
        next if self.is_maintenance_release? and ReleaseTarget.where(repository: pkg.project.repositories, target_repository: Project.find_by_name(p).repositories, trigger: "maintenance").count < 1
        # rubocop:enable Metrics/LineLength

        newAction = self.dup
        newAction.source_package = pkg.name
        unless self.is_maintenance_incident?
          newAction.target_project = p
          newAction.target_package = pkg.name + incident_suffix
        end
        newactions << newAction
      end
    end

    return newactions
  end

  def check_action_permission_source!
    return nil unless self.source_project

    sprj = Project.get_by_name self.source_project
    unless sprj
      raise UnknownProject.new "Unknown source project #{self.source_project}"
    end
    unless sprj.class == Project or [:submit, :maintenance_incident].include? self.action_type
      raise NotSupported.new "Source project #{self.source_project} is not a local project. This is not supported yet."
    end
    if self.source_package
      spkg = Package.get_by_project_and_name(self.source_project, self.source_package, use_source: true, follow_project_links: true)
      spkg.check_weak_dependencies! if spkg && self.sourceupdate == 'cleanup'
    end

    sprj
  end

  def check_action_permission!(skip_source = nil)
    # find objects if specified or report error
    role=nil
    sprj=nil
    tprj=nil
    if self.person_name
      # validate user object
      User.find_by_login!(self.person_name)
    end
    if self.group_name
      # validate group object
      Group.find_by_title!(self.group_name)
    end
    if self.role
      # validate role object
      role = Role.find_by_title!(self.role)
    end

    sprj = check_action_permission_source! unless skip_source
    tprj = check_action_permission_target!

    # Type specific checks
    if self.action_type == :delete or self.action_type == :add_role or self.action_type == :set_bugowner
      # check existence of target
      unless tprj
        raise UnknownProject.new 'No target project specified'
      end
      if self.action_type == :add_role
        unless role
          raise UnknownRole.new 'No role specified'
        end
      end
    elsif [:submit, :change_devel, :maintenance_release, :maintenance_incident].include?(self.action_type)
      # check existence of source
      unless sprj || skip_source
        # no support for remote projects yet, it needs special support during accept as well
        raise UnknownProject.new 'No target project specified'
      end

      if self.is_maintenance_incident?
        if self.target_package
          raise IllegalRequest.new 'Maintenance requests accept only projects as target'
        end
        raise 'We should have expanded a target_project' unless self.target_project
        # validate project type
        prj = Project.get_by_name(self.target_project)
        unless %w(maintenance maintenance_incident).include? prj.kind
          raise IncidentHasNoMaintenanceProject.new 'incident projects shall only create below maintenance projects'
        end
      end

      # source update checks
      if [:submit, :maintenance_incident].include?(self.action_type)
        # cleanup implicit home branches. FIXME3.0: remove this, the clients should do this automatically meanwhile
        if self.sourceupdate.nil? and self.target_project
          if User.current.branch_project_name(self.target_project) == self.source_project
            self.sourceupdate = 'cleanup'
          end
        end
      end
      if self.action_type == :submit and tprj.kind_of? Project
        at = AttribType.find_by_namespace_and_name!("OBS", "MakeOriginOlder")
        self.makeoriginolder = true if tprj.attribs.where(attrib_type_id: at.id).first
      end
      # allow cleanup only, if no devel package reference
      if self.sourceupdate == 'cleanup' and sprj.class != Project and not skip_source
        raise NotSupported.new "Source project #{self.source_project} is not a local project. cleanup is not supported."
      end

      if self.action_type == :change_devel
        unless self.target_package
          raise UnknownPackage.new 'No target package specified'
        end
      end
    end

    self.check_permissions!
  end

  def check_action_permission_target!
    return nil unless self.target_project

    tprj = Project.get_by_name self.target_project
    if tprj.is_a? Project
      if tprj.is_maintenance_release? and self.action_type == :submit
        raise SubmitRequestRejected.new "The target project #{self.target_project} is a maintenance release project, " +
                                        "a submit self is not possible, please use the maintenance workflow instead."
      end
      a = tprj.find_attribute('OBS', 'RejectRequests')
      if a && a.values.first
        if a.values.length < 2 or a.values.find_by_value(self.action_type)
          raise RequestRejected.new "The target project #{self.target_project} is not accepting requests because: #{a.values.first.value}"
        end
      end
    end
    if self.target_package
      if Package.exists_by_project_and_name(self.target_project, self.target_package) ||
        [:delete, :change_devel, :add_role, :set_bugowner].include?(self.action_type)
        tpkg = Package.get_by_project_and_name self.target_project, self.target_package
      end
      a = tpkg.find_attribute('OBS', 'RejectRequests') if defined?(tpkg) && tpkg
      if defined?(a) && a && a.values.first
        if a.values.length < 2 or a.values.find_by_value(self.action_type)
          raise RequestRejected.new "The target package #{self.target_project} / #{self.target_package} is not accepting " +
                                    "requests because: #{a.values.first.value}"
        end
      end
    end

    tprj
  end

  def check_permissions!
    # to be overloaded in action classes if needed
  end

  def expand_targets(ignore_build_state)
    # expand target_package

    if [:submit, :maintenance_incident].include?(self.action_type)
      if self.target_package and
         Package.exists_by_project_and_name(self.target_project, self.target_package, { :follow_project_links => false })
        raise MissingAction.new unless self.contains_change?
        return nil
      end
    end

    # complete in formation available already?
    return nil if self.action_type == :submit and self.target_package
    return nil if self.action_type == :maintenance_release and self.target_package
    if self.action_type == :maintenance_incident and self.target_releaseproject and self.source_package
      pkg = Package.get_by_project_and_name(self.source_project, self.source_package)
      prj = Project.get_by_name(self.target_releaseproject).update_instance
      self.target_releaseproject = prj.name
      get_releaseproject(pkg, prj) if pkg
      return nil
    end

    if [:submit, :maintenance_release, :maintenance_incident].include?(self.action_type)
      per_package_locking = false
      packages = Array.new
      if self.source_package
        packages << Package.get_by_project_and_name(self.source_project, self.source_package)
        per_package_locking = true
      else
        packages = Project.get_by_name(self.source_project).packages
      end

      return create_expand_package(packages, {ignore_build_state: ignore_build_state}),
             per_package_locking
    end

    return nil
  end

  def source_access_check!
    sp = Package.find_by_project_and_name(self.source_project, self.source_package)
    if sp.nil?
      # either not there or read permission problem
      if Package.exists_on_backend?(self.source_package, self.source_project)
        # user is not allowed to read the source, but when he can write
        # the target, the request creator (who must have permissions to read source)
        # wanted the target owner to review it
        tprj = Project.find_by_name(self.target_project)
        if tprj.nil? or not User.current.can_modify_project? tprj
          # produce an error for the source
          Package.get_by_project_and_name(self.source_project, self.source_package)
        end
        return
      end
      if Project.exists_by_name(self.source_project)
        # it is a remote project
        return
      end
      # produce the same exception for webui
      Package.get_by_project_and_name(self.source_project, self.source_package)
    end
    if sp.class == String
      # a remote package
      return
    end
    sp.check_source_access!
  end

  def check_for_expand_errors!(add_revision)
    return unless [:submit, :maintenance_incident, :maintenance_release].include? self.action_type

    # validate that the sources are not broken
    begin
      query = {}
      query[:expand] = "1" unless self.updatelink
      query[:rev] = self.source_rev if self.source_rev
      # FIXM2.4 we have a Directory model
      url = Package.source_path(self.source_project, self.source_package, nil, query)
      c = Suse::Backend.get(url).body
      if add_revision and !self.source_rev
        self.source_rev = Xmlhash.parse(c)['srcmd5']
      end
    rescue ActiveXML::Transport::Error
      # rubocop:disable Metrics/LineLength
      raise ExpandError.new "The source of package #{self.source_project}/#{self.source_package}#{self.source_rev ? " for revision #{self.source_rev}" : ''} is broken"
      # rubocop:enable Metrics/LineLength
    end
  end

  #### Alias of methods
end
