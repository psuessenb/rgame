# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CircleCollider do
  # A collider's world centre is its node's resolved absolute origin, so build it
  # under a parent and run an update to resolve coordinates. It has to be `update`:
  # that is the only phase that resolves the transform, since `control` reads no
  # coordinates and `draw` expresses position by pushing a transform instead.
  def collider_at(x, y, radius)
    parent = RGame::Engine::Node2D.new
    node = parent.add_node(RGame::Engine::Node2D.new(x: x, y: y))
    collider = node.add_component(described_class.new(radius: radius))
    parent.update(0.0)
    collider
  end

  describe '#overlap?' do
    it 'is true when the circles intersect' do
      expect(collider_at(0, 0, 10).overlap?(collider_at(15, 0, 10))).to be(true)
    end

    it 'is false when the circles are apart' do
      expect(collider_at(0, 0, 10).overlap?(collider_at(50, 0, 10))).to be(false)
    end
  end

  describe 'tree lifecycle' do
    let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
    let(:node)  { RGame::Engine::Node2D.new }

    let!(:world) { scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64)) }

    before { scene.enter_tree }

    it 'registers with the scene CollisionWorld when it enters the tree' do
      collider = node.add_component(described_class.new(radius: 8))
      allow(world).to receive(:register).and_call_original
      scene.add_node(node)
      expect(world).to have_received(:register).with(collider)
    end

    it 'unregisters when it leaves the tree' do
      collider = node.add_component(described_class.new(radius: 8))
      scene.add_node(node)
      allow(world).to receive(:unregister).and_call_original
      node.queue_free
      scene.sweep_freed
      expect(world).to have_received(:unregister).with(collider)
    end
  end

  # The two edges CollisionWorld drives: the step a contact starts, and the step it
  # ends. They are separate signals rather than one with a flag, so a listener that
  # only cares about arrivals never has to ask which kind of call it is in.
  describe '#emit_hit' do
    it 'notifies listeners connected via #on_hit with the other collider' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(radius: 5))
      other = instance_double(described_class)
      received = nil
      collider.on_hit { |o| received = o }
      collider.emit_hit(other)
      expect(received).to be(other)
    end

    it 'does not notify listeners connected via #on_separated' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(radius: 5))
      received = nil
      collider.on_separated { |o| received = o }
      collider.emit_hit(instance_double(described_class))
      expect(received).to be_nil
    end
  end

  describe '#emit_separated' do
    it 'notifies listeners connected via #on_separated with the other collider' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(radius: 5))
      other = instance_double(described_class)
      received = nil
      collider.on_separated { |o| received = o }
      collider.emit_separated(other)
      expect(received).to be(other)
    end

    it 'does not notify listeners connected via #on_hit' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(radius: 5))
      received = nil
      collider.on_hit { |o| received = o }
      collider.emit_separated(instance_double(described_class))
      expect(received).to be_nil
    end
  end

  # The same shape as BoxCollider's, for a round collider: its centre is the
  # node's own origin, which is (0, 0) in the space a component draws in.
  describe 'drawing its shape' do
    let(:renderer) { FakeRenderer.new }

    def scene_with(debug)
      root = RGame::Engine::Node2D.new
      root.add_component(debug) if debug
      node = root.add_node(RGame::Engine::Node2D.new(x: 100, y: 200))
      node.add_component(described_class.new(radius: 12))
      root.enter_tree
      root
    end

    it 'draws its circle at its node\'s origin while the channel is on' do
      debug = RGame::Engine::Debug.new
      root = scene_with(debug)
      debug.show(:shapes)

      root.draw(renderer, screen_view)

      expect(renderer.calls_to(:debug_circle).map(&:args)).to eq([[0, 0, 12]])
    end

    it 'follows a radius the node retuned' do
      debug = RGame::Engine::Debug.new
      root = scene_with(debug)
      debug.show(:shapes)
      root.children.first.get_component(described_class).radius = 20

      root.draw(renderer, screen_view)

      expect(renderer.calls_to(:debug_circle).map(&:args)).to eq([[0, 0, 20]])
    end

    it 'draws nothing while the channel is off' do
      root = scene_with(RGame::Engine::Debug.new)

      root.draw(renderer, screen_view)

      expect(renderer.drawn?(:debug_circle)).to be(false)
    end

    it 'draws nothing in a scene with no debug layer above it' do
      root = scene_with(nil)

      root.draw(renderer, screen_view)

      expect(renderer.drawn?(:debug_circle)).to be(false)
    end
  end
end
