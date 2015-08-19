module CommentEvent

  def self.included(base)
    base.class_eval do
      payload_keys :commenters, :commenter, :comment_body, :comment_title
      receiver_roles :commenter
    end
  end

  def expanded_payload
    p = payload.dup
    p['commenter'] = User.find(p['commenter'])
    p
  end

  def originator
    User.find(payload['commenter'])
  end

  def commenters
    return [] unless payload['commenters']
    User.find(payload['commenters'])
  end
end

class Event::CommentForProject < ::Event::Project
  include CommentEvent
  receiver_roles :maintainer

  self.description = 'New comment for project created'

  def subject
    "New comment in project #{payload['project']} by #{User.find(payload['commenter']).login}"
  end

end

class Event::CommentForPackage < ::Event::Package
  include CommentEvent
  receiver_roles :maintainer

  self.description = 'New comment for package created'

  def subject
    "New comment in package #{payload['project']}/#{payload['package']} by #{User.find(payload['commenter']).login}"
  end

end

class Event::CommentForRequest < ::Event::Request

  include CommentEvent
  self.description = 'New comment for request created'
  payload_keys :request_id
  receiver_roles :source_maintainer, :target_maintainer, :creator, :reviewer

  def subject
    req = BsRequest.find(payload['id'])
    req_payload = req.notify_parameters
    "Request #{payload['id']} commented by #{User.find(payload['commenter']).login} (#{BsRequest.actions_summary(req_payload)})"
  end

end

