# frozen_string_literal: true
require 'mail'
require 'net/http'
require 'uri'
require 'json'

module Services
  class Deploy

    class << self

    end

    # @param [String] project
    # @param [Hash] payload from GitHub
    def initialize(project, payload)
      @project = project
      @payload = payload
    end

    def circle_ci_success?
      @payload['context'] == 'ci/circleci' && @payload['state'] == 'success'
    end

    def right_branch?
      @payload['branches'].select { |k| k['name'] == $config[:projects][@project.to_sym][:branch] }.any?
    end

    def update!
      Thread.new do
        Dir.chdir($config[:projects][@project.to_sym][:path]) do
          $logger.debug Dir.getwd
          deploy_failed = false
          $config[:projects][@project.to_sym][:commands].each do |command|
            if command.key?('run')
              $logger.debug `#{command['run']}`
              if $?.exitstatus.to_i != 0
                send_email failed_command: command['run'], exitstatus: $?.exitstatus
                deploy_failed = true
                break
              end
            end
          end
          send_email unless deploy_failed
          notify_slack unless deploy_failed
        end
      end
      'Deployment started!'
    end

    private

    def send_email(failed_command: nil, exitstatus: nil)
      subject_text = "Deployment of #{@payload['repository']['name']} #{failed_command ? 'failed on ' : 'was'} #{failed_command || 'successful'}#{" with exitstatus #{exitstatus}" if exitstatus}!"
      author = @payload['commit']['commit']['author']['email']
      commit = @payload['commit']
      Mail.deliver do
        from "notification@jchsoft.cz"
        to author
        subject subject_text
        body JSON.pretty_generate(commit)
      end
    end

    def notify_slack
      return unless $config[:projects][@project.to_sym][:slack]
      return unless $config[:projects][@project.to_sym][:slack][:use]

      subject_text = "Deployment of #{@payload['repository']['name']} was successful!"
      author = @payload['commit']['commit']['author']['email']
      commit = @payload['commit']['commit']['message']

      uri = URI($config[:projects][@project.to_sym][:slack][:notif_url])
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = {text: "#{subject_text}\n#{commit}\n#{author}"}.to_json
      res = Net::HTTP.start(uri.hostname, uri.port) do |http|
        http.request(req)
      end
      $logger.debug "slack response: #{res.inspect}"
    end
  end
end
