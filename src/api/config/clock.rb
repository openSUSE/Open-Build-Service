require File.dirname(__FILE__) + '/boot'
require File.dirname(__FILE__) + '/environment'

# make sure our event is loaded first - the clockwork::event is *not* ours
require 'event'

require 'clockwork'
require_relative '../lib/obsapi/sphinx_interface'

module Clockwork
  every(30.seconds, 'status.refresh') do
    # this should be fast, so don't delay
    WorkerStatus.new.update_workerstatus_cache
  end

  every(1.hour, 'refresh issues') do
    IssueTracker.update_all_issues
  end

  every(1.hour, 'accept requests') do
    User.current = User.get_default_admin
    BsRequest.delayed_auto_accept
  end

  every(49.minutes, 'rescale history') do
    StatusHistoryRescaler.new.delay.rescale
  end

  every(1.day, 'optimize history', thread: true) do
    ActiveRecord::Base.connection_pool.with_connection do |sql|
      sql.execute 'optimize table status_histories;'
    end
  end

  every(30.seconds, 'send notifications') do
    ::Event::NotifyBackends.trigger_delayed_sent
  end

  every(17.seconds, 'fetch notifications', thread: true) do
    ActiveRecord::Base.connection_pool.with_connection do |sql|
      # this will return if there is already a thread running
      UpdateNotificationEvents.new.perform
    end
  end

  # We want Sphinx to be started everytime clockworkd starts. Scheduling a restart
  # every week ensures that initial start and doesn't really hurt. Not the
  # cleanest solution, but avoids creating/modifying init.d scripts
  every(1.week, 're(start) sphinx', thread: true) do
    OBSApi::SphinxInterface.restart
  end

  every(1.hour, 'reindex sphinx', thread: true) do
    OBSApi::SphinxInterface.index
  end

  every(1.day, 'refresh dirties') do
    # inject a delayed job for every dirty project
    BackendPackage.refresh_dirty
  end

  every(10.minutes, 'project log rotates') do
    ProjectLogRotate.new.delay.perform
  end

  every(1.day, 'clean old events') do
    CleanupEvents.new.delay.perform
  end

  every(1.day, 'create cleanup requests') do
    User.current = User.get_default_admin
    ProjectCreateAutoCleanupRequests.new.delay.perform
  end
end
