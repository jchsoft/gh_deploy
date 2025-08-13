# frozen_string_literal: true

require 'minitest/autorun'
require 'logger'

# Load services without test_helper mocks
require_relative '../services/deploy'

# Mock config and logger for testing
$config = {
  projects: {
    test_project: {
      branch: 'main',
      path: '/tmp/test',
      commands: [{ 'run' => 'echo "test deploy"' }]
    }
  },
  mail_to: ['admin@example.com']
}
$logger = Logger.new(File::NULL)

class EmailValidationTest < Minitest::Test
  def test_valid_email_regex_constant_exists
    assert_kind_of Regexp, Services::Deploy::VALID_EMAIL_REGEX
  end

  def test_valid_email_addresses_accepted
    valid_emails = [
      'user@example.com',
      'test.email@domain.org',
      'admin+notifications@company.co.uk',
      'developer123@subdomain.example.net'
    ]

    valid_emails.each do |email|
      assert email.match?(Services::Deploy::VALID_EMAIL_REGEX),
             "Valid email '#{email}' should match the regex"
    end
  end

  def test_invalid_email_addresses_rejected
    invalid_emails = [
      '49699333+dependabot[bot]@users.noreply.github.com',
      'not-an-email',
      '@invalid.com',
      'user@',
      'spaces in@email.com',
      'user[bot]@noreply.github.com'
    ]

    invalid_emails.each do |email|
      refute email.match?(Services::Deploy::VALID_EMAIL_REGEX),
             "Invalid email '#{email}' should not match the regex"
    end
  end

  def test_email_filtering_in_send_email_method
    # Create a mock deploy instance to test email filtering
    deploy = Services::Deploy.new('test_project', mock_github_payload, 'github_actions')
    
    # Mock the actual email sending to capture the filtered recipients
    filtered_recipients = nil
    
    # Temporarily override the Mail.deliver method to capture recipients
    original_deliver = nil
    mail_class = Class.new do
      def self.deliver(&block)
        mail_instance = self.new
        mail_instance.instance_eval(&block)
        mail_instance
      end
      
      attr_accessor :recipients
      
      def from(email); end
      def subject(text); end  
      def body(content); end
      def to(recipients)
        @recipients = recipients
      end
    end
    
    # Stub Mail constant temporarily
    old_mail = Object.const_get(:Mail)
    Object.send(:remove_const, :Mail)
    Object.const_set(:Mail, mail_class)
    
    # Test with mixed valid/invalid emails in config
    $config[:mail_to] = ['admin@example.com', 'invalid[bot]@noreply.github.com']
    
    begin
      # Capture output to suppress puts in send_email
      original_stdout = $stdout
      $stdout = File.new(File::NULL, 'w')
      
      # Call send_email method which should filter emails
      mail_instance = deploy.send(:send_email)
      filtered_recipients = mail_instance.recipients
      
      $stdout = original_stdout
      
      # Verify that only valid emails are in the recipients
      assert_includes filtered_recipients, 'admin@example.com'
      assert_includes filtered_recipients, 'dev@example.com' # from payload
      refute_includes filtered_recipients, 'invalid[bot]@noreply.github.com'
      
      # Verify dependabot email is filtered out
      $config[:mail_to] = ['admin@example.com']
      deploy_with_bot = Services::Deploy.new('test_project', mock_dependabot_payload, 'github_actions')
      mail_instance2 = deploy_with_bot.send(:send_email)
      bot_filtered_recipients = mail_instance2.recipients
      
      assert_includes bot_filtered_recipients, 'admin@example.com'
      refute_includes bot_filtered_recipients, '49699333+dependabot[bot]@users.noreply.github.com'
      
    ensure
      # Restore original Mail constant
      Object.send(:remove_const, :Mail)  
      Object.const_set(:Mail, old_mail)
      $stdout = original_stdout if original_stdout
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
          'message' => 'Test commit'
        }
      },
      'repository' => { 'name' => 'test-repo' }
    }
  end

  def mock_dependabot_payload
    {
      'action' => 'completed',
      'workflow_run' => {
        'conclusion' => 'success',
        'event' => 'push',
        'head_branch' => 'main',
        'head_commit' => {
          'author' => { 'email' => '49699333+dependabot[bot]@users.noreply.github.com' },
          'message' => 'Bump some dependency'
        }
      },
      'repository' => { 'name' => 'test-repo' }
    }
  end
end