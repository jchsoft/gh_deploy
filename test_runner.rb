#!/usr/bin/env ruby
# frozen_string_literal: true

puts '🧪 Running webhook tests...'
system('ruby -Itest test/webhook_test.rb')

puts "\n🔐 Running signature validation tests..."
system('ruby -Itest test/signature_test.rb')

puts "\n📝 Running JSON error handling tests..."
system('ruby -Itest test/json_error_test.rb')

puts "\n🔄 Running real GitHub Actions webhook tests..."
system('ruby -Itest test/real_github_test.rb')

puts "\n📧 Running email validation tests..."
system('ruby -Itest test/email_validation_test.rb')

puts "\n✅ All tests completed!"
