# frozen_string_literal: true

require 'bundler/setup'

Bundler.require(:default)

require 'active_support'
require 'active_support/core_ext'
require 'active_record'

require_relative 'support/logger_mock'

# Configure rspec matchers
RSpec::Matchers.define_negated_matcher :not_change, :change

# Create logging
ActiveSupport::LogSubscriber.colorize_logging = false

# Initialize ActiveRecord
ActiveRecord::Base.logger = LoggerMock.new
ActiveRecord::Base.establish_connection(
  url: 'postgresql://localhost/test',
  pool: 5
)

# Configure Backfiller
Backfiller.configure do |config|
  config.task_directory = File.expand_path('../db/backfill', __dir__)
  config.task_namespace = 'backfill'
  config.batch_size = 4
  config.cursor_threshold = 10
  config.logger = ActiveRecord::Base.logger
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before do
    ActiveRecord::Base.logger.reset
  end
end
