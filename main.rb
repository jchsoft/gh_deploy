require 'sinatra'
require_relative 'app/config'
require_relative 'services/deploy'
require_relative 'lib/http_status'

set :server, :puma

post '/event_handler/:project' do
  $logger.info"for: #{params['project']}"

  halt NOT_FOUND, "#{params['project']} not found!" unless $config[:projects][params['project'].to_sym]
  halt BAD_REQUEST, "payload in data not found!" unless params['payload']

  payload = JSON.parse(params['payload'])
  $logger.info "payload commit: #{payload['commit'].inspect}"

  deploy = Services::Deploy.new params['project'], payload

  halt OK, 'not a circleCi success' unless deploy.circle_ci_success?
  halt OK, 'not a master branch' unless deploy.right_branch?

  deploy.update!
end
