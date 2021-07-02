# frozen_string_literal: true

module Backfiller
  class << self
    def configure
      yield self
    end

    attr_accessor :task_directory

    attr_accessor :task_namespace

    attr_accessor :batch_size

    attr_accessor :logger

    def run(task_name)
      Backfiller::Runner.new(task_name).run
    end

    def log(message)
      return unless logger

      logger.info "[Backfiller] #{message}"
    end
  end
end
