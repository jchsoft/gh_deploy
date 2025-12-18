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
    VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i

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

    def signoff_status_success?
      @payload['context'] == 'signoff' && @payload['state'] == 'success'
    end

    def github_actions_success?
      workflow_run = @payload['workflow_run']
      return false unless workflow_run

      @payload['action'] == 'completed' &&
        workflow_run['conclusion'] == 'success' &&
        workflow_run['event'] == 'push'
    end

    def signoff_success?
      check_run = @payload['check_run']
      return false unless check_run

      @payload['action'] == 'completed' &&
        check_run['conclusion'] == 'success' &&
        check_run['name'] == 'signoff'
    end

    def right_branch?
      target_branch = $config[:projects][@project.to_sym][:branch]

      case @ci_type
      when 'circleci', 'signoff_status'
        @payload['branches'].any? { |b| b['name'] == target_branch }
      when 'github_actions'
        workflow_run = @payload['workflow_run']
        return false unless workflow_run

        workflow_run['head_branch'] == target_branch
      when 'signoff'
        check_run = @payload['check_run']
        return false unless check_run

        check_run.dig('check_suite', 'head_branch') == target_branch
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

            command_output = `#{command['run']}`
            $logger.debug command_output
            next unless $CHILD_STATUS.exitstatus.to_i != 0

            send_email failed_command: command['run'], exitstatus: $CHILD_STATUS.exitstatus,
                       command_output: command_output
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

    def send_email(failed_command: nil, exitstatus: nil, command_output: nil)
      subject_text = "Deployment of #{@project} #{$config[:projects][@project.to_sym][:branch]} #{failed_command ? 'failed on ' : 'was'} #{failed_command || 'successful'}#{if exitstatus
                                                                                                                                                                              " with exitstatus #{exitstatus}" end}!"

      case @ci_type
      when 'circleci'
        author = @payload['commit']['commit']['author']['email']
        commit = @payload['commit']['commit']
      when 'signoff_status'
        author = @payload['commit']['commit']['author']['email']
        commit = @payload['commit']['commit'].merge('signoff' => "Local CI signoff: #{@payload['description']}")
      when 'github_actions'
        author = @payload['workflow_run']['head_commit']['author']['email']
        commit = @payload['workflow_run']['head_commit']
      when 'signoff'
        # check_run payload has limited commit info, use sender and check_run details
        sender_login = @payload.dig('sender', 'login')
        author = @payload.dig('sender', 'email') || "#{sender_login}@users.noreply.github.com"
        commit = { 'sha' => @payload.dig('check_run', 'head_sha'), 'message' => "Local CI signoff by #{sender_login}" }
      else
        author = 'unknown@example.com'
        commit = {}
      end

      # Filter out invalid email addresses (like dependabot bot emails)
      recipients = ($config[:mail_to] << author).uniq.grep(VALID_EMAIL_REGEX)
      $logger.debug "Sending email to #{recipients.inspect} with subject '#{subject_text}'"

      # Build email body with commit info and optional error details
      email_body = if failed_command && command_output
                     <<~EMAIL
                       #{JSON.pretty_generate(commit)}

                       --- DEPLOYMENT FAILURE DETAILS ---
                       Failed Command: #{failed_command}
                       Exit Status: #{exitstatus}

                       Command Output:
                       #{command_output}
                     EMAIL
                   else
                     JSON.pretty_generate(commit)
                   end

      Mail.deliver do
        from 'notification@jchsoft.cz'
        to recipients
        subject subject_text
        body email_body
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
      when 'signoff_status'
        author = @payload['commit']['commit']['author']['email']
        commit = "#{@payload['commit']['commit']['message']} (#{@payload['description']})"
      when 'github_actions'
        author = @payload['workflow_run']['head_commit']['author']['email']
        commit = @payload['workflow_run']['head_commit']['message']
      when 'signoff'
        sender_login = @payload.dig('sender', 'login')
        author = @payload.dig('sender', 'email') || "#{sender_login}@users.noreply.github.com"
        commit = "Local CI signoff by #{sender_login}"
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
