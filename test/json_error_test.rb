# frozen_string_literal: true

require 'minitest/autorun'
require 'rack/test'
require 'json'

# Set test environment before loading main
ENV['RACK_ENV'] = 'test'
require_relative '../main'

# Configure Sinatra for testing
set :environment, :test
set :show_exceptions, false
set :raise_errors, true

# Test JSON error handling
class JsonErrorTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    # Mock config for testing
    $config = {
      projects: {
        test_project: {
          branch: 'main',
          path: '/tmp/test',
          commands: [{ 'run' => 'echo "test deploy"' }]
        }
      },
      mail_to: ['test@example.com'],
      github_webhook_secret: nil
    }

    # Mock logger
    $logger = Logger.new(File::NULL)
  end

  def test_invalid_json_returns_json_error
    post '/event_handler/test_project',
         'invalid json content',
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 400, last_response.status
    assert_equal 'application/json', last_response.content_type
    
    response_data = JSON.parse(last_response.body)
    assert_equal 'Invalid JSON in request body', response_data['error']
    assert_includes response_data['message'], 'unexpected character'
  end

  def test_missing_github_event_header
    post '/event_handler/test_project',
         '{}',
         { 'CONTENT_TYPE' => 'application/json' }

    assert_equal 400, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'Unsupported GitHub event', response_data['error']
    assert_nil response_data['event']
  end

  def test_content_type_is_json
    post '/event_handler/test_project',
         '{}',
         { 'HTTP_X_GITHUB_EVENT' => 'unknown' }

    assert_equal 'application/json', last_response.content_type
  end
end