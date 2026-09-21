# Tile maps

**`RGame::Engine::TileMap` holds a map made in [Tiled](https://www.mapeditor.org/)
as plain data**: its size, its layers, the tile in every cell, what each tile is,
and the objects placed on it. It loads no image and names no renderer, so it runs
headless and in specs.

A game rarely builds one itself. The pieces that use it are:

| | Uses the map to |
|---|---|
| [`TileWorld`](components.md#tileworld) | answer solidity and world-size questions for actors |
| [`TileMapLayer`](components.md#tileworld) | draw one layer per node |
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

parsed = RGame::Engine::Tiled::Map.load('examples/assets/town.tmx')
map = RGame::Engine::TileMap.from_tiled(parsed)

map.width         # => 60 — in tiles
map.pixel_width   # => 960
map.layer_count   # => 2
map.tile_count    # => 132
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

Some of what is read is not drawn. `TileMapRenderer` draws every tile unturned,
draws a hidden layer, and draws every layer at full opacity. The asset loader
raises for a tileset with a margin or spacing, and for a collection of images,
because it slices only a sheet of tiles packed edge to edge. Per-layer offset,
parallax and tint are not read.

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
map.tile_class(tile)         # the class set in Tiled, or nil
map.tile_properties(tile)    # its custom properties
map.animated_tiles           # the tiles that animate
map.frame_tile(tile, 0.25)   # the tile showing 0.25 s into its animation
```

**A tile is solid when it has a collision shape in Tiled.** Open the tileset in
Tiled's collision editor and draw any shape on the tile. The shape itself is
ignored: rgame treats a solid tile as a solid square, so the map carries its
collision and changing which tiles block needs no code.

**`frame_tile(tile, elapsed)` takes seconds**, like `dt`.
The animation loops, and a tile that does not animate answers itself. The time is
an argument, not a clock read, so pausing is "stop accumulating". Animate a tile in
Tiled's tile animation editor.

### Solidity

```ruby
map.solid_tile?(12, 7)          # any layer solid at that cell?
map.solid_at?(200.5, 116.0)     # the same, from a world position in pixels
```

**A cell is solid when any layer holds a solid tile there**, a hidden layer
included: hiding a layer in Tiled changes how it draws, not what blocks.
`solid_at?(world_x, world_y)` divides by the tile size and asks `solid_tile?` for
that cell. **Outside the map is not solid.** Keep actors inside with
`blocked_by: [:bounds]` on their mover.

Actors do not call these per step. [`TileWorld`](components.md#tileworld) reads
`solid_tile?` once per cell into a
[`Util::SolidGrid`](values.md#rgameutilsolidgrid), and collision and pathfinding
read that grid.

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
`TileWorld#first_above_layer` returns the first flagged layer, and
[`TileMapLayer.mount`](components.md#tileworld) leaves the actors' gap below it.

`map.image_layers` lists the image layers, each a `TileMap::ImageLayer`: a
`Layer` that adds `image` (the image's path, or `nil`), `offset_x` and `offset_y`
in the map's pixels, and `repeat_x?` and `repeat_y?`.

### Objects

```ruby
map.objects   # => every object of every object layer, as MapObjects
```

**A `RGame::Engine::MapObject` is in the game's coordinates.** `x` and `y` are its
top-left corner in pixels, for every shape, and `rotation` turns it clockwise, in
degrees, about that corner. Tiled measures a tile object from its bottom-left
corner; `from_tiled` moves it, so a tile object and a rectangle over the same
cells report the same corner.

| | |
|---|---|
| `id`, `name`, `class_name` | as set in Tiled |
| `layer` | the index of the layer it sits in |
| `x`, `y`, `width`, `height`, `rotation` | its box, as above |
| `shape` | `:rectangle`, `:ellipse`, `:point`, `:polygon`, `:polyline` or `:text` |
| `points` | a polygon's or polyline's corners, in the same coordinates, before `rotation` |
| `tile`, `orientation` | a tile object's tile id and how it is turned; `nil` and the identity for a shape |
| `visible?` | false when the designer hid it |
| `properties` | its custom properties |

**No node is built from an object.** The map reads them; placing something for
each is the game's code.

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
```

| Tiled type | Ruby |
|---|---|
| `string` | `String` |
| `int`, `object` | `Integer`; an object property is the object's id |
| `float` | `Float` |
| `bool` | `true` or `false` |
| `color` | `Util::Color`, or `nil` when Tiled has no colour to write |
| `file` | `String`, resolved against the file that states it |
| `class` | a nested `Properties` |

**A class member left at its default is absent.** Tiled writes only the members
that differ from the class's defaults, and keeps the defaults in the project file,
which rgame does not read. Read such a member with `fetch(name, default)`.

A `Properties` is frozen and compares by its contents. "No properties" is
`Properties::EMPTY`, never `nil`.

## Testing against a map

`TileMapRenderer` draws any object that answers the tile map contract, and never
names `TileMap`. rgame's own suite states that contract in
`spec/support/shared_examples/a_tile_map.rb`. It checks both `TileMap` and the
spec stand-in `StubTileMap` against it. The contract covers `layer_count`,
`layer`, `width`, `height`, `tile_width`, `tile_height`, `tile`, `orientation`,
`solid?`, `animated_tiles` and `frame_tile`.

A spec that needs a map but no files parses a `.tmx` String with its tilesets
embedded, as [above](#loading-a-map).
