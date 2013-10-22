ENV['RAILS_ENV'] = 'test'

require 'simplecov'
require 'simplecov-rcov'
SimpleCov.start 'rails' do
  add_filter '/app/indices/'
  add_filter '/app/models/user_ldap_stretegy.rb'
end if ENV['DO_COVERAGE']

require File.expand_path('../../config/environment', __FILE__)
require 'rails/test_help'

require 'minitest/unit'

require 'webmock/minitest'

require 'opensuse/backend'

require_relative 'activexml_matcher'

require 'test/unit/assertions'
require 'mocha/setup'

require 'headless'

require 'capybara/rails'
Capybara.default_driver = :webkit
## this is the build service! 2 seconds - HAHAHA
Capybara.default_wait_time = 10

WebMock.disable_net_connect!(allow_localhost: true)

unless File.exists? '/proc'
  print 'ERROR: proc file system not mounted, aborting'
  exit 1
end
unless File.exists? '/dev/fd'
  print 'ERROR: /dev/fd does not exist, aborting'
  exit 1
end

# uncomment to enable tests which currently are known to fail, but where either the test
# or the code has to be fixed
#$ENABLE_BROKEN_TEST=true

def inject_build_job(project, package, repo, arch)
  job=IO.popen("find #{Rails.root}/tmp/backend_data/jobs/#{arch}/ -name #{project}::#{repo}::#{package}-*")
  jobfile=job.readlines.first
  return unless jobfile
  jobfile.chomp!
  jobid=''
  IO.popen("md5sum #{jobfile}|cut -d' ' -f 1") do |io|
    jobid = io.readlines.first.chomp
  end
  data = REXML::Document.new(File.new(jobfile))
  verifymd5 = data.elements['/buildinfo/verifymd5'].text
  f = File.open("#{jobfile}:status", 'w')
  f.write("<jobstatus code=\"building\"> <jobid>#{jobid}</jobid> <workerid>simulated</workerid> <hostarch>#{arch}</hostarch> </jobstatus>")
  f.close
  system("cd #{Rails.root}/test/fixtures/backend/binary/; exec find . -name '*#{arch}.rpm' -o -name '*src.rpm' -o -name logfile -o -name _statistics | cpio -H newc -o 2>/dev/null | curl -s -X POST -T - 'http://localhost:3201/putjob?arch=#{arch}&code=success&job=#{jobfile.gsub(/.*\//, '')}&jobid=#{jobid}' > /dev/null")
  system("echo \"#{verifymd5}  #{package}\" > #{jobfile}:dir/meta")
end

module ActionDispatch
  module Integration
    class Session
      def add_auth(headers)
        headers = Hash.new if headers.nil?
        if !headers.has_key? 'HTTP_AUTHORIZATION' and IntegrationTest.basic_auth
          headers['HTTP_AUTHORIZATION'] = IntegrationTest.basic_auth
        end
        return headers
      end

      alias_method :real_process, :process

      def process(method, path, parameters, rack_env)
        CONFIG['global_write_through'] = true
        if path !~ %r{/webui2}
          self.accept = 'text/xml,application/xml'
        else
          reset!
        end
        real_process(method, path, parameters, add_auth(rack_env))
      end

      def raw_post(path, data, parameters = nil, rack_env = nil)
        rack_env ||= Hash.new
        rack_env['CONTENT_TYPE'] ||= 'application/octet-stream'
        rack_env['CONTENT_LENGTH'] = data.length
        rack_env['RAW_POST_DATA'] = data
        process(:post, path, parameters, add_auth(rack_env))
      end

      def raw_put(path, data, parameters = nil, rack_env = nil)
        rack_env ||= Hash.new
        rack_env['CONTENT_TYPE'] ||= 'application/octet-stream'
        rack_env['CONTENT_LENGTH'] = data.length
        rack_env['RAW_POST_DATA'] = data
        process(:put, path, parameters, add_auth(rack_env))
      end

    end
  end
end

