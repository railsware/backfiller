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
        expect(runner.batch_size).to eq(4)
        expect(runner.cursor_threshold).to eq(10)
        expect(runner.process_method).to eq(runner.method(:process_row))
      end
    end

    context 'with custom options' do
      before do
        File.write task_path, <<~TASK
          class Backfill::Dummy
            def batch_size
              2000
            end

            def cursor_threshold
              200000
            end

            def process_row
            end
          end
        TASK
      end

      specify do
        expect(runner.task.class).to eq(Backfill::Dummy)
        expect(runner.batch_size).to eq(2000)
        expect(runner.cursor_threshold).to eq(200_000)
        expect(runner.process_method).to eq(runner.task.method(:process_row))
      end
    end
  end

  describe '#run' do
    subject { runner.run }

    let(:batch_size) { 2 }
    let(:cursor_threshold) { 5 }

    before do
      File.write task_path, <<~TASK
        class Backfill::Dummy
          def batch_size
            #{batch_size}
          end

          def cursor_threshold
            #{cursor_threshold}
          end

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
      expect(messages[1]).to eq('[Backfiller] Start cursor loop')

      expect(messages[2]).to eq('[Backfiller] Open cursor')
      expect(messages[3]).to match(/TRANSACTION \(.*\)  BEGIN/)
      expect(messages[4]).to include(
        'DECLARE backfill_cursor NO SCROLL CURSOR WITHOUT HOLD FOR ' \
        'SELECT * FROM backfiller_records WHERE full_name IS NULL'
      )
      expect(messages[5]).to eq('[Backfiller] Start fetch loop')
      expect(messages[6]).to include('FETCH 2 FROM backfill_cursor')
      expect(messages[7]).to include(
        "UPDATE backfiller_records SET full_name = 'Jon Snow' WHERE id = 1"
      )
      expect(messages[8]).to include(
        "UPDATE backfiller_records SET full_name = 'Aria Stark' WHERE id = 2"
      )
      expect(messages[9]).to eq('[Backfiller] Processed 2')
      expect(messages[10]).to include('FETCH 2 FROM backfill_cursor')
      expect(messages[11]).to eq('[Backfiller] Close cursor')
      expect(messages[12]).to include('CLOSE backfill_cursor')
      expect(messages[13]).to match(/TRANSACTION \(.*\)  COMMIT/)
      expect(messages[14]).to eq('[Backfiller] Total processed 2')

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

    context 'cursor threshold' do
      let(:messages) do
        ActiveRecord::Base.logger.messages
      end

      before do
        ActiveRecord::Base.connection.insert_fixture(
          [
            { first_name: 'First01', last_name: 'Last01' },
            { first_name: 'First02', last_name: 'Last02' },
            { first_name: 'First03', last_name: 'Last03' },
            { first_name: 'First04', last_name: 'Last04' },
            { first_name: 'First05', last_name: 'Last05' },
            { first_name: 'First06', last_name: 'Last06' },
            { first_name: 'First07', last_name: 'Last07' }
          ], :backfiller_records
        )

        ActiveRecord::Base.logger.reset

        subject
      end

      shared_examples :single_cursor_session do
        specify do
          expect(messages.size).to eq(26)

          expect(messages[0]).to eq('[Backfiller] Build dummy task')
          expect(messages[1]).to eq('[Backfiller] Start cursor loop')

          expect(messages[2]).to eq('[Backfiller] Open cursor')
          expect(messages[3]).to match(/TRANSACTION \(.*\)  BEGIN/)
          expect(messages[4]).to include('DECLARE backfill_cursor')
          expect(messages[5]).to eq('[Backfiller] Start fetch loop')
          expect(messages[6]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[7]).to include("UPDATE backfiller_records SET full_name = 'First01 Last01' WHERE id = 1")
          expect(messages[8]).to include("UPDATE backfiller_records SET full_name = 'First02 Last02' WHERE id = 2")
          expect(messages[9]).to eq('[Backfiller] Processed 2')
          expect(messages[10]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[11]).to include("UPDATE backfiller_records SET full_name = 'First03 Last03' WHERE id = 3")
          expect(messages[12]).to include("UPDATE backfiller_records SET full_name = 'First04 Last04' WHERE id = 4")
          expect(messages[13]).to eq('[Backfiller] Processed 4')
          expect(messages[14]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[15]).to include("UPDATE backfiller_records SET full_name = 'First05 Last05' WHERE id = 5")
          expect(messages[16]).to include("UPDATE backfiller_records SET full_name = 'First06 Last06' WHERE id = 6")
          expect(messages[17]).to eq('[Backfiller] Processed 6')
          expect(messages[18]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[19]).to include("UPDATE backfiller_records SET full_name = 'First07 Last07' WHERE id = 7")
          expect(messages[20]).to eq('[Backfiller] Processed 7')
          expect(messages[21]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[22]).to eq('[Backfiller] Close cursor')
          expect(messages[23]).to include('CLOSE backfill_cursor')
          expect(messages[24]).to match(/TRANSACTION \(.*\)  COMMIT/)
          expect(messages[25]).to eq('[Backfiller] Total processed 7')
        end
      end

      context 'nil' do
        let(:cursor_threshold) { nil }

        include_examples :single_cursor_session
      end

      context 'large' do
        let(:cursor_threshold) { 8 }

        include_examples :single_cursor_session
      end

      context 'small' do
        specify do
          expect(messages.size).to eq(34)

          expect(messages[0]).to eq('[Backfiller] Build dummy task')
          expect(messages[1]).to eq('[Backfiller] Start cursor loop')

          expect(messages[2]).to eq('[Backfiller] Open cursor')
          expect(messages[3]).to match(/TRANSACTION \(.*\)  BEGIN/)
          expect(messages[4]).to include('DECLARE backfill_cursor')
          expect(messages[5]).to eq('[Backfiller] Start fetch loop')
          expect(messages[6]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[7]).to include("UPDATE backfiller_records SET full_name = 'First01 Last01' WHERE id = 1")
          expect(messages[8]).to include("UPDATE backfiller_records SET full_name = 'First02 Last02' WHERE id = 2")
          expect(messages[9]).to eq('[Backfiller] Processed 2')
          expect(messages[10]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[11]).to include("UPDATE backfiller_records SET full_name = 'First03 Last03' WHERE id = 3")
          expect(messages[12]).to include("UPDATE backfiller_records SET full_name = 'First04 Last04' WHERE id = 4")
          expect(messages[13]).to eq('[Backfiller] Processed 4')
          expect(messages[14]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[15]).to include("UPDATE backfiller_records SET full_name = 'First05 Last05' WHERE id = 5")
          expect(messages[16]).to include("UPDATE backfiller_records SET full_name = 'First06 Last06' WHERE id = 6")
          expect(messages[17]).to eq('[Backfiller] Processed 6')
          expect(messages[18]).to eq('[Backfiller] Close cursor')
          expect(messages[19]).to include('CLOSE backfill_cursor')
          expect(messages[20]).to match(/TRANSACTION \(.*\)  COMMIT/)
          expect(messages[21]).to eq('[Backfiller] Total processed 6')

          expect(messages[22]).to eq('[Backfiller] Open cursor')
          expect(messages[23]).to match(/TRANSACTION \(.*\)  BEGIN/)
          expect(messages[24]).to include('DECLARE backfill_cursor')
          expect(messages[25]).to eq('[Backfiller] Start fetch loop')
          expect(messages[26]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[27]).to include("UPDATE backfiller_records SET full_name = 'First07 Last07' WHERE id = 7")
          expect(messages[28]).to eq('[Backfiller] Processed 1')
          expect(messages[29]).to include('FETCH 2 FROM backfill_cursor')
          expect(messages[30]).to eq('[Backfiller] Close cursor')
          expect(messages[31]).to include('CLOSE backfill_cursor')
          expect(messages[32]).to match(/TRANSACTION \(.*\)  COMMIT/)
          expect(messages[33]).to eq('[Backfiller] Total processed 7')
        end
      end
    end
  end
end
