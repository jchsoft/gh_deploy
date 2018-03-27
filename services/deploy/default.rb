# frozen_string_literal: true
require 'mail'

module Services
  module Deploy
    class Default

      class << self

        # @param [Hash] payload from GitHub
        def circle_ci_success?(payload)
          payload['context'] == 'ci/circleci' && payload['state'] == 'success'
        end

        def master_branch?(branches)
          branches.select { |k| k['name'] == 'master' }.any?
        end

        # @param [Symbol] :project
        # @param [Hash] payload from GitHub
        def update(project, payload)
          Thread.new do
            Dir.chdir($config[:projects][project][:path]) do
              $logger.debug Dir.getwd
              deploy_failed = false
              $config[:projects][project][:commands].each do |command|
                if command.key?('run')
                  $logger.debug `#{command['run']}`
                  if $?.exitstatus.to_i != 0
                    Services::Deploy::Default.send_email(payload, failed_command: command['run'], exitstatus: $?.exitstatus)
                    deploy_failed = true
                    break
                  end
                end
              end
              Services::Deploy::Default.send_email payload unless deploy_failed
            end
          end
          'Deployment started!'
        end

        def send_email(payload, failed_command: nil, exitstatus: nil)
          subject_text = "Deployment of #{payload['repository']['name']} #{failed_command ? 'failed on ': 'was'} #{failed_command || 'successful'}#{" with exitstatus #{exitstatus}" if exitstatus}!"
          Mail.deliver do
            from     "notification@jchsoft.cz"
            to       payload['commit']['commit']['author']['email']
            subject  subject_text
            body     JSON.pretty_generate(payload['commit'])
          end
        end

      end

    end
  end
end
