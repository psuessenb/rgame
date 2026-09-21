# frozen_string_literal: true

RSpec.describe RGame::Engine::StateMachine do
  def build(start: :a, &) = RGame::Engine::StateGraph.build(start:, &)

  let(:log) { [] }

  describe 'starting' do
    it 'enters the start state, counts it once and runs its enter:' do
      entered = []
      machine = described_class.new(build { state(:a, enter: ->(m) { entered << m.state }) })
      expect([machine.state, machine.visits(:a), entered]).to eq([:a, 1, [:a]])
    end

    it 'counts a state never entered as 0' do
      expect(described_class.new(build { state :a }).visits(:b)).to eq(0)
    end

    it 'keeps the context and facts it was given' do
      machine = described_class.new(build { state :a }, context: :hero, facts: :facts)
      expect([machine.context, machine.facts]).to eq(%i[hero facts])
    end
  end

  describe '#take' do
    let(:log_graph) do
      log = self.log
      build do
        state :a do
          go to: :b, then: ->(m) { log << [:effect, m.state, m.visits(:b)] }
        end
        state :b, enter: ->(m) { log << [:enter, m.state, m.visits(:b)] }
      end
    end

    it 'runs the effect, changes state, counts, runs enter:, then emits, in that order' do
      machine = described_class.new(log_graph)
      machine.on_changed { |from, to, _| log << [:changed, from, to, machine.visits(:b)] }
      machine.take(machine.transitions.first)
      expect(log).to eq([[:effect, :a, 0], [:enter, :b, 1], [:changed, :a, :b, 1]])
    end

    it 'returns the transition and passes it to listeners' do
      machine = described_class.new(log_graph)
      heard = nil
      machine.on_changed { |_, _, transition| heard = transition }
      taken = machine.take(machine.transitions.first)
      expect([taken, heard]).to all(equal(log_graph.transitions(:a).first))
    end

    it 'refuses a transition not listed for the current state' do
      graph = build do
        state(:a) { go to: :b }
        state(:b) { go to: :a }
      end
      machine = described_class.new(graph)
      expect { machine.take(graph.transitions(:b).first) }.to raise_error(ArgumentError, /not listed/)
    end

    it 'refuses an unavailable transition and changes nothing' do
      machine = described_class.new(build { state(:a) { go to: :a, if: ->(_) { false } } })
      expect { machine.take(machine.transitions.first) }.to raise_error(ArgumentError, /not available/)
      expect(machine.visits(:a)).to eq(1)
    end

    it 'counts re-entering a state through a cycle' do
      machine = described_class.new(build { state(:a) { go to: :a } })
      2.times { machine.take(machine.transitions.first) }
      expect(machine.visits(:a)).to eq(3)
    end
  end

  describe '#available?' do
    def machine_with(**conditions)
      described_class.new(build { state(:a) { go(to: :a, **conditions) } })
    end

    it 'requires if: to hold and unless: not to' do
      results = [[true, false], [true, true], [false, false]].map do |yes, no|
        machine = machine_with(if: ->(_) { yes }, unless: ->(_) { no })
        machine.available?(machine.transitions.first)
      end
      expect(results).to eq([true, false, false])
    end

    it 'treats a transition with no conditions as available' do
      machine = machine_with
      expect(machine.available?(machine.transitions.first)).to be true
    end

    it 'runs its condition on every call' do
      count = 0
      machine = machine_with(if: ->(_) { count += 1 })
      3.times { machine.available?(machine.transitions.first) }
      expect(count).to eq(3)
    end

    it 'refuses a transition from another state, as take does' do
      graph = build do
        state(:a) { go to: :b }
        state(:b) { go to: :a }
      end
      expect { described_class.new(graph).available?(graph.transitions(:b).first) }
        .to raise_error(ArgumentError, /not listed/)
    end
  end

  describe '#fire' do
    let(:graph) do
      build do
        state :a do
          on :go, to: :b, if: ->(m) { m.context == :locked }
          on :go, to: :c
        end
        state :b
        state :c
      end
    end

    it 'takes the first available transition with that event, and returns it' do
      machine = described_class.new(graph)
      expect([machine.fire(:go), machine.state]).to eq([graph.transitions(:a).last, :c])
    end

    it 'ignores an event with no available transition, returning nil' do
      machine = described_class.new(graph)
      emitted = false
      machine.on_changed { emitted = true }
      expect([machine.fire(:jump), machine.state, emitted]).to eq([nil, :a, false])
    end
  end

  describe 'ending' do
    let(:machine) { described_class.new(build { state(:a) { on :quit } }) }

    it 'ends on a transition with no to:, emitting nil as the new state' do
      heard = nil
      machine.on_changed { |from, to, _| heard = [from, to] }
      machine.fire(:quit)
      expect([machine.ended?, machine.state, heard]).to eq([true, nil, [:a, nil]])
    end

    it 'lists nothing and fires nothing once ended' do
      machine.fire(:quit)
      expect([machine.transitions, machine.fire(:quit)]).to eq([[], nil])
    end
  end

  describe 're-entry' do
    it 'refuses a take from inside its own effect' do
      machine = described_class.new(build { state(:a) { on :go, to: :a, then: ->(m) { m.fire(:go) } } })
      expect { machine.fire(:go) }.to raise_error(RuntimeError, /own effect/)
    end

    it 'refuses a fire from inside its own listener, and can move again afterwards' do
      machine = described_class.new(build { state(:a) { on :go, to: :a } })
      calls = 0
      machine.on_changed { machine.fire(:go) if (calls += 1) == 1 }
      expect { machine.fire(:go) }.to raise_error(RuntimeError, /own effect or listener/)
      expect(machine.fire(:go)).not_to be_nil
    end

    it 'lets an effect drive a second machine' do
      quest = described_class.new(build(start: :open) do
        state(:open) { on :done, to: :closed }
        state :closed
      end)
      talk = described_class.new(build { state(:a) { go to: :a, then: ->(_) { quest.fire(:done) } } })
      talk.take(talk.transitions.first)
      expect(quest.state).to eq(:closed)
    end
  end

  describe 'allocation' do
    it 'reads transitions and visits without allocating' do
      machine = described_class.new(build { state(:a) { go to: :a } })
      expect do
        machine.transitions
        machine.visits(:a)
        machine.visits(:never)
      end.to allocate_nothing
    end
  end
end
