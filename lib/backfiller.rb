# frozen_string_literal: true

require_relative 'backfiller/configuration'
require_relative 'backfiller/cursor'
require_relative 'backfiller/runner'

require_relative 'backfiller/railtie' if defined?(Rails::Railtie)
