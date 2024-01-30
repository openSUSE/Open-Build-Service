module Event
  class AppealCreated < Base
    receiver_roles :moderator

    self.description = 'A user has appealed the decision of a moderator'

    payload_keys :id, :appellant_id, :decision_id, :reason, :report_last_id, :reportable_type

    def subject
      appeal = Appeal.find(payload['id'])
      "Appeal to #{appeal.decision.reports.first.reportable&.class&.name || appeal.decision.reports.first.reportable_type} decision".squish
    end
  end
end

# == Schema Information
#
# Table name: events
#
#  id          :bigint           not null, primary key
#  eventtype   :string(255)      not null, indexed
#  mails_sent  :boolean          default(FALSE), indexed
#  payload     :text(65535)
#  undone_jobs :integer          default(0)
#  created_at  :datetime         indexed
#  updated_at  :datetime
#
# Indexes
#
#  index_events_on_created_at  (created_at)
#  index_events_on_eventtype   (eventtype)
#  index_events_on_mails_sent  (mails_sent)
#
