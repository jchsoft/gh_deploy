# frozen_string_literal: true

require 'yaml'
require 'logger'

require_relative '../lib/symbolize_hash'

$config = YAML.load_file('config.yml').symbolize_keys

VERSION = 0.01

$environment = $config[:environment] || ENV['RACK_ENV'] || 'development'

$logger = Logger.new case $config[:log_to]
                     when 'STDOUT'
                       $stdout
                     when 'STDERR'
                       $stderr
                     when 'FILE'
                       "log/#{$environment}.log"
                     else
                       raise "unknown config log_to: #{$config[:log_to]}"
                     end
