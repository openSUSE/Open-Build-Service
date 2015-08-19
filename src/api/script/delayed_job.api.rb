#!/usr/bin/env ruby

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'config', 'environment'))
require 'delayed/command'
require 'workers/import_requests.rb'
require 'workers/update_issues.rb'
Delayed::Command.new(ARGV).daemonize
