# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::FeetCollider do
  # A collider's world box is derived from its node's resolved absolute origin, so
  # build it under a parent and run an update to resolve coordinates — the same
  # setup box_collider_spec uses, with the node given a sprite size because that is
  # what this collider derives its shape from.
  def feet_collider_on(node, width:, height:, layer: :default)
    parent = RGame::Engine::Node2D.new
    parent.add_node(node)
    collider = node.add_component(described_class.new(width: width, height: height, layer: layer))
    parent.update(0.0)
    collider
  end

  def sprite_node(x, y, width:, height:)
    RGame::Engine::Node2D.new(x: x, y: y, width: width, height: height)
  end

  describe '#box' do
    it 'centres the box horizontally and anchors it to the bottom of the node' do
      collider = feet_collider_on(sprite_node(100, 200, width: 16, height: 22), width: 12, height: 6)
      expect([collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h]).to eq([102, 216, 12, 6])
    end

    # The box cannot be built at construction: a node is sized by AnimatedSprite#on_attach,
    # so building it early would bake a box anchored to a 0x0 node. Deferring the build to
    # the first read is what makes the order components were added in irrelevant.
    it 'builds the box on first read rather than at construction' do
      node = RGame::Engine::Node2D.new
      collider = node.add_component(described_class.new(width: 12, height: 6))
      node.width = 32
      node.height = 40
      expect([collider.box.offset_x, collider.box.offset_y]).to eq([10, 34])
    end

    it 'raises naming the size when the node has none' do
      node = RGame::Engine::Node2D.new
      collider = feet_collider_on(node, width: 12, height: 6)
      expect { collider.box }.to raise_error(/but it is 0x0/)
    end

    # Memoised, so an actor whose sprite frame changes size mid-animation keeps one
    # shape rather than growing and shrinking a collision box under the player.
    it 'keeps the box it first reported when the node grows later' do
      node = sprite_node(0, 0, width: 16, height: 22)
      collider = feet_collider_on(node, width: 12, height: 6)
      first = collider.box
      node.width = 64
      node.height = 64
      expect(collider.box).to be(first)
    end

    it 'is replaced by an assigned box, which leaves nothing to memoise' do
      collider = feet_collider_on(sprite_node(100, 100, width: 16, height: 22), width: 12, height: 6)
      collider.box = RGame::Engine::CollisionBox.new(width: 4, height: 4, offset_x: 1, offset_y: 2)
      expect([collider.aabb_x, collider.aabb_y, collider.aabb_w, collider.aabb_h]).to eq([101, 102, 4, 4])
    end
  end

  # Being a BoxCollider is the whole point: a sibling that pulls the shape by its base
  # class finds this one, and the broadphase needs no change at all.
  it 'is found by get_component(BoxCollider)' do
    node = sprite_node(0, 0, width: 16, height: 22)
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
      hero = add_node(sprite_node(100, 200, width: 16, height: 22))
      feet = hero.add_component(described_class.new(width: 12, height: 6, layer: :hero))
      wall = add_node(RGame::Engine::Node2D.new(x: 110, y: 218))
      wall.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, layer: :wall))

      hits = []
      feet.on_hit { |other| hits << other.layer }
      scene.update(0.0)
      expect(hits).to eq([:wall])
    end

    # The broadphase reads aabb_x/y/w/h per collider per frame, and the lazy box is on
    # that path — so the memoisation has to hold after the first read, not merely
    # produce the same numbers.
    it 'allocates nothing per frame once the box is built' do
      hero = add_node(sprite_node(100, 200, width: 16, height: 22))
      hero.add_component(described_class.new(width: 12, height: 6, layer: :hero))
      scene.update(0.0)
      expect { scene.update(0.0) }.to allocate_nothing
    end

    # The box sits at the node's feet, so a box level with the node's *head* misses it —
    # which is the reason for using this collider rather than the node's whole rectangle.
    it 'reports nothing against a box level with the node the feet box clears' do
      hero = add_node(sprite_node(100, 200, width: 16, height: 22))
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
