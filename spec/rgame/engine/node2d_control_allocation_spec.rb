# frozen_string_literal: true

# The control traversal runs once per node per tick, and routing input by owner
# put two new things on it: an `actions_for` call per node and an `abs_input_owner`
# assignment in `resolve_origin`. Neither may allocate — a steady 60fps frame
# that allocates is a GC pause waiting to happen, and this is the path every
# node in the game goes through.
RSpec.describe RGame::Engine::Node2D do
  let(:controls) { RGame::Util::Controls }

  let(:one) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD) }
  let(:two) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
  let(:players) { RGame::Engine::Players.new([one, two]) }

  # A tree with both kinds of node: some claiming an owner, some inheriting.
  let(:root) do
    described_class.new.tap do |node|
      left = node.add_node(described_class.new(input_owner: one))
      right = node.add_node(described_class.new(input_owner: two))
      3.times { left.add_node(described_class.new) }
      3.times { right.add_node(described_class.new) }
    end
  end

  before { players.poll(FakeInputBackend.new) }

  it 'allocates nothing while routing input by owner' do
    expect { root.control(players) }.to allocate_nothing
  end

  it 'allocates nothing when driven by a bare snapshot either' do
    snapshot = RGame::Engine::Actions.new(held: { fire: false })
    expect { root.control(snapshot) }.to allocate_nothing
  end
end
