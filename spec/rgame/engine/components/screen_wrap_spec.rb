# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::ScreenWrap do
  let(:node) { RGame::Engine::Node2D.new }

  describe '#update' do
    subject(:wrap) { described_class.new(width: 100, height: 80, margin: 5) }

    before do
      node.add_component(wrap)
      node.enter_tree # bounds are resolved at attach, so the node has to be live
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

    it 'leaves a node inside the bounds untouched' do
      node.x = 50
      node.y = 40
      wrap.update(0.0)
      expect([node.x, node.y]).to eq([50, 40])
    end
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
      node.add_component(RGame::Engine::Components::World.new(width: 100, height: 80))
      node.add_component(wrap)
      node.enter_tree

      node.x = -6
      wrap.update(0.0)
      expect(node.x).to eq(105)
    end

    it 'prefers explicit bounds over the world system' do
      explicit = described_class.new(width: 100, height: 80, margin: 5)
      node.add_component(RGame::Engine::Components::World.new(width: 999, height: 999))
      node.add_component(explicit)
      node.enter_tree

      node.x = -6
      explicit.update(0.0)
      expect(node.x).to eq(105)
    end

    it 'refuses to attach where nothing answers for the world size' do
      node.add_component(wrap)

      expect { node.enter_tree }.to raise_error(RuntimeError, /no world bounds in scope/)
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
