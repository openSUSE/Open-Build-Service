class Webui::CommentsController < Webui::WebuiController
  def destroy
    comment = Comment.find(params[:id])
    unless comment.check_delete_permissions
      flash[:error] = 'No permissions to delete comment'
      redirect_to :back
      return
    end
    comment.blank_or_destroy

    respond_to do |format|
      format.js { render json: 'ok' }
      format.html do
        flash[:notice] = 'Comment deleted successfully'
      end
    end
    redirect_to :back
  end
end
