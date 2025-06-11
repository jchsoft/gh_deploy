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

class SignatureTest < Minitest::Test
  include Rack::Test::Methods

  def app  
    Sinatra::Application
  end

  def setup
    # Mock config with webhook secret
    $config = {
      projects: {
        test_project: {
          branch: 'main',
          path: '/tmp/test',
          commands: [{'run' => 'echo "test deploy"'}]
        }
      },
      mail_to: ['test@example.com'],
      github_webhook_secret: 'my_secret_key'
    }
    
    # Mock logger
    $logger = Logger.new('/dev/null')
  end

  def test_valid_signature
    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'main',
        head_commit: {
          author: {email: 'dev@example.com'},
          message: 'Test commit'
        }
      },
      repository: {full_name: 'user/test-repo'}
    }

    payload_body = github_payload.to_json
    signature = 'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), 'my_secret_key', payload_body)

    post '/event_handler/test_project',
         payload_body,
         {
           'HTTP_X_GITHUB_EVENT' => 'workflow_run',
           'HTTP_X_HUB_SIGNATURE_256' => signature,
           'CONTENT_TYPE' => 'application/json'
         }

    assert_equal 200, last_response.status
    assert_equal 'Deployment started!', last_response.body
  end

  def test_invalid_signature
    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'main'
      },
      repository: {full_name: 'user/test-repo'}
    }

    payload_body = github_payload.to_json
    invalid_signature = 'sha256=invalid_signature_here'

    post '/event_handler/test_project',
         payload_body,
         {
           'HTTP_X_GITHUB_EVENT' => 'workflow_run',
           'HTTP_X_HUB_SIGNATURE_256' => invalid_signature,
           'CONTENT_TYPE' => 'application/json'
         }

    assert_equal 401, last_response.status
    assert_equal 'Invalid signature', last_response.body
  end

  def test_missing_signature_header
    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'main'
      },
      repository: {full_name: 'user/test-repo'}
    }

    post '/event_handler/test_project',
         github_payload.to_json,
         {
           'HTTP_X_GITHUB_EVENT' => 'workflow_run',
           'CONTENT_TYPE' => 'application/json'
           # Missing signature header
         }

    assert_equal 401, last_response.status
    assert_equal 'Invalid signature', last_response.body
  end

  def test_signature_validation_disabled
    # Test with no webhook secret configured
    $config[:github_webhook_secret] = nil

    github_payload = {
      action: 'completed',
      workflow_run: {
        conclusion: 'success',
        event: 'push',
        head_branch: 'main',
        head_commit: {
          author: {email: 'dev@example.com'},
          message: 'Test commit'
        }
      },
      repository: {full_name: 'user/test-repo'}
    }

    post '/event_handler/test_project',
         github_payload.to_json,
         {
           'HTTP_X_GITHUB_EVENT' => 'workflow_run',
           'CONTENT_TYPE' => 'application/json'
           # No signature header needed when validation disabled
         }

    assert_equal 200, last_response.status
    assert_equal 'Deployment started!', last_response.body
  end
end