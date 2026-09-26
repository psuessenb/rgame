# frozen_string_literal: true

RSpec.describe RGame::Engine::Exploration do
  def script(start: :greeting, &) = RGame::Engine::Dialogue::Script.build(start:, scope: 'smith', &)

  def talk(script, **) = RGame::Engine::Dialogue.new(script, **)

  let(:engine) { RGame::Engine }
  let(:purse_class) { Struct.new(:gold) }

  describe 'a machine' do
    let(:hammer) do
      engine::StateGraph.build(start: :not_started) do
        state(:not_started) { on :accepted, to: :searching }
        state(:searching) { on :hammer_found, to: :found }
        state(:found) { on :returned, to: :done }
        state :done
      end
    end

    it 'reports a quest whose every stage leads on as clean, ending at the state with no transitions' do
      report = described_class.run { engine::StateMachine.new(hammer) }
      expect([report.problems, report.ending.size, report.unreached]).to eq([[], 3, []])
    end

    it 'finds a stage no transition can leave, with the path there' do
      locked = engine::StateGraph.build(start: :open) do
        state(:open) { on :enter, to: :vault }
        state(:vault) { on :leave, to: :open, if: ->(_) { false } }
      end
      report = described_class.run { engine::StateMachine.new(locked) }
      expect(report.problems).to eq(['stuck at :vault after open: enter: no transition is available',
                                     'no path reaches an end'])
    end
  end

  describe 'a dialogue' do
    let(:smith) do
      script do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'ask_work', to: :work, once: true
          respond 'bribe', to: :bribed, if: ->(m) { m.context.gold >= 50 }
          respond 'bye'
        end
        beat :work, speaker: :smith, line: 'work', to: :greeting
        beat :bribed, speaker: :smith, line: 'bribed'
      end
    end

    it 'reports a conversation with a way out of every beat as clean' do
      report = described_class.run { talk(smith, context: purse_class.new(0)) }
      expect(report.problems).to eq([])
    end

    it 'lists the beats the world it was given shuts, as unreached rather than a problem' do
      poor = described_class.run { talk(smith, context: purse_class.new(0)) }
      rich = described_class.run { talk(smith, context: purse_class.new(60)) }
      expect([poor.unreached, rich.unreached]).to eq([[:bribed], []])
    end

    it 'gives the shortest path to an end' do
      report = described_class.run { talk(smith, context: purse_class.new(0)) }
      expect(report.ending).to eq(['greeting: bye'])
    end

    it 'finds a beat that waits with no response available, with the path there' do
      dead = script do
        beat :greeting, speaker: :smith, line: 'greeting', to: :shut
        beat(:shut, speaker: :smith, line: 'shut') { respond 'bye', if: ->(_) { false } }
      end
      report = described_class.run { talk(dead) }
      expect(report.problems.first).to match(/\Astuck at :shut after greeting: continue: RuntimeError: .*no way out/)
    end

    it 'finds a state with no line that hangs, only on the path that reaches it' do
      hang = script do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'ask', to: :branch
          respond 'bye'
        end
        state(:branch) { go to: :greeting, if: ->(_) { false } }
      end
      report = described_class.run { talk(hang) }
      expect([report.stuck.map(&:path), report.ends?]).to eq([[['greeting: ask']], true])
    end

    it 'reports a conversation with no end' do
      endless = script { beat :greeting, speaker: :smith, line: 'greeting', to: :greeting }
      expect(described_class.run { talk(endless) }.problems).to eq(['no path reaches an end'])
    end

    it 'counts a question asked again and again as one position, beside the end' do
      again = script do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'again', to: :greeting
          respond 'bye'
        end
      end
      report = described_class.run { talk(again) }
      expect([report.problems, report.positions]).to eq([[], 2])
    end

    it 'reports a world the block cannot build' do
      picky = script { beat(:greeting, speaker: :smith, line: 'greeting') { respond 'bye', if: :ready? } }
      report = described_class.run { talk(picky, context: Object.new) }
      expect(report.problems.first)
        .to match(/\Athe block raised building the world: NoMethodError: Object does not answer :ready\?/)
    end

    it 'reports a condition that raises as stuck where it is asked' do
      report = described_class.run { talk(smith, context: Object.new) }
      expect(report.problems.first)
        .to match(/\Astuck at :greeting after the start: NoMethodError: undefined method 'gold'/)
    end
  end

  describe 'the facts' do
    let(:counting) do
      script do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'count', to: :greeting, then: ->(m) { m.facts[:count] = m.facts.fetch(:count, 0) + 1 }
          respond 'bye'
        end
      end
    end

    it 'tells positions apart by their facts, and stops at the limit' do
      report = described_class.run(max_moves: 5) { talk(counting, facts: engine::Components::FactsDatabase.new) }
      expect([report.truncated?,
              report.problems.last]).to eq([true, 'stopped with positions unexplored, at 5 moves or 10000 positions'])
    end

    it 'refuses a block that builds a different world on a replay' do
      builds = 0
      expect do
        described_class.run do
          facts = engine::Components::FactsDatabase.new
          facts[:build] = builds += 1
          talk(counting, facts:)
        end
      end.to raise_error(ArgumentError, /different world on a replay/)
    end
  end

  describe 'key:' do
    let(:shop) do
      script do
        beat :greeting, speaker: :smith, line: 'greeting' do
          respond 'earn', to: :greeting, then: ->(m) { m.context.gold += 10 }
          respond 'buy', to: :bought, if: ->(m) { m.context.gold >= 30 }
        end
        beat :bought, speaker: :smith, line: 'bought'
      end
    end

    it 'misses what the context holds without it' do
      report = described_class.run { talk(shop, context: purse_class.new(0)) }
      expect([report.unreached, report.problems]).to eq([[:bought], ['no path reaches an end']])
    end

    it 'tells positions apart by what it returns' do
      report = described_class.run(key: lambda { |t|
        t.context.gold.clamp(..30)
      }) { talk(shop, context: purse_class.new(0)) }
      expect([report.unreached, report.problems, report.ending.size]).to eq([[], [], 5])
    end
  end

  it 'needs a block' do
    expect { described_class.run }.to raise_error(ArgumentError, /needs a block/)
  end
end
