module Backfiller
  class Railtie < Rails::Railtie

    rake_tasks do
      load 'backfiller/tasks/db.rake'
    end

    initializer 'backfiller.configure' do
      Backfiller.configure do |config|
        config.task_directory = Rails.root.join('db', 'backfill')

        config.task_namespace = 'backfill'

        config.batch_size = 1_000

        config.connection_pool = defined?(ApplicationRecord) ? ApplicationRecord.connection_pool : ActiveRecord::Base.connection_pool

        config.logger = defined?(ApplicationRecord) ? ApplicationRecord.logger : ActiveRecord::Base.logger
      end
    end

    config.after_initialize do
      task_module = Backfiller.task_namespace.classify
      Object.const_set(task_module, Module.new) unless Object.const_defined?(task_module)
    end

  end
end
