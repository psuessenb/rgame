# frozen_string_literal: true

# The builder meets the records it will meet in a game: each map here is a
# `.tmx` string, parsed and turned into a TileMap, so an object reaches `build`
# as `from_tiled` made it. The node classes live in two games' modules, as a
# game's classes do, and MapSettings reads their tags from this file.

# rubocop:disable Lint/UnusedMethodArgument -- a signature is what MapSettings reads

# A game whose scene mounts the maps below, with a class of each kind a map
# names.
module SpecMapGame
  # The scene class the builder resolves in.
  class Room < RGame::Engine::Node2D
    # A class of the scene's own, found before the game's.
    class Lamp < RGame::Engine::Node2D; end
  end

  # A chest with one keyword of each type a map can hold.
  class Chest < RGame::Engine::Node2D
    # A chest.
    #
    # @param contents [String] the item inside
    # @param count [Integer] how many of it
    # @param weight [Float] in kilograms
    # @param locked [Boolean] whether it takes a key to open
    # @param wood [Symbol] what it is made of
    # @param lid [:flat, :round] the shape of its lid
    # @param tint [Util::Color] the colour it is painted
    # @param rng [Random] where its loot rolls come from
    def initialize(contents:, count: 1, weight: 1.0, locked: false, wood: :oak, lid: :flat, tint: nil,
                   rng: nil, **)
      super(**)
      @settings = { contents:, count:, weight:, locked:, wood:, lid:, tint: }
    end

    attr_reader :settings
  end

  # A crate whose map sets one value it derives its box from, as a node that
  # lets a designer tune a component does.
  class Crate < RGame::Engine::Node2D
    # @param size [Float] the crate's side, in pixels
    def initialize(size: 16.0, **)
      super(**)
      add_component(RGame::Engine::Components::BoxCollider.new(width: size, height: size, offset_x: -size / 2,
                                                               offset_y: -size))
    end
  end

  # A raft that requires the size the object's box gives it, as a node that
  # derives its box from that size does.
  class Raft < RGame::Engine::Node2D
    def initialize(width:, height:, **)
      super
      add_component(RGame::Engine::Components::BoxCollider.new(width:, height:, offset_x: -width / 2,
                                                               offset_y: -height))
    end
  end

  # A ferry that sails the route its object draws, and needs one.
  class Ferry < RGame::Engine::Node2D
    def initialize(route:, **)
      super(**)
      @route = route
    end

    attr_reader :route
  end

  # A buoy that drifts along a route when its object draws one, and floats in
  # place otherwise.
  class Buoy < RGame::Engine::Node2D
    def initialize(route: nil, **)
      super(**)
      @route = route
    end

    attr_reader :route
  end

  # A flag that shows its object's name.
  class Flag < RGame::Engine::Node2D
    def initialize(name:, **)
      super(**)
      @name = name
    end

    attr_reader :name
  end

  # A lever whose designer may name the key it keeps its state under.
  class Lever < RGame::Engine::Node2D
    # @param fact [Symbol] the key it keeps its state under
    def initialize(fact: nil, **)
      super(**)
      @fact = fact
    end

    attr_reader :fact
  end

  # A crate sharing its name with one at the top level.
  class SpecMapCrate < RGame::Engine::Node2D; end

  # A module the game keeps a second chest in, for a path.
  module Town
    # A chest named by its path, `Town::Chest`.
    class Chest < RGame::Engine::Node2D; end
  end
end

# A second game sharing the maps, with a chest of its own.
module SpecMapOtherGame
  # The scene class the builder resolves in.
  class Room < RGame::Engine::Node2D; end

  # The other game's chest, which takes nothing from a map.
  class Chest < RGame::Engine::Node2D; end
end

# A node at the top level, which every game's names reach last.
class SpecMapBarrel < RGame::Engine::Node2D; end

# A node at the top level that a game's own class of the same name hides.
class SpecMapCrate < RGame::Engine::Node2D; end

