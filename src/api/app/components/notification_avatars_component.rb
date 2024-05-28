class NotificationAvatarsComponent < ApplicationComponent
  MAXIMUM_DISPLAYED_AVATARS = 6

  def initialize(notification)
    super

    @notification = notification
  end

  private

  # rubocop:disable Metrics/CyclomaticComplexity
  # Moved to model
  def avatar_objects
    @avatar_objects ||= case @notification.notifiable_type
                        when 'Comment'
                          commenters
                        when 'Project', 'Package'
                          [User.find_by(login: @notification.event_payload['who'])]
                        when 'Report'
                          [User.find_by(login: @notification.event_payload['reporter'])]
                        when 'Decision'
                          [User.find(@notification.event_payload['moderator_id'])]
                        when 'Appeal'
                          [User.find(@notification.event_payload['appellant_id'])]
                        when 'WorkflowRun'
                          [Token.find(@notification.event_payload['token_id'])&.executor].compact
                        else
                          reviews = @notification.notifiable.reviews
                          reviews.select(&:new?).map(&:reviewed_by) + User.where(login: @notification.notifiable.creator)
                        end
  end
  # rubocop:enable Metrics/CyclomaticComplexity

  def avatars_to_display
    avatar_objects.first(MAXIMUM_DISPLAYED_AVATARS).reverse
  end

  def number_of_hidden_users
    [0, avatar_objects.size - MAXIMUM_DISPLAYED_AVATARS].max
  end

  # NOTE: moved to model
  def commenters
    comments = @notification.notifiable.commentable.comments
    comments.select { |comment| comment.updated_at >= @notification.unread_date }.map(&:user).uniq
  end

  def package_title(package)
    "Package #{package.project}/#{package}"
  end

  def project_title(project)
    "Project #{project}"
  end
end
