# frozen_string_literal: true

RSpec.describe Backfiller::Parallel::Queue do
  subject { described_class.new }

  specify do
    10.times do |i|
      subject.enqueue("Message #{i}")
    end

    threads = 5.times.map do |thread_id|
      Thread.new(thread_id) do
        messages = []

        loop do
          Timeout::timeout(1) do
            messages << subject.dequeue
          end
          sleep 0.1
        rescue Timeout::Error
          break
        end

        messages
      end
    end

    threads.each(&:join)

    values = threads.map(&:value)

    expect(values.size).to eq(5)

    expect(values[0].size).to eq(2)
    expect(values[1].size).to eq(2)
    expect(values[2].size).to eq(2)
    expect(values[3].size).to eq(2)
    expect(values[4].size).to eq(2)

    expect(values.flatten.sort).to eq([
      'Message 0',
      'Message 1',
      'Message 2',
      'Message 3',
      'Message 4',
      'Message 5',
      'Message 6',
      'Message 7',
      'Message 8',
      'Message 9'
    ])
  end
end
