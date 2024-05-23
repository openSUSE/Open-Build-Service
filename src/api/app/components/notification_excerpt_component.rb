class NotificationExcerptComponent < ApplicationComponent
  TRUNCATION_LENGTH = 100
  TRUNCATION_ELLIPSIS_LENGTH = 3 # `...` is the default ellipsis for String#truncate

  def initialize(notifiable)
    super

    @notifiable = notifiable
  end

  def call
    text = case @notifiable.class.name
           when 'BsRequest'
             @notifiable.description.to_s # description can be nil
           when 'Comment'
             helpers.render_without_markdown(@notifiable.body)
           when 'Report', 'Decision', 'Appeal', 'DecisionFavoredWithDeleteRequest', 'DecisionFavoredWithUserCommentingRestrictions', 'DecisionFavoredWithCommentModeration', 'DecisionFavoredWithUserDeletion'
             @notifiable.reason
           when 'WorkflowRun'
             "In repository #{@notifiable.repository_full_name}"
           else
             ''
           end

    truncate_to_first_new_line(text)
  end

  private

  def truncate_to_first_new_line(text)
    first_new_line_index = text.index("\n")
    truncation_index = !first_new_line_index.nil? && first_new_line_index < TRUNCATION_LENGTH ? first_new_line_index + TRUNCATION_ELLIPSIS_LENGTH : TRUNCATION_LENGTH
    text.truncate(truncation_index)
  end
end
