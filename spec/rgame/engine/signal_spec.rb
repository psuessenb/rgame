# frozen_string_literal: true

RSpec.describe RGame::Engine::Signal do
  subject(:signal) { described_class.define.new }

  it 'triggers a connected listener block' do
    called = false
    signal.connect { called = true }

    signal.emit
    expect(called).to be true
  end

  it 'notifies multiple listeners in the order they were connected' do
    execution_order = []

    signal.connect { execution_order << 'first' }
    signal.connect { execution_order << 'second' }

    signal.emit
    expect(execution_order).to eq(%w[first second])
  end

  it 'does not crash if emitted with no listeners connected' do
    expect { signal.emit }.not_to raise_error
  end

  describe 'a one-argument signal' do
    subject(:signal) { described_class.define(:argument).new }

    it 'passes a single argument to the listener without keyword' do
      received_data = nil
      signal.connect { |data| received_data = data }

      signal.emit('hello')
      expect(received_data).to eq('hello')
    end
  end

  describe 'a multi-argument signal' do
    subject(:signal) { described_class.define(:a, :b, :c).new }

    it 'passes multiple arguments via splat parameters' do
      received_args = []
      signal.connect { |a, b, c| received_args = [a, b, c] }

      signal.emit(a: 1, b: 2, c: 3)
      expect(received_args).to eq([1, 2, 3])
    end
  end

  describe '#disconnect' do
    it 'successfully stops a listener from receiving future emissions' do
      trigger_count = 0

      handle = signal.connect { trigger_count += 1 }
      signal.emit
      expect(trigger_count).to eq(1)

      signal.disconnect(handle)

      signal.emit
      expect(trigger_count).to eq 1
    end
  end
end
