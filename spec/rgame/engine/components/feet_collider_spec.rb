# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::FeetCollider do
  # A collider's world box is derived from its node's resolved absolute origin, so
  # build it under a parent and run an update to resolve coordinates — the same
  # setup box_collider_spec uses.
  def feet_collider_on(node, width:, height:, layer: :default)
    parent = RGame::Engine::Node2D.new
    parent.add_node(node)
    collider = node.add_component(described_class.new(width: width, height: height, layer: layer))
    parent.update(0.0)
    collider
  end

  def sprite_node(x, y, width: 16, height: 22)
    RGame::Engine::Node2D.new(x: x, y: y, width: width, height: height)
  end

  describe '#box' do
    it 'centres the box across the origin with its bottom edge on it' do
      collider = feet_collider_on(sprite_node(100, 200), width: 12, height: 6)
      expect([collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h]).to eq([94, 194, 12, 6])
    end

    # The origin is where the node stands, so the box needs no size from the
    # node, and a component built before its sprite attached is already right.
    it 'is right from construction, on a node with no size and no parent' do
      collider = RGame::Engine::Node2D.new.add_component(described_class.new(width: 12, height: 6))
      expect([collider.box.offset_x, collider.box.offset_y]).to eq([-6, -6])
    end

    it 'stays where it is when the node changes size' do
      node = sprite_node(0, 0)
      collider = feet_collider_on(node, width: 12, height: 6)
      node.width = 64
      node.height = 64
      expect([collider.box.offset_x, collider.box.offset_y]).to eq([-6, -6])
    end

    it 'is replaced by an assigned box' do
      collider = feet_collider_on(sprite_node(100, 100), width: 12, height: 6)
      collider.box = RGame::Engine::CollisionBox.new(width: 4, height: 4, offset_x: 1, offset_y: 2)
      expect([collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h]).to eq([101, 102, 4, 4])
    end
  end

  # Being a BoxCollider is the whole point: a sibling that pulls the shape by its base
  # class finds this one, and the broadphase needs no change at all.
  it 'is found by get_component(BoxCollider)' do
    node = sprite_node(0, 0)
    collider = feet_collider_on(node, width: 12, height: 6)
    expect(node.get_component(RGame::Engine::Components::BoxCollider)).to be(collider)
  end

  describe 'in a CollisionWorld' do
    let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }

    before do
      scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      scene.enter_tree
    end

    def add_node(node) = scene.add_node(node)

    it 'reports a contact against a plain box that overlaps its feet' do
      hero = add_node(sprite_node(108, 222))
      feet = hero.add_component(described_class.new(width: 12, height: 6, layer: :hero))
      wall = add_node(RGame::Engine::Node2D.new(x: 110, y: 218))
      wall.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, layer: :wall))

      hits = []
      feet.on_hit { |other| hits << other.layer }
      scene.update(0.0)
      expect(hits).to eq([:wall])
    end

    # The broadphase reads aabb_x/y/w/h per collider per frame.
    it 'allocates nothing per frame' do
      hero = add_node(sprite_node(108, 222))
      hero.add_component(described_class.new(width: 12, height: 6, layer: :hero))
      scene.update(0.0)
      expect { scene.update(0.0) }.to allocate_nothing
    end

    # The box sits at the node's feet, so a box level with the node's *head* misses it —
    # which is the reason for using this collider rather than the node's whole rectangle.
    it 'reports nothing against a box level with the node the feet box clears' do
      hero = add_node(sprite_node(108, 222))
      feet = hero.add_component(described_class.new(width: 12, height: 6, layer: :hero))
      head = add_node(RGame::Engine::Node2D.new(x: 100, y: 200))
      head.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 8, layer: :wall))

      hits = []
      feet.on_hit { |other| hits << other.layer }
      scene.update(0.0)
      expect(hits).to be_empty
    end
  end
end
