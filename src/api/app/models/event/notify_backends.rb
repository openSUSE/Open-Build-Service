module Event
# performed from delayed job triggered by clockwork
 class NotifyBackends
  def self.trigger_delayed_sent
    self.new.delay.send_not_in_queue
  end

  def send_not_in_queue
    Event::Base.not_in_queue.find_each do |e|
      e.notify_backend
    end
  end
 end
end
