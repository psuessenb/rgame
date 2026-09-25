# frozen_string_literal: true

# Heroes walking east along row 1 of a strip map, through checkpoints and into a gap
# at x 96..144. A hero's box's centre is 3 px above its origin, as in footing_spec,
# and a checkpoint's box stands on its origin, 16 px square.
RSpec.describe RGame::Engine::Components::Checkpoint do
  let(:root) do
    engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(['............', '......~~~...', '............'])
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
      scene.add_component(parts::CollisionWorld.new(cell_size: 64))
      scene.enter_tree
    end
  end

  def engine = RGame::Engine
  def parts = RGame::Engine::Components
  def dt = 1.0 / 60

  def hero(x, layer: :hero, respawn: true)
    node = engine::Node2D.new(x: x, y: 27.0)
    node.add_component(parts::FeetCollider.new(width: 12, height: 6, layer: layer))
    node.add_component(parts::CharacterBody.new(speed: 60))
    node.add_component(parts::Footing.new(coyote: 0, fall: 0.25))
    node.add_component(parts::Respawn.new(flash: 0)) if respawn
    root.add_node(node)
  end

  def flag(x, y = 27.0)
    node = engine::Node2D.new(x: x, y: y)
    node.add_component(parts::BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -16, layer: :flag))
    node.add_component(described_class.new(by: :hero))
    root.add_node(node)
  end

  def checkpoint(node) = node.get_component(described_class)
  def point(node) = node.get_component(parts::Respawn).then { [it.point_x, it.point_y] }
  def walk(node, direction) = node.get_component(parts::CharacterBody).set_intent(direction, 0)

  def tick
    root.update(dt)
    root.sweep_freed
  end

  def ticks(count) = count.times { tick }

  describe 'a touch' do
    it 'moves the toucher’s respawn point to its own, then says so once with the collider' do
      post = flag(56.0)
      walker = hero(24.0)
      feet = walker.get_component(parts::Collider)
      seen = []
      checkpoint(post).on_reached { |other| seen << [other.equal?(feet), point(walker)] }
      walk(walker, 1)
      ticks(30)

      expect(seen).to eq([[true, [56.0, 27.0]]])
    end

    it 'ignores a collider on any other layer' do
      post = flag(56.0)
      walker = hero(24.0, layer: :npc)
      seen = []
      checkpoint(post).on_reached { seen << it }
      walk(walker, 1)
      ticks(30)

      expect([seen, point(walker)]).to eq([[], [24.0, 27.0]])
    end

    it 'brings the hero back there after a fall' do
      flag(56.0)
      walker = hero(24.0)
      walk(walker, 1)
      ticks(75) # the centre steps off at x 96 on tick 72
      walk(walker, 0)
      ticks(30)

      expect([walker.world_x, walker.world_y]).to eq([56.0, 27.0])
    end

    it 'moves only the toucher’s point, so each hero comes back on its own' do
      flag(56.0)
      toucher = hero(24.0)
      other = hero(88.0)
      [toucher, other].each { walk(it, 1) }
      ticks(10) # the other steps off on tick 8
      walk(other, 0)
      ticks(65)
      walk(toucher, 0)
      ticks(30)

      expect([toucher.world_x, other.world_x, point(other)]).to eq([56.0, 88.0, [88.0, 27.0]])
    end

    it 'leaves the last checkpoint touched as the point, an earlier one touched again included' do
      flag(40.0)
      flag(72.0)
      walker = hero(24.0)
      walk(walker, 1)
      ticks(55)
      east = point(walker)
      walk(walker, -1)
      ticks(55)

      expect([east, point(walker)]).to eq([[72.0, 27.0], [40.0, 27.0]])
    end

    it 'raises for a node on its layer with no Respawn, naming its class and the layer' do
      flag(56.0)
      hero(56.0, respawn: false)

      expect { tick }.to raise_error(RuntimeError, /Node2D on :hero touched a Checkpoint, and has no Respawn/)
    end
  end

  describe 'attaching' do
    it 'raises over a gap, naming where it stands' do
      expect { flag(104.0) }.to raise_error(ArgumentError, /Checkpoint at \(104.0, 27.0\) is over a gap/)
    end

    it 'raises without a Collider on the node' do
      node = engine::Node2D.new(x: 56.0, y: 27.0)
      node.add_component(described_class.new(by: :hero))

      expect { root.add_node(node) }.to raise_error(RuntimeError, /Collider/)
    end

    it 'fires once per touch after leaving the tree and coming back' do
      post = flag(56.0)
      seen = []
      checkpoint(post).on_reached { seen << it }
      walker = hero(56.0)
      tick
      root.remove_node(post)
      root.add_node(post)
      walker.x = 24.0
      tick
      walker.x = 56.0
      tick

      expect(seen.length).to eq(2)
    end
  end

  it 'allocates nothing while nobody touches it' do
    flag(56.0)
    hero(24.0)
    tick

    expect { tick }.to allocate_nothing
  end
end
