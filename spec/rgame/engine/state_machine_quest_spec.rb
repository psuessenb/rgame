# frozen_string_literal: true

require 'tmpdir'

# The first caller using both the machine and the facts: a hammer quest and a
# gate, each moved on by the other. Accepting the quest lowers the bridge, the
# gate follows that fact, and the hammer can only be found once the gate is open.
RSpec.describe RGame::Engine::StateMachine do
  let(:engine) { RGame::Engine }

  before do
    stub_const('Gate', Class.new(engine::Node2D) do
      const_set(:GRAPH, RGame::Engine::StateGraph.build(start: :shut) do
        state(:shut) { on :lower, to: :open }
        state :open
      end)

      def on_add
        @facts = system(RGame::Engine::Components::Facts)
        @machine = RGame::Engine::StateMachine.new(self.class::GRAPH, facts: @facts, name: :gate)
        @bridge = @facts.watch(:bridge_down) { |down| @machine.fire(:lower) if down }
      end

      def on_remove = @facts.unwatch(@bridge)

      def open? = @machine.state == :open
    end)

    stub_const('Village', Class.new(engine::Node2D) do
      const_set(:HAMMER, RGame::Engine::StateGraph.build(start: :not_started) do
        state(:not_started) { on :accepted, to: :searching, then: ->(m) { m.facts[:bridge_down] = true } }
        state(:searching) { on :hammer_found, to: :found, if: :gate_open? }
        state(:found) { on :returned, to: :done, then: :pay_reward }
        state :done
      end)

      attr_reader :gate, :hammer
      attr_accessor :gold

      def initialize
        super
        @gold = 0
        @gate = add_node(Gate.new)
      end

      def on_add
        facts = system(RGame::Engine::Components::Facts)
        @hammer = RGame::Engine::StateMachine.new(self.class::HAMMER, context: self, facts:, name: :hammer)
      end

      def gate_open? = gate.open?
      def pay_reward = @gold += 100
    end)
  end

  def world
    root = engine::Node2D.new
    root.add_component(engine::Components::Facts.new)
    root.enter_tree
    root
  end

  def facts_of(root) = root.system(engine::Components::Facts)

  def save_and_read(root, village)
    Dir.mktmpdir do |dir|
      save = RGame::Util::SaveFile.new('slot1.json', dir:)
      save.write(world: facts_of(root).to_h, gold: village.gold)
      save.read
    end
  end

  def played_to_found
    root = world
    village = root.add_node(Village.new)
    village.hammer.fire(:hammer_found)
    village.hammer.fire(:accepted)
    village.hammer.fire(:hammer_found)
    [root, village]
  end

  it 'moves each machine on because of the other' do
    root = world
    village = root.add_node(Village.new)
    expect(village.hammer.fire(:hammer_found)).to be_nil
    village.hammer.fire(:accepted)
    expect(village.gate).to be_open
    village.hammer.fire(:hammer_found)
    village.hammer.fire(:returned)
    expect([village.hammer.state, village.gold]).to eq([:done, 100])
  end

  it 'saves as one entry and resumes in a village built after the load' do
    saved = save_and_read(*played_to_found)
    root = world
    facts_of(root).restore(saved[:world])
    village = root.add_node(Village.new)
    village.gold = saved[:gold]
    expect([village.hammer.state, village.gate.open?]).to eq([:found, true])
    village.hammer.fire(:returned)
    expect(village.gold).to eq(100)
  end

  it 'resumes the same in a village built before the load' do
    saved = save_and_read(*played_to_found)
    root = world
    village = root.add_node(Village.new)
    facts_of(root).restore(saved[:world])
    expect([village.hammer.state, village.gate.open?]).to eq([:found, true])
  end

  it 'keeps its place when the player leaves the village and comes back' do
    root, village = played_to_found
    root.remove_node(village)
    village = root.add_node(Village.new)
    expect([village.hammer.state, village.gate.open?]).to eq([:found, true])
  end

  it 'opens the gate from the fact alone, for a save made before the gate had a name' do
    saved = save_and_read(*played_to_found)
    root = world
    village = root.add_node(Village.new)
    facts_of(root).restore(values: saved[:world][:values], machines: saved[:world][:machines].except(:gate))
    expect(village.gate).to be_open
  end
end
