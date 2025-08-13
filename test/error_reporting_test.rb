# frozen_string_literal: true

require 'minitest/autorun'
require 'logger'
require 'tempfile'

# Load services without test_helper mocks to test actual behavior
require_relative '../services/deploy'

# Mock config and logger for testing
$config = {
  projects: {
    test_project: {
      branch: 'main',
      path: Dir.tmpdir, # Use system temp dir that exists
      commands: [{ 'run' => 'exit 1' }] # Command that will fail
    }
  },
  mail_to: ['admin@example.com']
}
$logger = Logger.new(File::NULL)

class ErrorReportingTest < Minitest::Test
  def test_enhanced_error_reporting_in_emails
    # Create a deploy instance that will execute a failing command
    deploy = Services::Deploy.new('test_project', mock_github_payload, 'github_actions')
    
    # Mock Mail.deliver to capture the email content instead of sending
    captured_email_body = nil
    
    mail_class = Class.new do
      def self.deliver(&block)
        mail_instance = self.new
        mail_instance.instance_eval(&block)
        mail_instance
      end
      
      attr_accessor :email_body
      
      def from(email); end
      def to(recipients); end  
      def subject(text); end
      def body(content)
        @email_body = content
      end
    end
    
    # Temporarily replace Mail constant
    old_mail = Object.const_get(:Mail)
    Object.send(:remove_const, :Mail)
    Object.const_set(:Mail, mail_class)
    
    begin
      # Run the deploy which should fail and trigger error reporting
      deploy.update!
      
      # Wait a bit for the thread to complete
      sleep 0.1
      
      # The email should have been "sent" with error details
      # Since we're using a mock, we need to check that send_email was called
      # with the right parameters by testing the method directly
      
      # Test send_email method directly with failure parameters
      mail_instance = deploy.send(:send_email, 
                                  failed_command: 'exit 1', 
                                  exitstatus: 1, 
                                  command_output: "some error output\n")
      
      email_body = mail_instance.email_body
      
      # Verify the email body contains error details
      assert_includes email_body, '--- DEPLOYMENT FAILURE DETAILS ---'
      assert_includes email_body, 'Failed Command: exit 1'
      assert_includes email_body, 'Exit Status: 1'
      assert_includes email_body, 'Command Output:'
      assert_includes email_body, 'some error output'
      
    ensure
      # Restore original Mail constant
      Object.send(:remove_const, :Mail)
      Object.const_set(:Mail, old_mail)
    end
  end

  def test_successful_deployment_email_unchanged
    # Test that successful deployments still get normal emails
    deploy = Services::Deploy.new('test_project', mock_github_payload, 'github_actions')
    
    # Mock Mail.deliver
    mail_class = Class.new do
      def self.deliver(&block)
        mail_instance = self.new
        mail_instance.instance_eval(&block)
        mail_instance
      end
      
      attr_accessor :email_body
      
      def from(email); end
      def to(recipients); end
      def subject(text); end
      def body(content)
        @email_body = content
      end
    end
    
    old_mail = Object.const_get(:Mail)
    Object.send(:remove_const, :Mail)
    Object.const_set(:Mail, mail_class)
    
    begin
      # Test successful email (no failure parameters)
      mail_instance = deploy.send(:send_email)
      email_body = mail_instance.email_body
      
      # Should not contain error reporting sections
      refute_includes email_body, '--- DEPLOYMENT FAILURE DETAILS ---'
      refute_includes email_body, 'Failed Command:'
      refute_includes email_body, 'Command Output:'
      
      # Should contain normal commit info
      assert_includes email_body, '"message":'
      
    ensure
      Object.send(:remove_const, :Mail)
      Object.const_set(:Mail, old_mail)
    end
  end

  private

  def mock_github_payload
    {
      'action' => 'completed',
      'workflow_run' => {
        'conclusion' => 'success',
        'event' => 'push',
        'head_branch' => 'main',
        'head_commit' => {
          'author' => { 'email' => 'dev@example.com' },
          'message' => 'Test commit',
          'id' => 'abc123'
        }
      },
      'repository' => { 'name' => 'test-repo' }
    }
  end
end