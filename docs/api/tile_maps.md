# Tile maps

**`RGame::Engine::TileMap` and `RGame::Engine::Tileset` hold a map made in
[Tiled](https://www.mapeditor.org/) as plain data.** `TileMap` holds the grid: its
size, its layers and the tile id in every cell. `Tileset` holds what each tile id
means: which tiles are solid and which are animated. Neither class loads an image
or names a renderer, so both run headless and in specs.

A game rarely touches either class directly. The pieces that use them are:

| | Uses the map to |
|---|---|
| [`TileWorld`](components.md#tileworld) | answer solidity and world-size questions for actors |
| [`TileMapLayer`](components.md#tileworld) | draw one layer per node |
| [`TileMapRenderer`](assets.md#tile-maps) | bake and draw the tiles |
| `RGame::Game`'s `:tilemap` asset loader | load a `.tmx` and pair it with its tileset image |

Read on when a scene queries the map itself, or when you author maps for rgame.

## Loading a map

```ruby
require 'rgame'

map, image_path = RGame::Engine::TileMap.load('examples/assets/town.tmx')

image_path      # => "examples/assets/tileset.png"
map.width       # => 60 — in tiles
map.pixel_width # => 960
map.tileset     # => RGame::Engine::Tileset
```

**`TileMap.load(tmx_path)` returns two values: the map and its tileset image
path.** It reads the `.tmx`, follows it to the `.tsx` it names, parses both, and
attaches the tileset to the map. It does not load the image. An image is a GPU
handle, and the engine layer may not hold one. `RGame::Game`'s asset loader
passes the path to the asset manager instead:

```ruby
app.assets.add_loader(:tilemap) do |path|
  map, image_path = RGame::Engine::TileMap.load(path)
  tiles = app.assets.image(image_path).tiles(map.tileset.tile_width,
                                             map.tileset.tile_height)
  RGame::Core::TileMapRenderer.new(map, tiles)
end
```

In a game, reach the parsed map through that loader:
`app.assets.tilemap('map/island.tmx').map`.

**Every path resolves relative to the file that names it.** The `.tsx` resolves
next to the `.tmx`, and the image next to the `.tsx`. Tiled writes paths this
way, so you can move a map and its tileset together.

`TileMap.parse(tmx_string)` parses a `.tmx` from a String and touches no files. It
leaves `tileset` as `nil`. Attach one with `map.tileset = Tileset.parse(...)`
before asking about solidity.

### What rgame reads from Tiled

rgame supports a subset of the `.tmx` format. A map outside it fails to parse or
parses wrongly, so author within these limits:

| | Supported |
|---|---|
| Orientation | orthogonal |
| Tilesets | **one**, in an external `.tsx` file; an embedded tileset has no `source` and `load` raises |
| Layer data | base64 with zlib compression (Tiled's "Base64 (zlib compressed)"); other encodings raise |
| Layers | tile layers only; object and image layers are ignored |
| Flipped or rotated tiles | the flip flags are stripped, so the tile draws unflipped |
| Map size | fixed; infinite maps are not read |

## `RGame::Engine::TileMap`

### Geometry

| Reader | |
|---|---|
| `width`, `height` | the map's size in tiles |
| `tile_width`, `tile_height` | one tile's size in pixels |
| `pixel_width`, `pixel_height` | the map's size in pixels |
| `layer_count` | how many tile layers the map has |
| `tileset`, `tileset=` | the attached `Tileset`, or `nil` |
| `tileset_source`, `firstgid` | the `.tsx` path the map names, and the tileset's first gid |

### Reading cells

```ruby
map.gid(0, 12, 7)          # the gid in layer 0 at column 12, row 7
map.in_bounds?(60, 0)      # => false — columns run 0..59
map.gid(0, -1, 0)          # => 0 — outside the map, every layer is empty
```

**A gid is Tiled's global tile id.** `0` means an empty cell. Any other gid names a
tile in the tileset; `Tileset#local_id(gid)` turns it into the tile's index in the
tileset image. Layer `0` is the bottom layer, as Tiled lists them.

`gid` answers `0` for any cell outside the map, so a caller never checks bounds
first. The map stores its gids in one
[`Util::Tensor`](values.md#rgameutiltensor), indexed column, row, layer.

### Solidity

```ruby
map.solid_tile?(12, 7)          # any layer solid at that cell?
map.solid_at?(200.5, 116.0)     # the same, from a world position in pixels
```

**A cell is solid when any layer holds a solid tile there.** Collision considers
every layer, whatever it draws like. `solid_at?(world_x, world_y)` divides by the
tile size and asks `solid_tile?` for that cell. **Outside the map is not solid.**
Keep actors inside with `blocked_by: [:bounds]` on their mover.

Both methods need an attached tileset, which `load` provides.

Actors do not call these per step. [`TileWorld`](components.md#tileworld) reads
`solid_tile?` once per cell into a
[`Util::SolidGrid`](values.md#rgameutilsolidgrid), and collision and pathfinding
read that grid.

### Layers drawn above the actors

```ruby
map.above_layer?(2)   # => true when Tiled marks layer 2 `above`
```

**Mark a layer `above` in Tiled** to draw it over the actors, for tree canopies
or roofs. Add a custom **bool** property named `above` to the layer and tick it. A
layer without the property draws below.

The flag affects drawing order only. `TileWorld#first_above_layer` returns the
first flagged layer, and
[`TileMapLayer.mount`](components.md#tileworld) leaves the actors' gap below it.
A map with no flagged layer puts the actors over everything.

### Building a map by hand

```ruby
require 'rgame'

map = RGame::Engine::TileMap.new(
  width: 2, height: 1, tile_width: 16, tile_height: 16,
  tileset_source: 'tiles.tsx', firstgid: 1,
  layers: [[1, 2]],          # one layer, gids row by row
  above: [false]
)
map.tileset = RGame::Engine::Tileset.new(
  firstgid: 1, columns: 2, tile_width: 16, tile_height: 16,
  image_source: 'tiles.png', animations: {}, solid_ids: Set[1]
)

map.solid_at?(20.0, 3.0)   # => true — gid 2 is local tile 1, which is solid
map.solid_at?(3.0, 3.0)    # => false
```

**Specs build small maps this way**, with no files. `layers:` is an Array of
layers. Each layer is a flat Array of `width * height` gids, row by row. `above:`
is optional and defaults to no layer above.

## `RGame::Engine::Tileset`

**A `Tileset` says what each tile in a sheet is.** It knows the sheet's geometry,
which tiles are solid, and which are animated.

| Reader | |
|---|---|
| `firstgid` | the gid of the tileset's first tile in the map |
| `columns` | how many tiles one row of the sheet holds |
| `tile_width`, `tile_height` | one tile's size in pixels |
| `image_source` | the sheet image, as the `.tsx` names it |
| `animations` | `{ local_id => [Frame, ...] }` for every animated tile |
| `animated_ids` | the local ids that have an animation |
| `solid_ids`, `solid_ids=` | a Set of the local ids that are solid |

`Tileset.parse(tsx_string, firstgid:)` parses a `.tsx` from a String. The
`firstgid` comes from the map, because Tiled stores it in the `.tmx`, not in the
`.tsx`.

### Local ids

```ruby
tileset.local_id(37)   # => 36 when firstgid is 1
```

**A local id is a tile's index in the sheet**, counted from 0, left to right and
top to bottom. It equals `gid - firstgid`. `Image#tiles` slices a sheet in the same
order, so a local id indexes that Array directly.

### Solid tiles

```ruby
tileset.solid?(gid)            # takes a gid, not a local id; 0 is never solid
tileset.solid_ids << 12        # make local tile 12 solid
```

**A tile is solid when it has a collision shape in Tiled.** Open the tileset in
Tiled's collision editor and draw any shape on the tile. `parse` marks every tile
whose `<objectgroup>` holds at least one object. The shape itself is ignored:
rgame treats a solid tile as a solid square. The map carries its collision, so
changing which tiles block needs no code.

`solid_ids` is writable, for a game that adds or removes solid tiles in code. Change
it before a `TileWorld` first asks, because the world copies solidity into its own
grid once.

### Animated tiles

```ruby
tileset.animations[37]           # => [#<struct Frame tile_id=37, duration=250>, ...]
tileset.frame_local_id(37, 0)    # => 37
tileset.frame_local_id(37, 250)  # => 46
```

**Animate a tile in Tiled's tile animation editor.** `parse` reads each frame as a
`Tileset::Frame` with a `tile_id` (a local id) and a `duration` in milliseconds.

`frame_local_id(local, ms)` returns the local id to draw for tile `local` after
`ms` milliseconds. The animation loops. A tile without an animation returns
itself. The time is an argument, not a clock read, so pausing is "stop
accumulating".

**Tiled speaks milliseconds; the engine speaks seconds.** `TileWorld` accumulates
`elapsed` in seconds, and `TileMapRenderer` converts it once per draw, as
`(elapsed * 1000).to_i`. Convert the same way when you call `frame_local_id`
yourself.

## Testing against a map

`TileMapRenderer` draws any object that answers the tile map contract, and never
names `TileMap`. rgame's own suite states that contract in
`spec/support/shared_examples/a_tile_map.rb`. It checks both `TileMap` and the
spec stand-in `StubTileMap` against it. The contract covers `layer_count`,
`width`, `height`, `tile_width`, `tile_height`, `gid`, and a `tileset` answering
`local_id`, `animations` and `frame_local_id`.

A spec that needs a map but no files builds one [by hand](#building-a-map-by-hand),
or parses a `.tmx` string with `TileMap.parse`.
