# frozen_string_literal: true

module Backfiller
  class Runner
    attr_reader \
      :task,
      :connection_pool,
      :batch_size,
      :cursor_threshold,
      :process_method

    def initialize(task_name)
      @task = build_task(task_name)
      @connection_pool = @task.respond_to?(:connection_pool) ? @task.connection_pool : default_connection_pool
      @batch_size = @task.respond_to?(:batch_size) ? @task.batch_size : Backfiller.batch_size
      @cursor_threshold = @task.respond_to?(:cursor_threshold) ? @task.cursor_threshold : Backfiller.cursor_threshold
      @process_method = @task.respond_to?(:process_row) ? @task.method(:process_row) : method(:process_row)
    end

    # It uses two connections from pool:
    # * master [M] - reads data using cursor in transaction
    # * worker [W] - changes data based on record red from master
    #
    # @example
    #   [M] BEGIN
    #   [M] DECLARE backfill_cursor SCROLL CURSOR WITHOUT HOLD FOR SELECT * FROM users
    #   // Start fetch and process loop:
    #   [M] FETCH 1000 backfill_cursor
    #     [W] UPDATE users SET full_name = '...' where id = 1
    #     [W] ...
    #     [W] UPDATE users SET full_name = '...' where id = 1000
    #   [M] FETCH 1000 backfill_cursor
    #     [W] UPDATE users SET full_name = '...' where id = 1001
    #     [W] ...
    #     [W] UPDATE users SET full_name = '...' where id = 2000
    #   // Records per cursor transaction threshold reached. Reopen transaction.
    #   [M] CLOSE backfill_cursor
    #   [M] COMMIT
    #   [M] BEGIN
    #   [M] DECLARE backfill_cursor SCROLL CURSOR WITHOUT HOLD FOR SELECT * FROM users
    #   [M] FETCH 1000 backfill_cursor
    #   // The end of cursor reached. Break cursor loop and exit.
    #   [M] CLOSE backfill_cursor
    #   [M] COMMIT
    def run
      master_connection = acquire_connection
      worker_connection = acquire_connection

      run_cursor_loop(master_connection) do |row|
        process_method.call(worker_connection, row)
      end

      release_connection(master_connection)
      release_connection(worker_connection)
    end

    private

    def build_task(task_name)
      Backfiller.log "Build #{task_name} task"
      require File.join(Backfiller.task_directory, task_name)
      "#{Backfiller.task_namespace}/#{task_name}".classify.constantize.new
    end

    ###########################################################################

    def default_connection_pool
      defined?(ApplicationRecord) ? ApplicationRecord.connection_pool : ActiveRecord::Base.connection_pool
    end

    def acquire_connection
      connection_pool.checkout
    end

    def release_connection(connection)
      connection_pool.checkin(connection)
    end

    ###########################################################################

    # Run loop that re-open cursor transaction on threshold
    def run_cursor_loop(connection, &block)
      Backfiller.log 'Start cursor loop'

      total_count = 0
      cursor = build_cursor(connection)

      loop do
        finished, count = cursor.transaction do
          run_fetch_loop(cursor, &block)
        end

        total_count += count

        Backfiller.log "Total processed #{total_count}"
        break if finished
      end
    end

    # @return [Array<Boolean, Integer>] finished_status/processed_count
    def run_fetch_loop(cursor, &block)
      Backfiller.log 'Start fetch loop'
      count = 0

      loop do
        result = cursor.fetch(batch_size)

        return [true, count] if result.empty?

        result.each do |row|
          block.call(row)
          count += 1
        end

        Backfiller.log "Processed #{count}"

        return [false, count] if cursor_threshold && count > cursor_threshold
      end
    end

    ###########################################################################

    # Build cursor object that will use master connection.
    def build_cursor(connection)
      Backfiller::Cursor.new(connection, 'backfill_cursor', task.select_sql)
    end

    # Process row using worker connection.
    def process_row(connection, row)
      Array(task.execute_sql(connection, row)).each do |sql|
        connection.execute(sql)
      end
    end
  end
end
