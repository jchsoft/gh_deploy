require 'minitest/autorun'
require 'logger'

# Suppress email sending during tests
module Services
  class Deploy
    private

    def send_email(failed_command: nil, exitstatus: nil)
      # Mock email sending in tests
      puts "Mock email: #{failed_command ? 'failed' : 'success'}"
    end

    def notify_slack
      # Mock slack notification in tests  
      puts "Mock slack notification"
    end
  end
end