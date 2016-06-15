class Webui::ConfigurationController < Webui::WebuiController
  before_filter :require_admin
  before_filter :set_configuration, only: [:update]
  before_filter :require_available_architectures, only: [:index]

  def index; end

  def interconnect; end

  def create_interconnect
    @project = RemoteProject.new(project_params)

    if @project.valid? && @project.store
      flash[:notice] = "Project '#{@project.name}' was created successfully"
      logger.debug "New remote project with url #{@project.remoteurl}"
      redirect_to controller: :project, action: 'show', project: @project.name
    else
      redirect_to :back, error: "Project can't be saved: #{@project.errors.full_messages.to_sentence}"
    end
  end

  def update
    respond_to do |format|
      if @configuration.update(configuration_params)
        format.html { redirect_to configuration_path, notice: 'Configuration was successfully updated.' }
      else
        format.html { redirect_to :back, error: "Configuration can't be saved: #{@configuration.errors.full_messages.to_sentence}" }
      end
    end
  end

  private

    # Never trust parameters from the scary internet, only allow the white list through.
    def project_params
      params.require(:project).permit(:name, :title, :remoteurl, :description)
    end

    def configuration_params
      params.require(:configuration).permit(:name, :title, :description)
    end

    def set_configuration
      @configuration = ::Configuration.first
    end
end
