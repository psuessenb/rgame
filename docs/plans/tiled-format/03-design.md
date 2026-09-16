# The design

## The two halves

```
  .tmx / .tsx / .tx
        |
        |  REXML, stdlib only, no graphics
        v
  RGame::Engine::Tiled::*        a faithful reading of the file
        |   Map, Tileset, Tile, TileLayer, ImageLayer,
        |   GroupLayer, ObjectLayer, Object, Properties
        |
        |  flatten, resolve gids, build the dense grid
        v
  RGame::Engine::TileMap         what actors and the renderer ask
        |   + Engine::Tileset
        |
        |  duck-typed, the 'a tile map' contract
        v
  RGame::Core::TileMapRenderer   bakes and draws
```

**The top half asserts nothing about games.** It answers "what does this file
say", keeps Tiled's names and Tiled's coordinates, and has no opinion about
solidity, draw order or cameras. That is what makes it testable against a file
Tiled wrote, and what gives an object layer somewhere to live.

**The bottom half asserts nothing about files.** It answers "is this cell
solid", "how big is the world", "what gid is at (3, 7)". It keeps the flat layer
index the scene tree needs and the dense `Util::Tensor` the C collision stack
reads.

Today one class does both, which is why every new attribute has to be threaded
through one constructor and why `above` is read by a method that knows its name.

## `Engine::Tiled` — the faithful parse

