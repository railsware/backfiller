# frozen_string_literal: true

module Backfiller
  module Parallel
    module Utils
      extend self

      INT32_DIRECTIVE = 'l'
      INT32_BYTES_SIZE = 4

      # @param pipe [Array<IO, IO>]
      # @return [Integer]
      def read_int32(pipe)
        data = read_data(pipe, INT32_BYTES_SIZE)
        data.unpack(INT32_DIRECTIVE).first
      end

      # @param pipe [Array<IO, IO>]
      # @param value [Integer]
      def write_int32(pipe, value)
        data = [value].pack(INT32_DIRECTIVE)
        write_data(pipe, data)
      end

      # @param pipe [Array<IO, IO>]
      # @param size [Integer]
      def read_data(pipe, size)
        pipe[0].readpartial(size)
      end

      # @param pipe [Array<IO, IO>]
      # @param size [String]
      def write_data(pipe, data)
        pipe[1].write(data)
      end
    end
  end
end
