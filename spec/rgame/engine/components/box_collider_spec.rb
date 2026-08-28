# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::BoxCollider do
  # A collider's world box is derived from its node's resolved absolute origin, so
  # build it under a parent and run an update to resolve coordinates. It has to be
  # `update`: that is the only phase that resolves the transform, since `control`
  # reads no coordinates and `draw` expresses position by pushing a transform instead.
  def collider_at(x, y, width:, height:, offset_x: 0, offset_y: 0)
    parent = RGame::Engine::Node2D.new
    node = parent.add_node(RGame::Engine::Node2D.new(x: x, y: y))
    collider = node.add_component(
      described_class.new(width: width, height: height, offset_x: offset_x, offset_y: offset_y)
    )
    parent.update(0.0)
    collider
  end

  def circle_at(x, y, radius)
    parent = RGame::Engine::Node2D.new
    node = parent.add_node(RGame::Engine::Node2D.new(x: x, y: y))
    collider = node.add_component(RGame::Engine::Components::CircleCollider.new(radius: radius))
    parent.update(0.0)
    collider
  end

  describe 'geometry' do
    it 'places the box at the node origin plus the offset' do
      collider = collider_at(100, 200, width: 16, height: 16, offset_x: 8, offset_y: 16)
      expect([collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h]).to eq([108, 216, 16, 16])
    end

    it 'reports the centre of the box, not the node origin' do
      collider = collider_at(100, 200, width: 20, height: 10)
      expect([collider.cx, collider.cy]).to eq([110.0, 205.0])
    end

    it 'follows a reassigned box (a pooled entity retuning its shape)' do
      collider = collider_at(100, 100, width: 8, height: 8)
      collider.box = RGame::Engine::CollisionBox.bottom_anchored(
        sprite_width: 32, sprite_height: 32, width: 16, height: 16
      )
      expect([collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h]).to eq([108, 116, 16, 16])
    end
  end

  describe '#overlap?' do
    it 'is true when two boxes intersect' do
      a = collider_at(0, 0, width: 20, height: 20)
      expect(a.overlap?(collider_at(10, 10, width: 20, height: 20))).to be(true)
    end

    it 'is false when two boxes are apart' do
      a = collider_at(0, 0, width: 20, height: 20)
      expect(a.overlap?(collider_at(50, 0, width: 20, height: 20))).to be(false)
    end

    it 'is false when the boxes overlap on one axis only' do
      a = collider_at(0, 0, width: 20, height: 20)
      expect(a.overlap?(collider_at(10, 50, width: 20, height: 20))).to be(false)
    end

    # The two shapes settle the test between themselves, so a box asked about a
    # circle and a circle asked about a box must agree.
    it 'is true against a circle whose edge reaches the box' do
      box = collider_at(0, 0, width: 20, height: 20)
      circle = circle_at(28, 10, 10)
      expect([box.overlap?(circle), circle.overlap?(box)]).to eq([true, true])
    end

    it 'is false against a circle that clears the nearest corner' do
      # The circle's centre is 10px past each corner axis: ~14.1px from the corner,
      # so a radius of 10 misses even though both bounding boxes overlap.
      box = collider_at(0, 0, width: 20, height: 20)
      circle = circle_at(30, 30, 10)
      expect([box.overlap?(circle), circle.overlap?(box)]).to eq([false, false])
    end
  end

  describe 'tree lifecycle' do
    let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
    let(:node)  { RGame::Engine::Node2D.new }

    let!(:world) { scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64)) }

    before { scene.enter_tree }

    it 'registers with the scene CollisionWorld when it enters the tree' do
      collider = node.add_component(described_class.new(width: 8, height: 8))
      allow(world).to receive(:register).and_call_original
      scene.add_node(node)
      expect(world).to have_received(:register).with(collider)
    end

    it 'unregisters when it leaves the tree' do
      collider = node.add_component(described_class.new(width: 8, height: 8))
      scene.add_node(node)
      allow(world).to receive(:unregister).and_call_original
      node.queue_free
      scene.sweep_freed
      expect(world).to have_received(:unregister).with(collider)
    end
  end

  describe '#emit_hit' do
    it 'notifies listeners connected via #on_hit with the other collider' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(width: 5, height: 5))
      other = instance_double(described_class)
      received = nil
      collider.on_hit { |o| received = o }
      collider.emit_hit(other)
      expect(received).to be(other)
    end
  end
end
