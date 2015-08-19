# Settings specified here will take precedence over those in config/environment.rb

OBSApi::Application.configure do

  # The production environment is meant for finished, "live" apps.
  # Code is not reloaded between requests
  config.cache_classes = true

  # Use a different logger for distributed setups
  # config.logger        = SyslogLogger.new
  config.log_level = :info

  config.eager_load = true

  # Enable serving of images, stylesheets, and javascripts from an asset server
  # config.action_controller.asset_host                  = "http://assets.example.com"

  # see http://guides.rubyonrails.org/action_mailer_basics.html#example-action-mailer-configuration
  config.action_mailer.delivery_method = :sendmail

  config.active_support.deprecation = :log
 
   # Enable serving of images, stylesheets, and javascripts from an asset server
   # config.action_controller.asset_host                  = "http://assets.example.com"
 
  config.cache_store = :dalli_store, '127.0.0.1:11211', {namespace: 'obs-api', compress: true, expires_in: 1.day }

  # Full error reports are disabled and caching is turned on
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Disable Rails's static asset server (Apache or nginx will already do this)
  config.serve_static_assets = false 

  # Compress JavaScripts and CSS
  config.assets.compress = true

  # Don't fallback to assets pipeline if a precompiled asset is missed
  config.assets.compile = false

  # Generate digests for assets URLs
  config.assets.digest = true

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation can not be found)
  config.i18n.fallbacks = true

  # compress our HTML
  config.middleware.use Rack::Deflater

end

# disabled on production for performance reasons
# CONFIG['response_schema_validation'] = true

#require 'memory_debugger'
# dumps the objects after every request
#config.middleware.insert(0, MemoryDebugger)

#require 'memory_dumper'
# dumps the full heap after next request on SIGURG
#config.middleware.insert(0, MemoryDumper)

