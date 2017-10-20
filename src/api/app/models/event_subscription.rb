class EventSubscription < ApplicationRecord
  enum channel: %i(disabled instant_email)

  belongs_to :user, inverse_of: :event_subscriptions
  belongs_to :group, inverse_of: :event_subscriptions

  validates :receiver_role, inclusion: {
    in: %i(maintainer
           bugowner
           reader
           source_maintainer
           target_maintainer
           reviewer
           commenter
           creator
           watcher
           source_watcher
           target_watcher)
  }

  scope :for_eventtype, ->(eventtype) { where(eventtype: eventtype) }
  scope :defaults, ->{ where(user_id: nil, group_id: nil) }
  scope :for_subscriber, lambda { |subscriber|
    if subscriber.kind_of? User
      where(user: subscriber)
    elsif subscriber.kind_of? Group
      where(group: subscriber)
    else
      defaults
    end
  }

  def subscriber
    if user_id.present?
      user
    elsif group_id.present?
      group
    end
  end

  def subscriber=(subscriber)
    if subscriber.is_a? User
      self.user = subscriber
    elsif subscriber.is_a? Group
      self.group = subscriber
    end
  end

  def event_class
    # NOTE: safe_ is required here because for some reason we were getting an uninitialized constant error
    # from this line from the functional tests (though not in rspec or in rails server)
    eventtype.safe_constantize
  end

  def receiver_role
    read_attribute(:receiver_role).to_sym
  end

  def enabled?
    !disabled?
  end
end

# == Schema Information
#
# Table name: event_subscriptions
#
#  id            :integer          not null, primary key
#  eventtype     :string(255)      not null
#  receiver_role :string(255)      not null
#  user_id       :integer          indexed
#  created_at    :datetime
#  updated_at    :datetime
#  group_id      :integer          indexed
#  channel       :integer          default("disabled"), not null
#
# Indexes
#
#  index_event_subscriptions_on_group_id  (group_id)
#  index_event_subscriptions_on_user_id   (user_id)
#