# rubocop:enable Lint/UnusedMethodArgument

RSpec.describe RGame::Engine::MapBuilder do
  subject(:builder) { described_class.new(tilemap_id: 'map/town.tmx', scope: SpecMapGame::Room) }

  def tileset(tiles = '')
    '<tileset firstgid="1" name="props" tilewidth="16" tileheight="16" tilecount="4" columns="2">' \
      "<image source=\"props.png\" width=\"32\" height=\"32\"/>#{tiles}</tileset>"
  end

  def objects(body, tilesets: [tileset])
    tiled = RGame::Engine::Tiled::Map.parse(
      '<map orientation="orthogonal" width="4" height="4" tilewidth="16" tileheight="16">' \
      "#{tilesets.join}<objectgroup name=\"things\">#{body}</objectgroup></map>"
    )
    RGame::Engine::TileMap.from_tiled(tiled).objects
  end

  def object(attributes, body = '', **) = objects(%(<object id="7" #{attributes}>#{body}</object>), **).first

  def properties(*entries)
    rows = entries.map do |name, type, value|
      typed = type ? %( type="#{type}") : ''
      %(<property name="#{name}"#{typed} value="#{value}"/>)
    end
    "<properties>#{rows.join}</properties>"
  end

  def chest(*entries, attributes: '')
    object(%(name="chest_1" type="Chest" x="0" y="0" width="16" height="16" #{attributes}),
           properties(['contents', nil, 'key'], *entries))
  end

  describe 'which class builds' do
    def built(class_name, scope: SpecMapGame::Room)
      described_class.new(tilemap_id: 'map/town.tmx', scope:)
                     .build(object(%(type="#{class_name}" x="0" y="0" width="16" height="16")))
    end

    it "resolves a name in the scene's module" do
      expect(built('Crate')).to be_a(SpecMapGame::Crate)
    end

    it "resolves a name in the scene class itself before the scene's module" do
      expect(built('Lamp')).to be_a(SpecMapGame::Room::Lamp)
    end

    it "resolves a name the game's module and the top level both define to the game's" do
      expect(built('SpecMapCrate')).to be_an_instance_of(SpecMapGame::SpecMapCrate)
    end

    it 'resolves a name only the top level defines' do
      expect(built('SpecMapBarrel')).to be_a(SpecMapBarrel)
    end

    it 'resolves a path from the scene outward' do
      expect(built('Town::Chest')).to be_a(SpecMapGame::Town::Chest)
    end

    it "resolves one map's name in each game that mounts it" do
      expect(built('Chest', scope: SpecMapOtherGame::Room)).to be_a(SpecMapOtherGame::Chest)
    end

    it 'resolves in an anonymous scene class through what it inherits and the top level' do
      expect(built('SpecMapBarrel', scope: Class.new(RGame::Engine::Node2D))).to be_a(SpecMapBarrel)
    end

    it 'builds nothing for a class starting with a lower-case letter, or none' do
      expect(%w[entrance gap].map { built(it) } << built('')).to eq([nil, nil, nil])
    end

    it 'refuses a name no constant has, naming the map, the object and the class' do
      expect { built('Chset') }.to raise_error(
        NameError, %r{object 7 of class 'Chset' in map/town.tmx names no constant in SpecMapGame::Room.*lower-case}
      )
    end

    it 'refuses a name that cannot be a constant' do
      expect { built('Chest Lid') }.to raise_error(NameError, %r{class 'Chest Lid' in map/town.tmx names no constant})
    end

    it 'refuses a constant that is not a Node2D class' do
      expect { built('Array') }
        .to raise_error(TypeError, %r{class 'Array' in map/town.tmx names Array, which is not a Node2D class})
    end

    it 'names the object in a refusal when the designer named it' do
      named = object(%(name="chest_1" type="Chset" x="0" y="0"))

      expect { builder.build(named) }.to raise_error(NameError, /object 7 'chest_1' of class 'Chset'/)
    end
  end

  describe 'the properties' do
    it 'passes each as the keyword it sets, cast as its tag says' do
      record = chest(['count', 'int', 3], ['weight', 'int', 2], ['locked', 'bool', true], ['wood', nil, 'pine'],
                     ['lid', nil, 'round'], ['tint', 'color', '#ff102030'])

      expect(builder.build(record).settings)
        .to eq(contents: 'key', count: 3, weight: 2.0, locked: true, wood: :pine, lid: :round,
               tint: RGame::Util::Color.new(16, 32, 48, 255))
    end

    it 'leaves a keyword no property sets at its default' do
      expect(builder.build(chest).settings).to include(count: 1, locked: false, wood: :oak)
    end

    it "passes a tile object's tile's properties as its own" do
      tiles = tileset(%(<tile id="0" type="Chest">#{properties(['contents', nil, 'gem'])}</tile>))
      placed = object('gid="1" x="0" y="16" width="16" height="16"', tilesets: [tiles])

      expect(builder.build(placed).settings[:contents]).to eq('gem')
    end

    it 'refuses a property no keyword takes, listing what a map may set' do
      expect { builder.build(chest(['lockd', 'bool', true])) }.to raise_error(
        ArgumentError, /sets 'lockd', which SpecMapGame::Chest does not let a map set \(settable: contents, count/
      )
    end

    it 'refuses a property for a keyword whose tag gives a type Tiled cannot hold' do
      expect { builder.build(chest(['rng', 'int', 4])) }.to raise_error(ArgumentError, /sets 'rng', which/)
    end

    it 'refuses a property of the wrong type, saying what to set in Tiled' do
      expect { builder.build(chest(['locked', nil, 'yes'])) }
        .to raise_error(TypeError, /sets 'locked' to "yes", and SpecMapGame::Chest takes a bool property there/)
    end

    it 'refuses a string outside the Symbols a list names' do
      expect { builder.build(chest(['lid', nil, 'domed'])) }
        .to raise_error(TypeError, /takes a string property holding flat, round there/)
    end

    it 'refuses a class property like any other value' do
      member = '<properties><property name="width" type="float" value="20"/></properties>'
      collider = %(<property name="contents" type="class" propertytype="Item">#{member}</property>)
      node = object('type="Chest" x="0" y="0"', "<properties>#{collider}</properties>")

      expect { builder.build(node) }.to raise_error(TypeError, /sets 'contents' to a value of the class 'Item'/)
    end

    it 'counts a required keyword the object\'s box sets as set' do
      raft = builder.build(object('type="Raft" x="0" y="0" width="48" height="16"'))

      expect([raft.width, raft.height]).to eq([48.0, 16.0])
    end

    it 'refuses an object that leaves out a required keyword' do
      bare = object('type="Chest" x="0" y="0"')

      expect { builder.build(bare) }
        .to raise_error(ArgumentError, /sets no 'contents', which SpecMapGame::Chest#initialize requires/)
    end
  end

  describe 'where the node stands' do
    def placed(attributes, body = '')
      node = builder.build(object(%(type="SpecMapBarrel" #{attributes}), body))
      [node.x, node.y, node.angle, node.width, node.height].map { it.round(9) }
    end

    it "stands at the bottom centre of a rectangle's box" do
      expect(placed('x="10" y="20" width="30" height="40"')).to eq([25.0, 60.0, 0.0, 30.0, 40.0])
    end

    it 'turns the bottom centre with the object, about its corner' do
      # Turned 90° clockwise about (100, 200), the box hangs to the left of
      # that corner, and its bottom edge is its left edge now.
      expect(placed('x="100" y="200" width="30" height="40" rotation="90"'))
        .to eq([60.0, 215.0, (Math::PI / 2).round(9), 30.0, 40.0])
    end

    it 'stands on the point of a point object' do
      expect(placed('x="10" y="20"', '<point/>').first(2)).to eq([10.0, 20.0])
    end

    it "stands on a polygon's own corner, which its points are relative to" do
      expect(placed('x="10" y="20"', '<polygon points="0,0 16,0 16,8"/>').first(2)).to eq([10.0, 20.0])
    end

    it 'stands where Tiled places a tile object by its bottom edge' do
      # Tiled's (100, 200) is the tile's bottom-left corner.
      tiles = tileset('<tile id="0" type="SpecMapBarrel"/>')
      node = builder.build(object('gid="1" x="100" y="200" width="16" height="16"', tilesets: [tiles]))

      expect([node.x, node.y]).to eq([108.0, 200.0])
    end
  end

  describe 'the object id' do
    it "gives the node its object's id" do
      expect(builder.build(chest).map_object_id).to eq(7)
    end

    it 'passes a fact property on as the keyword it sets, like any other' do
      lever = object('type="Lever" x="0" y="0"', properties(%w[fact string town_lever]))

      expect(builder.build(lever).fact).to eq(:town_lever)
    end

    it 'refuses a fact property the class does not tag, as any other' do
      expect { builder.build(chest(['fact', nil, 'town_chest'])) }
        .to raise_error(ArgumentError, /sets 'fact', which SpecMapGame::Chest does not let a map set/)
    end
  end

  describe 'the route and the name' do
    def ferry(shape, attributes = '')
      builder.build(object(%(type="Ferry" x="10" y="20" #{attributes}), shape))
    end

    def waypoints(route) = Array.new(route.count) { [route.x_at(it).round(9), route.y_at(it).round(9)] }

    it "gives a polyline's route, open, to a class that names route:" do
      route = ferry('<polyline points="0,0 16,0 16,8"/>').route

      expect([route.closed?, waypoints(route)]).to eq([false, [[10.0, 20.0], [26.0, 20.0], [26.0, 28.0]]])
    end

    it "gives a polygon's route, closed" do
      route = ferry('<polygon points="0,0 16,0 16,8"/>').route

      expect([route.closed?, waypoints(route).last]).to eq([true, [10.0, 20.0]])
    end

    it 'turns the route with its object' do
      # Turned 90° clockwise about (10, 20), a leg running east runs south.
      route = ferry('<polyline points="0,0 16,0"/>', 'rotation="90"').route

      expect(waypoints(route)).to eq([[10.0, 20.0], [10.0, 36.0]])
    end

    it 'refuses a shape with no route for a class that requires route:, naming the object and its shape' do
      expect { ferry('', 'width="16" height="16"') }.to raise_error(
        ArgumentError, %r{object 7 of class 'Ferry' in map/town.tmx is a rectangle, and SpecMapGame::Ferry#initialize}
      )
    end

    it 'gives no route to a class whose route: is optional, for a shape with none' do
      expect(builder.build(object('type="Buoy" x="0" y="0" width="16" height="16"')).route).to be_nil
    end

    it "gives the object's name to a class that names name:" do
      expect(builder.build(object('name="north" type="Flag" x="0" y="0"', '<point/>')).name).to eq('north')
    end

    it 'gives an empty name for an object the designer left unnamed' do
      expect(builder.build(object('type="Flag" x="0" y="0"', '<point/>')).name).to eq('')
    end

    it 'gives neither to a class that names neither, though it forwards the rest to Node2D' do
      named = object('name="north" type="SpecMapBarrel" x="0" y="0"', '<polyline points="0,0 16,0"/>')

      expect(builder.build(named)).to be_a(SpecMapBarrel)
    end
  end

  describe 'a tile object' do
    let(:map_tile) { RGame::Engine::Components::MapTile }

    # Tile 1 of the tileset is a tree; gid 0x80000001 places it mirrored.
    def placed(attributes, gid: 1)
      tiles = tileset('<tile id="0" type="tree"/>')
      builder.build(object(%(gid="#{gid}" x="100" y="200" width="16" height="32" #{attributes}), tilesets: [tiles]))
    end

    it 'gives the node its class builds a MapTile of its tile and orientation' do
      tile = placed('type="SpecMapBarrel"', gid: 0x80000001).get_component(map_tile)

      expect([tile.tile, tile.orientation.mirrored?, tile.orientation.quarter_turns]).to eq([1, true, 0])
    end

    it "adds the MapTile after the class's own components" do
      node = placed('type="Crate"')

      expect(node.components.map(&:class)).to eq([RGame::Engine::Components::BoxCollider, map_tile])
    end

    it 'builds a plain Node2D carrying its tile when its class is data' do
      node = placed('')

      expect([node.class, node.get_component(map_tile).tile]).to eq([RGame::Engine::Node2D, 1])
    end

    it 'places the plain node as any node, and gives it the object id' do
      node = placed('')

      expect([node.x, node.y, node.width, node.height, node.map_object_id]).to eq([108.0, 200.0, 16.0, 32.0, 7])
    end

    it 'still builds nothing for a shape object whose class is data' do
      expect(builder.build(object('type="tree" x="0" y="0" width="16" height="16"'))).to be_nil
    end
  end

  describe 'an object hidden in Tiled' do
    it 'builds at opacity 0, so it updates and collides and draws nothing' do
      node = builder.build(object('type="Crate" x="0" y="0" width="16" height="16" visible="0"'))

      expect([node.opacity, node.get_component(RGame::Engine::Components::BoxCollider)]).to match([0, be])
    end

    it 'builds a data tile object at opacity 0 too' do
      node = builder.build(object('gid="1" x="0" y="16" width="16" height="16" visible="0"'))

      expect([node.class, node.opacity]).to eq([RGame::Engine::Node2D, 0])
    end

    it 'leaves a shown object at full opacity' do
      expect(builder.build(object('type="Crate" x="0" y="0" width="16" height="16"')).opacity).to eq(1)
    end
  end

  # The caller that uses both: a crate the map sizes, whose collider the crate
  # derives from that size. Its box has to land where the designer drew it.
  describe 'a node that passes a map setting on to its collider' do
    let(:root) { RGame::Engine::Node2D.new }

    def crate(attributes)
      root.add_node(builder.build(object(%(type="Crate" #{attributes}), properties(%w[size float 24]))))
    end

    def box_of(node) = node.get_component(RGame::Engine::Components::BoxCollider)

    it "puts an unturned object's collider on the object's box" do
      node = crate('x="100" y="200" width="24" height="24"')
      box = box_of(node)

      expect([box.aabb_x, box.aabb_y, box.aabb_w, box.aabb_h]).to eq([100.0, 200.0, 24.0, 24.0])
    end

    it "puts the collider's corners on a turned object's corners, in the node's own frame" do
      # A BoxCollider stays axis-aligned in the world, so only the node's frame
      # turns with the object. Each corner of the box, carried through that
      # frame, lands on a corner of the box Tiled draws.
      node = crate('x="100" y="200" width="24" height="24" rotation="30"')
      box = box_of(node).box
      corners = [[box.offset_x, box.offset_y], [box.offset_x + box.width, box.offset_y],
                 [box.offset_x + box.width, box.offset_y + box.height], [box.offset_x, box.offset_y + box.height]]
      landed = corners.map do |cx, cy|
        marker = node.add_node(RGame::Engine::Node2D.new(x: cx, y: cy))
        [marker.world_x.round(9), marker.world_y.round(9)]
      end

      radians = Math::PI / 6
      drawn = [[0, 0], [24, 0], [24, 24], [0, 24]].map do |dx, dy|
        [(100 + (dx * Math.cos(radians)) - (dy * Math.sin(radians))).round(9),
         (200 + (dx * Math.sin(radians)) + (dy * Math.cos(radians))).round(9)]
      end
      expect(landed).to eq(drawn)
    end
  end
end
