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

      def open
        @connection.execute "DECLARE #{@name} NO SCROLL CURSOR WITHOUT HOLD FOR #{@query}"
      end

      def fetch(count)
        @connection.select_all "FETCH #{count} FROM #{@name}"
      end

      def close
        @connection.execute "CLOSE #{@name}"
      end
    end
  end
end
