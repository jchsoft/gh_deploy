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

# Test with real GitHub Actions data
class RealGithubTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    # Mock config for testing with real project name from fixture
    $config = {
      projects: {
        vector: {  # Project name from URL path
          branch: 'master',  # Branch from fixture
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

  def test_real_github_in_progress_request
    # Load real GitHub Actions request
    fixture_path = File.join(__dir__, 'fixtures', 'gh_request.json')
    github_payload = File.read(fixture_path)

    post '/event_handler/vector',
         github_payload,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    assert_equal 'application/json', last_response.content_type

    response_data = JSON.parse(last_response.body)
    assert_equal 'ignored', response_data['status']
    assert_equal 'not a GitHub Actions success', response_data['reason']

    puts "✅ Real GitHub 'in_progress' request correctly ignored"
  end

  def test_real_github_completed_success_request
    # Modify real request to simulate completed successful workflow
    fixture_path = File.join(__dir__, 'fixtures', 'gh_request.json')
    github_data = JSON.parse(File.read(fixture_path))
    
    # Change to completed successful workflow
    github_data['action'] = 'completed'
    github_data['workflow_run']['conclusion'] = 'success'
    github_data['workflow_run']['status'] = 'completed'

    post '/event_handler/vector',
         github_data.to_json,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'success', response_data['status']
    assert_equal 'Deployment started!', response_data['message']

    puts "✅ Modified GitHub 'completed/success' request triggers deployment"
  end

  def test_real_github_wrong_branch
    # Modify real request to use different branch
    fixture_path = File.join(__dir__, 'fixtures', 'gh_request.json')
    github_data = JSON.parse(File.read(fixture_path))
    
    # Change to completed successful workflow but wrong branch
    github_data['action'] = 'completed'
    github_data['workflow_run']['conclusion'] = 'success' 
    github_data['workflow_run']['head_branch'] = 'develop'  # Wrong branch

    post '/event_handler/vector',
         github_data.to_json,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'ignored', response_data['status']
    assert_equal 'not the right branch', response_data['reason']

    puts "✅ Wrong branch correctly ignored"
  end

  def test_real_github_completed_success_fixture
    # Test with actual successful workflow fixture
    fixture_path = File.join(__dir__, 'fixtures', 'gh_workflow_success.json')
    github_payload = File.read(fixture_path)

    post '/event_handler/vector',
         github_payload,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    assert_equal 'application/json', last_response.content_type

    response_data = JSON.parse(last_response.body)
    assert_equal 'success', response_data['status']
    assert_equal 'Deployment started!', response_data['message']

    puts "✅ Real successful GitHub workflow triggers deployment"
  end
end