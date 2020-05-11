require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'
require 'socket'

Selenium::WebDriver::Chrome::Service.driver_path = '/usr/lib64/chromium/chromedriver'

Capybara.register_driver :selenium_chrome_headless do |app|
  browser_options = ::Selenium::WebDriver::Chrome::Options.new
  browser_options.args << '--headless'
  browser_options.args << '--no-sandbox'
  browser_options.args << '--allow-insecure-localhost'
  browser_options.add_option('w3c', false)
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: browser_options)
end

Capybara.default_driver = :selenium_chrome_headless
Capybara.javascript_driver = :selenium_chrome_headless
Capybara.save_path = '/tmp/rspec_screens'

# Set hostname
begin
  hostname = Socket.gethostbyname(Socket.gethostname).first
rescue SocketError
  hostname = ""
end
ipaddress = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
hostname = ipaddress if hostname.empty?

Capybara.app_host = ENV.fetch('SMOKETEST_HOST', "https://#{hostname}")

RSpec.configure do |config|
  config.include Capybara::DSL
end
