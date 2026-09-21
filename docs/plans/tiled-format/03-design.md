# The design

## The two halves, and the transform between them

```
  .tmx / .tsx / .tx
        |
        |  REXML, stdlib only, no graphics
        v
  RGame::Engine::Tiled::*        a faithful reading of the file
        |   Map, Tileset, Tile, TileLayer, ImageLayer,
        |   GroupLayer, ObjectLayer, Object, Properties
        |
        |  TileMap.from_tiled — the transform:
        |  flatten the tree, number the tiles, decode the orientations,
        |  shift the origin, normalise the objects
        v
  RGame::Engine::TileMap         what actors and the renderer ask
        |
        |  duck-typed, the 'a tile map' contract
        v
  RGame::Core::TileMapRenderer   bakes and draws
```

**The top half asserts nothing about games.** It answers "what does this file
say", keeps Tiled's names and Tiled's coordinates, and has no opinion about
solidity, draw order or cameras. That is what makes it testable against a file
Tiled wrote, and what gives an object layer somewhere to live.

**The bottom half asserts nothing about files.** It answers "what is in this
cell", "is it solid", "how is it turned", "how big is the world". It is built
for the questions a game asks, at the cost the game can pay, and it keeps the
dense `Util::Tensor` the C collision stack reads.

**The transform is where Tiled's world becomes the game's.** It absorbs every
awkwardness the format has, once: a global id space with per-tileset offsets,
three flip bits, a chunk origin that depends on where a designer painted, a tile
object measured from its bottom-left corner. Nothing below it has to know the
file exists.

Today one class does both, which is why every new attribute has to be threaded
through one constructor and why `above` is read by a method that knows its name.

## What the runtime view may not say

The transform earns its place only if the vocabulary stops at it. So the test,
applied to every method on `TileMap`:

> **Does this name exist because Tiled exists?** If so, the transform should
> have absorbed it.

Six things fail that test in the obvious design, and each is absorbed below:

