# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::ScreenWrap do
  # The node is a child rather than a root, because a root is pinned to the world origin
  # whatever its own x and y say, and this component reads the world position.
  let(:root) { RGame::Engine::Node2D.new }
  let(:node) { RGame::Engine::Node2D.new.tap { root.add_node(it) } }

  describe '#update' do
    subject(:wrap) { described_class.new(width: 100, height: 80, margin: 5) }

    before do
      node.add_component(wrap)
      root.enter_tree # bounds are resolved at attach, so the node has to be live
    end

    it 'wraps a node past the left edge round to the right' do
      node.x = -6
      wrap.update(0.0)
      expect(node.x).to eq(105) # width + margin
    end

    it 'wraps a node past the right edge round to the left' do
      node.x = 106
      wrap.update(0.0)
      expect(node.x).to eq(-5) # -margin
    end

    it 'wraps a node past the top edge round to the bottom' do
      node.y = -6
      wrap.update(0.0)
      expect(node.y).to eq(85) # height + margin
    end

    it 'wraps a node past the bottom edge round to the top' do
      node.y = 86
      wrap.update(0.0)
      expect(node.y).to eq(-5)
    end

    # world_x walks up to the nearest current ancestor, so a wrap under a container is
    # the case that could have started allocating.
    it 'allocates nothing under an offset container' do
      container = RGame::Engine::Node2D.new(x: 40.0, y: 30.0)
      nested = RGame::Engine::Node2D.new(x: -50.0, y: 10.0)
      nested_wrap = nested.add_component(described_class.new(width: 100, height: 80, margin: 5))
      container.add_node(nested)
      root.add_node(container)
      root.enter_tree
      nested_wrap.update(0.0) # warm the transform cache: this one wraps to the right
      expect do
        nested.x -= 200.0
        nested_wrap.update(0.0)
      end.to allocate_nothing
    end

    it 'leaves a node inside the bounds untouched' do
      node.x = 50
      node.y = 40
      wrap.update(0.0)
      expect([node.x, node.y]).to eq([50, 40])
    end
  end

  it_behaves_like 'a world edge response' do
    def add_response(node, vx:)
      node.add_component(RGame::Engine::Components::Velocity.new(vx: vx))
      node.add_component(described_class.new)
    end

    # A wrap is a jump to the far side, so a node that has wrapped is further from where
    # it started than a few steps of walking could take it.
    def responded?(node, from) = (node.world_x - from).abs > 100
  end

  # With no explicit size the bounds come from the scene's world system, which is
  # what lets a pooled entity be built outside the tree with nothing to close over.
  describe 'bounds resolution' do
    subject(:wrap) { described_class.new(margin: 5) }

    def world_node(width, height)
      RGame::Engine::Node2D.new.tap do |scene|
        scene.add_component(RGame::Engine::Components::World.new(width: width, height: height))
        scene.enter_tree
      end
    end

    it 'takes the world system bounds when none were passed' do
      root.add_component(RGame::Engine::Components::World.new(width: 100, height: 80))
      node.add_component(wrap)
      root.enter_tree

      node.x = -6
      wrap.update(0.0)
      expect(node.x).to eq(105)
    end

    it 'prefers explicit bounds over the world system' do
      explicit = described_class.new(width: 100, height: 80, margin: 5)
      root.add_component(RGame::Engine::Components::World.new(width: 999, height: 999))
      node.add_component(explicit)
      root.enter_tree

      node.x = -6
      explicit.update(0.0)
      expect(node.x).to eq(105)
    end

    it 'refuses to attach where nothing answers for the world size' do
      node.add_component(wrap)

      expect { root.enter_tree }.to raise_error(RuntimeError, /no world bounds in scope/)
    end

    it 're-resolves on each entry, so a recycled node follows the scene it lands in' do
      small = world_node(100, 80)
      large = world_node(400, 300)

      node.add_component(wrap)
      small.add_node(node)
      small.remove_node(node)
      large.add_node(node) # the pool's move: same component instance, new scene

      node.x = -6
      wrap.update(0.0)
      expect(node.x).to eq(405)
    end
  end
end
