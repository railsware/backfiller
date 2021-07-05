# frozen_string_literal: true

module Backfiller
  class << self
    def configure
      yield self
    end

    # directory for backfill ruby classes
    attr_accessor :task_directory

    # ruby module of backfill classes
    attr_accessor :task_namespace

    # Max size of records in one cursor fetch
    attr_accessor :batch_size

    # Size of processed records after which cursor will be re-opened
    attr_accessor :cursor_threshold

    # Logger
    attr_accessor :logger

    # @param task_name [String] name of backfill task file
    def run(task_name)
      Backfiller::Runner.new(task_name).run
    end

    # @param message [String] log message
    def log(message)
      return unless logger

      logger.info "[Backfiller] #{message}"
    end
  end
end
