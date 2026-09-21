# frozen_string_literal: true

RSpec.describe RGame::Engine::StateGraph do
  let(:graph) do
    described_class.build(start: :idle) do
      state :idle, enter: :greet, data: { line: 'hello' } do
        on :start, to: :running, if: :ready?, then: ->(m) { m }
        go to: :idle, unless: :tired?, data: { label: 'wait' }
      end
      state :running do
        go then: :stop_all
      end
    end
  end

  it 'lists the transitions out of a state in the order they were declared' do
    expect(graph.transitions(:idle).map(&:to)).to eq(%i[running idle])
  end

  it 'answers state? for declared states only' do
    expect([graph.state?(:running), graph.state?(:flying)]).to eq([true, false])
  end

  it 'lands if:, unless: and then: in requires, forbids and effect' do
    first, second = graph.transitions(:idle)
    expect([first.event, first.requires, second.forbids, second.event]).to eq([:start, :ready?, :tired?, nil])
  end

  it 'leaves to: nil on a transition that ends the machine' do
    expect(graph.transitions(:running).first.to).to be_nil
  end

  it 'passes data: through untouched on states and transitions' do
    expect([graph.state(:idle).data, graph.transitions(:idle).last.data]).to eq([{ line: 'hello' }, { label: 'wait' }])
  end

  it 'finds every Symbol given as a condition or effect, on transitions and states, once each' do
    expect(graph.each_symbol.to_a).to contain_exactly(:greet, :ready?, :tired?, :stop_all)
  end

  it 'allows a state no transition reaches' do
    expect { described_class.build(start: :a) { %i[a orphan].each { state it } } }.not_to raise_error
  end

  describe 'freezing' do
    it 'freezes the graph, each transition Array and each transition' do
      expect([graph, graph.transitions(:idle), graph.transitions(:idle).first]).to all(be_frozen)
    end
  end

  describe 'build errors' do
    def build(start: :a, &) = described_class.build(start:, &)

    it 'refuses a to: naming no state, naming it' do
      expect { build { state(:a) { go to: :nowhere } } }.to raise_error(ArgumentError, /:nowhere/)
    end

    it 'refuses a start that is not a state' do
      expect { build(start: :missing) { state :a } }.to raise_error(ArgumentError, /:missing/)
    end

    it 'refuses a state declared twice' do
      expect { build { 2.times { state :a } } }.to raise_error(ArgumentError, /:a declared twice/)
    end

    it 'refuses on outside a state block' do
      expect { build { on :go, to: :a } }.to raise_error(ArgumentError, /inside a state/)
    end

    it 'refuses go outside a state block' do
      expect { build { go to: :a } }.to raise_error(ArgumentError, /inside a state/)
    end

    it 'refuses a state declared inside another' do
      expect { build { state(:a) { state :b } } }.to raise_error(ArgumentError, /inside :a/)
    end

    it 'refuses a condition that is neither callable nor a Symbol' do
      expect { build { state(:a) { go if: 'ready?' } } }.to raise_error(ArgumentError, /if:/)
    end

    it 'refuses an effect that is neither callable nor a Symbol' do
      expect { build { state(:a, enter: 42) } }.to raise_error(ArgumentError, /enter:/)
    end

    it 'refuses a state name that is not a Symbol, since a save would bring it back one' do
      expect { build(start: 'a') { state 'a' } }.to raise_error(ArgumentError, /Symbol/)
    end
  end
end
