# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::DespawnOffscreen do
  # The node is a child rather than a root, because a root is pinned to the world origin
  # whatever its own x and y say, and this component reads the world position.
  let(:root) { RGame::Engine::Node2D.new }
  let(:node) { RGame::Engine::Node2D.new.tap { root.add_node(it) } }

  describe '#update' do
    subject(:despawn) { described_class.new(width: 100, height: 80, margin: 5) }

    before do
      node.add_component(despawn)
      root.enter_tree # bounds are resolved at attach, so the node has to be live
    end

    it 'queues the node for removal once its origin is further than the margin past an edge' do
      node.x = 106
      despawn.update(0.0)
      expect(node).to be_freed
    end

    it 'leaves a node inside the bounds (plus margin) alive' do
      node.x = -5
      node.y = 85
      despawn.update(0.0)
      expect(node).not_to be_freed
    end
  end

  it_behaves_like 'a world edge response' do
    def add_response(node, vx:)
      node.add_component(RGame::Engine::Components::Velocity.new(vx: vx))
      node.add_component(described_class.new)
    end

    def responded?(node, _from) = node.freed?
  end

  describe 'bounds resolution' do
    subject(:despawn) { described_class.new(margin: 5) }

    it 'takes the world system bounds when none were passed' do
      root.add_component(RGame::Engine::Components::World.new(width: 100, height: 80))
      node.add_component(despawn)
      root.enter_tree

      node.x = 106
      despawn.update(0.0)
      expect(node).to be_freed
    end

    it 'refuses to attach where nothing answers for the world size' do
      node.add_component(despawn)

      expect { root.enter_tree }.to raise_error(RuntimeError, /no world bounds in scope/)
    end
  end
end
