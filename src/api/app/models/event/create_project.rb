module Event
  class CreateProject < Base
    self.description = 'Project is created'
    payload_keys :project, :sender
    after_create_commit :send_to_bus

    def self.message_bus_routing_key
      'project.create'
    end

    def subject
      "New Project #{payload['project']}"
    end

    private

    def metric_tags
      { project: payload['project'], home: ::Project.home?(payload['project']) }
    end

    def metric_fields
      { count: Project.count }
    end
  end
end

# == Schema Information
#
# Table name: events
#
#  id          :integer          not null, primary key
#  eventtype   :string(255)      not null, indexed
#  payload     :text(65535)
#  created_at  :datetime         indexed
#  updated_at  :datetime
#  undone_jobs :integer          default(0)
#  mails_sent  :boolean          default(FALSE), indexed
#
# Indexes
#
#  index_events_on_created_at  (created_at)
#  index_events_on_eventtype   (eventtype)
#  index_events_on_mails_sent  (mails_sent)
#
