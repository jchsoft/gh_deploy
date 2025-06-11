# frozen_string_literal: true

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'cgi'

# Set test environment before loading main
ENV['RACK_ENV'] = 'test'
require_relative '../main'

# Configure Sinatra for testing
set :environment, :test
set :show_exceptions, false
set :raise_errors, true

# Test URL-encoded webhook data like on server
class UrlEncodedTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    $config = {
      projects: {
        vector: {
          branch: 'master',
          path: '/tmp/test',
          commands: [{ 'run' => 'echo "test deploy"' }]
        }
      },
      mail_to: ['test@example.com'],
      github_webhook_secret: nil
    }

    $logger = Logger.new(File::NULL)
  end

  def test_url_encoded_github_actions_data
    # Simulate URL-encoded data like from journalctl.log
    fixture_path = File.join(__dir__, 'fixtures', 'gh_workflow_success.json')
    json_data = File.read(fixture_path)
    
    # URL encode like GitHub sends it
    url_encoded_payload = "payload=#{CGI.escape(json_data)}"
    
    puts "Original JSON length: #{json_data.length}"
    puts "URL encoded length: #{url_encoded_payload.length}"
    puts "First 100 chars: #{url_encoded_payload[0..100]}"

    # Test current handling (should parse JSON correctly)
    post '/event_handler/vector',
         json_data,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'success', response_data['status']
    
    puts "✅ Current implementation handles raw JSON correctly"
  end

  def test_url_encoded_github_workflow_data
    # Test URL-encoded GitHub webhook like server receives
    fixture_path = File.join(__dir__, 'fixtures', 'gh_workflow_success.json')
    json_data = File.read(fixture_path)
    
    # URL encode like GitHub sends it
    url_encoded_payload = "payload=#{CGI.escape(json_data)}"
    
    post '/event_handler/vector',
         url_encoded_payload,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/x-www-form-urlencoded' }

    if last_response.status != 200
      puts "❌ Error response: #{last_response.body}"
    end
    
    assert_equal 200, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'success', response_data['status']
    
    puts "✅ URL-encoded webhook data processed successfully"
  end
end