class CleanupEvents < ActiveJob::Base
  def perform
    Event::Base.transaction do
      Event::Base.where(project_logged: true, queued: true, undone_jobs: 0).lock(true).delete_all
    end
  end
end
