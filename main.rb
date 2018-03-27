require 'sinatra'
require_relative 'app/config'
require_relative 'services/deploy/default'
require_relative 'lib/http_status'

set :server, :puma

post '/event_handler/:project' do
  $logger.info"for: #{params['project']}"
  $logger.info'Hello world!'
  halt NOT_FOUND, "#{params['project']} not found!" unless $config[:projects][params['project'].to_sym]
  halt BAD_REQUEST, "payload in data not found!" unless params['payload']
  payload = JSON.parse(params['payload'])
  $logger.info "payload commit: #{payload['commit'].inspect}"

  halt OK, 'not a circleCi success' unless Services::Deploy::Default.circle_ci_success?(payload)
  halt OK, 'not a master branch' unless Services::Deploy::Default.master_branch?(payload['branches'])

  Services::Deploy::Default.update params['project'].to_sym, payload
end
