class Webui::CommentsController < Webui::WebuiController
  before_action :require_login
  before_action :set_commented, only: :create
  before_action :set_comment, only: [:moderate, :history]

  def create
    if @commented.nil?
      flash.now[:error] = "Failed to create comment: This #{@commentable_type.name.downcase} does not exist anymore."
      render partial: 'layouts/webui/flash' and return
    end

    comment = @commented.comments.new(permitted_params)
    authorize comment, :create?
    User.session!.comments << comment
    @commentable = comment.commentable

    status = if comment.save
               flash.now[:success] = 'Comment created successfully.'
               :ok
             else
               flash.now[:error] = "Failed to create comment: #{comment.errors.full_messages.to_sentence}."
               :unprocessable_entity
             end

    if Flipper.enabled?(:request_show_redesign, User.session) && ['BsRequest', 'BsRequestAction'].include?(comment.commentable_type)
      respond_to do |format|
        format.html
        format.js { render_diff }
      end
    else
      render(partial: 'webui/comment/comment_list',
             locals: { commentable: @commentable, diff_ref: comment.root.diff_ref },
             status: status,
             root_comment: comment.root)
    end
  end

  def update
    comment = Comment.find(params[:id])
    authorize comment, :update?
    comment.assign_attributes(permitted_params)

    status = if comment.save
               flash.now[:success] = 'Comment updated successfully.'
               :ok
             else
               flash.now[:error] = "Failed to update comment: #{comment.errors.full_messages.to_sentence}."
               :unprocessable_entity
             end

    respond_to do |format|
      format.html do
        if Flipper.enabled?(:request_show_redesign, User.session) && ['BsRequest', 'BsRequestAction'].include?(comment.commentable_type)
          render(partial: 'webui/comment/beta/comments_thread',
                 locals: { comment: comment.root, commentable: comment.commentable, level: 1 },
                 status: status)
        else
          render(partial: 'webui/comment/comment_list',
                 locals: { commentable: comment.commentable, diff_ref: comment.root.diff_ref },
                 status: status)
        end
      end
    end
  end

  # TODO: Once we ship this and we remove the flipper check, this methods will
  # get simpler, so I'll just shut rubocop up for now.
  # rubocop:disable Metrics/CyclomaticComplexity
  # rubocop:disable Metrics/PerceivedComplexity
  def destroy
    comment = Comment.find(params[:id])
    authorize comment, :destroy?
    @commentable = comment.commentable

    status = if comment.blank_or_destroy
               flash.now[:success] = 'Comment deleted successfully.'
               :ok
             else
               flash.now[:error] = "Failed to delete comment: #{comment.errors.full_messages.to_sentence}."
               :unprocessable_entity
             end

    if Flipper.enabled?(:request_show_redesign, User.session) && ['BsRequest', 'BsRequestAction'].include?(comment.commentable_type)
      # if we're a root comment with no replies there is no need to re-render anything
      return head(:ok) if comment.root? && comment.leaf?

      # If we're a reply of an already deleted parent comment, we don't re-render anything
      return head(:ok) if comment.root == comment.parent && comment.unused_parent?

      # If all ancestors are already deleted we don't re-render anything
      return head(:ok) if !comment.root? && comment.ancestors.all?(&:destroyed?)

      # if we're a reply or a comment with replies we should re-render the updated thread
      render(partial: 'webui/comment/beta/comments_thread',
             locals: { comment: comment.root, commentable: @commentable, level: 1 },
             status: status)
    else
      render(partial: 'webui/comment/comment_list', locals: { commentable: @commentable, diff_ref: comment.root.diff_ref }, status: status)
    end
  end
  # rubocop:enable Metrics/PerceivedComplexity
  # rubocop:enable Metrics/CyclomaticComplexity

  def preview
    markdown = helpers.render_as_markdown(permitted_params[:body])
    respond_to do |format|
      format.json { render json: { markdown: markdown } }
    end
  end

  def moderate
    authorize @comment, :moderate?

    state = ActiveModel::Type::Boolean.new.cast(params[:moderation_state])

    status = if @comment.moderate(state)
               flash.now[:success] = 'Comment moderated successfully.'
               :ok
             else
               flash.now[:error] = "Failed to moderate comment: #{@comment.errors.full_messages.to_sentence}."
               :unprocessable_entity
             end

    if Flipper.enabled?(:request_show_redesign, User.session) && ['BsRequest', 'BsRequestAction'].include?(@comment.commentable_type)
      render(partial: 'webui/comment/beta/comments_thread',
             locals: { comment: @comment.root, commentable: @comment.commentable, level: 1 },
             status: status)
    else
      render(partial: 'webui/comment/comment_list',
             locals: { commentable: @comment.commentable, diff_ref: @comment.root.diff_ref },
             status: status,
             root_comment: @comment.root)
    end
  end

  def history
    authorize @comment, :history?

    @version = @comment.versions.find(params[:version_id])
    respond_to do |format|
      format.js { render 'webui/comment/history' }
    end
  end

  def render_diff
    bs_request = @commentable.bs_request
    action = bs_request.webui_actions(diffs: true, action_id: @commentable.id, cacheonly: 1).first
    sourcediff = action[:sourcediff].first
    file_name = params[:file_name]
    file_index = sourcediff['filenames'].index(file_name)
    file_info = sourcediff['files'][file_name]
    commented_lines = @commentable.comments.where('diff_ref LIKE ?', "diff_#{file_index}%").select(:diff_ref).distinct.pluck(:diff_ref)

    render partial: 'webui/comment/render_diff', locals: { 
      diff: file_info.dig('diff', '_content'), file_index: file_index,
      commentable: @commentable, commented_lines: commented_lines, file_name: file_name 
    }
  end

  private

  def permitted_params
    params.require(:comment).permit(:body, :parent_id, :diff_ref)
  end

  # FIXME: Use this function for the rest of the actions
  def set_comment
    @comment = Comment.find(params[:comment_id] || params[:id])
  rescue ActiveRecord::RecordNotFound => e
    flash[:error] = e.message
    render partial: 'layouts/webui/flash'
  end

  def set_commented
    @commentable_type = [Project, Package, BsRequest, BsRequestActionSubmit].find { |klass| klass.name == params[:commentable_type] }
    @commented = @commentable_type&.find_by(id: params[:commentable_id])
    return if @commentable_type.present?

    flash[:error] = "Invalid commentable #{params[:commentable_type]} supplied."
    render partial: 'layouts/webui/flash'
  end
end
