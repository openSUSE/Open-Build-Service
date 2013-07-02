# Be sure to restart your web server when you modify this file.

# Load the rails application
require File.expand_path('../application', __FILE__)

path = Rails.root.join("config", "options.yml")

begin
  CONFIG = YAML.load_file(path)
rescue Exception
  puts "Error while parsing config file #{path}"
  CONFIG = Hash.new
end

CONFIG['schema_location'] ||= File.expand_path("public/schema")+"/"
CONFIG['global_write_through'] ||= true

# Initialize the rails application
OBSApi::Application.initialize!

