# frozen_string_literal: true

require 'English'

require 'mail'
require 'net/http'
require 'uri'
require 'json'

# From Rails: config.action_mailer.smtp_settings = { openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE }
Mail.defaults do
  delivery_method :smtp, openssl_verify_mode: OpenSSL::SSL::VERIFY_NONE
end

module Services
  # Handles deployment operations for CI/CD webhooks
  class Deploy
    class << self
    end

    # @param [String] project
    # @param [Hash] payload from GitHub
    # @param [String] ci_type either 'circleci' or 'github_actions'
    def initialize(project, payload, ci_type = 'circleci')
      @project = project
      @payload = payload
      @ci_type = ci_type
    end

    def circle_ci_success?
      @payload['context'] == 'ci/circleci: build' && @payload['state'] == 'success'
    end

    def github_actions_success?
      workflow_run = @payload['workflow_run']
      return false unless workflow_run

      @payload['action'] == 'completed' &&
        workflow_run['conclusion'] == 'success' &&
        workflow_run['event'] == 'push'
    end

    def right_branch?
      case @ci_type
      when 'circleci'
        @payload['branches'].any? { |k| k['name'] == $config[:projects][@project.to_sym][:branch] }
      when 'github_actions'
        workflow_run = @payload['workflow_run']
        return false unless workflow_run

        target_branch = $config[:projects][@project.to_sym][:branch]
        workflow_run['head_branch'] == target_branch
      else
        false
      end
    end

    def update!
      Thread.new do
        Dir.chdir($config[:projects][@project.to_sym][:path]) do
          $logger.debug Dir.getwd
          deploy_failed = false
          $config[:projects][@project.to_sym][:commands].each do |command|
            next unless command.key?('run')

            $logger.debug `#{command['run']}`
            next unless $CHILD_STATUS.exitstatus.to_i != 0

            send_email failed_command: command['run'], exitstatus: $CHILD_STATUS.exitstatus
            deploy_failed = true
            break
          end
          send_email unless deploy_failed
          notify_slack unless deploy_failed
        end
      end
      'Deployment started!'
    end

    private

    def send_email(failed_command: nil, exitstatus: nil)
      subject_text = "Deployment of #{@project} #{$config[:projects][@project.to_sym][:branch]} #{failed_command ? 'failed on ' : 'was'} #{failed_command || 'successful'}#{exitstatus ? " with exitstatus #{exitstatus}" : ''}!"

      case @ci_type
      when 'circleci'
        author = @payload['commit']['commit']['author']['email']
        commit = @payload['commit']['commit']
      when 'github_actions'
        author = @payload['workflow_run']['head_commit']['author']['email']
        commit = @payload['workflow_run']['head_commit']
      else
        author = 'unknown@example.com'
        commit = {}
      end

      recipients = ($config[:mail_to] << author).uniq
      $logger.debug "Sending email to #{recipients.inspect} with subject '#{subject_text}'"

      Mail.deliver do
        from 'notification@jchsoft.cz'
        to recipients
        subject subject_text
        body JSON.pretty_generate(commit)
      end
    end

    def notify_slack
      return unless $config[:projects][@project.to_sym][:slack]
      return unless $config[:projects][@project.to_sym][:slack][:use]

      subject_text = "Deployment of #{@payload['repository']['name']} was successful!"

      case @ci_type
      when 'circleci'
        author = @payload['commit']['commit']['author']['email']
        commit = @payload['commit']['commit']['message']
      when 'github_actions'
        author = @payload['workflow_run']['head_commit']['author']['email']
        commit = @payload['workflow_run']['head_commit']['message']
      else
        author = 'unknown@example.com'
        commit = 'Unknown commit'
      end

      notif_url = $config[:projects][@project.to_sym][:slack][:notif_url]
      return unless notif_url

      uri = URI(notif_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri)
      request.body = {
        text: subject_text,
        attachments: [
          title: author,
          text: commit
        ]
      }.to_json
      response = http.request(request)

      $logger.debug "slack response: #{response.inspect}"
    end
  end
end
