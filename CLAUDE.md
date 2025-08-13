# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Ruby Sinatra webhook application that handles CI/CD deployment triggers from GitHub (both CircleCI status events and GitHub Actions workflow_run events). The app validates webhooks, executes deployment commands, and sends email/Slack notifications.

## Architecture

- **main.rb**: Sinatra application entry point with webhook endpoints
- **app/config.rb**: Global configuration loader using `config.yml`
- **services/deploy.rb**: Core deployment logic and notification handling
- **lib/**: Utility modules (HTTP status codes, hash symbolization)
- **test/**: Comprehensive test suite with fixtures for webhook validation

The application uses global variables (`$config`, `$logger`) for shared state across modules.

## Common Commands

### Development
```bash
# Install dependencies
bundle install

# Run the application
ruby main.rb

# Run all tests
ruby test_runner.rb

# Run specific test files
ruby -Itest test/webhook_test.rb
ruby -Itest test/signature_test.rb
ruby -Itest test/json_error_test.rb
ruby -Itest test/real_github_test.rb

# Lint code
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a
```

### Configuration
- Main config: `config.yml` - defines projects, deployment paths, commands, and notification settings
- Logging configured via `log_to` setting (STDOUT/STDERR/FILE)
- Optional GitHub webhook signature validation via `github_webhook_secret`

## Key Components

### Webhook Handling
- POST `/event_handler/:project` - handles GitHub webhooks
- Supports both `status` events (CircleCI) and `workflow_run` events (GitHub Actions)
- Handles URL-encoded and raw JSON payloads
- Optional HMAC-SHA256 signature verification

### Deployment Flow
1. Webhook validation (signature, event type, branch matching)
2. Asynchronous command execution in project directory
3. Email notifications to configured recipients + commit author
4. Optional Slack notifications

### Testing Strategy
- Fixtures in `test/fixtures/` contain real webhook payloads
- Tests cover signature validation, JSON error handling, and webhook processing
- Use `rack-test` for endpoint testing

## Project Structure Notes

- Commands are executed via shell in the configured project path
- Email delivery uses the `mail` gem with SMTP settings
- Global exception handling returns JSON error responses
- RuboCop configuration allows global variables for this specific use case