| Tiled's word | What the game asks | Where it goes |
|---|---|---|
| `gid`, `firstgid`, per-tileset local ids | what tile is in this cell | [one tile table](#tiles-one-table-and-no-gid-below-the-transform) |
| three flip bits, 0..7 | how is this tile turned | [an orientation](#orientation-eight-of-them-decoded-once) |
| `Tiled::Object`, bottom-left tile objects | where is this thing | [one object record](#objects-one-record-in-the-games-coordinates) |
| `properties['above']` | does this layer cover the actors | [`layer.above?`](#layers-the-tree-the-flat-index-and-what-stays-stable) |
| the infinite-map chunk origin | — nothing | [stays on the parse](#infinite-maps-and-the-origin-shift) |
| frame durations in milliseconds | how long is this frame | [seconds, like every other duration](#the-runtime-view) |

What survives the test, and stays: layer **names** and paths, because a designer
and a programmer share them; custom **properties**, because a designer authors
them for the game to read; a tile's **class**, for the same reason.

The guard is a grep, in the shape the project already uses for `REXML`:
`RGame::Engine::Tiled` may be named inside `lib/rgame/engine/tiled/` and in the
one transform file, and nowhere else. See
[step 4's verify](04-roadmap.md#step-4--tilemap-and-the-transform).

## `Engine::Tiled` — the faithful parse

One class per element, following [pytmx and tmxlite](02-prior-art.md#pytmx-and-tmxlite).
Sketched, not final:

```ruby
module RGame::Engine::Tiled
  Map         # orientation, render_order, infinite?, width, height,
              # tile_width, tile_height, background_color, class_name,
              # properties, tilesets (Array<TilesetRef>), layers (Array, the tree),
              # origin_col, origin_row
  TilesetRef  # firstgid + tileset; the pairing the .tmx owns and the .tsx does not
  Tileset     # name, class_name, tile_width, tile_height, spacing, margin,
              # tile_count, columns, image, offset_x, offset_y,
              # tiles (Hash<local_id, Tile>), properties
  Tileset::Image  # source (a path), width, height — never a GPU handle
  Tile        # id, class_name, properties, image, frames, collision_shapes
  Frame       # tile_id, duration_ms

  Layer       # id, name, class_name, visible?, opacity, properties
  TileLayer   < Layer   # width, height, origin_col, origin_row, gids (flat Array, raw)
  ImageLayer  < Layer   # image, repeat_x?, repeat_y?, offset_x, offset_y
  GroupLayer  < Layer   # layers
  ObjectLayer < Layer   # draw_order, objects
  Object      # id, name, class_name, x, y, width, height, rotation,
              # gid, visible?, shape, points, properties
end
```

`Tiled::Map.parse(string)` takes a String and touches no files. `Tiled::Map.load(path)`
adds the file plumbing: following each `<tileset source>` to its `.tsx`,
resolving relative to the file that named it, and following each
`<object template>` to its `.tx`.

**This half keeps every unit and every coordinate the file states.** Durations
stay in milliseconds, a tile object keeps its bottom-left origin, a gid keeps
its flip bits, and an infinite map records where its chunks began. Converting
any of it here would make the parse harder to check against Tiled's own
reference, which is the one thing this half is for.

**Refusals belong here, and they are loud.** A non-orthogonal orientation, a
zstd-compressed layer, a tileset the `.tsx` for which is missing: each raises
with a message naming the file, the element and what to change in Tiled. A parser
that half-reads a map it does not understand is the failure mode
[F1](01-current-state.md#f1) through [F4](01-current-state.md#f4) all share.

## Properties

```ruby
props = layer.properties
props['above']              # => true          — already a boolean
props.fetch('damage')       # => 10            — raises with the property name
props.key?('spawn')         # => false
props.to_h                  # => { 'above' => true, 'damage' => 10 }
```

Values are cast at parse time, by Tiled's declared `type`:

| Tiled type | Ruby |
|---|---|
| `string` (the default) | `String` |
| `int` | `Integer` |
| `float` | `Float` |
| `bool` | `true` / `false` |
| `color` | `RGame::Util::Color` |
| `file` | `String`, resolved relative to the file that named it |
| `object` | `Integer` — an object id, left unresolved |
| `class` | `Properties` — nested, recursively |

Two format details the parser must not miss.
**A multi-line string has no `value` attribute** and lives in the element's text
instead. And **`color` is `#AARRGGBB`**, alpha first — or `#RRGGBB` when Tiled
has no alpha to write. `Util::Color` parses no strings at all, so the parser converts
both forms into `Color.new(r, g, b, a)` itself.

Casting at parse rather than at read is deliberate: a bool property read as the
String `"true"` is truthy when it is false, and every caller would have to
remember. That is exactly the remembered rule CLAUDE.md refuses.

`Properties` is the one parse type the runtime view hands out unchanged. A
custom property is authored by a designer *for the game*, so it is already in
the game's world; the values are plain Ruby and the bag is frozen data.

## Tiles: one table, and no gid below the transform

**The transform numbers every tile the map can hold, and a cell holds that
number.** `gid` and `firstgid` never appear below `Engine::Tiled`.

```ruby
map.tile(layer, col, row)   # => an rgame tile id; 0 is an empty cell
map.tile_count              # => how many tiles the map's tilesets hold, together
map.tile_table              # => Array, index = tile id, each entry naming its
                            #    tileset and local id — what the glue slices against
```

Tile ids run from 1, so 0 stays the empty cell the renderer already skips. They
are dense, so every per-tile fact is an array read:

```ruby
map.solid?(tile)
map.tile_class(tile)            # the Tiled class, or nil
map.tile_properties(tile)       # => Properties
map.frame_tile(tile, elapsed)   # the tile showing now, or `tile` if it has no frames
map.animated_tiles              # the tiles that have frames
```

Building the table is one pass over the tilesets at load: concatenate them in
`firstgid` order, and record a flat `gid → tile id` lookup. Resolving a cell is
then one array read, not a reverse scan for the last tileset whose `firstgid`
fits.

### Why this, and what it costs

**A gid exists to multiplex several tilesets into one number space.** That is
the format's problem, solved for the format's benefit. A game asks what is in a
cell, and a dense id answers it without the offset arithmetic that produced it.

What falls out, none of it planned for:

- **`TileMapRenderer`'s signature stops changing.** `tiles` stays one flat Array
  indexed by tile id, exactly as it takes today. No per-tileset resolution at
  bake time, no Array of Arrays.
- **Sheet tilesets and collections become indistinguishable** below the
  transform, which is what [the images section](#images-margin-spacing-and-collections)
  wants and does not otherwise get.
- **`solid_tile?` becomes an array read** rather than a layer scan crossed with
  `firstgid` arithmetic and a Set lookup. It also puts a `Util::SolidGrid` filled
  at load within reach, which is where `OccupiesCell` and runtime-mutable maps
  both want to live.
- **`Engine::Tileset` dissolves.** Its `spacing`, `margin`, `columns`,
  `offset_x`, `offset_y` and `tile_count` exist only so something can slice a
  sheet. Slicing happens once, in the glue, which reads `Tiled::Tileset`
  directly. Nothing a game asks at runtime is per-tileset; it is all per-tile.
- **`TileMap.load` goes away.** See [the runtime view](#the-runtime-view).
- **The contract and `StubTileMap` get smaller**, not larger: `tileset`,
  `local_id` and `firstgid` leave rather than `tilesets` and `tileset_for`
  arriving.

*(measured, at `2a9e8e7`)* The table costs one array lookup inside a loop that
already runs, because `TileMap` already walks every cell writing into a `Tensor`:
**+0.04 ms** on `town.tmx`, **+2.8 ms** on a 250×250×6 map, **+16 ms** on a
500×500×8 one. See [the brief's measurements](README.md#what-was-measured-while-designing-the-transform).

### Rejected: keep the gid, and resolve it per read

Hold raw gids in the Tensor as today, add `map.tilesets` and `map.tileset_for(gid)`,
and let each reader resolve. It is the smaller diff and it keeps a word Tiled
users recognise.

It fails on who pays and who has to remember. Four readers repeat the same
resolution: solidity per cell per step, the bake, the animated pass, and a game
looking at a cell. Each one costs a reverse scan and an offset subtraction the
load had everything it needed to do once. It also makes `Engine::Tileset` a near
copy of `Tiled::Tileset`, row for row — the parallel-vocabulary smell CLAUDE.md
names.

### Rejected: a tile id per orientation, Godot-style

Generate an extra tileset entry for each orientation a map actually uses, so a
flipped tile is just a different id.

It makes a **tileset's** ids depend on which map loaded it. Two maps sharing one
`.tsx` would disagree about what tile 140 is, and `Image#tiles` slices by index.

The tile table above looks like this and is not: each tileset keeps its own local
id space, `Image#tiles` still slices per tileset, and the asset manager still
shares one upload between maps. What is per-map is only the numbering the map
uses to index into those slices — which the glue builds from `map.tile_table`,
in one place.

## Orientation: eight of them, decoded once

**A second plane, parallel to the tile grid, allocated only when the map uses
one.**

```ruby
map.orientation(layer, col, row)   # => one of eight frozen values

o.quarter_turns   # 0, 1, 2 or 3, clockwise
o.mirrored?       # whether it is flipped across the vertical axis after turning
o.identity?       # the common case, and the value every cell of an unflipped map gets
```

`TileMap` holds `@tiles` (a `Util::Tensor` of tile ids) and `@orientations` (a
second `Util::Tensor`, or `nil`). A map with no flipped tile allocates nothing
and `orientation` answers the identity from the `nil` check, so the common map
pays nothing and the contract stays the same shape either way.

**The eight values are frozen constants in a table indexed by Tiled's three
bits**, so reading one allocates nothing either.

**Why not hand out the bits.** Tiled expresses the eight orientations as
`(diagonal << 2) | (vertical << 1) | horizontal`, where the diagonal flip is an
axis swap applied first. Turning that into a rotation and a mirror is easy to
get backwards, and a backwards rotation produces a picture that looks
deliberate. Handing out the bits gives three consumers their own chance to get
it wrong: the bake, a game reading a cell, and `StubTileMap`. A stub's author
would have to know Tiled's bit order to write one. Decoding once, in the
transform, leaves one place to be right and one table to pin with tests.

**The exact mapping is pinned by tests against a map Tiled wrote, not asserted
here** — the same reason `test/test_transform.c` asserts on coordinates rather
than matrix entries.

Drawing an orientation means a rotation of 0, 90, 180 or 270 degrees and an
optional mirror. `renderer.rotated` and a negative scale on `image_at` cover all
eight, and [F6](01-current-state.md#f6) says the bake absorbs both.

The parse keeps the bits, and the mask becomes `0x0FFFFFFF`, clearing bit 29 as
[F3](01-current-state.md#f3) requires.

### Rejected: packing the flip bits into the tile id

Keep one plane and let each reader mask.

It fails on the reader that forgets. A reader that skips the mask gets an id in
the hundreds of millions — not an error, just the wrong tile or a `nil` out of
the image array three calls later. A rule every caller must remember is the
design CLAUDE.md rejects.

It is also what the parse already does, faithfully, in `TileLayer#gids`. Keeping
it below the transform would mean the transform had absorbed nothing.

## Layers: the tree, the flat index, and what stays stable

Tiled nests. rgame's scene tree needs a flat, ordered list, because
`TileMapLayer` mounts one node per layer and the actors sit in a gap between
two of them.

**So the tree flattens in the transform, depth first, in Tiled's own order.** A
group contributes no index of its own; its children do, in place. Going down, a
group multiplies its children's opacity and ANDs its visibility — which is what
Tiled shows you in the editor.

A flat index alone is fragile: adding a group in Tiled renumbers everything
below it, and the scene's `under:` argument silently moves. So a layer is also
addressable by **path**:

```ruby
map.layer_index('Background/ground')   # => 0
map.layer(0).path                      # => ['Background', 'ground']
map.layer(0).name                      # => 'ground'
```

and `TileMapLayer.mount(world, under: 'canopy')` takes a name or a path as
readily as an index. A name is what a designer sees in Tiled; an index is an
implementation detail that happens to be convenient.

Each layer carries what the renderer and the scene need:

```ruby
layer.visible?    # false => not drawn, and not baked
layer.opacity     # 0.0..1.0, already multiplied down the group tree
layer.kind        # :tile, :image, :object
layer.above?      # whether it covers the actors
layer.properties  # everything else the designer attached
```

**`above?` is a named question, not a property lookup.** Tiled carries it as a
bool property and the transform reads it once. `TileMapLayer.mount` picks its gap
from this, and a misspelled `properties['above']` would read as `nil`, then
false, then actors drawn on top of every canopy — silently. `TileMap.layer_flag?`
([F9](01-current-state.md#f9)) still goes; what replaces it is one reader rather
than one string every caller spells.

A hidden layer still counts for **collision**, as every layer does today. That
is deliberate and worth stating out loud: Tiled's `visible` is an editor and
render setting, and a designer who hides the obstacles layer to see the ground
underneath has not made the walls passable.

## Infinite maps and the origin shift

The parse reads the chunks, takes the bounding box of the non-empty ones across
**every** layer, and writes the result into an ordinary dense grid. That is still
a faithful reading: no coordinate moves, and `Tiled::Map` records where the box
began.

**The runtime view has one coordinate system: cell (0, 0) is the map's
top-left.** Where a designer happened to paint relative to Tiled's origin is a
fact about the file, so `origin_col` and `origin_row` live on `Tiled::Map` and
stop there. A tool that wants to show editor coordinates reads the parse.

Two rules make the shift safe rather than a trap.

**The bounding box is taken across all layers at once**, never per layer.
Per-layer bounds would give two layers different origins, and the tile at
`(3, 7)` would mean two different places.

**Every coordinate the file states is shifted by the same amount, in one
place** — the transform. That is object positions and image-layer offsets. A
caller never shifts anything, and a fixed map and an infinite one are
indistinguishable below the transform, which is the whole point of flattening
them ([decision 4](README.md#decisions-already-taken)).

## Objects: one record, in the game's coordinates

**One record type, and the transform has already normalised it.**

```ruby
MapObject = Data.define(:id, :name, :class_name, :x, :y, :width, :height,
                        :rotation, :tile, :shape, :points, :properties)

map.objects   # => Array<MapObject>, every object layer, flattened
```

Not `Tiled::Object`. The parse type keeps the file's coordinates and stops at
the transform, like every other parse type.

What the transform does on the way through, so that no caller does it:

1. **A tile object's `(x, y)` becomes its top-left corner.** The file states the
   bottom-left ([Tiled's reference](https://doc.mapeditor.org/en/stable/reference/tmx-map-format/#object)),
   and treating it like a rectangle's puts every tile object one tile-height too
   low. The conversion is arithmetic nobody should repeat.
2. **`gid` becomes a `tile`** — the map's own id, or `nil` for a shape object,
   with its orientation folded in.
3. **The infinite-map origin shift is applied**, to `x`, `y` and every point of
   a polygon or polyline.
4. **`points` are absolute**, not relative to the object's own origin.
5. **`rotation` states what it turns about.** The file rotates clockwise about
   `(x, y)`, which for a tile object is the bottom-left corner — a different
   point from the one rule 1 just moved.

Rule 5 is the one to write a test for before writing the code: two traps
compose there, and getting either wrong produces a plausible picture.

## The runtime view

```ruby
class RGame::Engine::TileMap
  attr_reader :width, :height, :tile_width, :tile_height,
              :pixel_width, :pixel_height, :tile_count, :tile_table,
              :properties, :source

  def self.from_tiled(tiled_map)   # the only transform

  # cells
  def tile(layer, col, row)
  def orientation(layer, col, row)
  def in_bounds?(col, row)

  # tiles
  def solid?(tile)
  def tile_class(tile)
  def tile_properties(tile)
  def frame_tile(tile, elapsed)
  def animated_tiles

  # collision
  def solid_tile?(col, row)
  def solid_at?(world_x, world_y)

  # layers and content
  def layer_count
  def layer(index)            # => TileMap::Layer
  def layer_index(name_or_path)
  def image_layers            # => Array<TileMap::ImageLayer>
  def objects                 # => Array<MapObject>
end
```

**`TileMap.load` and `TileMap.parse` both go.** Reading a file is the parse's
job and slicing an image is the glue's, so the map is built from an already-read
`Tiled::Map` and nothing else:

```ruby
tiled = RGame::Engine::Tiled::Map.load(path)
map   = RGame::Engine::TileMap.from_tiled(tiled)
tiles = slice(tiled)                                 # Core, in RGame::Game
RGame::Core::TileMapRenderer.new(map, tiles)
```

That also kills two shapes the old signature forced.
`TileMap.load` returned `[map, image_path]` only because the map did the file
plumbing while being forbidden to hold a texture
([constraint 1](README.md#hard-constraints)); the glue names both layers legally
and reads the paths off the parse. And `image_paths` would otherwise have been
an Array whose *shape* varied with the tileset kind — nested for a collection,
flat for a sheet.

`TileMap.parse(tmx_string)` went with them. The design that keeps it hands back
a map with no tilesets attached, which cannot answer solidity and cannot be
built at all once the tile table exists. Headless specs lose nothing:
`Tiled::Map.parse` takes a String and touches no files, and a map with an
embedded tileset needs no filesystem from end to end
([constraint 7](README.md#hard-constraints)).

**Durations are seconds.** `frame_tile(tile, elapsed)` takes the same unit `dt`
and every other duration in the engine uses. Tiled states frame durations in
milliseconds and the parse keeps them that way; the transform converts once, at
load. Today the renderer converts per draw call — per layer, per viewport, per
frame ([tile_map_renderer.rb:156](../../../lib/rgame/core/tile_map_renderer.rb#L156))
— which is Tiled's unit surfacing on a hot path.

## What the transform produces, and why it is plain data

**A built `TileMap` holds plain Ruby values and one thing produces it.** Both
properties are needed anyway, and together they leave a door open that costs
nothing to leave open.

1. **`from_tiled` is the only transform, and `initialize` takes already-built
   data.** A second producer would feed the same constructor.
2. **Nothing reachable from a built map is a `Tiled::*` object.** The tile table
   holds integers, strings and `Properties`. The grep guard above enforces it.
3. **`initialize` takes flat Arrays, not a `Tensor`, and builds the `Tensor`
   itself.** `Tensor` defines `initialize`, `[]`, `[]=`, `width`, `height` and
   `depth` and nothing else — no `_dump`, no `_load`
   ([tensor.c:180-185](../../../ext/rgame_util/tensor.c#L180-L185)). A
   constructor that takes a `Tensor` would put a C object in the way of anything
   that ever wants to serialise a map. Flat Arrays also happen to be what a bulk
   `Tensor` fill would take.
4. **`source` records where the map was built from**, with the parser's own
   version constant. Three attributes, no mechanism.

**The door those four leave open is a cache of built maps across process runs**,
and it stays shut. Within one run the pre-build already exists:
`AssetManager#fetch` is `@cache[key] ||= yield`
([asset_manager.rb:182](../../../lib/rgame/core/asset_manager.rb#L182)) and
`preload` is the "build these at startup" entry point, so a map is transformed
once per process whatever else changes.

Across runs it would need a format, a location, and a rule for what invalidates
it — and the measurements say nothing is hurting:
a 250×250×6 map transforms in about 35 ms, once, on a scene load. The cheaper
move comes first anyway, and it is not a cache: the dominant cost is per-cell
Ruby-to-C crossings through `Tensor#[]=`, and a bulk fill in C halves it.
See [open question 4](README.md#open-questions).

**A second producer waits until something needs one.** A cache reader with no
writer, or two paths to a `TileMap` both green in isolation, is exactly the
parallel-implementation trap CLAUDE.md has the worked example for.

## What the renderer changes

Less than the parse rewrite suggests, because the tile table absorbs the part
that would have touched it.

```ruby
RGame::Core::TileMapRenderer.new(map, tiles)   # unchanged: one flat Array
```

`tiles` stays indexed by tile id, with `nil` at 0. The glue builds it by slicing
each tileset once and laying the slices out along `map.tile_table`.

Three additions, all inside the existing bake-and-replay shape:

- **An oriented tile** is baked under a `rotated` push and a negative scale.
  Per [F6](01-current-state.md#f6) this costs bake time only.
- **A layer's opacity** is a tint on `Recording#draw` and a colour on the
  animated `image_at`, per [F7](01-current-state.md#f7).
- **A hidden layer** returns before baking, so it costs nothing at all.

The `a tile map` contract is rewritten rather than grown. It loses `tileset`,
`gid` and everything reached through `map.tileset`; it gains `tile`,
`orientation`, `frame_tile`, `solid?` and the layer readers. `StubTileMap`
follows in the same commit ([constraint 6](README.md#hard-constraints)), and
comes out shorter than it is today. [F10](01-current-state.md#f10) counts the
`map.tileset` sites.

Image layers do **not** go through this class. An image at a position with
optional repeat is `renderer.image_at` in a loop, so it is an engine-layer node
and Core learns nothing new.

## Images: margin, spacing, and collections

```ruby
image.tiles(16, 16, margin: 1, spacing: 2, count: 132, columns: 12)
```

Built over the existing C `subimage`. `margin` is the border around the sheet,
`spacing` the gap between tiles; `count` and `columns` come from the `.tsx` and
stop a sheet with trailing blank space from yielding tiles nobody asked for.
**Zero margin and zero spacing keeps the current C fast path**, so no existing
caller changes and nothing regresses.

Slicing happens in the glue, which reads `Tiled::Tileset` for the numbers and
`map.tile_table` for where each slice goes. A collection-of-images tileset has
no sheet: each `<tile>` names its own file, so the glue loads one image per tile
and drops it at the same tile id a sheet slice would have taken. The renderer
never learns which kind it had.

## Nodes on a map

Three pieces, from smallest to largest. The record they pass around is
[`MapObject`](#objects-one-record-in-the-games-coordinates).

### 1. Tile coordinates, on `TileWorld`

*Re-planned: the four conversions go on `TileMap`, which `TileWorld` forwards,
and `place` is dropped. See
[step 7](04-roadmap.md#step-7--nodes-on-a-map).*

```ruby
world.cell_x(col)               # the cell's left edge, in world pixels
world.cell_y(row)
world.cell_centre(col, row)     # => [x, y]
world.col_at(world_x)
world.row_at(world_y)
world.place(node, col, row, align: :centre)
```

**This is the seam [decision 1](README.md#decisions-already-taken) buys**, and
the four copies in [F8](01-current-state.md#f8) collapse into it —
`TileMap#solid_at?`, `TileMapRenderer#draw_animated`, `Navigator#cell_at` and
friends, and `Util::TileSweep`'s C arithmetic, which stays in C but stops being
a fifth independent answer.

### 2. A slot per gap, not one gap

*Re-planned: a gap's value names the layer that covers it, as `under:` did,
and `under:` goes. See
[step 6](04-roadmap.md#step-6--the-rest-of-what-tiled-shows-and-a-slot-per-gap).*

```ruby
slots = TileMapLayer.mount(world, gaps: { actors: nil, bridge: 'river' })
slots[:actors]     # the default gap, at the first layer where above? is true
slots[:bridge]     # a node between 'river' and whatever follows it
```

`mount` hands out z slots, so the gaps have to be declared when it runs. Calling
it with no `gaps:` returns a slots object that still answers `[:actors]`, so
every existing scene changes by one character.

### 3. The factory registry

```ruby
factory = RGame::Engine::MapObjects.new
factory.define('chest') { |o| Chest.new(x: o.x, y: o.y, contents: o.properties['contents']) }
factory.define('trap')  { |o| Trap.new(x: o.x, y: o.y, damage: o.properties['damage']) }

factory.build(object)              # => a node, or nil for an unregistered class
factory.spawn_into(slots[:actors], objects)
```

Keyed by **class**, following
[SuperTiled2Unity](02-prior-art.md#supertiled2unity--the-object-to-node-mapping-done-at-import),
and shaped after `AssetManager#add_loader` — a name, a block, and the registry
holds them. An unregistered class returns `nil` rather than raising, because a
map carries objects a scene has no interest in.

A scene builds the records in code today:

```ruby
factory.spawn_into(slots[:actors], [
  MapObject.new(class_name: 'chest', x: 320, y: 128, properties: { 'contents' => 'key' }, ...)
])
```

and reads them off the map later, with nothing else changing. That is the whole
point of the shape, and it works because `map.objects` already hands out the
same record in the same coordinates.

### 4. `Components::OccupiesCell`

```ruby
crate.add_component(Components::OccupiesCell.new(col: 12, row: 7))
```

Marks the cell solid while the node is in the tree and clears it when the node
leaves. This is the answer to the question `docs/plans/possible-todos.md` left
open — it records that `TileWorld` deliberately exposes no bare `set_solid`
because "a solidity change without the drawn tile is an invisible wall".

**A component tied to a node is what closes that hole.** The node draws the
crate; the component makes its cell solid; remove the node and both go. There is
no state where something blocks and nothing is there. A bare `set_solid` stays
unexposed, and the tile Tiled drew underneath stays whatever the designer drew.

What it does not solve is a `Navigator` already walking a route through that
cell. `possible-todos.md` records that it stops at the new wall and reports
`on_blocked` by `:tiles` with nothing saying why, and this plan does not change
it.

## The object layer: parsed, not wired

**Decided:** the parser reads object layers into records, the transform
normalises them, and nothing builds a node from them
([decision 11](README.md#decisions-already-taken)).

**What the format holds.** An `<objectgroup>` has a `draworder` of `index` or
`topdown`, and holds `<object>` elements. An object has an id, a name, a **type**
(Tiled's word for its class), a position, a size, a rotation in degrees, an
opacity, a visibility, optional custom properties, and one of six shapes:
rectangle (the default, no child element), `<ellipse/>`, `<point/>`,
`<polygon points="…"/>`, `<polyline points="…"/>` or `<text>`. An object with a
`gid` is a **tile object** — it draws a tile rather than a shape.

A `template` attribute names a `.tx` file the object borrows everything from,
with its own attributes taking priority. An object element in a map can
therefore be almost empty and still mean something.

The bottom-left origin and the rotation point are the two traps, and
[the objects section](#objects-one-record-in-the-games-coordinates) says where
they are dealt with.

**What the design already provides.** The parser produces `Tiled::ObjectLayer`
and `Tiled::Object`; the transform turns them into `MapObject`s in the game's
coordinates; `map.objects` hands them out; `MapObjects` is the registry; the
slots say where a built node goes; `Properties` carries what the designer
attached. The step that is not here is one call:

```ruby
factory.spawn_into(slots[:actors], map.objects)
```

**What is deliberately unresolved,** and why it is not guessed at now:

- **Which slot an object belongs in.** Its own object layer's position in the
  layer order is the obvious answer, and it is probably right — but it makes
  every object layer a slot, and nothing has built a map that wants that yet.
- **What happens on a scene reload.** A chest that was opened must not come back
  full. That is `Components::Identity` and the save format's problem, and it
  wants a real game to be designed against.
- **Whether an object's class maps to a node or to a component.** Both are
  defensible, and the answer will be obvious once two games have wanted it.

CLAUDE.md's test applies here and is the reason to stop: *what does a caller
using both look like, and does anything exercise it?* Nothing in this repo has
yet built a scene that wants objects from a map. Building the wiring before that
caller exists is how two subsystems end up needing a hook whose only job is
handing one's data to the other.

## Considered and rejected

### Grow `TileMap.parse` in place

It is 25 lines, and multiple tilesets plus CSV is maybe 30 more. Tempting, and
it is what a smaller request would deserve.

It fails at the third feature. Group layers change what a layer index means, and
that meaning is depended on by `TileMapLayer`, `TileMapRenderer`, `TileWorld`
and the shared contract. Infinite maps change what a coordinate means.
Collections of images change what a tileset *is*. Each of those is a second
special case inside a class that also answers `solid_at?`, and the object layer
has nowhere at all to go.

### Convert `.tmx` to an rgame format at build time

Godot and Unity both import rather than parse
([prior art](02-prior-art.md#godot)). An offline converter would make the
runtime trivial and the startup cost zero.

It fails on this project's shape. There is no asset pipeline and no build step
between a designer saving a map and a game running it, and adding one would mean
a game cannot load a map a player made. `Tiled::Map.parse` taking a String is
also what keeps the specs headless and file-free, and a converter would put a
build artifact between the spec and the thing it tests.

**A runtime cache is a different proposal** and is left open rather than
rejected: it fills itself on first load, so a miss just parses and a player-made
map still works. What keeps it open is
[the transform's output being plain data](#what-the-transform-produces-and-why-it-is-plain-data),
and what keeps it shut is that nothing measures as slow.

### Keep `map.tileset` working for single-tileset maps

A reader that returns the only tileset and raises when there are two. Softer than
a rename, and every current caller keeps working.

It fails on someone else's map. A method whose meaning depends on the file
raises in the field and never in the checkout, and every consumer is in this
repo anyway ([decision 9](README.md#decisions-already-taken)).

### A parallel `TiledMap` class, leaving `TileMap` alone

Build the new reader beside the old one and migrate callers gradually.

It fails the same way every parallel implementation does: two answers to "what is
in the way", both green in isolation, and the composition nobody wrote. CLAUDE.md
has the worked example, and it cost six steps to undo.