One class per element, following [pytmx and tmxlite](02-prior-art.md#pytmx-and-tmxlite).
Sketched, not final:

```ruby
module RGame::Engine::Tiled
  Map         # orientation, render_order, infinite?, width, height,
              # tile_width, tile_height, background_color, class_name,
              # properties, tilesets (Array<TilesetRef>), layers (Array, the tree)
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

`Tiled::Map.parse(string)` takes a String and touches no files, as
`TileMap.parse` does today. `Tiled::Map.load(path)` adds the file plumbing:
following each `<tileset source>` to its `.tsx`, resolving relative to the file
that named it, and following each `<object template>` to its `.tx`.

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

`above` becomes an ordinary property, and `TileMap.layer_flag?`
([F9](01-current-state.md#f9)) is deleted.

## Gids, tilesets, and where the flip lives

A gid resolves to a tileset by the rule every engine in
[prior art](02-prior-art.md#what-they-agree-on) uses: the last tileset whose
`firstgid` does not exceed it. Tilesets are held in `firstgid` order, and the
search is a small reverse scan — there are rarely more than a handful, and a
binary search would be slower.

```ruby
map.tilesets              # => [Tileset, Tileset]  in firstgid order
map.tileset_for(gid)      # => the Tileset holding it, or nil for gid 0
tileset.local_id(gid)     # => gid - firstgid
tileset.include?(gid)     # => firstgid <= gid < firstgid + tile_count
```

### Where the flip lives

**In a second plane, parallel to the gid grid, allocated only when the map uses
one.**

```ruby
map.gid(layer, col, row)    # the clean gid — never carries a flag
map.flip(layer, col, row)   # 0..7; 0 for an unflipped tile, and for every
                            # cell of a map that has none
```

`TileMap` holds `@tiles` (a `Util::Tensor` of clean gids, as today) and
`@flips` (a second `Util::Tensor`, or `nil`). A map with no flipped tile
allocates nothing and `flip` answers 0 from the `nil` check, so the common map
pays nothing and the contract stays the same shape either way.

The 0..7 value is the eight-element dihedral group Tiled can express, as
`(diagonal << 2) | (vertical << 1) | horizontal`. Drawing it means a rotation of
0, 90, 180 or 270 degrees and an optional mirror — `renderer.rotated` and a
negative scale on `image_at` cover all eight, and
[F6](01-current-state.md#f6) says the bake absorbs both.

**The exact mapping from the three bits to an angle and a mirror is pinned by
tests against a map Tiled wrote, not asserted here.** Tiled's rule is that the
diagonal flip happens first and is an x/y axis swap, then horizontal, then
vertical; getting a rotation backwards produces a picture that looks deliberate,
which is precisely why `test/test_transform.c` asserts on coordinates rather than
matrix entries.

And the mask becomes `0x0FFFFFFF`, clearing bit 29 as
[F3](01-current-state.md#f3) requires.

### Rejected: packing the flip bits into the gid

Keep the raw gid in the one Tensor and let each reader mask. It costs no second
plane and no branch.

It fails on the reader that forgets. `gid` is read by solidity, by the bake, by
the animated-tile pass, by `StubTileMap`, and by any game that looks at a cell. A
reader that skips the mask gets a local id in the hundreds of millions — not an
error, just the wrong tile or a `nil` out of the image array three calls later.
A rule every caller must remember is the design CLAUDE.md rejects, and the second
plane costs 8 bytes a cell only on maps that use it.

### Rejected: a tile id per orientation, Godot-style

Generate an extra tileset entry for each orientation a map actually uses, so a
flipped tile is just a different id.

It makes a tileset's ids depend on which map loaded it. Two maps sharing one
`.tsx` would disagree about what tile 140 is, and `Image#tiles` slices by index.

## Layers: the tree, the flat index, and what stays stable

Tiled nests. rgame's scene tree needs a flat, ordered list, because
`TileMapLayer` mounts one node per layer and the actors sit in a gap between
two of them.

**So the tree flattens on load, depth first, in Tiled's own order.** A group
contributes no index of its own; its children do, in place. Going down, a group
multiplies its children's opacity and ANDs its visibility — which is what Tiled
shows you in the editor.

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

Each layer carries what the renderer needs:

```ruby
layer.visible?    # false => not drawn, and not baked
layer.opacity     # 0.0..1.0, already multiplied down the group tree
layer.kind        # :tile, :image, :object
layer.properties  # incl. 'above'
```

A hidden layer still counts for **collision**, as every layer does today. That
is deliberate and worth stating out loud: Tiled's `visible` is an editor and
render setting, and a designer who hides the obstacles layer to see the ground
underneath has not made the walls passable.

## Infinite maps and the origin shift

Chunks are read, the bounding box of the non-empty ones across **every** layer is
taken, and the result is written into an ordinary dense grid. The map's origin
moves to that corner.

```ruby
map.origin_col   # => -16 for a map painted west of Tiled's origin; 0 for a fixed map
map.origin_row   # => -32
```

Two rules make this safe rather than a trap.

**The bounding box is taken across all layers at once**, never per layer.
Per-layer bounds would give two layers different origins, and the gid at
`(3, 7)` would mean two different places.

**Every coordinate the file states is shifted by the same amount, in one
place.** That is object positions today (parsed, unused) and image-layer offsets.
The shift is a single method, and the `origin_col`/`origin_row` readers exist so
that a game showing Tiled's own coordinates can shift back.

## The runtime view

```ruby
class RGame::Engine::TileMap
  attr_reader :width, :height, :tile_width, :tile_height,
              :pixel_width, :pixel_height,
              :tilesets, :properties, :origin_col, :origin_row

  def self.load(tmx_path)     # => [map, image_paths]
  def self.parse(tmx_string)  # => map, with no tilesets attached
  def self.from_tiled(tiled_map)

  def layer_count
  def layer(index)            # => TileMap::Layer
  def layer_index(name_or_path)
  def gid(layer, col, row)
  def flip(layer, col, row)
  def in_bounds?(col, row)
  def tileset_for(gid)
  def solid_tile?(col, row)
  def solid_at?(world_x, world_y)
  def image_layers            # => Array<Tiled::ImageLayer>
  def objects                 # => Array<Tiled::Object>, every object layer, flattened
end
```

`load` returns **`[map, image_paths]`** rather than `[map, image_path]` — an
Array of paths, one per tileset, in `firstgid` order, and for a
collection-of-images tileset a nested Array, one per tile. Two values for the
same reason as today: the map is the grid, and the paths are where its pixels
live. The engine layer may not hold a texture ([constraint 1](README.md#hard-constraints)).

`Engine::Tileset` keeps its name and grows what a sheet actually has:

```ruby
class RGame::Engine::Tileset
  attr_reader :firstgid, :columns, :tile_width, :tile_height,
              :spacing, :margin, :tile_count, :offset_x, :offset_y,
              :image_source, :tile_image_sources, :animations, :properties
  attr_accessor :solid_ids

  def local_id(gid)
  def include?(gid)
  def solid?(gid)
  def frame_local_id(local, ms)
  def tile_class(local)        # the tile's Tiled class, or nil
  def tile_properties(local)   # => Properties
  def collection?              # one image per tile, no sheet
end
```

## What the renderer changes

```ruby
RGame::Core::TileMapRenderer.new(map, images)
```

`images` becomes an Array parallel to `map.tilesets`, each entry the tiles of one
tileset indexed by local id. Resolving a gid is then two lookups instead of one,
both done once per tile at bake time.

Three additions, all inside the existing bake-and-replay shape:

- **A flipped tile** is baked under a `rotated` push and/or a negative scale.
  Per [F6](01-current-state.md#f6) this costs bake time only.
- **A layer's opacity** is a tint on `Recording#draw` and a colour on the
  animated `image_at`, per [F7](01-current-state.md#f7).
- **A hidden layer** returns before baking, so it costs nothing at all.

The `a tile map` contract grows `flip`, `tilesets`, `layer(index)` and the
`visible?`/`opacity` readers, and `StubTileMap` grows them in the same commit
([constraint 6](README.md#hard-constraints)). `map.tileset` singular goes;
[F10](01-current-state.md#f10) counts the sites.

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

A collection-of-images tileset has no sheet. Each `<tile>` names its own file, so
the asset loader loads one image per tile and the local id indexes that Array —
which is the same Array shape the sheet case produces, so the renderer never
learns which kind it has.

## Nodes on a map

Four pieces, from smallest to largest.

### 1. Tile coordinates, on `TileWorld`

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

```ruby
slots = TileMapLayer.mount(world, gaps: { actors: nil, bridge: 'river' })
slots[:actors]     # the default gap, at the first layer flagged `above`
slots[:bridge]     # a node between 'river' and whatever follows it
```

`mount` hands out z slots, so the gaps have to be declared when it runs. Calling
it with no `gaps:` returns a slots object that still answers `[:actors]`, so
every existing scene changes by one character.

### 3. `MapObject` and the factory registry

```ruby
MapObject = Data.define(:id, :name, :class_name, :x, :y, :width, :height,
                        :rotation, :gid, :shape, :points, :properties)

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
point of the shape.

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

**Decided:** the parser reads object layers into records, and nothing builds a
node from them ([decision 11](README.md#decisions-already-taken)).

**What the format holds.** An `<objectgroup>` has a `draworder` of `index` or
`topdown`, and holds `<object>` elements. An object has an id, a name, a **type**
(Tiled's word for its class), a position, a size, a rotation in degrees, an
opacity, a visibility, optional custom properties, and one of six shapes:
rectangle (the default, no child element), `<ellipse/>`, `<point/>`,
`<polygon points="…"/>`, `<polyline points="…"/>` or `<text>`. An object with a
`gid` is a **tile object** — it draws a tile rather than a shape.

**Three traps worth writing down now**, because each is a wrong position rather
than an error:

1. **A tile object's `(x, y)` is its bottom-left corner**, while a rectangle's is
   its top-left ([Tiled's reference](https://doc.mapeditor.org/en/stable/reference/tmx-map-format/#object)).
   Treating them alike puts every tile object one tile-height too low.
2. **Rotation is clockwise about `(x, y)`**, not about the object's centre — so
   for a tile object it is about the bottom-left corner.
3. **A `template` attribute names a `.tx` file** the object borrows everything
   from, with its own attributes taking priority. An object element in a map can
   therefore be almost empty and still mean something.

**What the design already provides for it.** The parser produces
`Tiled::ObjectLayer` and `Tiled::Object`; `TileMap#objects` flattens them;
`MapObject` is the record a factory takes; `MapObjects` is the registry; the
slots say where a built node goes; `Properties` carries what the designer
attached. The step that is not here is one method:

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
a game cannot load a map a player made. `TileMap.parse` taking a String is also
what keeps the specs headless and file-free, and a converter would put a build
artifact between the spec and the thing it tests.

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
