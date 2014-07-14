class CreateJob
  
  def initialize(event) 
    self.event = event
  end

  def after(job)
    event = job.payload_object.event
    # in test suite the undone_jobs are 0 as the delayed jobs are not delayed
    Rails.logger.debug "WITH #{event.inspect}"
    event.with_lock do
      event.undone_jobs -= 1
      Rails.logger.debug "WITHOUT #{event.inspect}"
      event.save!
    end
  end

  def error(job, exception)
    HoptoadNotifier.notify(exception, job.inspect)
    notify_hoptoad(ex)
  end
end
