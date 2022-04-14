# frozen_string_literal: true

module Backfiller
  module Parallel
    class Queue
      def initialize
        @write_mutex = Mutex.new
        @read_mutex = Mutex.new
        @pipe = IO.pipe
      end

      def enqueue(object)
        @write_mutex.synchronize do
          body = Marshal.dump(object)
          size = body.size
          Utils.write_int32(@pipe, size)
          Utils.write_data(@pipe, body)
          nil
        end
      end

      def dequeue
        @read_mutex.synchronize do
          size = Utils.read_int32(@pipe)
          body = Utils.read_data(@pipe, size)
          object = Marshal.load(body)
          object
        end
      end
    end
  end
end
