# Settings specified here will take precedence over those in config/environment.rb

OBSApi::Application.configure do

  # Settings specified here will take precedence over those in config/application.rb

  # In the development environment your application's code is reloaded on
  # every request. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Show full error reports and disable caching
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = true
  config.cache_store = :dalli_store, '127.0.0.1:11211', {namespace: 'obs-api', expires_in: 1.hour }

  # Don't care if the mailer can't send
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.delivery_method = :test

  # Print deprecation notices to the Rails logger
  config.active_support.deprecation = :log

  # Only use best-standards-support built into browsers
  config.action_dispatch.best_standards_support = :builtin

  # Do not compress assets
  config.assets.compress = false

  # Expands the lines which load the assets
  config.assets.logger = nil
  config.assets.debug = false

  # Enable debug logging by default
  config.log_level = :debug

  config.action_controller.perform_caching = true

  config.eager_load = false

  config.secret_key_base = '92b2ed725cb4d68cc5fbf86d6ba204f1dec4172086ee7eac8f083fb62ef34057f1b770e0722ade7b298837be7399c6152938627e7d15aca5fcda7a4faef91fc7'
end

CONFIG['extended_backend_log'] = true
CONFIG['response_schema_validation'] = true

CONFIG['frontend_host'] = "localhost"
CONFIG['frontend_protocol'] = "http"

require 'socket'
fname = "#{Rails.root}/config/environments/development.#{Socket.gethostname}.rb"
if File.exists? fname
  STDERR.puts "Using local environment #{fname}"
  eval File.read(fname)  
else
  STDERR.puts "Custom development.#{Socket.gethostname}.rb not found - using defaults"
end


