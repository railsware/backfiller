require 'backfiller/cursor/postgresql'

module Backfiller
  module Cursor

    def self.new(connection, *args)
      case connection
      when ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
        Backfiller::Cursor::Postgresql.new(connection, *args)
      else
        raise "Unsupported connection #{connection.inspect}"
      end
    end

  end
end
