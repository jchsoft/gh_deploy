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

class WebhookTest < Minitest::Test
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
      github_webhook_secret: nil # Disable signature validation for tests
    }

    # Mock logger
    $logger = Logger.new(File::NULL)
  end

  def test_circleci_success_webhook
    circleci_payload = {
      context: 'ci/circleci: build',
      state: 'success',
      branches: [{ 'name' => 'main' }],
      commit: {
        commit: {
          author: { email: 'dev@example.com' },
          message: 'Test commit'
        }
      },
      repository: { name: 'test-repo' }
    }

    post '/event_handler/test_project',
         { payload: circleci_payload.to_json },
         { 'HTTP_X_GITHUB_EVENT' => 'status' }

    puts "Response: #{last_response.status} - #{last_response.body}" if last_response.status != 200
    assert_equal 200, last_response.status
    assert_equal 'Deployment started!', last_response.body
  end

  def test_circleci_wrong_context
    circleci_payload = {
      context: 'ci/travis: build', # Wrong context
      state: 'success',
      branches: [{ 'name' => 'main' }]
    }

    post '/event_handler/test_project',
         { payload: circleci_payload.to_json },
         { 'HTTP_X_GITHUB_EVENT' => 'status' }

    assert_equal 200, last_response.status
    assert_equal 'not a circleCi success', last_response.body
  end

  def test_circleci_wrong_branch
    circleci_payload = {
      context: 'ci/circleci: build',
      state: 'success',
      branches: [{ 'name' => 'develop' }] # Wrong branch
    }

    post '/event_handler/test_project',
         { payload: circleci_payload.to_json },
         { 'HTTP_X_GITHUB_EVENT' => 'status' }

    assert_equal 200, last_response.status
    assert_equal 'not a right branch', last_response.body
  end

  def test_github_actions_success_webhook
    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        name: 'CI',
        head_branch: 'main',
        head_commit: {
          author: { email: 'dev@example.com' },
          message: 'Test commit',
          id: 'abc123'
        }
      },
      repository: {
        name: 'test-repo',
        full_name: 'user/test-repo'
      }
    }

    post '/event_handler/test_project',
         github_payload.to_json,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    assert_equal 'Deployment started!', last_response.body
  end

  def test_github_actions_wrong_conclusion
    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'failure',  # Wrong conclusion
        event: 'push',
        head_branch: 'main'
      },
      repository: { full_name: 'user/test-repo' }
    }

    post '/event_handler/test_project',
         github_payload.to_json,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    assert_equal 'not a github actions success', last_response.body
  end

  def test_github_actions_wrong_branch
    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'develop'  # Wrong branch
      },
      repository: { full_name: 'user/test-repo' }
    }

    post '/event_handler/test_project',
         github_payload.to_json,
         { 'HTTP_X_GITHUB_EVENT' => 'workflow_run', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status
    assert_equal 'not a right branch', last_response.body
  end

  def test_unknown_event_type
    post '/event_handler/test_project',
         '{}',
         { 'HTTP_X_GITHUB_EVENT' => 'unknown_event', 'CONTENT_TYPE' => 'application/json' }

    assert_equal 400, last_response.status
    assert_equal 'Unsupported GitHub event: unknown_event', last_response.body
  end

  def test_nonexistent_project
    post '/event_handler/nonexistent_project',
         { payload: '{}' }.to_json,
         { 'HTTP_X_GITHUB_EVENT' => 'status' }

    assert_equal 404, last_response.status
    assert_equal 'nonexistent_project not found!', last_response.body
  end
end
