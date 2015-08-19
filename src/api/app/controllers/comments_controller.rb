class CommentsController < ApplicationController

  before_filter :require_login, only: [:destroy, :create]
  before_filter :find_obj, only: [:show_comments, :create]

  def show_comments
    @comments = @obj.comments.order(:id)
    render "show_#{@template}_comments"
  end

  def create
    @obj.comments.create!(body: request.raw_post, user: User.current)
    render_ok
  end

  def destroy
    comment = Comment.find params[:id]
    unless comment.check_delete_permissions
      raise NoPermission.new "No permission to delete #{params[:id]}"
    end
    comment.blank_or_destroy
    render_ok
  end

  protected

  def find_obj
    if params[:project]
      if params[:package]
        @template = 'package'
        @obj = Package.get_by_project_and_name(params[:project], params[:package])
      else
        @template = 'project'
        @obj = Project.get_by_name(params[:project])
      end
    else
      @template = 'request'
      @obj = BsRequest.find(params[:id])
    end
  end
end
