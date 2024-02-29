# frozen_string_literal: true

module Backfiller
  module Cursor
    class Postgresql
      attr_reader :connection

      def initialize(connection, name, query)
        @connection = connection
        @name = name
        @query = query
      end

      # Open cursor, call black and close cursor in transaction.
      #
      # @return [Object] yielded block result.
      def transaction
        result = nil

        @connection.transaction do
          Backfiller.log 'Open cursor'
          open

          result = yield

          Backfiller.log 'Close cursor'
          close
        end

        result
      end

      def open
        @connection.execute "DECLARE #{@name} NO SCROLL CURSOR WITHOUT HOLD FOR #{@query}"
      end

      def fetch(count)
        @connection.exec_query "FETCH #{count} FROM #{@name}"
      end

      def close
        @connection.execute "CLOSE #{@name}"
      end
    end
  end
end
