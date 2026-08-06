# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::CircleCollider do
  # A collider's world centre is its node's resolved absolute origin, so build it
  # under a parent and run a phase to resolve coordinates.
  def collider_at(x, y, radius)
    parent = RGame::Engine::Node2D.new
    node = parent.add_node(RGame::Engine::Node2D.new(x: x, y: y))
    collider = node.add_component(described_class.new(radius: radius))
    parent.control(RGame::Engine::Actions.new) # resolve abs_x/abs_y
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

  describe '#emit_hit' do
    it 'notifies listeners connected via #on_hit with the other collider' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(radius: 5))
      other = instance_double(described_class)
      received = nil
      collider.on_hit { |o| received = o }
      collider.emit_hit(other)
      expect(received).to be(other)
    end
  end
end
