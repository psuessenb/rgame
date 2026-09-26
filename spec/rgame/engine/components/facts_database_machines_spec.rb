# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RGame::Engine::Components::FactsDatabase do
  let(:facts) { described_class.new }
  let(:trail) { [] }

  let(:graph) do
    RGame::Engine::StateGraph.build(start: :a) do
      state :a, enter: ->(m) { m.context << :entered_a } do
        on :go, to: :b
      end
      state :b do
        on :quit
      end
    end
  end

  def machine(name = :quest, **) = RGame::Engine::StateMachine.new(graph, context: trail, facts:, name:, **)

  def round_trip(state)
    Dir.mktmpdir do |dir|
      save = RGame::Util::SaveFile.new('slot.json', dir:)
      save.write(world: state)
      save.read[:world]
    end
  end

  describe 'a named machine' do
    it 'refuses name: without facts:' do
      expect { RGame::Engine::StateMachine.new(graph, context: trail, name: :quest) }
        .to raise_error(ArgumentError, /needs facts:/)
    end

    it 'refuses name: with from:' do
      expect { machine(from: { state: :b }) }.to raise_error(ArgumentError, /takes no from:/)
    end

    it 'refuses a name that is not a Symbol' do
      expect { machine('quest') }.to raise_error(TypeError, /"quest" \(String\)/)
    end

    it 'takes over from a machine already under its name, where it had got to' do
      first = machine
      first.fire(:go)
      second = machine
      second.fire(:quit)
      expect([second.visits(:b), facts.to_h[:machines][:quest]]).to eq([1, { state: nil, visits: { a: 1, b: 1 } }])
    end

    it 'retires the machine it replaced, which then refuses to move' do
      first = machine
      machine
      expect { first.fire(:go) }.to raise_error(RuntimeError, /:quest was replaced by a newer one/)
    end

    it 'starts fresh with no entry, and appears in to_h' do
      quest = machine
      expect([quest.state, trail]).to eq([:a, [:entered_a]])
      expect(facts.to_h[:machines]).to eq(quest: { state: :a, visits: { a: 1 } })
    end
  end

  describe 'a machine built after restore' do
    it 'resumes from its entry, running nothing' do
      facts.restore(round_trip(values: {}, machines: { quest: { state: :b, visits: { a: 1, b: 1 } } }))
      quest = machine
      expect([quest.state, quest.visits(:b), trail]).to eq([:b, 1, []])
    end

    it 'raises for an entry naming a state its graph lacks' do
      facts.restore(values: {}, machines: { quest: { state: 'gone', visits: {} } })
      expect { machine }.to raise_error(ArgumentError, /"gone"/)
    end
  end

  describe 'a machine built before restore' do
    it 'is put where its entry says, running nothing and emitting nothing' do
      quest = machine
      changed = false
      quest.on_changed { changed = true }
      trail.clear
      facts.restore(round_trip(values: {}, machines: { quest: { state: :b, visits: { a: 2, b: 1 } } }))
      expect([quest.state, quest.visits(:a), trail, changed]).to eq([:b, 2, [], false])
    end

    it 'goes back to its start state with no entry, running nothing' do
      quest = machine
      quest.fire(:go)
      trail.clear
      facts.restore(nil)
      expect([quest.state, quest.to_h[:visits], trail]).to eq([:a, { a: 1 }, []])
    end

    it 'is in place before any fact watcher runs' do
      quest = machine
      heard = []
      facts.watch(:flag) { heard << [it, quest.state] }
      facts.restore(values: { flag: true }, machines: { quest: { state: :b } })
      expect(heard).to eq([[nil, :a], [true, :b]])
    end
  end

  describe 'an entry no machine claims' do
    it 'survives restore and to_h unchanged' do
      machine
      entry = { state: 'searching', visits: { searching: 1 } }
      facts.restore(values: {}, machines: { quest: { state: :a }, hammer: entry })
      expect(round_trip(facts.to_h)[:machines][:hammer]).to eq(entry)
    end
  end

  describe 'a failed restore' do
    it 'changes no fact and no machine' do
      quest = machine
      quest.fire(:go)
      facts[:wolves] = 3
      before = facts.to_h
      expect { facts.restore(values: { wolves: 4 }, machines: { quest: { state: 'gone' } }) }
        .to raise_error(ArgumentError, /"gone"/)
      expect([facts.to_h, quest.state]).to eq([before, :b])
    end
  end
end
