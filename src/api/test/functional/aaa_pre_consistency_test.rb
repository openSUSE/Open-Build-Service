require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_consistency_helper"
require File.join(Rails.root, 'app/jobs/consistency_check.rb')

class AAAPreConsistency < ActionDispatch::IntegrationTest
  fixtures :all

  def test_resubmit_fixtures
    login_king
    wait_for_scheduler_start

    ConsistencyCheckJob.new.perform

    resubmit_all_fixtures

    ConsistencyCheckJob.new.perform
  end
end
