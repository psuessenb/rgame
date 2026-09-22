# frozen_string_literal: true

RSpec.describe RGame::Engine::Signal::DSL do
  let(:lever_class) do
    Class.new do
      extend RGame::Engine::Signal::DSL

      signal :pulled
      signal :moved, :to
      signal :changed, :index, :value

      attr_reader :pulled

      def pull
        @pulled = :by_hand
        pulled_signal.emit
      end

      def move(to) = moved_signal.emit(to)
      def change(index, value) = changed_signal.emit(index:, value:)
    end
  end
  let(:lever) { lever_class.new }

  it 'adds on_ to the event for the public connect method' do
    expect(lever_class.public_method_defined?(:on_pulled)).to be(true)
  end

  it 'keeps the emit reader private' do
    expect(lever_class.private_method_defined?(:pulled_signal)).to be(true)
  end

  it 'connects a listener and returns it as the handle' do
    heard = []
    handle = lever.on_pulled { heard << :pulled }
    lever.pull

    expect([heard, handle]).to match([[:pulled], an_instance_of(Proc)])
  end

  it 'emits one field positionally' do
    heard = nil
    lever.on_moved { heard = it }
    lever.move(:up)

    expect(heard).to eq(:up)
  end

  it 'emits several fields as keywords' do
    heard = nil
    lever.on_changed { |index, value| heard = [index, value] }
    lever.change(2, :hard)

    expect(heard).to eq([2, :hard])
  end

  it 'keeps the signal beside an instance variable named after the event' do
    lever.on_pulled { nil }
    lever.pull

    expect(lever.pulled).to eq(:by_hand)
  end

  it 'gives each instance its own signal' do
    heard = []
    lever.on_pulled { heard << :first }
    lever_class.new.pull

    expect(heard).to be_empty
  end

  it 'refuses a name that starts with on_, naming the declaration to write' do
    expect { Class.new(lever_class) { signal :on_pulled } }
      .to raise_error(ArgumentError, 'signal :on_pulled: declare the event, signal :pulled; the DSL adds on_')
  end

  it 'refuses a signal class where the fields go' do
    payload = RGame::Engine::Signal.define(:index)

    expect { Class.new(lever_class) { signal :changed, payload } }.to raise_error(ArgumentError, /invalid field name/)
  end
end
