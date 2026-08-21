# frozen_string_literal: true

# Which player a node answers to, and how that reaches its subtree.
#
# The mechanism is deliberately the one the transform already uses: ownership is
# resolved onto `abs_input_owner` in `resolve_origin` and accumulates down the tree.
# So `ship.input_owner = players[1]` puts everything under the ship on player two,
# and a tree that names nobody reads the primary player — which is what keeps
# single player free of ceremony.
RSpec.describe RGame::Engine::Node2D do
  let(:controls) { RGame::Util::Controls }
  let(:backend)  { FakeInputBackend.new }

  let(:one) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD) }
  let(:two) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
  let(:players) { RGame::Engine::Players.new([one, two]) }

  # Player one holds a key, player two holds the pad button bound to the same
  # action. Reading :fire then says which player a node is listening to.
  before do
    backend.hold(controls::KEY_SPACE)
    backend.hold(controls::PAD_A, device: controls.gamepad(0))
    players.poll(backend)
  end

  # Records the Actions its node was driven with.
  def recorder
    Class.new(described_class) do
      attr_reader :seen

      def on_control(actions) = @seen = actions
    end.new
  end

  describe 'resolving the owner' do
    it 'is nobody by default' do
      root = described_class.new
      root.control(players)
      expect(root.abs_input_owner).to be_nil
    end

    it 'is the player a node was given' do
      root = described_class.new(input_owner: two)
      root.control(players)
      expect(root.abs_input_owner).to equal(two)
    end

    it 'is inherited by a child that names nobody' do
      root = described_class.new(input_owner: two)
      child = root.add_node(described_class.new)
      root.control(players)
      expect(child.abs_input_owner).to equal(two)
    end

    it 'reaches all the way down a subtree' do
      root = described_class.new(input_owner: two)
      leaf = root.add_node(described_class.new).add_node(described_class.new)
      root.control(players)
      expect(leaf.abs_input_owner).to equal(two)
    end

    it 'is overridden by a child that names its own' do
      root = described_class.new(input_owner: two)
      child = root.add_node(described_class.new(input_owner: one))
      root.control(players)
      expect(child.abs_input_owner).to equal(one)
    end

    it 'is resolved in update too, so a HUD can read it outside control' do
      root = described_class.new(input_owner: two)
      root.update(0.016)
      expect(root.abs_input_owner).to equal(two)
    end
  end

  describe 'the actions a node is driven with' do
    it 'is the primary player\'s when nobody claims it' do
      root = described_class.new
      node = root.add_node(recorder)
      root.control(players)
      expect(node.seen).to equal(one.actions)
    end

    it 'is its owner\'s when one is named' do
      root = described_class.new
      node = root.add_node(recorder)
      node.input_owner = two
      root.control(players)
      expect(node.seen).to equal(two.actions)
    end

    # The point of the whole design: one traversal, two players, two answers.
    it 'differs between two subtrees under one tick' do
      root = described_class.new
      left = root.add_node(described_class.new(input_owner: one)).add_node(recorder)
      right = root.add_node(described_class.new(input_owner: two)).add_node(recorder)

      root.control(players)

      expect([left.seen.held?(:fire), right.seen.held?(:fire)]).to eq([true, true])
    end

    it 'gives each subtree the snapshot of its own player, not a shared one' do
      root = described_class.new
      left = root.add_node(described_class.new(input_owner: one)).add_node(recorder)
      right = root.add_node(described_class.new(input_owner: two)).add_node(recorder)

      root.control(players)

      expect(left.seen).not_to equal(right.seen)
    end

    # A player with nothing pressed reads false for the same action the other
    # player is holding — which is what "two controllers" has to mean.
    it 'does not leak one player\'s input into another\'s subtree' do
      idle = RGame::Engine::Player.new(id: 2, device: RGame::Util::Controls.gamepad(1))
      registry = RGame::Engine::Players.new([one, idle])
      registry.poll(backend)

      root = described_class.new
      held = root.add_node(described_class.new(input_owner: one)).add_node(recorder)
      quiet = root.add_node(described_class.new(input_owner: idle)).add_node(recorder)
      root.control(registry)

      expect([held.seen.held?(:fire), quiet.seen.held?(:fire)]).to eq([true, false])
    end
  end

  describe 'what components receive' do
    # Unchanged, and that is the design: a component belongs to one node, so one
    # player's snapshot is exactly right for it. Nothing in components/ had to
    # change for any of this.
    it 'is a plain Actions, not the source' do
      root = described_class.new(input_owner: two)
      body = root.add_component(RGame::Engine::Components::ActionTrigger.new(fire: 0.0))
      seen = nil
      allow(body).to receive(:control) { |actions| seen = actions }

      root.control(players)

      expect(seen).to equal(two.actions)
    end
  end

  describe 'a bare Actions as the source' do
    # A snapshot resolves to itself for every player, so a tree driven with one
    # behaves exactly as it did before ownership existed. Every spec in this
    # suite that predates players relies on this.
    it 'drives an owned node just the same' do
      snapshot = RGame::Engine::Actions.new(held: { fire: true })
      root = described_class.new(input_owner: two)
      node = root.add_node(recorder)

      root.control(snapshot)

      expect(node.seen).to equal(snapshot)
    end
  end
end
