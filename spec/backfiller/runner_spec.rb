# frozen_string_literal: true

RSpec.describe Backfiller::Runner do
  let(:runner) do
    described_class.new(task_name)
  end

  let(:task_path) { File.join(Backfiller.task_directory, "#{task_name}.rb") }
  let(:task_name) { 'dummy' }

  before do
    Object.const_set('Backfill', Module.new)
    ActiveRecord::Base.connection.create_table(:backfiller_records) do |t|
      t.column :first_name, :string
      t.column :last_name, :string
      t.column :full_name, :string
    end
  end

  after do
    $LOADED_FEATURES.delete task_path
    FileUtils.rm task_path
    ActiveRecord::Base.connection.drop_table(:backfiller_records)
    Object.send :remove_const, 'Backfill'
  end

  describe '#initialize' do
    context 'no options' do
      before do
        File.write task_path, <<~TASK
          class Backfill::Dummy
          end
        TASK
      end

      specify do
        expect(runner.task.class).to eq(Backfill::Dummy)
        expect(runner.batch_size).to eq(10)
        expect(runner.process_method).to eq(runner.method(:process_row))
      end
    end

    context 'with custom options' do
      before do
        File.write task_path, <<~TASK
          class Backfill::Dummy
            def batch_size
              20
            end

            def process_row
            end
          end
        TASK
      end

      specify do
        expect(runner.task.class).to eq(Backfill::Dummy)
        expect(runner.batch_size).to eq(20)
        expect(runner.process_method).to eq(runner.task.method(:process_row))
      end
    end
  end

  describe '#run' do
    subject { runner.run }

    before do
      File.write task_path, <<~TASK
        class Backfill::Dummy
          def select_sql()
            'SELECT * FROM backfiller_records WHERE full_name IS NULL'
          end

          def execute_sql(connection, row)
            'UPDATE backfiller_records SET full_name = ' +
              connection.quote(row['first_name'] + ' ' + row['last_name']) +
              ' WHERE id = ' + connection.quote(row['id'])
          end
        end
      TASK
    end

    specify do
      ActiveRecord::Base.connection.insert_fixture(
        [
          {
            first_name: 'Jon',
            last_name: 'Snow'
          },
          {
            first_name: 'Aria',
            last_name: 'Stark'
          },
          {
            first_name: 'George',
            last_name: 'Martin',
            full_name: 'George R. R. Martin'
          }
        ], :backfiller_records
      )

      ActiveRecord::Base.logger.reset

      subject

      messages = ActiveRecord::Base.logger.messages
      expect(messages[0]).to eq('[Backfiller] Build dummy task')
      expect(messages[1]).to eq('[Backfiller] Open cursor')
      expect(messages[2]).to match(/TRANSACTION \(.*\)  BEGIN/)
      expect(messages[3]).to include(
        'DECLARE backfill_cursor NO SCROLL CURSOR WITHOUT HOLD FOR ' \
        'SELECT * FROM backfiller_records WHERE full_name IS NULL'
      )
      expect(messages[4]).to eq('[Backfiller] Start fetch loop')
      expect(messages[5]).to include('FETCH 10 FROM backfill_cursor')
      expect(messages[6]).to include(
        "UPDATE backfiller_records SET full_name = 'Jon Snow' WHERE id = 1"
      )
      expect(messages[7]).to include(
        "UPDATE backfiller_records SET full_name = 'Aria Stark' WHERE id = 2"
      )
      expect(messages[8]).to eq('[Backfiller] Processed 2')
      expect(messages[9]).to include('FETCH 10 FROM backfill_cursor')
      expect(messages[10]).to eq('[Backfiller] Close cursor')
      expect(messages[11]).to include('CLOSE backfill_cursor')
      expect(messages[12]).to match(/TRANSACTION \(.*\)  COMMIT/)

      expect(
        ActiveRecord::Base.connection.select_all('SELECT * FROM backfiller_records ORDER BY id').to_a
      ).to eq(
        [
          {
            'id' => 1,
            'first_name' => 'Jon',
            'last_name' => 'Snow',
            'full_name' => 'Jon Snow'
          },
          {
            'id' => 2,
            'first_name' => 'Aria',
            'last_name' => 'Stark',
            'full_name' => 'Aria Stark'
          },
          {
            'id' => 3,
            'first_name' => 'George',
            'last_name' => 'Martin',
            'full_name' => 'George R. R. Martin'
          }
        ]
      )
    end
  end
end
