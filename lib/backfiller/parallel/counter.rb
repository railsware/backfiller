# frozen_string_literal: true

module Backfiller
  module Parallel
    class Counter
      def initialize
        @pipe = IO.pipe
        Utils.write_int32(@pipe, 0)
      end

      def increment(delta = 1)
        value = Utils.read_int32(@pipe)
        value += delta
        Utils.write_int32(@pipe, value)
        nil
      end

      def decrement(delta = 1)
        value = Utils.read_int32(@pipe)
        value -= delta
        Utils.write_int32(@pipe, value)
        nil
      end

      def count
        value = Utils.read_int32(@pipe)
        Utils.write_int32(@pipe, value)
        value
      end

      def wait_zero
        loop do
          break if count.zero?
        end
      end
    end
  end
end
