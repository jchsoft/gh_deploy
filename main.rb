require 'sinatra'
require 'openssl'
require_relative 'app/config'
require_relative 'services/deploy'
require_relative 'lib/http_status'

set :server, :puma

# Optional GitHub webhook signature validation
def verify_signature(payload_body, signature)
  return true unless $config[:github_webhook_secret]
  
  expected_sig = 'sha256=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), $config[:github_webhook_secret], payload_body)
  Rack::Utils.secure_compare(expected_sig, signature || '')
end

post '/event_handler/:project' do
  $logger.info"for: #{params['project']}"

  halt NOT_FOUND, "#{params['project']} not found!" unless $config[:projects][params['project'].to_sym]

  github_event = request.env['HTTP_X_GITHUB_EVENT']
  $logger.info "GitHub event: #{github_event}"

  case github_event
  when 'status'
    # Handle CircleCI status events (existing logic)
    halt BAD_REQUEST, "payload in data not found!" unless params['payload']
    payload = JSON.parse(params['payload'])
    $logger.info "payload commit: #{payload['commit'].inspect}"

    deploy = Services::Deploy.new params['project'], payload, 'circleci'

    halt OK, 'not a circleCi success' unless deploy.circle_ci_success?
    halt OK, 'not a right branch' unless deploy.right_branch?

    deploy.update!

  when 'workflow_run'
    # Handle GitHub Actions workflow_run events
    payload_body = request.body.read
    
    # Optional signature validation
    signature = request.env['HTTP_X_HUB_SIGNATURE_256']
    halt UNAUTHORIZED, 'Invalid signature' unless verify_signature(payload_body, signature)
    
    payload = JSON.parse(payload_body)
    $logger.info "workflow_run payload: action=#{payload['action']}, conclusion=#{payload['workflow_run']['conclusion']}, event=#{payload['workflow_run']['event']}"
    $logger.info "workflow name: #{payload['workflow_run']['name']}, repository: #{payload['repository']['full_name']}"

    deploy = Services::Deploy.new params['project'], payload, 'github_actions'

    halt OK, 'not a github actions success' unless deploy.github_actions_success?
    halt OK, 'not a right branch' unless deploy.right_branch?

    deploy.update!

  else
    halt BAD_REQUEST, "Unsupported GitHub event: #{github_event}"
  end
end
