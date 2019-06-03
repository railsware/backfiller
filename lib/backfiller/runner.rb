module Backfiller
  class Runner

    attr_reader \
      :task,
      :connection_pool,
      :batch_size,
      :process_method

    def initialize(task_name)
      @task = build_task(task_name)
      @connection_pool = @task.respond_to?(:connection_pool) ? @task.connection_pool : Backfiller.connection_pool
      @batch_size = @task.respond_to?(:batch_size) ? @task.batch_size : Backfiller.batch_size
      @process_method = @task.respond_to?(:process_row) ? @task.method(:process_row) : self.method(:process_row)
    end

    def run
      master_connection = acquire_connection
      worker_connection = acquire_connection

      fetch_each(master_connection) do |row|
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

    def acquire_connection
      connection_pool.checkout
    end

    def release_connection(connection)
      connection_pool.checkin(connection)
    end

    ###########################################################################

    def build_cursor(connection)
      Backfiller::Cursor.new(connection, 'backfill_cursor', task.select_sql)
    end

    def fetch_each(master_connection, &block)
      cursor = build_cursor(master_connection)

      cursor.connection.transaction do
        Backfiller.log "Open cursor"
        cursor.open

        Backfiller.log "Start fetch loop"
        fetch_loop(cursor, &block)

        Backfiller.log "Close cursor"
        cursor.close
      end
    end

    def fetch_loop(cursor, &block)
      count = 0

      loop do
        result = cursor.fetch(batch_size)

        break if result.empty?

        result.each do |row|
          block.call(row)
          count += 1
        end

        Backfiller.log "Processed #{count}"
      end
    end

    def process_row(connection, row)
      Array(task.execute_sql(connection, row)).each do |sql|
        connection.execute(sql)
      end
    end
  end
end
