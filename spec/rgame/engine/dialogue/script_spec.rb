# frozen_string_literal: true

RSpec.describe RGame::Engine::Dialogue::Script do
  def build(start: :a, scope: 'smith', &) = described_class.build(start:, scope:, &)

  let(:engine) { RGame::Engine }

  describe 'a beat' do
    let(:script) do
      build(start: :greeting) do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'ask_work', to: :work
          respond 'bye'
        end
        beat :work, speaker: :smith, line: 'work', to: :greeting
        beat :bribed, speaker: :smith, line: :bribed
      end
    end

    it 'is a state carrying its speaker, the name key and the line key under the scope' do
      beat = script.graph.state(:greeting).data
      expect([beat.speaker, beat.speaker_name.key, beat.line.key,
              beat.line.scope]).to eq([:smith, 'speakers.smith', 'greeting', 'smith'])
    end

    it 'shares one name Text between every beat of a speaker' do
      expect(script.graph.state(:greeting).data.speaker_name).to equal(script.graph.state(:work).data.speaker_name)
    end

    it 'puts its responses in its transitions, each carrying its label' do
      labels = script.graph.transitions(:greeting).map { it.data.label.key }
      expect(labels).to eq(%w[ask_work bye])
    end

    it 'continues to its to: on :continue' do
      transition = script.graph.transitions(:work).first
      expect([transition.event, transition.to]).to eq(%i[continue greeting])
    end

    it 'ends on :continue with neither responses nor to:' do
      transition = script.graph.transitions(:bribed).first
      expect([transition.event, transition.to]).to eq([:continue, nil])
    end

    it 'is told apart from a state with no line' do
      branchy = build(start: :greeting) do
        beat :greeting, speaker: :smith, line: 'greeting', to: :branch
        state(:branch) { go to: :greeting }
      end
      expect([branchy.beat?(:greeting), branchy.beat?(:branch)]).to eq([true, false])
    end

    it 'refuses responses together with a to:' do
      expect do
        build { beat(:a, speaker: :smith, line: 'x', to: :a) { respond 'bye' } }
      end.to raise_error(ArgumentError, /:a has responses and a to:/)
    end

    it 'refuses on and go inside its block' do
      expect do
        build do
          beat(:a, speaker: :smith, line: 'x') do
            go to: :a
          end
        end
      end.to raise_error(ArgumentError, /go inside beat :a/)
      expect do
        build do
          beat(:a, speaker: :smith, line: 'x') do
            on :poke
          end
        end
      end.to raise_error(ArgumentError, /on inside beat :a/)
    end

    it 'refuses a speaker that is not a Symbol' do
      expect do
        build do
          beat :a, speaker: 'smith', line: 'x'
        end
      end.to raise_error(ArgumentError, /speaker must be a Symbol/)
    end

    it 'keeps enter: as the state effect' do
      effect = ->(_) {}
      expect(build { beat :a, speaker: :smith, line: 'x', enter: effect }.graph.state(:a).enter).to equal(effect)
    end
  end

  describe 'text' do
    it 'uses an Engine::Text as it is' do
      line = engine::Text.new('elsewhere.line')
      label = engine::Text.new('elsewhere.bye')
      script = build { beat(:a, speaker: :smith, line:) { respond label } }
      expect([script.graph.state(:a).data.line,
              script.graph.transitions(:a).first.data.label]).to all(be_a(engine::Text))
      expect(script.graph.state(:a).data.line).to equal(line)
    end

    it 'refuses a line that is neither a key nor an Engine::Text' do
      expect { build { beat :a, speaker: :smith, line: 42 } }.to raise_error(TypeError, /translation key or an Engine::Text/)
    end

    it 'refuses such a response label' do
      expect do
        build do
          beat(:a, speaker: :smith, line: 'x') do
            respond 42
          end
        end
      end.to raise_error(TypeError, /response label/)
    end

    it 'keeps a scope of nil when given none' do
      script = described_class.build(start: :a) { beat :a, speaker: :smith, line: 'greeting' }
      expect([script.scope, script.graph.state(:a).data.line.scope]).to eq([nil, nil])
    end
  end

  describe 'vars:' do
    it 'keeps a block or a Symbol for a line with variables' do
      line = engine::Text.new('gold', :gold)
      script = build { beat :a, speaker: :smith, line:, vars: :purse }
      expect(script.graph.state(:a).data.vars).to eq(:purse)
    end

    it 'is refused on a line that names no variables' do
      expect do
        build do
          beat :a, speaker: :smith, line: 'x', vars: :purse
        end
      end.to raise_error(ArgumentError, /names no variables/)
    end

    it 'is required by a line that names variables' do
      line = engine::Text.new('gold', :gold)
      expect { build { beat :a, speaker: :smith, line: } }.to raise_error(ArgumentError, /needs gold:; give it vars:/)
    end

    it 'is refused when neither callable nor a Symbol' do
      line = engine::Text.new('gold', :gold)
      expect do
        build do
          beat :a, speaker: :smith, line:, vars: 3
        end
      end.to raise_error(ArgumentError, /vars: must be callable/)
    end
  end

  describe 'once:' do
    it 'hides the response once its target was entered' do
      script = build { beat(:a, speaker: :smith, line: 'x') { respond 'again', to: :a, once: true } }
      forbids = script.graph.transitions(:a).first.forbids
      machine = instance_double(engine::StateMachine)
      allow(machine).to receive(:visits).with(:a).and_return(0, 1)
      expect([forbids.call(machine), forbids.call(machine)]).to eq([false, true])
    end

    it 'is refused on a response with no to:' do
      expect { build { beat(:a, speaker: :smith, line: 'x') { respond 'bye', once: true } } }
        .to raise_error(ArgumentError, /once: but has no to:/)
    end

    it 'is refused together with unless:' do
      expect { build { beat(:a, speaker: :smith, line: 'x') { respond 'bye', to: :a, once: true, unless: :x? } } }
        .to raise_error(ArgumentError, /once: or unless:, not both/)
    end
  end

  describe 'a state with no line' do
    it 'still takes state, on and go' do
      script = build(start: :branch) do
        state :branch do
          go to: :rich, if: :rich?
          go to: :poor
        end
        beat :rich, speaker: :smith, line: 'rich'
        beat :poor, speaker: :smith, line: 'poor'
      end
      expect(script.graph.transitions(:branch).map(&:to)).to eq(%i[rich poor])
    end

    it 'refuses a respond' do
      expect { build { state(:a) { respond 'bye' } } }.to raise_error(ArgumentError, /inside a beat block/)
    end
  end

  it 'lists every Symbol it sends to the context, vars: included' do
    line = engine::Text.new('gold', :gold)
    script = build do
      beat :a, speaker: :smith, line:, vars: :purse, enter: :greet do
        respond 'bribe', to: :a, if: :can_bribe?, then: :pay_bribe
      end
    end
    expect(script.each_symbol.to_a).to contain_exactly(:purse, :greet, :can_bribe?, :pay_bribe)
  end

  it 'raises the graph build errors, such as a to: naming no state' do
    expect do
      build do
        beat :a, speaker: :smith, line: 'x', to: :nowhere
      end
    end.to raise_error(ArgumentError, /:nowhere, which is no state/)
  end

  it 'is frozen, with a frozen graph' do
    script = build { beat :a, speaker: :smith, line: 'x' }
    expect([script, script.graph]).to all(be_frozen)
  end
end