module Webui
  class IntegrationTest < ActionDispatch::IntegrationTest
    # Make the Capybara DSL available
    include Capybara::DSL

    @@frontend = nil
    def self.start_test_api
      return if @@frontend
      if ENV['API_STARTED']
        @@frontend = :dont
        return
      end
      # avoid a race
      Suse::Backend.start_test_backend
      @@frontend = IO.popen(Rails.root.join('script', 'start_test_api').to_s)
      puts "Starting test API with pid: #{@@frontend.pid}"
      lines = []
      while true do
        line = @@frontend.gets
        unless line
          puts lines.join()
          raise RuntimeError.new('Frontend died')
        end
        break if line =~ /Test API ready/
        lines << line
      end
      puts "Test API up and running with pid: #{@@frontend.pid}"
      at_exit do
        puts "Killing test API with pid: #{@@frontend.pid}"
        Process.kill "INT", @@frontend.pid
        Process.wait
        @@frontend = nil
      end
    end

    def login_user(user, password, do_assert = true)
      # no idea why calling it twice would help
      WebMock.disable_net_connect!(allow_localhost: true)
      visit webui_engine.root_path
      click_link 'login-trigger'
      within('#login-form') do
        fill_in 'Username', with: user
        fill_in 'Password', with: password
        click_button 'Log In'
      end
      @current_user = user
      if do_assert
        find('#flash-messages').must_have_content("You are logged in now")
      end
    end

    # will provide a user without special permissions
    def login_tom
      login_user('tom', 'thunder')
    end

    def login_Iggy
      login_user('Iggy', 'asdfasdf')
    end

    def login_adrian
      login_user('adrian', 'so_alone')
    end

    def login_king
      login_user("king", "sunflower", false)
    end

    def login_fred
      login_user("fred", "geröllheimer")
    end

    def logout
      @current_user = nil
      ll = page.first('#logout-link')
      ll.click if ll
    end

    def current_user
      @current_user
    end

    @@display = nil

    self.use_transactional_fixtures = false
    fixtures :all

    setup do
      if !@@display
        @@display = Headless.new
        @@display.start
      end
      olddriver = Capybara.current_driver
      Capybara.current_driver = :rack_test
      self.class.start_test_api
      ActiveXML::api.http_do :post, "/test/test_start"
      Capybara.current_driver = olddriver
      @starttime = Time.now
      WebMock.disable_net_connect!(allow_localhost: true)
      #max=::BsRequest.maximum(:id)
      #::BsRequest.connection.execute("alter table bs_requests AUTO_INCREMENT = #{max+1}")
      CONFIG['global_write_through'] = true
    end

    teardown do
      dirpath = Rails.root.join("tmp", "capybara")
      htmlpath = dirpath.join(self.__name__ + ".html")
      if !passed?
        Dir.mkdir(dirpath) unless Dir.exists? dirpath
        save_page(htmlpath)
      elsif File.exists?(htmlpath)
        File.unlink(htmlpath)
      end
      logout

      Capybara.reset_sessions!
      Capybara.use_default_driver
      Rails.cache.clear
      WebMock.reset!
      ActiveRecord::Base.clear_active_connections!
      DatabaseCleaner.clean_with :truncation,  pre_count: true

      #puts "#{self.__name__} took #{Time.now - @starttime}"
    end

    # ============================================================================
    # Checks if a flash message is displayed on screen
    #
    def flash_message_appeared?
      flash_message_type != nil
    end

    # ============================================================================
    # Returns the text of the flash message currenlty on screen
    # @note Doesn't fail if no message is on screen. Returns empty string instead.
    # @return [String]
    #
    def flash_message
      results = all(:css, "div#flash-messages p")
      if results.empty?
        return "none"
      end
      raise "One flash expected, but we had more." if results.count != 1
      return results.first.text
    end

    # ============================================================================
    # Returns the text of the flash messages currenlty on screen
    # @note Doesn't fail if no message is on screen. Returns empty list instead.
    # @return [array]
    #
    def flash_messages
      results = all(:css, "div#flash-messages p")
      ret = []
      results.each { |r| ret << r.text }
      return ret
    end

    # ============================================================================
    # Returns the type of the flash message currenlty on screen
    # @note Does not fail if no message is on screen! Returns nil instead!
    # @return [:info, :alert]
    #
    def flash_message_type
      result = first(:css, "div#flash-messages span")
      return nil unless result
      return :info if result["class"].include? "info"
      return :alert if result["class"].include? "alert"
    end

    # helper function for teardown
    def delete_package project, package
      visit webui_engine.package_show_path(package: package, project: project)
      find(:id, 'delete-package').click
      find(:id, 'del_dialog').must_have_text 'Delete Confirmation'
      find_button("Ok").click
      find('#flash-messages').must_have_text "Package '#{package}' was removed successfully"
    end

  end
