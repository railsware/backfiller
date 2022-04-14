# frozen_string_literal: true

RSpec.describe Backfiller::Parallel::Mutex do
  subject { described_class.new }

  specify 'acquire/release' do
    expect(subject).to_not be_locked

    subject.acquire
    expect(subject).to be_locked

    subject.release
    expect(subject).to_not be_locked

    expect { subject.release }.to raise_error(
      Backfiller::Parallel::Error,
      'lock released too many times'
    )
  end

  specify 'synchronize' do
    mutex = subject
    pipe = IO.pipe

    2.times do |i|
      Process.fork do
        mutex.synchronize do
          8.times do |j|
            pipe[1].write("#{i}:#{j}\n")
            sleep 0.1
          end
        end
      end
    end

    Process.waitall

    expect(pipe[0].readpartial(1024)).to eq <<~DATA
      0:0
      0:1
      0:2
      0:3
      0:4
      0:5
      0:6
      0:7
      1:0
      1:1
      1:2
      1:3
      1:4
      1:5
      1:6
      1:7
    DATA
  end
end
