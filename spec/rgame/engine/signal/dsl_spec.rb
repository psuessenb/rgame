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

  it 'makes the disconnect public beside the connect' do
    expect(lever_class.public_method_defined?(:disconnect_pulled)).to be(true)
  end

  # Ending a connection belongs to whoever made it, so the handle `on_pulled`
  # returned is enough — the signal itself stays private, because emitting is
  # the class's.
  it 'ends one connection through the handle, leaving the others' do
    heard = []
    going = lever.on_pulled { heard << :going }
    lever.on_pulled { heard << :staying }

    lever.disconnect_pulled(going)
    lever.pull

    expect(heard).to eq([:staying])
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

  describe 'a method replacing one the DSL generated' do
    before { stub_const('Lever', lever_class) }

    it 'raises for the connect method, naming the signal and where it was declared' do
      expect { Class.new(Lever) { def on_pulled = nil } }
        .to raise_error(NameError, /#on_pulled would replace what signal :pulled generated in Lever,/)
    end

    it 'raises for the emit reader' do
      expect { Class.new(Lever) { private def moved_signal = nil } }
        .to raise_error(NameError, /#moved_signal would replace what signal :moved generated in Lever,/)
    end

    it 'raises however the method is made' do
      expect { Class.new(Lever) { define_method(:on_changed) { nil } } }.to raise_error(NameError)
    end

    it 'raises in the declaring class too, after the declaration' do
      expect { Lever.class_eval { def on_pulled = nil } }.to raise_error(NameError)
    end

    it 'raises for the disconnect method' do
      expect { Class.new(Lever) { def disconnect_pulled(handle) = handle } }
        .to raise_error(NameError, /#disconnect_pulled would replace what signal :pulled generated in Lever,/)
    end

    it 'raises when a subclass declares the same signal again' do
      expect { Class.new(Lever) { signal :pulled } }.to raise_error(NameError)
    end

    it 'names how to react to the signal instead' do
      expect { Class.new(Lever) { def on_pulled = nil } }
        .to raise_error(NameError, /connect a block: on_pulled \{ ... \}/)
    end
  end
end
