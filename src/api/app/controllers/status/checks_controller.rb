class Status::ChecksController < ApplicationController
  before_action :require_project
  before_action :require_repository
  before_action :require_checkable, only: [:index, :show, :destroy, :update]
  before_action :require_or_initialize_checkable, only: :create
  before_action :require_check, only: [:show, :destroy, :update]
  before_action :set_xml_check, only: [:create, :update]
  skip_before_action :require_login, only: [:show, :index]
  after_action :verify_authorized

  # GET /projects/:project_name/repositories/:repository_name/repository_publishes/:repository_publish_build_id/checks
  def index
    @checks = @checkable.checks
    @missing_checks = @checkable.missing_checks
    authorize @checks
  end

  # GET /projects/:project_name/repositories/:repository_name/repository_publishes/:repository_publish_build_id/checks/:id
  def show
    authorize @check
  end

  # POST /projects/:project_name/repositories/:repository_name/repository_publishes/:repository_publish_build_id/checks
  def create
    @xml_check[:checkable] = @checkable
    @check = Status::Check.new(@xml_check)
    authorize @check
    if @check.save
      render :show
    else
      render_error(status: 422, errorcode: 'invalid_check', message: "Could not save check: #{@check.errors.full_messages.to_sentence}")
    end
  end

  # PATCH /projects/:project_name/repositories/:repository_name/repository_publishes/:repository_publish_build_id/checks/:id
  def update
    authorize @check
    if @check.update(@xml_check)
      render :show
    else
      render_error(status: 422, errorcode: 'invalid_check', message: "Could not save check: #{@check.errors.full_messages.to_sentence}")
    end
  end

  # DELETE /projects/:project_name/repositories/:repository_name/repository_publishes/:repository_publish_build_id/checks/:id
  def destroy
    authorize @check
    if @check.destroy
      render_ok
    else
      render_error(status: 422, errorcode: 'invalid_check', message: "Could not delete check: #{@check.errors.full_messages.to_sentence}")
    end
  end

  private

  def require_or_initialize_checkable
    @checkable = @repository.status_publishes.find_or_initialize_by(build_id: params[:repository_publish_build_id])
  end

  def require_checkable
    @checkable = Status::RepositoryPublish.find_by(build_id: params[:repository_publish_build_id]) if params[:repository_publish_build_id]
    render_error(status: 404, errorcode: 'not_found', message: "Unable to find status_repository_publish with id '#{params[:repository_publish_build_id]}'") unless @checkable
  end

  def require_check
    @check = @checkable.checks.find_by(id: params[:id])
    render_error(status: 404, errorcode: 'not_found', message: "Unable to find check with id '#{params[:id]}'") unless @check
  end

  def set_xml_check
    @xml_check = xml_hash
    return if @xml_check.present?
    render_error status: 404, errorcode: 'empty_body', message: 'Request body is empty!'
  end

  def require_project
    @project = Project.get_by_name(params[:project_name])
  end

  def require_repository
    @repository = @project.repositories.find_by(name: params[:repository_name])
    raise UnknownRepository, "Repository does not exist #{params[:repository_name]}" unless @repository
  end

  def xml_hash
    result = (Xmlhash.parse(request.body.read) || {}).with_indifferent_access
    result.slice(:url, :state, :short_description, :name)
  end
end
