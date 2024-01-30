class Webui::PackageController < Webui::WebuiController
  include ParsePackageDiff
  include Webui::PackageHelper
  include Webui::ManageRelationships

  before_action :set_project, only: [:show, :edit, :update, :index, :users, :dependency, :requests, :statistics, :revisions,
                                     :new, :branch_diff_info, :rdiff, :create, :save, :remove,
                                     :remove_file, :save_person, :save_group, :remove_role, :view_file, :abort_build, :trigger_rebuild,
                                     :trigger_services, :wipe_binaries, :buildresult, :rpmlint_result, :rpmlint_log, :meta, :save_meta, :files]

  before_action :require_package, only: [:edit, :update, :show, :dependency, :requests, :statistics, :revisions,
                                         :branch_diff_info, :rdiff, :save, :save_meta, :remove,
                                         :remove_file, :save_person, :save_group, :remove_role, :view_file, :abort_build, :trigger_rebuild,
                                         :trigger_services, :wipe_binaries, :buildresult, :rpmlint_result, :rpmlint_log, :meta, :files, :users]

  before_action :validate_xml, only: [:save_meta]

  before_action :check_ajax, only: [:devel_project, :buildresult, :rpmlint_result]
  # make sure it's after the require_, it requires both
  before_action :require_login, except: [:show, :index, :branch_diff_info,
                                         :users, :requests, :statistics, :revisions, :view_file,
                                         :devel_project, :buildresult, :rpmlint_result, :rpmlint_log, :meta, :files]

  # FIXME: Remove this before_action, it's doing validation and authorization at the same time
  before_action :check_package_name_for_new, only: [:create]

  prepend_before_action :lockout_spiders, only: [:revisions, :dependency, :rdiff, :requests]

  after_action :verify_authorized, only: [:new, :create, :remove_file, :remove, :abort_build, :trigger_rebuild, :wipe_binaries, :save_meta, :save, :abort_build]

  def index
    render json: PackageDatatable.new(params, view_context: view_context, project: @project)
  end

  def show
    # FIXME: Remove this statement when scmsync is fully supported
    if @project.scmsync.present?
      flash[:error] = "Package sources for project #{@project.name} are received through scmsync.
                       This is not yet fully supported by the OBS frontend"
      redirect_back(fallback_location: project_show_path(@project))
      return
    end

    if @spider_bot
      params.delete(:rev)
      params.delete(:srcmd5)
      @expand = 0
    elsif params[:expand]
      @expand = params[:expand].to_i
    else
      @expand = 1
    end

    @srcmd5 = params[:srcmd5]
    @revision_parameter = params[:rev]

    @bugowners_mail = (@package.bugowner_emails + @project.bugowner_emails).uniq
    @revision = params[:rev]
    @failures = 0

    @is_current_rev = false
    if set_file_details
      if @forced_unexpand.blank? && @service_running.blank?
        @is_current_rev = (@revision == @current_rev)
      elsif @service_running
        flash.clear
        flash.now[:notice] = "Service currently running (<a href='#{package_show_path(project: @project, package: @package)}'>reload page</a>)."
      else
        @more_info = @package.service_error
        flash.now[:error] = "Files could not be expanded: #{@forced_unexpand}"
      end
    elsif @revision_parameter
      flash[:error] = "No such revision: #{@revision_parameter}"
      redirect_back(fallback_location: { controller: :package, action: :show, project: @project, package: @package })
      return
    end

    @comments = @package.comments.includes(:user)
    @comment = Comment.new

    if User.session && params[:notification_id]
      @current_notification = Notification.find(params[:notification_id])
      authorize @current_notification, :update?, policy_class: NotificationPolicy
    end

    @services = @files.any? { |file| file[:name] == '_service' }

    @package.cache_revisions(@revision)

    respond_to do |format|
      format.html
      format.js
      format.json { render template: 'webui/package/show', formats: [:html] }
    end
  end

  def new
    authorize Package.new(project: @project), :create?
  end

  def edit
    authorize @package, :update?
    respond_to do |format|
      format.js
    end
  end

  def create
    @package = @project.packages.build(package_params)
    authorize @package, :create?

    @package.flags.build(flag: :sourceaccess, status: :disable) if params[:source_protection]
    @package.flags.build(flag: :publish, status: :disable) if params[:disable_publishing]

    if @package.save
      flash[:success] = "Package '#{elide(@package.name)}' was created successfully"
      redirect_to action: :show, project: params[:project], package: @package.name
    else
      flash[:error] = "Failed to create package: #{@package.errors.full_messages.join(', ')}"
      redirect_to controller: :project, action: :show, project: params[:project]
    end
  end

  def update
    authorize @package, :update?
    respond_to do |format|
      if @package.update(package_details_params)
        format.html do
          flash[:success] = 'Package was successfully updated.'
          redirect_to package_show_path(@package)
        end
        format.js { flash.now[:success] = 'Package was successfully updated.' }
      else
        format.html do
          flash[:error] = 'Failed to update package'
          redirect_to package_show_path(@package)
        end
        format.js
      end
    end
  end

  def main_object
    @package # used by mixins
  end

  # rubocop:disable Lint/NonLocalExitFromIterator
  def dependency
    dependant_project = Project.find_by_name(params[:dependant_project]) || Project.find_remote_project(params[:dependant_project]).try(:first)
    unless dependant_project
      flash[:error] = "Project '#{elide(params[:dependant_project])}' is invalid."
      redirect_back(fallback_location: root_path)
      return
    end

    unless Architecture.archcache.include?(params[:arch])
      flash[:error] = "Architecture '#{params[:arch]}' is invalid."
      redirect_back(fallback_location: project_show_path(project: @project.name))
      return
    end

    # FIXME: It can't check repositories of remote projects
    project_repositories = dependant_project.remoteurl.blank? ? dependant_project.repositories.pluck(:name) : []
    [:repository, :dependant_repository].each do |repo_key|
      next if project_repositories.include?(params[repo_key])

      flash[:error] = "Repository '#{params[repo_key]}' is invalid."
      redirect_back(fallback_location: project_show_path(project: @project.name))
      return
    end

    @arch = params[:arch]
    @repository = params[:repository]
    @dependant_repository = params[:dependant_repository]
    @dependant_project = params[:dependant_project]
    @package_name = "#{params[:package]}:#{params[:dependant_name]}"
    # Ensure it really is just a file name, no '/..', etc.
    @filename = File.basename(params[:filename])
    @fileinfo = Backend::Api::BuildResults::Binaries.fileinfo_ext(params[:dependant_project], '_repository', params[:dependant_repository],
                                                                  @arch, params[:dependant_name])
    return if @fileinfo # avoid displaying an error for non-existing packages

    redirect_back(fallback_location: project_package_repository_binary_path(project_name: params[:project], package_name: params[:package],
                                                                            repository_name: @repository, arch: @arch, filename: @filename))
  end
  # rubocop:enable Lint/NonLocalExitFromIterator

  def statistics
    @repository = params[:repository]
    @package_name = params[:package]

    @statistics = LocalBuildStatistic::ForPackage.new(package: @package_name,
                                                      project: @project.name,
                                                      repository: @repository,
                                                      architecture: params[:arch]).results
  end

  def users
    @users = [@project.users, @package.users].flatten.uniq
    @groups = [@project.groups, @package.groups].flatten.uniq
    @roles = Role.local_roles
    if User.session && params[:notification_id]
      @current_notification = Notification.find(params[:notification_id])
      authorize @current_notification, :update?, policy_class: NotificationPolicy
    end
    @current_request_action = BsRequestAction.find(params[:request_action_id]) if User.session && params[:request_action_id]
  end

  def requests
    @default_request_type = params[:type] if params[:type]
    @default_request_state = params[:state] if params[:state]
  end

  def revisions
    unless @package.check_source_access?
      flash[:error] = 'Could not access revisions'
      redirect_to action: :show, project: @project.name, package: @package.name
      return
    end

    per_page = 20
    revision_count = (params[:rev] || @package.rev).to_i
    per_page = revision_count if User.session && params['show_all']
    @revisions = Kaminari.paginate_array((1..revision_count).to_a.reverse).page(params[:page]).per(per_page)
  end

  def rdiff
    @last_rev = @package.dir_hash['rev']
    @linkinfo = @package.linkinfo
    if params[:oproject]
      @oproject = ::Project.find_by_name(params[:oproject])
      @opackage = @oproject.find_package(params[:opackage]) if @oproject && params[:opackage]
    end

    @last_req = find_last_req

    @rev = params[:rev] || @last_rev
    @linkrev = params[:linkrev]

    options = {}
    [:orev, :opackage, :oproject, :linkrev, :olinkrev].each do |k|
      options[k] = params[k] if params[k].present?
    end
    options[:rev] = @rev if @rev
    options[:filelimit] = 0 if params[:full_diff] && User.session
    options[:tarlimit] = 0 if params[:full_diff] && User.session
    return unless get_diff(@project.name, @package.name, options)

    # we only look at [0] because this is a generic function for multi diffs - but we're sure we get one
    filenames = sorted_filenames_from_sourcediff(@rdiff)[0]

    @files = filenames['files']
    @not_full_diff = @files.any? { |file| file[1]['diff'].try(:[], 'shown') }
    @filenames = filenames['filenames']

    # FIXME: moved from the old view, needs refactoring
    @submit_url_opts = {}
    if @oproject && @opackage && !@oproject.find_attribute('OBS', 'RejectRequests') && !@opackage.find_attribute('OBS', 'RejectRequests')
      @submit_message = "Submit to #{@oproject.name}/#{@opackage.name}"
      @submit_url_opts[:target_project] = @oproject.name
      @submit_url_opts[:targetpackage] = @opackage.name
    elsif @rev != @last_rev
      @submit_message = "Revert #{@project.name}/#{@package.name} to revision #{@rev}"
      @submit_url_opts[:target_project] = @project.name
    end
  end

  def branch_diff_info
    linked_package = @package.backend_package.links_to
    target_project = target_package = description = ''
    if linked_package
      target_project = linked_package.project.name
      target_package = linked_package.name
      description = @package.commit_message_from_changes_file(target_project, target_package)
    end

    render json: {
      targetProject: target_project,
      targetPackage: target_package,
      description: description,
      cleanupSource: @project.branch? # We should remove the package if this request is a branch
    }
  end

  def save
    authorize @package, :update?
    @package.title = params[:title]
    @package.description = params[:description]
    if @package.save
      flash[:success] = "Package data for '#{elide(@package.name)}' was saved successfully"
    else
      flash[:error] = "Failed to save package '#{elide(@package.name)}': #{@package.errors.full_messages.to_sentence}"
    end
    redirect_to action: :show, project: params[:project], package: params[:package]
  end

  def remove
    authorize @package, :destroy?

    # Don't check weak dependencies if we force
    @package.check_weak_dependencies? unless params[:force]
    if @package.errors.empty?
      @package.destroy
      redirect_to(project_show_path(@project), success: 'Package was successfully removed.')
    else
      redirect_to(package_show_path(project: @project, package: @package),
                  error: "Package can't be removed: #{@package.errors.full_messages.to_sentence}")
    end
  end

  def trigger_services
    authorize @package, :update?

    begin
      Backend::Api::Sources::Package.trigger_services(@project.name, @package.name, User.session!.to_s)
      flash[:success] = 'Services successfully triggered'
    rescue Timeout::Error => e
      flash[:error] = "Services couldn't be triggered: " + e.message
    rescue Backend::Error => e
      flash[:error] = "Services couldn't be triggered: " + Xmlhash::XMLHash.new(error: e.summary)[:error]
    end
    redirect_to package_show_path(@project, @package)
  end

  def remove_file
    authorize @package, :update?

    filename = params[:filename]
    begin
      @package.delete_file(filename)
      flash[:success] = "File '#{filename}' removed successfully"
    rescue Backend::NotFoundError
      flash[:error] = "Failed to remove file '#{filename}'"
    end
    redirect_to action: :show, project: @project, package: @package
  end

  def view_file
    @filename = params[:filename] || params[:file] || ''
    if binary_file?(@filename) # We don't want to display binary files
      flash[:error] = "Unable to display binary file #{@filename}"
      redirect_back(fallback_location: { action: :show, project: @project, package: @package })
      return
    end
    @rev = params[:rev]
    @expand = params[:expand]
    @addeditlink = false
    if User.possibly_nobody.can_modify?(@package) && @rev.blank? && @package.scmsync.blank?
      begin
        files = package_files(@rev, @expand)
      rescue Backend::Error
        files = []
      end
      files.each do |file|
        if file[:name] == @filename
          @addeditlink = file[:editable]
          break
        end
      end
    end
    begin
      @file = @package.source_file(@filename, fetch_from_params(:rev, :expand))
    rescue Backend::NotFoundError
      flash[:error] = "File not found: #{@filename}"
      redirect_to action: :show, package: @package, project: @project
      return
    rescue Backend::Error => e
      flash[:error] = "Error: #{e}"
      redirect_back(fallback_location: { action: :show, project: @project, package: @package })
      return
    end

    render(template: 'webui/package/simple_file_view') && return if @spider_bot
  end

  def abort_build
    authorize @package, :update?

    if @package.abort_build(params)
      flash[:success] = "Triggered abort build for #{elide(@project.name)}/#{elide(@package.name)} successfully."
      redirect_to package_show_path(project: @project, package: @package)
    else
      flash[:error] = "Error while triggering abort build for #{elide(@project.name)}/#{elide(@package.name)}: #{@package.errors.full_messages.to_sentence}."
      redirect_to package_live_build_log_path(project: @project, package: @package, repository: params[:repository], arch: params[:arch])
    end
  end

  def trigger_rebuild
    rebuild_trigger = PackageControllerService::RebuildTrigger.new(package_object: @package, package_name_with_multibuild_suffix: params[:package],
                                                                   project: @project, repository: params[:repository], arch: params[:arch])
    authorize rebuild_trigger.policy_object, :update?

    if rebuild_trigger.rebuild?
      flash[:success] = rebuild_trigger.success_message
      redirect_to package_show_path(project: @project, package: @package)
    else
      flash[:error] = rebuild_trigger.error_message
      redirect_to project_package_repository_binaries_path(project_name: @project, package_name: @package, repository_name: params[:repository])
    end
  end

  def wipe_binaries
    authorize @package, :update?

    if @package.wipe_binaries(params)
      flash[:success] = "Triggered wipe binaries for #{elide(@project.name)}/#{elide(@package.name)} successfully."
    else
      flash[:error] = "Error while triggering wipe binaries for #{elide(@project.name)}/#{elide(@package.name)}: #{@package.errors.full_messages.to_sentence}."
    end

    redirect_to project_package_repository_binaries_path(project_name: @project, package_name: @package, repository_name: params[:repository])
  end

  def devel_project
    tgt_pkg = Package.find_by_project_and_name(params[:project], params[:package])

    render plain: tgt_pkg.try(:develpackage).try(:project).to_s
  end

  def buildresult
    if @project.repositories.any?
      show_all = params[:show_all].to_s.casecmp?('true')
      @index = params[:index]
      @buildresults = @package.buildresult(@project, show_all)

      # TODO: this is part of the temporary changes done for 'request_show_redesign'.
      request_show_redesign_partial = 'webui/request/beta_show_tabs/build_status' if params.fetch(:inRequestShowRedesign, false)

      render partial: request_show_redesign_partial || 'buildstatus', locals: { buildresults: @buildresults,
                                                                                index: @index,
                                                                                project: @project,
                                                                                collapsed_packages: params.fetch(:collapsedPackages, []),
                                                                                collapsed_repositories: params.fetch(:collapsedRepositories, {}) }
    else
      render partial: 'no_repositories', locals: { project: @project }
    end
  end

  def rpmlint_result
    @repo_arch_hash = {}
    @buildresult = Buildresult.find_hashed(project: @project.to_param, package: @package.to_param, view: 'status')
    repos = [] # Temp var
    if @buildresult
      @buildresult.elements('result') do |result|
        if result.value('repository') != 'images' &&
           (result.value('status') && result.value('status').value('code') != 'excluded')
          hash_key = valid_xml_id(elide(result.value('repository'), 30))
          @repo_arch_hash[hash_key] ||= []
          @repo_arch_hash[hash_key] << result['arch']
          repos << result.value('repository')
        end
      end
    end

    @repo_list = repos.uniq.collect do |repo_name|
      [repo_name, valid_xml_id(elide(repo_name, 30))]
    end

    if @repo_list.empty?
      render partial: 'no_repositories', locals: { project: @project }
    else
      # TODO: this is part of the temporary changes done for 'request_show_redesign'.
      request_show_redesign_partial = 'webui/request/beta_show_tabs/rpm_lint_result' if params.fetch(:inRequestShowRedesign, false)

      render partial: request_show_redesign_partial || 'rpmlint_result', locals: { index: params[:index], project: @project, package: @package,
                                                                                   repository_list: @repo_list, repo_arch_hash: @repo_arch_hash,
                                                                                   is_staged_request: params[:is_staged_request] }
    end
  end

  def rpmlint_log_params
    params.require([:project, :package, :repository, :architecture])
    params.slice(:project, :package, :repository, :architecture).permit!
  end

  def rpmlint_log
    rpmlint_log_file = RpmlintLogExtractor.new(rpmlint_log_params).call
    render plain: 'No rpmlint log' and return if rpmlint_log_file.blank?

    render_chart = params[:renderChart] == 'true'
    parsed_messages = RpmlintLogParser.new(content: rpmlint_log_file).call if render_chart
    render partial: 'rpmlint_log', locals: { rpmlint_log_file: rpmlint_log_file, render_chart: render_chart, parsed_messages: parsed_messages }
  end

  def meta
    @meta = @package.render_xml
  end

  def save_meta
    errors = []

    authorize @package, :save_meta_update?

    errors << 'admin rights are required to raise the protection level of a package' if FlagHelper.xml_disabled_for?(@meta_xml, 'sourceaccess')

    errors << 'project name in xml data does not match resource path component' if @meta_xml['project'] && @meta_xml['project'] != @project.name

    errors << 'package name in xml data does not match resource path component' if @meta_xml['name'] && @meta_xml['name'] != @package.name

    if errors.empty?
      begin
        @package.update_from_xml(@meta_xml)
        flash.now[:success] = 'The Meta file has been successfully saved.'
        status = 200
      rescue Backend::Error, NotFoundError => e
        flash.now[:error] = "Error while saving the Meta file: #{e}."
        status = 400
      end
    else
      flash.now[:error] = "Error while saving the Meta file: #{errors.compact.join("\n")}."
      status = 400
    end
    render layout: false, status: status, partial: 'layouts/webui/flash', object: flash
  end

  private

  def package_params
    params.require(:package).permit(:name, :title, :description)
  end

  def package_details_params
    # We use :package_details instead of the canonical :package param key
    # because :package is already used in the Webui::WebuiController#require_package
    # filter.
    # TODO: rename the usage of :package in #require_package to :package_name to unlock
    # the proper use of defaults.
    params
      .require(:package_details)
      .permit(:title,
              :description,
              :url)
  end

  def validate_xml
    Suse::Validator.validate('package', params[:meta])
    @meta_xml = Xmlhash.parse(params[:meta])
  rescue Suse::ValidationError => e
    flash.now[:error] = "Error while saving the Meta file: #{e}."
    render layout: false, status: :bad_request, partial: 'layouts/webui/flash', object: flash
  end

  def package_files(rev = nil, expand = nil)
    query = {}
    query[:expand]  = expand  if expand
    query[:rev]     = rev     if rev

    dir_xml = @package.source_file(nil, query)
    return [] if dir_xml.blank?

    dir = Xmlhash.parse(dir_xml)
    @serviceinfo = dir.elements('serviceinfo').first
    files = []
    dir.elements('entry') do |entry|
      file = Hash[*[:name, :size, :mtime, :md5].map! { |x| [x, entry.value(x.to_s)] }.flatten]
      file[:viewable] = !binary_file?(file[:name]) && file[:size].to_i < 2**20 # max. 1 MB
      file[:editable] = file[:viewable] && !file[:name].match?(/^_service[_:]/)
      file[:srcmd5] = dir.value('srcmd5')
      files << file
    end
    files
  end

  def require_architecture
    @architecture = Architecture.archcache[params[:arch]]
    return if @architecture

    flash[:error] = "Couldn't find architecture '#{params[:arch]}'"
    redirect_to project_package_repository_binaries_path(project_name: @project, package_name: @package, repository_name: @repository.name)
  end

  def require_repository
    @repository = @project.repositories.find_by(name: params[:repository])
    return if @repository

    flash[:error] = "Couldn't find repository '#{params[:repository]}'"
    redirect_to package_show_path(project: @project, package: @package)
  end

  def set_file_details
    @forced_unexpand ||= ''

    # check source access
    @files = []
    return false unless @package.check_source_access?

    set_linkinfo

    begin
      @current_rev = @package.rev
      @revision = @current_rev if !@revision && !@srcmd5 # on very first page load only

      @files = package_files(@srcmd5 || @revision, @expand)
    rescue Backend::Error => e
      # TODO: crudest hack ever!
      if e.summary == 'service in progress' && @expand == 1
        @expand = 0
        @service_running = true
        # silently in this case
        return set_file_details
      end
      if @expand == 1
        @forced_unexpand = e.details || e.summary
        @expand = 0
        return set_file_details
      end
      return false
    end

    true
  end

  def set_linkinfo
    return unless @package.is_link?

    # FIXME: We have a rails bug here.
    # the `.backend_package.links_to` is an association chain.
    # Due to this bug https://github.com/rails/rails/issues/38709 `linked_package` will not get the refreshed
    # contents and then the md5 at the bottom of this method are the same, thus no rendering the linkinfo
    linked_package = @package.backend_package.links_to
    return set_remote_linkinfo unless linked_package

    @linkinfo = { package: linked_package, error: @package.backend_package.error }
    @linkinfo[:diff] = true if linked_package.backend_package.verifymd5 != @package.backend_package.verifymd5
  end

  def set_remote_linkinfo
    linkinfo = @package.linkinfo

    return unless linkinfo && linkinfo['package'] && linkinfo['project']
    return unless Package.exists_on_backend?(linkinfo['package'], linkinfo['project'])

    @linkinfo = { remote_project: linkinfo['project'], package: linkinfo['package'] }
  end

  def check_package_name_for_new
    package_name = params[:package][:name]

    # FIXME: This should be a validation in the Package model
    unless Package.valid_name?(package_name)
      flash[:error] = "Invalid package name: '#{elide(package_name)}'"
      redirect_to action: :new, project: @project
      return false
    end
    # FIXME: This should be a validation in the Package model
    if Package.exists_by_project_and_name(@project.name, package_name)
      flash[:error] = "Package '#{elide(package_name)}' already exists in project '#{elide(@project.name)}'"
      redirect_to action: :new, project: @project
      return false
    end

    true
  end

  def find_last_req
    return if @oproject.blank? || @opackage.blank?

    last_req = find_last_declined_bs_request

    return if last_req.blank?

    { id: last_req.number, decliner: last_req.commenter,
      when: last_req.updated_at, comment: last_req.comment }
  end

  def find_last_declined_bs_request
    last_req = BsRequestAction.joins(:bs_request).where(target_project: @oproject,
                                                        target_package: @opackage,
                                                        source_project: @package.project,
                                                        source_package: @package.name)
                              .order(:bs_request_id).last

    return if last_req.blank?

    last_req.bs_request if bs_request.state == :declined
  end

  def get_diff(project, package, options = {})
    options[:view] = :xml
    options[:cacheonly] = 1 unless User.session
    options[:withissues] = 1
    begin
      @rdiff = Backend::Api::Sources::Package.source_diff(project, package, options.merge(expand: 1))
    rescue Backend::Error => e
      flash[:error] = 'Problem getting expanded diff: ' + e.summary
      begin
        @rdiff = Backend::Api::Sources::Package.source_diff(project, package, options.merge(expand: 0))
      rescue Backend::Error => e
        flash[:error] = 'Error getting diff: ' + e.summary
        redirect_back(fallback_location: package_show_path(project: @project, package: @package))
        return false
      end
    end
    true
  end

  def fetch_from_params(*arr)
    opts = {}
    arr.each do |k|
      opts[k] = params[k] if params[k].present?
    end
    opts
  end
end
