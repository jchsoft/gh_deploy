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

# Compare both GitHub webhook fixtures
class WebhookComparisonTest < Minitest::Test
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

  def test_in_progress_vs_success_comparison
    puts "\n🔄 Testing in_progress webhook..."
    
    # Test in_progress webhook
    in_progress_path = File.join(__dir__, 'fixtures', 'gh_request.json')
    in_progress_data = JSON.parse(File.read(in_progress_path))
    
    puts "   Action: #{in_progress_data['action']}"
    puts "   Conclusion: #{in_progress_data['workflow_run']['conclusion']}"
    puts "   Status: #{in_progress_data['workflow_run']['status']}"
    
    post '/event_handler/vector',
         File.read(in_progress_path),
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }
    
    response_data = JSON.parse(last_response.body)
    puts "   Result: #{response_data['status']} - #{response_data['reason']}"
    
    assert_equal 'ignored', response_data['status']
    
    puts "\n✅ Testing success webhook..."
    
    # Test success webhook
    success_path = File.join(__dir__, 'fixtures', 'gh_workflow_success.json')
    success_data = JSON.parse(File.read(success_path))
    
    puts "   Action: #{success_data['action']}"
    puts "   Conclusion: #{success_data['workflow_run']['conclusion']}"
    puts "   Status: #{success_data['workflow_run']['status']}"
    
    post '/event_handler/vector',
         File.read(success_path),
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }
    
    response_data = JSON.parse(last_response.body)
    puts "   Result: #{response_data['status']} - #{response_data['message']}"
    
    assert_equal 'success', response_data['status']
    
    puts "\n🎯 Both webhooks handled correctly!"
  end
end