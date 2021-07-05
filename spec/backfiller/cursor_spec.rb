# frozen_string_literal: true

RSpec.describe Backfiller::Cursor do
  let(:cursor) { described_class.new(connection, 'backfill_cursor', select_sql) }
  let(:connection) { ActiveRecord::Base.connection }
  let(:select_sql) do
    <<~SQL
      SELECT * FROM (
        VALUES
        (1, 'Alice'),
        (2, 'Bob'),
        (3, 'Carlos')
      ) AS t(
        id, name
      )
    SQL
  end

  specify do
    expect(cursor).to be_instance_of(Backfiller::Cursor::Postgresql)
  end

  describe '#fetch' do
    subject do
      results = []
      connection.transaction do
        cursor.open
        results << cursor.fetch(2)
        results << cursor.fetch(2)
        results << cursor.fetch(2)
        cursor.close
      end
      results
    end

    specify do
      expect(subject.size).to eq(3)

      expect(subject[0]).to be_instance_of(ActiveRecord::Result)
      expect(subject[0].length).to eq(2)
      expect(subject[0][0]).to eq('id' => 1, 'name' => 'Alice')
      expect(subject[0][1]).to eq('id' => 2, 'name' => 'Bob')

      expect(subject[1]).to be_instance_of(ActiveRecord::Result)
      expect(subject[1].length).to eq(1)
      expect(subject[1][0]).to eq('id' => 3, 'name' => 'Carlos')

      expect(subject[2]).to be_instance_of(ActiveRecord::Result)
      expect(subject[2].length).to eq(0)
    end
  end
end
