#!/usr/bin/env ruby
# frozen_string_literal: true

puts '🧪 Running webhook tests...'
system('ruby -Itest test/webhook_test.rb')

puts "\n🔐 Running signature validation tests..."
system('ruby -Itest test/signature_test.rb')

puts "\n✅ All tests completed!"
