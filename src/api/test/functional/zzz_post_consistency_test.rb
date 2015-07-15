require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_consistency_helper"

class ZZZPostConsistency < ActionDispatch::IntegrationTest
  require 'source_controller'
  fixtures :all

  def setup
    super
    wait_for_scheduler_start
  end

  def test_resubmit_fixtures
    resubmit_all_fixtures
  end

  def test_check_maintenance_project
    login_king
    get "/source/My:Maintenance/_meta"
    assert_response :success

    get "/search/project", :match => '[maintenance/maintains/@project="BaseDistro2.0:LinkedUpdateProject"]'
    assert_response :success
    assert_tag :tag => 'collection', :children => { :count => 1 }
    assert_tag :tag => 'project', :attributes => { :name => "My:Maintenance" }
  end

  def test_fsck_backend

    perlopts="-I#{Rails.root}/../backend -I#{Rails.root}/../backend/build"

    progress=nil
    failed=nil
    # rubocop:disable Metrics/LineLength
    IO.popen("cd #{Rails.root}/tmp/backend_config; exec perl #{perlopts} ./bs_check_consistency --check-all --do-check-meta --do-check-signatures 2>&1") do |io|
      io.each do |line|
#        puts ">#{line}<"
        next if line.blank?

        # catch progress lines
        if line.starts_with? "PROGRESS:"
          progress=line
          next
        end
        next if line.starts_with? "DBPROGRESS:"

        # acceptable during test suite run
        next if line =~ /jobs.dispatchprios missing/;
        next if line =~ /jobs.load missing/;
        next if line =~ /^check finished/;
        next if line =~ /status file without existing job/;
        # broken rpm and broken signature warning. Travis-ci has more errors here
        next if line =~ /broken rpm/;
        next if line =~ /broken signature/;

        # unhandled line, dump a failure
        failed=true
        puts progress if progress
        progress=nil
        puts line
      end
    # rubocop:enable Metrics/LineLength
    end

    assert_nil failed
  end
end
