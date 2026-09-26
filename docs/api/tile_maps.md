# Tile maps

**`RGame::Engine::TileMap` holds a map made in [Tiled](https://www.mapeditor.org/)
as plain data**: its size, its layers, the tile in every cell, what each tile is,
and the objects placed on it. It loads no image and names no renderer, so it runs
headless and in specs.

A game rarely builds one itself. The pieces that use it are:

| | Uses the map to |
|---|---|
| [`TileWorld`](components.md#tileworld) | answer solidity and world-size questions for actors |
| [`TileMapLayer`](components.md#tileworld) | draw one layer per node, and [build a node from each object](#building-nodes-from-objects) |
| [`TileMapRenderer`](assets.md#tile-maps) | bake and draw the tiles |
| `RGame::Game`'s `:tilemap` asset loader | read a `.tmx`, build the map and slice its tileset images |

Read on when a scene queries the map itself, or when you author maps for rgame.

## Loading a map

In a game, the asset loader reads the map, and the scene reaches it through the
renderer the loader returns:

```ruby
map = app.assets.tilemap('map/island.tmx').map
```

Headless, as in a spec, read the file and build the map in two calls:

```ruby
require 'rgame'

parsed = RGame::Engine::Tiled::Map.load('examples/assets/town_with_gate.tmx')
map = RGame::Engine::TileMap.from_tiled(parsed)

map.width         # => 60 — in tiles
map.pixel_width   # => 960
map.layer_count   # => 3 — ground, obstacles and the doors object layer
map.tile_count    # => 132
map.object_named('start').x # => 376.0 — a point the doors layer names
```

**`Tiled::Map.load(path)` reads the file as Tiled wrote it**, with every tileset
and template it names. **`TileMap.from_tiled` turns that into the map a game
reads**, and is the only way one is built. Everything else under
`RGame::Engine::Tiled` is internal to that pair.

**Every path resolves against the file that names it.** A `.tsx` resolves next to
the `.tmx`, an image next to the `.tsx`, and a template next to the `.tmx`. Tiled
writes paths this way, so you can move a map and its tilesets together.

`Tiled::Map.parse(tmx_string, source_path: nil)` reads a `.tmx` from a String. A
map whose tilesets are embedded needs no file at all, which is how a spec builds a
small one:

```ruby
require 'rgame'

parsed = RGame::Engine::Tiled::Map.parse(<<~TMX)
  <map orientation="orthogonal" width="2" height="1" tilewidth="16" tileheight="16">
    <tileset firstgid="1" name="walls" tilewidth="16" tileheight="16" tilecount="2" columns="2">
      <image source="walls.png" width="32" height="16"/>
      <tile id="1"><objectgroup><object x="0" y="0" width="16" height="16"/></objectgroup></tile>
    </tileset>
    <layer name="ground" width="2" height="1"><data encoding="csv">1,2</data></layer>
  </map>
TMX
map = RGame::Engine::TileMap.from_tiled(parsed)

map.tile(0, 1, 0)          # => 2
map.solid_at?(20.0, 3.0)   # => true — tile 2 has a collision shape
map.solid_at?(3.0, 3.0)    # => false
```

A map parsed from a String that names an external `.tsx` or `.tx` needs
`source_path:`, the file those paths resolve against. Without it, `parse` raises.

### What rgame reads from Tiled

A map outside these limits raises `Tiled::FormatError`, naming the file and the
element:

| | Read |
|---|---|
| Orientation | orthogonal only; isometric, staggered and hexagonal raise |
| Tilesets | any number, in `.tsx` files or embedded in the map |
| Layer data | XML, CSV, and base64 plain or compressed with zlib or gzip; zstd raises |
| Layers | tile, image, object and group layers |
| Map size | fixed or infinite |
| Custom properties | on the map, layers, tiles and objects, with Tiled's types |
| Object templates | an object placed from a `.tx` gets the template's values, and its own win |
| Object shapes | rectangle, ellipse, capsule, point, polygon, polyline, text and tile; any other raises |
| Tile objects | placed by their tileset's object alignment, and given their tile's class and properties |
| Tileset drawing | `tilerendersize="tile"` and `fillmode="stretch"`, Tiled's defaults; `grid` and `preserve-aspect-fit` raise, since rgame draws neither |

### How the map is drawn

`TileMapRenderer` draws what Tiled shows for the parts below:

| | Drawn |
|---|---|
| Turned tiles | in all eight orientations, about the tile's centre |
| Hidden layers | not at all |
| Layer opacity | the layer and its animated tiles fade by the layer's opacity, groups included |
| Tile sheets | cut with their margin and spacing |
| Collections of images | one image per tile, each at its own size |
| Drawing offset | every tile of the tileset moves by it, with `y` down |
| Image layers | the image at the layer's offset, repeated along x, y or both as far as the view reaches |

**A tile stands on its cell's bottom-left corner.** A tile taller than the map's
cells, such as a tree two cells high, reaches up into the cell above. A turned
tile that is not square keeps that corner too. A tileset's drawing offset then
moves the tile, and the tile turns about its moved centre.

Per-layer offset, parallax and tint are not read.

## `RGame::Engine::TileMap`

### Geometry

| Reader | |
|---|---|
| `width`, `height` | the map's size in tiles |
| `tile_width`, `tile_height` | one tile's size in pixels |
| `pixel_width`, `pixel_height` | the map's size in pixels |
| `properties` | the map's own custom properties |
| `source` | a `TileMap::Source`: the file the map was read from, or `nil`, and the `parser_version` that read it |

**An infinite map is one grid too.** Its size is the box around every chunk that
holds a tile, across all layers, and cell `(0, 0)` is that box's top-left. Objects
and image layers move with it, so an infinite map and a fixed one with the same
picture answer every question the same way.

### Cells

```ruby
map.tile(0, 12, 7)          # the tile in layer 0 at column 12, row 7
map.in_bounds?(60, 0)       # => false — columns run 0..59
map.tile(0, -1, 0)          # => 0 — outside the map, every layer is empty
map.orientation(0, 12, 7)   # how that tile is turned
```

**A cell holds a tile id.** Ids start at 1 and run to `tile_count`, across every
tileset the map uses, in the order Tiled numbers them. `0` means an empty cell.
`tile` answers `0` outside the map, and in a layer that holds no tiles, so a
caller never checks first. Layer `0` is the bottom layer.

`map.tile_table[id]` says where a tile came from: a `TileMap::TileSource` whose
`tileset` is the tileset's position in the map and whose `local_id` is the tile's
index in that tileset. Entry `0` is `nil`. The asset loader slices the tileset
images against it.

**`orientation` answers a `TileMap::Orientation`**, one of eight frozen values in
`Orientation::ALL`:

| | |
|---|---|
| `quarter_turns` | 0 to 3, clockwise |
| `mirrored?` | whether the tile is then flipped across its vertical axis |
| `identity?` | the tile is drawn as its sheet shows it |

A cell with no turned tile answers `Orientation::IDENTITY`. In Tiled, a tile is
turned with the rotate and flip buttons of the tile stamp.

### What a tile is

```ruby
map.solid?(tile)             # whether it blocks movement
map.gap?(tile)               # whether its cell is a gap: its class is `gap`
map.tile_class(tile)         # the class set in Tiled, or nil
map.tile_properties(tile)    # its custom properties
map.animated_tiles           # the tiles that animate
map.frame_tile(tile, 0.25)   # the tile showing 0.25 s into its animation
map.tile_offset(tile)        # => [0, -4] — where it draws, relative to its cell
```

**A tile is solid when it has a collision shape in Tiled.** Open the tileset in
Tiled's collision editor and draw any shape on the tile. The shape itself is
ignored: rgame treats a solid tile as a solid square, so the map carries its
collision and changing which tiles block needs no code.

**`frame_tile(tile, elapsed)` takes seconds**, like `dt`.
The animation loops, and a tile that does not animate answers itself. The time is
an argument, not a clock read, so pausing is "stop accumulating". Animate a tile in
Tiled's tile animation editor.

**`tile_offset(tile)` is its tileset's Drawing Offset** from Tiled's tileset
properties, as a frozen `[x, y]` in pixels with `y` down. A tile whose tileset
has none answers `[0, 0]`.

### Cells and pixels

```ruby
map.cell_x(12)       # => 192 — column 12's left edge, in world pixels, on 16 px tiles
map.cell_y(7)        # => 112 — row 7's top edge
map.col_at(200.5)    # => 12 — the column holding that x
map.row_at(-0.5)     # => -1 — floored, so left of or above the map is negative
```

**These four are the only conversions between cells and pixels.** The renderer,
`solid_at?` and [`TileWorld`](components.md#tileworld) all call them. They answer for
any cell, inside the map or not: `cell_x(map.width)` is the map's right edge. A point
on a cell's left or top edge is in that cell.

### Solidity

```ruby
map.solid_tile?(12, 7)          # any layer solid at that cell?
map.solid_at?(200.5, 116.0)     # the same, from a world position in pixels
```

**A cell is solid when any layer holds a solid tile there**, a hidden layer
included: hiding a layer in Tiled changes how it draws, not what blocks.
`solid_at?(world_x, world_y)` asks `solid_tile?` about the cell holding that
point. **Outside the map is not solid.** Keep actors inside with
`blocked_by: [:bounds]` on their mover.

Actors do not call these per step. [`TileWorld`](components.md#tileworld) reads
`solid_tile?` once per cell into a
[`Util::SolidGrid`](values.md#rgameutilsolidgrid), and collision and pathfinding
read that grid.

### Gaps

```ruby
map.gap_tile?(12, 7)            # any layer holds a gap tile at that cell?
```

**A gap is a cell with no floor**: a chasm or a pit, which a walker falls into
and a hop crosses. Give a tile the class `gap` in Tiled's tileset editor, and
every cell holding it is a gap, on any layer, a hidden one included. The
constant `TileMap::GAP` is that class. A cell off the map is not a gap, as it is
not solid. Build a bridge by painting a floor tile where the gap tile was, or
move one over the gap with a [`Platform`](components.md#platform).

**Five components play on gaps, and each asks the scene's
[`TileWorld`](components.md#tileworld) where the floor is.** The floor is every
cell without a gap tile, plus the box of every `Platform` over a gap.
`TileWorld#floor_at?` answers for a world point, and the rules follow from it:

- **A node stands at the centre of its [`BoxCollider`](components.md#boxcollider)
  box.** For a character, that box is its
  [`FeetCollider`](components.md#feetcollider).
- **A [`Footing`](components.md#footing) drops a node off the floor**, once it
  has been off for more than `coyote` seconds. A node that lands on a gap falls on
  the tick it lands, and a node in the air never falls. The fall shrinks the node
  over `fall` seconds, then brings it back or frees it.
- **A node rides the `Platform` under its centre**, where the cell is a gap. The
  platform's mover carries it through the rider's own mover, so a wall still stops
  it.
- **`blocked_by: [:gaps]` keeps the centre of a [mover](components.md#mover)'s
  box on the floor**, platforms included. A step that starts off the floor is free.
- **A [`Respawn`](components.md#respawn) point and a
  [`Checkpoint`](components.md#checkpoint) stand on ground.** Each raises over a
  gap, even one a platform covers. A checkpoint moves only the point of the node
  that touches it.

Add order changes a result by one tick at most. `Footing` finds the node's `Hop`
and mover on its first update, and a mover finds its `Platform` the same way, so
those may go on in any order.

### Layers

```ruby
map.layer_count                    # every layer, of every kind
map.layer(1).name                  # => "obstacles" — in town.tmx
map.layer_index('obstacles')       # => 1
map.layer_index('Background/sky')  # a layer inside the group Background
```

**Tiled's groups flatten.** A group takes no index of its own; its layers follow
one another in Tiled's order, depth first. `layer(index)` answers a
`TileMap::Layer`, and raises `IndexError` for an index the map lacks:

| | |
|---|---|
| `index` | its place in the flat list |
| `name`, `path` | its name, and the names of the groups around it and its own |
| `kind` | `:tile`, `:image` or `:object` |
| `class_name` | the class set in Tiled |
| `visible?` | false when the layer or any group around it is hidden |
| `opacity` | the layer's opacity times every group's around it |
| `above?` | whether it covers the actors |
| `properties` | its custom properties |

**Find a layer by name rather than by index.** `layer_index` takes a name or a
`'Group/layer'` path, and a group added above a layer in Tiled changes neither.
It raises `KeyError` listing the map's layers when nothing matches, and when a
bare name matches layers in two groups.

**Mark a layer `above` in Tiled** to draw it over the actors, for tree canopies or
roofs: add a custom **bool** property named `above` and tick it. A layer without
the property draws below, and an `above` property of any other type raises.
`TileWorld#first_above_layer` returns the first flagged layer. On a map that
marks no layer `actors`, [`TileMapLayer.mount`](components.md#tileworld) puts
the actors' place below it. Tiles in a tile layer do not sort with the actors, so
a tree whose canopy a character walks under is two layers: a trunk below the
actors and a canopy in an `above` layer. A tree placed as a tile object in the
actors' layer sorts with them instead.

**An object layer is a `TileMap::ObjectLayer`**, a `Layer` that adds two
answers. `y_sort?` is true for Tiled's *Top Down* draw order, the default, and
false for *Manual*, which keeps the order Tiled lists the objects in. `actors?`
is true for the layer marked for the actors: an object layer with a custom
**bool** property named `actors`, ticked. `map.actors_layer` is that layer's
index, or `nil` when no layer is marked, and `TileWorld#actors_layer` answers the
same. A map may mark one object layer. A mark on a tile layer, an image layer or
a group, marks on two layers, a mark on a hidden layer, and an `actors` property
that is not a bool each raise `Tiled::FormatError`, naming the layers. No actor
spawned into a hidden layer would draw.

`map.image_layers` lists the image layers, each a `TileMap::ImageLayer`: a
`Layer` that adds `image` (the image's path, or `nil`), `offset_x` and `offset_y`
in the map's pixels, and `repeat_x?` and `repeat_y?`. The asset loader loads each
layer's image, and the layer draws in its place among the others. Set the image
and the repeat in the layer's properties in Tiled.

### Objects

```ruby
map.objects                 # => every object of every object layer, each a MapObject
map.object_named('gate_in') # => the one object named gate_in
```

**`TileMap#object_named` finds an object a designer named,** such as a spawn point
or the entrance a door leads to. It raises `KeyError`, listing the map's object
names, for a name no object has. It raises `ArgumentError`, naming the objects'
ids, for a name two objects share, since either could be meant. An object left
unnamed in Tiled has the name `''`.

**A `RGame::Engine::MapObject` is in the game's coordinates.** `x` and `y` are its
top-left corner in pixels, for every shape, and `rotation` turns it clockwise, in
degrees, about that corner. Tiled places a tile object by the point its tileset's
**Object Alignment** names, and by its bottom-left corner when the tileset leaves
that unset. `from_tiled` moves it, so a tile object and a rectangle over the same
cells report the same corner.

**A tile object inherits from its tile,** as Tiled shows it. With no class of
its own, it has its tile's. Its properties hold its tile's, and its own win
over them by name.

| | |
|---|---|
| `id`, `name`, `class_name` | as set in Tiled; a tile object with no class has its tile's |
| `layer` | the index of the layer it sits in |
| `x`, `y`, `width`, `height`, `rotation` | its box, as above |
| `shape` | `:rectangle`, `:ellipse`, `:capsule`, `:point`, `:polygon`, `:polyline` or `:text` |
| `points` | a polygon's or polyline's corners, in the same coordinates, before `rotation` |
| `tile`, `orientation` | a tile object's tile id and how it is turned; `nil` and the identity for a shape. [`Components::MapTile`](components.md#maptile) draws that tile |
| `visible?` | false when the designer hid it |
| `properties` | its custom properties, over its tile's for a tile object |

### Building nodes from objects

**[`TileMapLayer.mount`](components.md#tileworld) builds a node for each object
whose class starts with a capital letter.** The class is the Class field Tiled
shows in an object's properties, and it names a `Node2D` subclass of the game's.
The scene that mounts the map writes no line for its objects:

```ruby
module MyGame
  Engine = RGame::Engine
  Components = Engine::Components

  class Chest < Engine::Node2D
    # A chest the hero opens once.
    #
    # @param contents [String] the item inside
    # @param locked [Boolean] whether it takes a key to open
    def initialize(contents:, locked: false, **)
      super(**)
      @contents = contents
      @locked = locked
      @facts = add_component(Components::Facts.new(state: 'closed'))
    end
  end

  class Town < Engine::Node2D
    def _enter_tree
      map = root.context.assets.tilemap('map/town.tmx').map
      add_component(Components::TileWorld.new(map:, tilemap_id: 'map/town.tmx'))
      @places = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))
    end
  end
end
```

An object of the class `Chest` with the property `contents: key` builds a
`MyGame::Chest`, standing on the object, under its layer's node.

- **The name resolves outward from the scene's class**, the class of the node
  the scene's `TileWorld` is attached to: `MyGame::Town::Chest`, then
  `MyGame::Chest`, then `::Chest`. A path such as `Town::Chest` resolves the
  same way. A map names no module, so one map serves two games that each define a
  `Chest`. A name that resolves to no constant raises `NameError`, and a constant
  that is not a `Node2D` class raises `TypeError`. Each names the map, the object
  and the class.
- **Any other class is data.** `entrance`, `start`, a terrain class such as
  `gap`, and no class at all build nothing from a shape. The object stays a
  record in `map.objects`, and `object_named` finds it.
- **The `@param` tags above `initialize` say what a map may set.** Each property
  sets the keyword of its name, cast to its tag's type. A property no tag makes
  settable, and a required keyword no property sets, each raise listing what a
  map may set. A value of the wrong type raises naming the Tiled type to use.
  [`MapBuilder`](internals.md#mapbuilder--a-node-from-a-maps-object) has the
  table of types and the rest of the rules.
- **The node stands at the bottom centre of the object's box**, turned with it.
  `angle` is the object's rotation, and `width` and `height` are its size. A
  point object's node stands on its point, and a polygon's or polyline's on its
  own corner.
- **A class receives `route:` and `name:` by naming them.** A class whose
  `initialize` names `route:` gets a polyline's or a polygon's route, as
  `Path.from_object` builds it. One that names `name:` gets the object's name,
  or `''` when the designer gave none. Neither needs a tag. Only the class's own
  `initialize` counts, so a subclass whose parent takes `name:` names it too.
- **The node keeps its object's id** as `Node2D#map_object_id`, and nothing
  else of it. [`Components::Facts`](components.md#facts) keys the node's record
  by it, so the chest above, opened once, stays open when its room is built
  again. A node built in code has no id, and passes `key:` to its `Facts`.
- **Every tile object draws its tile.** Its node gets a
  [`Components::MapTile`](components.md#maptile), which draws under whatever the
  class draws. A tile object whose class is data builds a plain `Node2D` to
  carry the tile, so a tree placed from a tileset stands in the world and sorts
  against the actors.
- **A hidden object builds at opacity 0.** It updates and collides, and draws
  nothing, as Tiled shows it. The objects of a hidden layer build too, and the
  layer's node draws none of them.

**Each object layer is a node in its place among the layers**, holding the nodes
its objects build, in the layer's order. It sorts them by where they stand when
Tiled draws the layer *Top Down*, and keeps Tiled's order for *Manual*. It
draws at the layer's opacity.

**Mark the layer the actors walk in.** Add a custom **bool** property named
`actors` to an object layer and tick it. `places[:actors]` is then that layer's
node, so a hero the scene spawns sorts against the trees placed there. On a map
with no mark, the actors get a node of their own below the first `above` layer.

**An object layer is also a place for what a scene adds itself.**
`places['doors']` is the object layer named `doors`, and a `'Group/layer'` path
names one inside a group. An empty object layer in Tiled marks a place in the
layer order. [`TileWorld`](components.md#tileworld) lists what `places` answers
and what it raises.

### A door from the map

**A door is an object of the class `Door`, whose properties say where it
leads.** In `town_with_gate.tmx`, the object `garden_gate` has the class `Door`
and the properties `to: garden` and `entrance: gate_in`. `gate_in` is a point
object in `garden.tmx`. Its class, `entrance`, starts with a lower-case letter,
so it stays data. A room built over each map mounts it, and the map builds the
doors:

```ruby
# A Scene::Room of a world whose Scene::Rooms defines :town and :garden.
class Grounds < RGame::Engine::Scene::Room
  def _enter_tree
    @map = root.context.assets.tilemap(@map_id).map
    add_component(RGame::Engine::Components::TileWorld.new(map: @map, tilemap_id: @map_id))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 32))
    @actors = RGame::Engine::TileMapLayer.mount(add_node(RGame::Engine::WorldView.new))[:actors]
  end

  def _arrive(node, entrance)
    spot = @map.object_named(entrance)
    node.x = spot.x
    node.y = spot.y
    @actors.add_node(node)
  end
end

# A box that asks the world's rooms for a move when a hero's feet touch it.
class Door < RGame::Engine::Node2D
  # @param to [Symbol] the room the door leads to
  # @param entrance [String] the entrance in that room where the hero arrives
  def initialize(to:, entrance:, **)
    super(**)
    @to = to
    @entrance = entrance
    add_component(RGame::Engine::Components::BoxCollider.new(width:, height:, offset_x: -width / 2.0,
                                                             offset_y: -height, layer: :door))
    add_component(RGame::Engine::Components::Collectable.new(by: :hero, free: false))
      .on_collected { |other| @rooms.move(other.node, to: destination, entrance: @entrance) }
  end

  def _enter_tree = @rooms = system!(RGame::Engine::Scene::Rooms)

  private

  def destination = @to
end

# A door into the room it stands in.
class Warp < Door
  # @param entrance [String] the entrance in this room where the hero arrives
  def initialize(entrance:, **) = super(to: nil, entrance:, **)

  private

  def destination = scene.name
end
```

- **The box goes back over the object.** A map-built node stands at the bottom
  centre of its object, so the collider's offsets are half the width to the left
  and the whole height up.
- **A `Warp` is a door into its own room**, so the map names only the entrance.
  A room is its own `scene`, and a move into the room a node stands in only
  places it again.
- **A door finds the rooms in the tree**, with `system!`, as any map-built node
  finds what it needs. The map passes it nothing but its object's settings.
- **An entrance lies off every door's box.** A hero arriving on a door would
  leave through it on its next step.

`examples/doors` is this code with a hero walking it, and
[Rooms](scene_graph.md#rooms-scenerooms) says how a move runs.

## `RGame::Engine::Properties`

**The custom properties a designer attached in Tiled**, already cast to Ruby types:

```ruby
props['speed']              # => 2.5, or nil when there is none
props.fetch('damage')       # => 10, or KeyError naming the property
props.fetch('speed', 1.0)   # a default for a member left unset
props.key?('speed')
props.each { |name, value| }
props.to_h
props.empty?
props['stats'].class_name   # => 'Stats', the custom class of a class property's value
props.class_name            # => nil, for a bag that is no class's value
```

| Tiled type | Ruby |
|---|---|
| `string` | `String` |
| `int`, `object` | `Integer`; an object property is the object's id |
| `float` | `Float` |
| `bool` | `true` or `false` |
| `color` | `RGame::Util::Color`, or `nil` when Tiled has no colour to write |
| `file` | `String`, resolved against the file that states it |
| `class` | a nested `Properties`, answering `class_name` |

**A class member left at its default is absent.** Tiled writes only the members
that differ from the class's defaults, and keeps the defaults in the project file,
which rgame does not read. Read such a member with `fetch(name, default)`.

A `Properties` is frozen, and two are equal when they hold the same values and
are values of the same class. "No properties" is `Properties::EMPTY`, never
`nil`.

## Testing against a map

`TileMapRenderer` draws any object that answers the tile map contract, and never
names `TileMap`. rgame's own suite states that contract in
`spec/support/shared_examples/a_tile_map.rb`. It checks both `TileMap` and the
spec stand-in `StubTileMap` against it. The contract covers `layer_count`,
`layer`, `layer_index`, `actors_layer`, `width`, `height`, `tile_width`,
`tile_height`, `cell_x`, `cell_y`, `col_at`, `row_at`, `tile`, `orientation`,
`solid?`, `tile_offset`, `animated_tiles` and `frame_tile`.

A spec that needs a map but no files parses a `.tmx` String with its tilesets
embedded, as [above](#loading-a-map).
