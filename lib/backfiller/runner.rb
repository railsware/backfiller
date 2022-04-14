# frozen_string_literal: true

module Backfiller
  module Runner
    class << self
      def new(*args)
        Single.new(*args)
      end
    end
  end
end
