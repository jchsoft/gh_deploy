# frozen_string_literal: true

require 'minitest/autorun'
require 'rack/test'
require 'json'
require 'openssl'

# Set test environment before loading main
ENV['RACK_ENV'] = 'test'
require_relative '../main'

# Configure Sinatra for testing
set :environment, :test
set :show_exceptions, false
set :raise_errors, true

# Test signature validation functionality
class SignatureTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    setup_config
    setup_logger
  end

  private

  def setup_config
    $config = {
      projects: {
        test_project: {
          branch: 'main',
          path: '/tmp/test',
          commands: [{ 'run' => 'echo "test deploy"' }]
        }
      },
      mail_to: ['test@example.com'],
      github_webhook_secret: 'my_secret_key'
    }
  end

  def setup_logger
    $logger = Logger.new(File::NULL)
  end

  public

  def test_valid_signature
    github_payload = valid_github_payload
    payload_body = github_payload.to_json
    signature = generate_signature(payload_body)

    post '/event_handler/test_project',
         payload_body,
         valid_signature_headers(signature)

    assert_equal 200, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'success', response_data['status']
    assert_equal 'Deployment started!', response_data['message']
  end

  def test_invalid_signature
    github_payload = simple_github_payload
    payload_body = github_payload.to_json
    invalid_signature = 'sha256=invalid_signature_here'

    post '/event_handler/test_project',
         payload_body,
         invalid_signature_headers(invalid_signature)

    assert_equal 401, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'Invalid webhook signature', response_data['error']
  end

  def test_missing_signature_header
    github_payload = simple_github_payload

    post '/event_handler/test_project',
         github_payload.to_json,
         missing_signature_headers

    assert_equal 401, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'Invalid webhook signature', response_data['error']
  end

  def test_signature_validation_disabled
    # Test with no webhook secret configured
    $config[:github_webhook_secret] = nil
    github_payload = valid_github_payload

    post '/event_handler/test_project',
         github_payload.to_json,
         disabled_validation_headers

    assert_equal 200, last_response.status
    response_data = JSON.parse(last_response.body)
    assert_equal 'success', response_data['status']
    assert_equal 'Deployment started!', response_data['message']
  end

  private

  def valid_github_payload
    {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'main',
        head_commit: {
          author: { email: 'dev@example.com' },
          message: 'Test commit'
        }
      },
      repository: { full_name: 'user/test-repo' }
    }
  end

  def simple_github_payload
    {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'main'
      },
      repository: { full_name: 'user/test-repo' }
    }
  end

  def generate_signature(payload_body)
    "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), 'my_secret_key', payload_body)}"
  end

  def valid_signature_headers(signature)
    {
      'HTTP_X_GITHUB_EVENT' => 'workflow_run',
      'HTTP_X_HUB_SIGNATURE_256' => signature,
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def invalid_signature_headers(signature)
    {
      'HTTP_X_GITHUB_EVENT' => 'workflow_run',
      'HTTP_X_HUB_SIGNATURE_256' => signature,
      'CONTENT_TYPE' => 'application/json'
    }
  end

  def missing_signature_headers
    {
      'HTTP_X_GITHUB_EVENT' => 'workflow_run',
      'CONTENT_TYPE' => 'application/json'
      # Missing signature header
    }
  end

  def disabled_validation_headers
    {
      'HTTP_X_GITHUB_EVENT' => 'workflow_run',
      'CONTENT_TYPE' => 'application/json'
      # No signature header needed when validation disabled
    }
  end
end
