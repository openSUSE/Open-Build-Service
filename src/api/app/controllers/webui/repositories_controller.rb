class Webui::RepositoriesController < Webui::WebuiController
  before_action :set_project
  before_action :set_repository, only: [:state]
  before_action :find_repository_parent, only: [:index, :create_flag, :remove_flag, :toggle_flag]
  after_action :verify_authorized, except: [:index, :distributions, :state]

  # GET /repositories/:project(/:package)
  # Compatibility routes
  # GET package/repositories/:project/:package
  # GET project/repositories/:project
  def index
    @build = @main_object.get_flags('build')
    @debuginfo = @main_object.get_flags('debuginfo')
    @publish = @main_object.get_flags('publish')
    @useforbuild = @main_object.get_flags('useforbuild')
    @architectures = @main_object.architectures.reorder('name').distinct

    @user_can_set_flags = policy(@project).update?

    switch_to_webui2 if @package
  end

  # GET project/add_repository/:project
  def new
    authorize @project, :update?
  end

  # GET project/add_repository_from_default_list/:project
  def distributions
    @distributions = {}
    Distribution.all_including_remotes.each do |dis|
      @distributions[dis['vendor']] ||= []
      @distributions[dis['vendor']] << dis
    end

    return unless @distributions.empty?
    redirect_to(action: 'new', project: @project) && return unless User.current.is_admin?
    redirect_to({ controller: 'configuration', action: 'interconnect' },
                alert: 'There are no distributions configured. Maybe you want to connect to one of the public OBS instances?')
  end

  # POST project/save_repository
  def create
    authorize @project, :update?
    repository = @project.repositories.find_or_initialize_by(name: params[:repository])
    if params[:target_repo]
      target_repository = Repository.find_by_project_and_name(params[:target_project], params[:target_repo])
      repository.path_elements.find_or_initialize_by(link: target_repository)
    end

    params[:architectures] ||= []
    params[:architectures].each do |architecture|
      repository.repository_architectures.find_or_initialize_by(architecture: Architecture.find_by(name: architecture))
    end

    if repository.save
      @project.store(comment: "Added #{repository.name} repository")
      flash[:success] = "Successfully added repository '#{repository.name}'"
      respond_to do |format|
        format.html { redirect_to(action: :index, project: @project) }
        format.js
      end
    else
      flash[:error] = "Can not add repository: #{repository.errors.full_messages.to_sentence}"
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path) }
        format.js
      end
    end
  end

  # POST project/update_target/:project
  def update
    authorize @project, :update?
    repo = @project.repositories.where(name: params[:repo]).first
    archs = []
    archs = params[:arch].keys.map { |arch| Architecture.find_by_name(arch) } if params[:arch]
    repo.architectures = archs
    repo.save
    @project.store(comment: "Modified #{repo.name} repository")

    # Merge project repo's arch list with currently available arches from API. This needed as you want
    # to keep currently non-working arches in the project meta.
    @repository_arch_hash = {}
    Architecture.available.each { |arch| @repository_arch_hash[arch.name] = false }
    repo.architectures.each { |arch| @repository_arch_hash[arch.name] = true }
    redirect_to({ action: :index }, notice: 'Successfully updated repository')
  end

  # DELETE /project/remove_target
  def destroy
    authorize @project, :update?
    repository = @project.repositories.find_by(name: params[:target])
    result = repository && @project.repositories.delete(repository)
    if @project.valid? && result
      @project.store(comment: "Removed #{repository.name} repository")
      respond_to do |format|
        flash[:success] = "Successfully removed repository '#{repository.name}'"
        format.html { redirect_to(action: :index, project: @project) }
        format.js
      end
    else
      msg = "Failed to remove repository: #{@project.errors.full_messages.to_sentence}"
      msg << 'Repository not found.' if @project.valid? && !result
      respond_to do |format|
        flash[:error] = msg
        format.html { redirect_back(fallback_location: root_path) }
        format.js
      end
    end
  end

  # GET project/repository_state/:project/:repository
  def state; end

  # POST /project/create_dod_repository
  def create_dod_repository
    authorize @project, :update?
    if Repository.find_by_name(params[:name])
      @error = "Repository with name '#{params[:name]}' already exists."
    end

    begin
      ActiveRecord::Base.transaction do
        @new_repository = @project.repositories.create!(name: params[:name])
        @new_repository.repository_architectures.create!(architecture: Architecture.find_by(name: params[:arch]), position: 1)
        @new_repository.download_repositories.create!(arch: params[:arch], url: params[:url], repotype: params[:repotype])
        @project.store
      end
    rescue ::Timeout::Error, ActiveRecord::RecordInvalid => e
      @error = "Couldn't add repository: #{e.message}"
    end
  end

  # POST project/create_image_repository
  def create_image_repository
    authorize @project, :update?
    repository = @project.repositories.new(name: 'images')

    if repository.save
      Architecture.available.each do |architecture|
        repository.repository_architectures.create(architecture: architecture)
      end

      @project.prepend_kiwi_config
      @project.store

      flash[:success] = 'Successfully added image repository'
      respond_to do |format|
        format.html { redirect_to(action: :index, project: @project) }
        format.js { render 'create' }
      end
    else
      flash[:error] = "Can not add image repository: #{repository.errors.full_messages.to_sentence}"
      respond_to do |format|
        format.html { redirect_back(fallback_location: root_path) }
        format.js { render 'create' }
      end
    end
  end

  # POST flag/:project(/:package)
  def create_flag
    authorize @main_object, :update?

    @flag = @main_object.flags.new(status: params[:status], flag: params[:flag])
    @flag.architecture = Architecture.find_by_name(params[:architecture])
    @flag.repo = params[:repository] if params[:repository].present?
    @user_can_set_flags = policy(@project).update?

    respond_to do |format|
      if @flag.save
        # FIXME: This should happen in Flag or even better in Project
        @main_object.store
        format.html { redirect_to(action: :index, controller: :repositories, project: params[:project], package: params[:package]) }
        format.js do
          switch_to_webui2 if params[:package].present?
          render 'change_flag'
        end
      else
        format.json { render json: @flag.errors, status: :unprocessable_entity }
      end
    end
  end

  # POST flag/:project(/:package)/:flag
  def toggle_flag
    authorize @main_object, :update?

    @flag = Flag.find(params[:flag])
    @flag.status = @flag.status == 'enable' ? 'disable' : 'enable'
    @user_can_set_flags = policy(@project).update?

    respond_to do |format|
      if @flag.save
        # FIXME: This should happen in Flag or even better in Project
        @main_object.store
        format.html { redirect_to(action: :index, project: params[:project], package: params[:package]) }
        format.js do
          switch_to_webui2 if params[:package].present?
          render 'change_flag'
        end
      else
        format.json { render json: @flag.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE flag/:project(/:package)/:flag
  def remove_flag
    authorize @main_object, :update?

    @flag = Flag.find(params[:flag])
    @main_object.flags.destroy(@flag)
    @flag = @flag.dup
    @flag.status = @flag.default_status
    @user_can_set_flags = policy(@project).update?

    respond_to do |format|
      # FIXME: This should happen in Flag or even better in Project
      @main_object.store
      format.html { redirect_to(action: :index, project: params[:project], package: params[:package]) }
      format.js do
        switch_to_webui2 if params[:package].present?
        render 'change_flag'
      end
    end
  end

  private

  def set_repository
    @repository = @project.repositories.find_by!(name: params[:repository])
  end

  def find_repository_parent
    if params[:package]
      # FIXME: Handle APIError different, this is just c&p from packages_controller
      begin
        @main_object = @package = Package.get_by_project_and_name(@project.to_param, params[:package], use_source: false, follow_project_links: true)
      rescue APIError
        flash[:error] = "Package \"#{params[:package]}\" not found in project \"#{params[:project]}\""
        redirect_to project_show_path(project: @project, nextstatus: 404)
        return
      end
    else
      @main_object = @project
    end
  end
end
