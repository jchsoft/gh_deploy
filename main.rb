require 'sinatra'
require 'services/deploy/default'

set :server, :puma

get '/' do
  $logger.info'Hello world!'
end
