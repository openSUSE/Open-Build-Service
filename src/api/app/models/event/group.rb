module Event
  class Group < Base
    self.abstract_class = true

    payload_keys :group, :member, :who

    receiver_roles :member

    def members
      [User.find_by(login: payload['member'])]
    end

    def originator
      payload_address('who')
    end

    def parameters_for_notification
      super.merge({ notifiable_type: 'Group',
                    notifiable_id: Group.find_by(title: payload['group']).id,
                    type: 'NotificationGroup' })
    end
  end
end