end

module ActionDispatch
  class IntegrationTest

    def teardown
      Rails.cache.clear
      reset_auth
      WebMock.reset!
    end

    @@auth = nil

    def reset_auth
      @@auth = nil
    end

    def self.basic_auth
      return @@auth
    end

    def basic_auth
      return @@auth
    end

    def prepare_request_with_user(user, passwd)
      re = 'Basic ' + Base64.encode64(user + ':' + passwd)
      @@auth = re
    end

    # will provide a user without special permissions
    def prepare_request_valid_user
      prepare_request_with_user 'tom', 'thunder'
    end

    def prepare_request_invalid_user
      prepare_request_with_user 'tom123', 'thunder123'
    end

    def load_backend_file(path)
      File.open(ActionController::TestCase.fixture_path + "/backend/#{path}").read()
    end

    def assert_xml_tag(conds)
      node = ActiveXML::Node.new(@response.body)
      ret = node.find_matching(NodeMatcher::Conditions.new(conds))
      raise MiniTest::Assertion.new("expected tag, but no tag found matching #{conds.inspect} in:\n#{node.dump_xml}") unless ret
    end

    def assert_no_xml_tag(conds)
      node = ActiveXML::Node.new(@response.body)
      ret = node.find_matching(NodeMatcher::Conditions.new(conds))
      raise MiniTest::Assertion.new("expected no tag, but found tag matching #{conds.inspect} in:\n#{node.dump_xml}") if ret
    end

    # useful to fix our test cases
    def url_for(hash)
      raise ArgumentError.new('we need a hash here') unless hash.kind_of? Hash
      raise ArgumentError.new('we need a :controller') unless hash.has_key?(:controller)
      raise ArgumentError.new('we need a :action') unless hash.has_key?(:action)
      super(hash)
    end

    def wait_for_publisher
      Rails.logger.debug 'Wait for publisher'
      counter = 0
      while counter < 100
        events = Dir.open(Rails.root.join('tmp/backend_data/events/publish'))
        #  3 => ".", ".." and ".ping"
        break unless events.count > 3
        sleep 0.5
        counter = counter + 1
      end
      if counter == 100
        raise 'Waited 50 seconds for publisher'
      end
    end

    def wait_for_scheduler_start
      # make sure it's actually tried to start
      Suse::Backend.start_test_backend
      Rails.logger.debug 'Wait for scheduler thread to finish start'
      counter = 0
      marker = Rails.root.join('tmp', 'scheduler.done')
      while counter < 100
        return if File.exists?(marker)
        sleep 0.5
        counter = counter + 1
      end
    end

    def run_scheduler(arch)
      Rails.logger.debug "RUN_SCHEDULER #{arch}"
      perlopts="-I#{Rails.root}/../backend -I#{Rails.root}/../backend/build"
      IO.popen("cd #{Rails.root}/tmp/backend_config; exec perl #{perlopts} ./bs_sched --testmode #{arch}") do |io|
        # just for waiting until scheduler finishes
        io.each { |line| line.strip.chomp unless line.blank? }
      end
    end

    def login_king
      prepare_request_with_user 'king', 'sunflower'
    end

    def login_Iggy
      prepare_request_with_user 'Iggy', 'asdfasdf'
    end

    def login_adrian
      prepare_request_with_user 'adrian', 'so_alone'
    end

    def login_fred
      prepare_request_with_user 'fred', 'geröllheimer'
    end

    def login_tom
      prepare_request_with_user 'tom', 'thunder'
    end

    def login_dmayr
      prepare_request_with_user 'dmayr', '123456'
    end

  end
end

class ActiveSupport::TestCase
  def assert_xml_tag(data, conds)
    node = ActiveXML::Node.new(data)
    ret = node.find_matching(NodeMatcher::Conditions.new(conds))
    assert ret, "expected tag, but no tag found matching #{conds.inspect} in:\n#{node.dump_xml}" unless ret
  end

  def assert_no_xml_tag(data, conds)
    node = ActiveXML::Node.new(data)
    ret = node.find_matching(NodeMatcher::Conditions.new(conds))
    assert !ret, "expected no tag, but found tag matching #{conds.inspect} in:\n#{node.dump_xml}" if ret
  end

  def load_backend_file(path)
    File.open(ActionController::TestCase.fixture_path + "/backend/#{path}").read()
  end

  def teardown
    Rails.cache.clear
  end
end

