# frozen_string_literal: true

module Backfiller
  module Parallel
    class Mutex
      BYTE = 255.chr.freeze

      def initialize
        @pipe = IO.pipe
        @pipe[1].write(BYTE)
      end

      def synchronize
        acquire
        yield
      ensure
        release
      end

      def acquire
        @pipe[0].readpartial(1)
      end

      def release
        raise Error, 'lock released too many times' unless locked?
        @pipe[1].write(BYTE)
      end

      def locked?
        @pipe[0].read_nonblock(1)
        @pipe[1].write(BYTE)
        false
      rescue IO::EAGAINWaitReadable
        true
      end
    end
  end
end
