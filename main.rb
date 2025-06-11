# frozen_string_literal: true

require 'sinatra'
require 'openssl'
require_relative 'app/config'
require_relative 'services/deploy'
require_relative 'lib/http_status'

set :server, :puma

# Set content type to JSON for API responses
before do
  content_type :json if request.path_info.start_with?('/event_handler')
end

# Error handlers for JSON responses
error JSON::ParserError do
  status 400
  { error: 'Invalid JSON in request body', message: env['sinatra.error'].message }.to_json
end

error do
  status 500
  { error: 'Internal server error', message: env['sinatra.error']&.message || 'Unknown error' }.to_json
end

# Optional GitHub webhook signature validation
def verify_signature(payload_body, signature)
  return true unless $config[:github_webhook_secret]

  expected_sig = "sha256=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), $config[:github_webhook_secret],
                                                   payload_body)}"
  Rack::Utils.secure_compare(expected_sig, signature || '')
end

post '/event_handler/:project' do
  $logger.info "for: #{params['project']}"

  unless $config[:projects][params['project'].to_sym]
    halt NOT_FOUND, { error: 'Project not found', project: params['project'] }.to_json
  end

  github_event = request.env['HTTP_X_GITHUB_EVENT']
  $logger.info "GitHub event: #{github_event}"

  case github_event
  when 'status'
    # Handle CircleCI status events (existing logic)
    unless params['payload']
      halt BAD_REQUEST, { error: 'Missing payload parameter' }.to_json
    end
    
    payload = JSON.parse(params['payload'])
    $logger.info "payload commit: #{payload['commit'].inspect}"

    deploy = Services::Deploy.new params['project'], payload, 'circleci'

    unless deploy.circle_ci_success?
      halt OK, { status: 'ignored', reason: 'not a CircleCI success' }.to_json
    end
    
    unless deploy.right_branch?
      halt OK, { status: 'ignored', reason: 'not the right branch' }.to_json
    end

    result = deploy.update!
    { status: 'success', message: result }.to_json

  when 'workflow_run'
    # Handle GitHub Actions workflow_run events
    payload_body = request.body.read

    # Optional signature validation
    signature = request.env['HTTP_X_HUB_SIGNATURE_256']
    unless verify_signature(payload_body, signature)
      halt UNAUTHORIZED, { error: 'Invalid webhook signature' }.to_json
    end

    payload = JSON.parse(payload_body)
    $logger.info "workflow_run payload: action=#{payload['action']}, conclusion=#{payload['workflow_run']['conclusion']}, event=#{payload['workflow_run']['event']}"
    $logger.info "workflow name: #{payload['workflow_run']['name']}, repository: #{payload['repository']['full_name']}"

    deploy = Services::Deploy.new params['project'], payload, 'github_actions'

    unless deploy.github_actions_success?
      halt OK, { status: 'ignored', reason: 'not a GitHub Actions success' }.to_json
    end
    
    unless deploy.right_branch?
      halt OK, { status: 'ignored', reason: 'not the right branch' }.to_json
    end

    result = deploy.update!
    { status: 'success', message: result }.to_json

  else
    halt BAD_REQUEST, { error: 'Unsupported GitHub event', event: github_event }.to_json
  end
end
