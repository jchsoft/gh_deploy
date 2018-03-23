require 'sinatra'
require_relative 'app/config'
require_relative 'services/deploy/default'

set :server, :puma

get '/event_handler/:project' do
  $logger.info"for: #{params['project']}"
  $logger.info'Hello world!'
  halt 404, "#{params['project']} not found!" unless $config[:projects][params['project']]
  payload = JSON.parse(params[:payload])
  $logger.info "payload: #{payload.inspect}"
  Services::Deploy::Default.update params['project'].to_sym
end
