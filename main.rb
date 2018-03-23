require 'sinatra'
require 'services/deploy/default'

set :server, :puma

get '/event_handler/:project' do
  $logger.info"for: #{params['project']}"
  $logger.info'Hello world!'
  payload = JSON.parse(params[:payload])
  $logger.info "payload: #{payload.inspect}"
  Services::Deploy::Default.update params['project'].to_sym if $config[:projects][params['project'].to_sym]
end
