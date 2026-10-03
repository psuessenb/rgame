# frozen_string_literal: true

# Heroes walking east along row 1 of a strip map, through checkpoints and into a gap
# at x 96..144. A hero's box's centre is 3 px above its origin, as in footing_spec,
# and a checkpoint's box stands on its origin, 16 px square. The map names one
# place, a point object called 'well' at (24, 27), whose id is 1.
RSpec.describe RGame::Engine::Components::Checkpoint do
  let(:root) do
    engine::Node2D.new.tap do |scene|
      scene.scene = scene
      map = WalledTileMap.build(['............', '......~~~...', '............'], objects: [['well', 24, 27]])
      scene.add_component(parts::TileWorld.new(map: map, tilemap_id: :map))
      scene.add_component(parts::CollisionWorld.new(cell_size: 64))
      scene.enter_tree
    end
  end

  def engine = RGame::Engine
  def parts = RGame::Engine::Components
  def dt = 1.0 / 60

  def hero(x, layer: :hero, respawn: true, into: root)
    node = engine::Node2D.new(x: x, y: 27.0)
    node.add_component(parts::FeetCollider.new(width: 12, height: 6, layer: layer))
    node.add_component(parts::CharacterBody.new(speed: 60))
    node.add_component(parts::Footing.new(coyote: 0))
    node.add_component(parts::Fall.new(duration: 0.25))
    node.add_component(parts::Respawn.new) if respawn
    into.add_node(node)
  end

  def flag(x, y = 27.0, location: nil, map_object_id: nil, into: root)
    node = engine::Node2D.new(x: x, y: y, map_object_id:)
    node.add_component(parts::BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -16, layer: :flag))
    node.add_component(described_class.new(by: :hero, location:))
    into.add_node(node)
  end

  def checkpoint(node) = node.get_component(described_class)
  def point(node) = node.get_component(parts::Respawn).then { [it.point.x, it.point.y] }
  def point_of(node) = node.get_component(parts::Respawn).point
  def walk(node, direction) = node.get_component(parts::CharacterBody).set_intent(direction, 0)

  def tick
    root.update(dt)
    root.sweep_freed
  end

  def ticks(count) = count.times { tick }

  describe '.new' do
    it 'refuses a location that is not a String' do
      expect { described_class.new(by: :hero, location: :bridge) }.to raise_error(TypeError, /not :bridge/)
    end

    it "refuses '', the name a map gives an object it leaves unnamed" do
      expect { described_class.new(by: :hero, location: '') }.to raise_error(ArgumentError, /unnamed/)
    end
  end

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

  describe 'its location' do
    let(:world) { root.get_component(parts::TileWorld) }

    it 'is a place the TileWorld names while it is attached, where its node stands' do
      post = flag(56.0, location: 'bridge')
      added = world.location('bridge')
      root.remove_node(post)

      expect(added).to eq(parts::TileWorld::Location.new(x: 56.0, y: 27.0))
      expect { world.location('bridge') }.to raise_error(KeyError, /no location named 'bridge'/)
    end

    it 'keeps the place of the first to add a name, when a second refused for it leaves the tree' do
      flag(56.0, location: 'bridge')
      expect { flag(72.0, location: 'bridge') }.to raise_error(ArgumentError, /'bridge' is already a location/)
      root.remove_node(root.children.last)

      expect(world.location('bridge')).to eq(parts::TileWorld::Location.new(x: 56.0, y: 27.0))
    end

    it 'raises at the attach for a name the map gives another object' do
      expect { flag(56.0, location: 'well') }.to raise_error(ArgumentError, /'well' names object 1/)
    end

    it "raises nothing for a node built from the map's object of that name, which the map answers for" do
      expect { flag(24.0, location: 'well', map_object_id: 1) }.not_to raise_error
      expect(world.location('well')).to eq(parts::TileWorld::Location.new(x: 24.0, y: 27.0))
    end

    it 'leaves a touch outside rooms handing a Point at its node' do
      flag(56.0, location: 'bridge')
      walker = hero(56.0)
      tick

      expect(point_of(walker)).to eq(parts::Respawn::Point.new(x: 56.0, y: 27.0))
    end
  end

  # A MappedRoom named :yard, all ground, its own scene under a root of its own.
  describe 'in a room' do
    let(:room) do
      MappedRoom.new(['....', '....'], objects: []).tap do |made|
        made.name = :yard
        made.scene = made
        engine::Node2D.new.add_node(made)
        made.root.enter_tree
      end
    end

    it 'raises at the attach with no location, naming the room' do
      expect { flag(24.0, into: room) }
        .to raise_error(ArgumentError, /Node2D's Checkpoint stands in room :yard and has no location/)
    end

    it 'adds nothing in a room with no TileWorld, whose _arrive knows the location itself' do
      bare = RGame::Engine::Scene::Room.new.tap do |made|
        made.name = :cellar
        made.scene = made
        made.add_component(parts::CollisionWorld.new(cell_size: 64))
        engine::Node2D.new.add_node(made)
        made.root.enter_tree
      end
      flag(24.0, location: 'bridge', into: bare)
      walker = engine::Node2D.new(x: 24.0, y: 27.0)
      walker.add_component(parts::FeetCollider.new(width: 12, height: 6, layer: :hero))
      walker.add_component(parts::Respawn.new)
      bare.add_node(walker)
      bare.root.update(dt)

      expect(point_of(walker)).to eq(parts::Respawn::RoomPoint.new(room: :cellar, location: 'bridge'))
    end

    it 'hands the toucher a RoomPoint at its room and its location' do
      flag(24.0, location: 'bridge', into: room)
      walker = hero(24.0, into: room)
      room.root.update(dt)

      expect(point_of(walker)).to eq(parts::Respawn::RoomPoint.new(room: :yard, location: 'bridge'))
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
