module Event
  class StatusCheckForPublished < StatusCheck
    self.description = 'Status Check for Published Repository Created'
    payload_keys :project, :repository, :uuid

    def self.message_bus_routing_key
      'published.status_report'
    end
  end
end
