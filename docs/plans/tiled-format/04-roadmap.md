# Roadmap

**Steps 0–5 are implemented.** Steps 6–9 are deliberately
rough and get re-planned once the step beneath each exists.

## Dependency shape

```
0 map requirements ───────────────────────────────────────────┐  (authoring runs in parallel)
                                                              │
1 Properties ─→ 2 Tiled tilesets ─→ 3 Tiled map ─→ 4 TileMap ─┼─→ 5 renderer + images ─┐
                                                              │                         ├─→ 8 authored map + example ─→ 9 fold back
                                                   4 ─→ 6 image layers + slots ─┐       │
                                                                                ├─→ 7 nodes on a map ─────────────────┘
                                                              5 ────────────────┘
```

Step 0 is first because the map is authored by hand, off this branch, while
steps 1–5 are built. Step 8 is where the two meet.

## The invariant every step preserves

> **`examples/assets/town.tmx` parses to the same grid, and the four examples
> that draw it draw the same thing.**

It is the only map in the repo ([F11](01-current-state.md#f11)), it is asserted
by `spec/example_assets_spec.rb`, and the four examples that draw it each have a
drive script. Those runs need no `--seed`: there is no RNG, the map is a file,
and the timestep is fixed, so two runs already match byte for byte. So a rebuilt
parser has a fixed point to land on from the first commit, and a step that moves
it says so rather than being noticed at step 8.

Run it per step:

```
bundle exec rspec spec/example_assets_spec.rb
ruby tools/drive_test_project.rb examples/pathfinding/main.rb --ticks 240 --texts
ruby tools/drive_test_project.rb examples/scroll_map/main.rb --ticks 240
```

And the standing one, which no step may break
([constraint 3](README.md#hard-constraints)):

```
bundle exec rspec spec/rgame/no_graphics_spec.rb
```

## What lands early, if the plan is abandoned

| Step | Defect it closes |
|---|---|
| 1 | Every Tiled custom property becomes readable; `above` stops being a special case ([F9](01-current-state.md#f9)) |
| 2 | Margin, spacing, embedded tilesets, tile class — a downloaded sheet stops rendering wrong ([F5](01-current-state.md#f5)) |
| 3 | CSV, XML, gzip, plain base64, chunks, multiple tilesets — four silent-wrong-output bugs become supported input or loud errors ([F1](01-current-state.md#f1)–[F4](01-current-state.md#f4)) |
| 4 | A gid from a second tileset stops resolving through the first ([F2](01-current-state.md#f2)); every tile’s class and properties become readable |
| 5 | Flipped tiles draw flipped; a sheet with spacing stops rendering smeared ([F5](01-current-state.md#f5)); hidden layers stop drawing |

Steps 1–3 are useful on their own even if 4 and 5 never land, because until then
nothing consumes them and nothing breaks.

---

## Step 0 — the requirements for the acceptance map

**No code.** One document, handed over so the map can be authored in Tiled while
the parser is built.

The map is the thing that catches what generated fixtures cannot: `TiledFixture`
writes what *this* parser reads, so the two agree by construction
([F11](01-current-state.md#f11)). Only a file Tiled itself wrote breaks that
circle.

### Shape

`docs/plans/tiled-format/map-requirements.md`, and it states for each
requirement: **what to do in Tiled**, **why the code needs it**, and **how step 8
checks it**. Sketch of the list:

| # | Requirement | Exercises |
|---|---|---|
| R1 | Two tilesets, both external `.tsx`, both used by at least one tile | gid → tileset resolution |
| R2 | A third tileset **embedded** in the `.tmx` | the no-`source` path |
| R3 | One tileset with non-zero `margin` **and** `spacing` | [F5](01-current-state.md#f5) |
| R4 | One tileset that is a **collection of images** | the no-sheet path |
| R5 | At least one tile flipped horizontally, one vertically, one rotated 90°, and one flipped diagonally | all 8 orientations of the flip table |
| R6 | Layer data saved as **CSV** | the encoding branch |
| R7 | A second map file, identical content, saved as **base64 + gzip** | two encodings, one expected grid |
| R8 | A **group** layer containing at least two tile layers | flattening and index stability |
| R9 | One layer with `visible` off, and one with `opacity` below 1 | the render settings |
| R10 | An **image layer** | the new node |
| R11 | A tile with an **animation** of at least two frames | unchanged behaviour, new parser |
| R12 | Solid tiles marked with collision shapes in the collision editor | unchanged behaviour |
| R13 | Custom properties of every type on something: `string`, `int`, `float`, `bool`, `color`, `file`, `object`, `class` | the whole property table |
| R14 | A multi-line `string` property | the text-node form, not the `value` attribute |
| R15 | An **object layer** with a rectangle, a point, an ellipse, a polygon and a **tile object** | the records, incl. the bottom-left origin trap |
| R16 | A third map file, same content, saved **Infinite**, painted west and north of the origin | chunks and the origin shift |
| R17 | Larger than 640×480 on both axes | so it can be an example that scrolls |

Plus the standing asset rule: **every tileset image is CC0 or authored here**,
with nothing in between, and `examples/assets/README.md` gets a source and
licence entry for each — see its own opening paragraph for why.

### Verify

The document exists, names every requirement with its Tiled menu path, and says
what step 8 will report when one is missed. Nothing to run.

**Landed.** [`map-requirements.md`](map-requirements.md) states 19
requirements, each with what to do in Tiled, why the code needs it, and the
message step 8 prints when it is missing. It also fixes the files to hand over,
their directory (`examples/assets/tiled_tour/`), and the order to build them in,
because three of them are Save As copies of the first. No code; nothing to run.

What the sketch got wrong:

- **An Infinite twin only matches if the chunks line up.** Tiled stores an
  infinite map in 16×16 chunks, so a bounding box taken over chunks is
  chunk-aligned. A 60×40 map, or an offset of a few tiles, flattens to a larger
  grid than its fixed twin, and step 4's rule 11 fails on the map rather than
  the code. The map is therefore 64×48 (R17), shifted by exactly 16 tiles (R16),
  with the ground filled edge to edge. Whether step 3 bounds by chunk or by
  non-empty cell is now [open question 5](README.md#open-questions).
- **Tiled has no key for a lone diagonal flip.** A quarter turn sets the
  diagonal and horizontal bits together. R5 asks for the eight orientations as
  turns and mirrors, which covers all eight bit combinations. Step 8's sketch
  suggested "Shift+X", which is not a Tiled shortcut; corrected in place.
- **Class members at their default value are not in the `.tmx`.** Tiled writes
  only the members that differ, and the defaults live in the project file. R13
  asks for every member set, and the project file ships with the map. What the
  parser does about defaults is [open question 6](README.md#open-questions).
- **Three requirements were missing.** R18, an object from a template, because
  step 3's rule 9 resolves templates and nothing Tiled-written exercised it.
  R19, Tiled's own exported picture of the map: step 5's rule 4 pins the
  orientation table against "what Tiled shows", and this is the only file that
  says what that is. And a polyline and a text object in R15, both in the
  design's object record.
- **The embedded tileset carries a drawing offset (R2)**, the `<tileoffset>`
  [decision 6](README.md#decisions-already-taken) adds. Step 5 has no rule for
  drawing it, and needs one when it is re-read before starting.

---

## Step 1 — `Engine::Tiled::Properties` (pure)

First because everything else carries one. Also the smallest thing that deletes
an existing special case, so it lands useful on its own.

### Shape

```ruby
module RGame::Engine::Tiled
  class Properties
    EMPTY = new({}).freeze

    def self.parse(element, base_path: nil)   # a <properties> element, or nil
    def [](name)
    def fetch(name, *default)
    def key?(name)
    def each(&)
    def to_h
    def empty?
  end
end
```

### The rules the tests pin

1. A missing `<properties>` element yields `EMPTY`, never `nil`. A caller never
   checks.
2. Each Tiled type casts to the Ruby type in
   [the design's table](03-design.md#properties), at parse time.
3. `type` absent means `string`.
4. A `string` whose value is in the element's **text** rather than its `value`
   attribute reads the same — that is how Tiled writes a multi-line value.
5. A `color` reads from both `#AARRGGBB` and `#RRGGBB`, alpha first in the long
   form. `Util::Color` has no string form — `coerce` takes nil, an Array or a
   Color — so this conversion is the parser's and belongs nowhere else.
6. A `file` resolves relative to the file that named it, like every other path.
7. An `object` property stays an `Integer` id. Resolving it would need the whole
   map, and nothing asks yet.
8. A `class` property nests a `Properties`, recursively.
9. An unknown `type` raises, naming the property and the type.
10. `fetch` with no default raises naming the property.

### Tests

`spec/rgame/engine/tiled/properties_spec.rb` — one example per type; the
text-node string; the `#AARRGGBB` order; a nested class property two deep; a
missing element; an unknown type; `fetch` raising; a relative `file` from a
subdirectory.

### Verify

`bundle exec rspec spec/rgame/engine/tiled/properties_spec.rb` is green, and
`bundle exec rubocop lib/rgame/engine/tiled/properties.rb` is clean. Nothing
else in the tree references it yet.

**Landed.** `RGame::Engine::Tiled::Properties` in
`lib/rgame/engine/tiled/properties.rb`, with the sketched interface plus
`Enumerable`, `==` and `hash`, and `Tiled::FormatError` for every refusal.
`require "rgame"` loads it; nothing else in `lib/` calls it yet. The spec has 29
examples, one per type and one per rule. `rake spec` ran 2453 examples and
`rake spec:core` 427, both with no failures. The invariant held: `example_assets_spec`
and `no_graphics_spec` stayed green, and the `pathfinding` and `scroll_map` drives
reported byte for byte what they reported on `main`. CI's first Windows run
failed one example: `/srv/tiles.png` has no drive letter, so Windows does not
call it absolute. The spec now builds its path with `File.expand_path`, and
steps 2 and 3 need the same care in every path they assert.

What the sketch got wrong:

- **`base_path:` became `source_path:`**, the file that named the element
  rather than its directory. Steps 2 and 3 already sketch `source_path:` for
  `Tileset.parse` and `Map.parse`, and one name across all three means a caller
  passes along the path it holds.
- **Rule 9 was too narrow.** An unknown type is not the only value the parser
  cannot read. An `int` or `float` that does not parse, a `bool` other than
  `true` or `false`, and a malformed colour also raise `FormatError`. The
  message names the property, the value and, when it knows it, the file.
- **Two types have an empty form.** Tiled writes `value=""` for a colour it
  has none for, and that reads as `nil`. An empty `file` value stays `''` rather
  than resolving to the directory of the file that named it.
- **A new public name fails the docs coverage spec.** `spec_core/api_docs/coverage_spec.rb`
  requires every public class to appear in `docs/api/` or carry `@api private`.
  Documenting a class nothing hands to a game would describe unreachable API,
  so the `Tiled` module carries `@api private` for now. Step 9 removes the tag
  when `docs/api/tile_maps.md` documents `Properties`, and says so in its list.
- **A class property's `propertytype` is dropped.** It names the custom class,
  and nothing asks for it yet. Adding it later means `Properties` gains a
  `class_name`, which no caller has to change for.
- **[Open question 6](README.md#open-questions) is settled:** the parser reads
  what the file states, and the gap is documented rather than closed.

---

## Step 2 — `Engine::Tiled::Tileset`, `Tile` and `.tsx` loading (pure)

Tilesets before maps, because a map references them and because this step alone
fixes the downloaded-sheet bug ([F5](01-current-state.md#f5)).

### Shape

```ruby
module RGame::Engine::Tiled
  class Tileset
    Image = Data.define(:source, :width, :height)

    def self.parse(tsx_string, source_path: nil)
    def self.load(tsx_path)

    attr_reader :name, :class_name, :tile_width, :tile_height,
                :spacing, :margin, :tile_count, :columns,
                :image, :offset_x, :offset_y, :tiles, :properties

    def collection?    # no sheet image; every tile names its own
    def tile(local_id) # => Tile, or nil
  end

  class Tile
    attr_reader :id, :class_name, :properties, :image, :frames, :collision_shapes
    def animated?
  end

  Frame = Data.define(:tile_id, :duration_ms)
end
```

### The rules the tests pin

1. `spacing` and `margin` default to 0, `columns` and `tile_count` to what the
   file says.
2. A tileset with `<image>` is a sheet; one whose `<tile>`s each carry an
   `<image>` is a collection, and `collection?` tells them apart.
3. `<tileoffset x y>` reads into `offset_x`/`offset_y`, defaulting to 0.
4. A tile's class reads from **`type` or `class`** — Tiled 1.9 wrote `class` and
   later versions write `type`, and a parser that reads one drops the other.
5. `collision_shapes` holds the tile's `<objectgroup>` objects with their class
   and properties. The geometry is kept in the parse and discarded by the runtime
   view ([decision 7](README.md#decisions-already-taken)).
6. Frame durations stay in **milliseconds**, as the file states them. Converting
   to seconds happens at the runtime boundary, once.
7. An image `source` resolves relative to the `.tsx`.

### Tests

`spec/rgame/engine/tiled/tileset_spec.rb` — margin and spacing; a collection;
a tile offset; `type` and `class` both reading as the class; collision shapes
with properties; an animation; `columns` absent; a relative image path from a
subdirectory. `TiledFixture` grows an emitter for each.

### Verify

The new specs are green. `examples/assets/tileset.tsx` parses through the new
class to the same tile count, the same animated ids and the same solid ids as
`Engine::Tileset.parse` produces today — asserted as a temporary example in the
spec, deleted in step 4 when the old class goes.

**Landed.** `Tiled::Tileset`, `Tiled::Tile`, `Tiled::Frame` and `Tiled::Object`
live in `lib/rgame/engine/tiled/`, with the sketched interface. `Tileset::Image`,
`Tile`, `Frame` and `Object` are `Data` records. `tileset_spec.rb` has 39
examples and `object_spec.rb` 11. `rake spec` ran 2503 examples and
`rake spec:core` 430, both with no failures. The invariant held: the
`pathfinding` and `scroll_map` drives reported byte for byte what they report on
`main`. The temporary example reads `examples/assets/tileset.tsx` to the same
columns, tile size and image, the same animated ids and the same solid ids as
`Engine::Tileset`, and counts 132 tiles.

What the sketch got wrong:

- **Collision shapes are objects, so `Tiled::Object` landed here.** Rule 5 needs
  a type for them, and it is the one step 3 sketches for object layers. Step 3
  reuses `Tiled::Object.parse` and adds template resolution to it. It does not
  write a second object parser.
- **An embedded tileset needs a parse that takes an element.**
  `Tileset.from_element(element, source_path:)` reads a `<tileset>` wherever it
  sits. `parse` calls it on a `.tsx`'s root, and step 3 calls it on an embedded
  tileset with the map as `source_path`.
- **Rule 1 had no answer for a missing `columns` or `tilecount`.** Both are
  counted from the image, margin and spacing included, when the file leaves
  them out. A collection counts its tiles and has 0 columns. A sheet whose image
  states no size to count from raises.
- **Reading numbers and paths is shared.** `Tiled::Attributes` reads integers,
  floats and relative paths, and raises `FormatError` naming the element, the
  attribute and the file. `Properties` now resolves `file` values through it,
  and step 3 should use it for every attribute it reads.
- **The `Tiled` module and `FormatError` moved to `lib/rgame/engine/tiled.rb`.**
  The docs coverage spec reads `@api private` from the first file that opens a
  module. Once several files opened `Tiled`, that first file depended on require
  order. Every file under `tiled/` requires `../tiled`, so the tagged file always
  comes first.
- **More refusals than the sketch named.** A root other than `<tileset>`, XML
  that is not well-formed, a missing tile size, an unreadable number, an image
  embedded as data, a frame with no `tileid` or `duration`, and polygon points
  that are not pairs all raise `FormatError`.
- **`TiledFixture` grew one emitter, not one per feature.** `write_tileset`
  writes a `.tsx` for the `load` examples. Every other example parses inline XML,
  which shows the attribute under test in the example itself.
- **Ignored for now:** a tile's sub-rectangle in an image collection (Tiled 1.9's
  `x`, `y`, `width`, `height` on `<tile>`), `probability`, `objectalignment`,
  `<grid>`, `<wangsets>` and `<transformations>`. Only the sub-rectangle changes
  what a tile draws, and the acceptance map does not ask for it.

---

## Step 3 — `Engine::Tiled::Map` and the layer tree (pure)

The bulk of the parser, and where every encoding and layer kind lands. It is one
step because a map with one encoding and no layer tree is not a checkpoint
anybody could use.

### Shape

```ruby
module RGame::Engine::Tiled
  class Map
    def self.parse(tmx_string, source_path: nil)
    def self.load(tmx_path)

    attr_reader :orientation, :render_order, :width, :height,
                :tile_width, :tile_height, :background_color,
                :class_name, :properties, :tilesets, :layers,
                :origin_col, :origin_row
    def infinite?
  end

  TilesetRef  = Data.define(:firstgid, :tileset)
  class Layer       ; end   # id, name, class_name, visible?, opacity, properties
  class TileLayer   < Layer ; end   # width, height, gids (flat, raw)
  class ImageLayer  < Layer ; end   # image, repeat_x?, repeat_y?, offset_x, offset_y
  class GroupLayer  < Layer ; end   # layers
  class ObjectLayer < Layer ; end   # draw_order, objects
  class Object      ; end   # see 03-design.md
end
```

### The rules the tests pin

1. **Every encoding decodes to the same gids**: XML `<tile gid>` elements, CSV,
   and base64 with no compression, with gzip and with zlib. One expected Array,
   five inputs.
2. **Zstd raises**, naming the compression and saying rgame does not carry that
   dependency ([constraint 4](README.md#hard-constraints)).
3. **A non-orthogonal `orientation` raises**, naming the orientation and the
   file ([decision 1](README.md#decisions-already-taken)).
4. **Several `<tileset>` elements all read**, in `firstgid` order, external and
   embedded alike.
5. **The gid mask is `0x0FFFFFFF`.** `gids` holds raw values including the three
   flip bits; bit 29 is cleared even on an orthogonal map
   ([F3](01-current-state.md#f3)).
6. **Chunks flatten.** The bounding box is taken across every layer at once, and
   `origin_col`/`origin_row` record the shift. A fixed map has both 0.
7. **Groups nest and carry down.** A child's effective opacity is the product
   down the tree and its visibility the conjunction.
8. **`layers` is the tree**, in Tiled's order. Flattening is the runtime view's
   job, not the parser's.
9. **A `<template>` on an object resolves** against the `.tx` it names, with the
   object's own attributes winning.
10. Every path resolves relative to the file that named it — the `.tsx` to the
    `.tmx`, the image to the `.tsx`, the `.tx` to the `.tmx`.
11. **Object layers parse into records and go no further.** `ObjectLayer` and
    `Object` come out with their class, position, shape and properties; nothing
    in the tree builds a node from one
    ([decision 11](README.md#decisions-already-taken)). A tile object keeps the
    coordinates the file states, bottom-left origin and all. Converting them is
    the transform's job, in [step 4](#step-4--tilemap-and-the-transform), so that
    no caller ever does it.

### Tests

`spec/rgame/engine/tiled/map_spec.rb`, with `TiledFixture` grown to emit each
encoding, chunks, groups, image layers and object layers. One `describe` per
rule above. The encoding examples share one expected grid, written once —
five encodings asserted against five hand-written Arrays would drift.

### Verify

New specs green, and `examples/assets/town.tmx` reads through `Tiled::Map.load`
to the same two layers, the same 60×40 size and the same gids the current parser
produces — again as a temporary example, deleted in step 4.

**Landed.** `Tiled::Map`, `TilesetRef`, `Layer` and its four subclasses,
`LayerData` and `Template` live in `lib/rgame/engine/tiled/`. `map_spec.rb` has
70 examples, one `describe` per rule, and the five encodings share one expected
grid. `rake spec` ran 2573 examples and `rake spec:core` 430, both with no
failures. The invariant held: the `pathfinding` and `scroll_map` drives
reported byte for byte what they report on `main`. The temporary example reads
`examples/assets/town.tmx` to the same 60×40 size, the same two layers and the
same gids as `TileMap.load`, once the flip bits are masked off.

What the sketch got wrong:

- **`parse` reads files.** The design had `Map.parse` touch no files and `load`
  follow the references. But a map string names its tilesets and templates by
  path, so `parse` follows them relative to `source_path`, the way `Tileset`
  resolves its image. A map parsed without a `source_path` that names an
  external tileset or template raises, and says to load the map from its file.
- **Rule 7 needs both values.** Each layer keeps its own `visible?` and
  `opacity`, as the file states them. `effective_visible?` and
  `effective_opacity` fold in every group around it. Step 4 flattens the tree
  and should read the effective pair.
- **An infinite map's size is the box.** `Map#width` and `height`, and every
  `TileLayer`'s, are the box around the non-empty chunks. The `width` and
  `height` Tiled writes on an infinite map are the editor's view and are
  ignored. The origin lives on `Map` only, not on each `TileLayer` as
  `03-design.md` sketched, since rule 6 makes it the same for every layer. The
  box is bounded by whole chunks, not by the tiles inside them.
- **A tile template needed its gid moved.** A `.tx` numbers its gid from its
  own `<tileset firstgid>`. `Template#apply` shifts it to where that `.tsx`
  sits in the map, and raises when the map does not name that tileset.
  Properties merge by name, and each `file` value resolves against the file
  that states it, so a template's sound path points beside the `.tx`.
- **Shared pieces moved up.** `Tiled.root` reads a root element and refuses a
  wrong one or broken XML, for maps, tilesets and templates alike. `Tiled.gid`,
  `GID_MASK` and `FLIP_BITS` hold the gid layout, and `Object` clears bit 29
  with them too. `Attributes.color` reads the map's `backgroundcolor`, and
  `Properties` casts a `color` property through the same code.
- **More refusals.** A layer holding a different number of tiles than its size,
  CSV that is not numbers, data that does not decompress, an encoding or
  compression Tiled does not write, a missing `.tsx` or `.tx`, and a map with
  no size all raise `FormatError`.
- **Ignored for now:** `offsetx`, `offsety`, `parallaxx`, `parallaxy` and
  `tintcolor` on tile, object and group layers
  ([decision 5](README.md#decisions-already-taken)); an object layer's
  `color`; and the map's `nextlayerid`, `nextobjectid` and `parallaxorigin`.
  An image layer keeps its offset, which the design asks for.

---

## Step 4 — `TileMap` and the transform

The breaking step, and the one where Tiled's world becomes the game's. It is one
branch because [F10](01-current-state.md#f10)'s sweep crosses `spec/` and
`spec_core/`, and a contract that lands in two commits is a red suite in between.

### Shape

The full sketch is in [03-design.md](03-design.md#the-runtime-view). What changes
for callers:

| Was | Becomes |
|---|---|
| `map.gid(l, c, r)` | `map.tile(l, c, r)` — an rgame tile id, 0 for empty |
| `map.tileset`, and `Engine::Tileset` | gone — `map.solid?`, `map.tile_class`, `map.tile_properties` |
| `map.tileset.frame_local_id(local, ms)` | `map.frame_tile(tile, elapsed)`, in seconds |
| `map.above_layer?(i)` | `map.layer(i).above?` |
| `TileMap.load` → `[map, image_path]` | gone — the glue reads `Tiled::Map` and calls `from_tiled` |
| `TileMap.parse(tmx_string)` | gone — `Tiled::Map.parse` then `TileMap.from_tiled` |
| — | `map.orientation`, `map.tile_table`, `map.layer`, `map.layer_index`, `map.objects`, `map.image_layers` |

### Sub-steps

- **4a** — `TileMap.from_tiled` and the runtime view rebuilt on it, with its own
  specs. Nothing outside `lib/rgame/engine/` moves.
- **4b** — the `a tile map` contract rewritten, `StubTileMap` rebuilt against it,
  and the `map.tileset` sweep across `lib/`, `spec/` and `spec_core/`.

### The rules the tests pin

1. **Tile ids are dense and start at 1**, with 0 the empty cell, and
   `tile_count` reports how many the map's tilesets hold together.
2. **A gid from the second tileset resolves to the second tileset.** This is
   [F2](01-current-state.md#f2) asserted directly: `tile_table[id]` names the
   tileset and the local id, and the two never cross.
3. **`orientation` returns one of eight frozen values, never bits.** A map with
   no flipped tile allocates no plane and answers the identity everywhere.
4. **Layers flatten depth first**, groups contributing no index of their own,
   opacity multiplied down the tree and visibility conjoined.
5. **`layer_index` takes a name or a `'Group/child'` path**, and raises naming
   the available layers when it misses.
6. **`layer.above?` is read once from the property**, and a layer without it is
   false.
7. **A hidden layer still counts for `solid_tile?`.**
8. **`solid_tile?` and `solid_at?` answer exactly as they do today for
   `town.tmx`** — this is the invariant, asserted directly.
9. **`frame_tile` takes seconds.** Frame durations convert from Tiled's
   milliseconds once, at load, and the same animation resolves to the same tile
   as `Tileset#frame_local_id` does today.
10. **An object comes out in the game's coordinates**: a tile object's `(x, y)`
    is its top-left, the origin shift is applied to it and to every polygon
    point, and its `gid` has become a `tile`. See
    [the objects section](03-design.md#objects-one-record-in-the-games-coordinates).
11. **A fixed map and its Infinite twin build the same `TileMap`** — same tiles,
    same orientations, same object coordinates. This is what proves the shift
    happens in one place.
12. **A built map is plain data.** `initialize` takes flat Arrays, not a
    `Tensor`, and no `Tiled::*` object is reachable from a built map
    ([decision 13](README.md#decisions-already-taken)).

### Tests

Rewrite `spec/rgame/engine/tile_map_spec.rb`; delete
`spec/rgame/engine/tileset_spec.rb` with the class. Rewrite
`spec/support/shared_examples/a_tile_map.rb` and rebuild `StubTileMap` against
it, in the same commit ([constraint 6](README.md#hard-constraints)) — and
`spec_core/rgame/core/tile_map_renderer_spec.rb`, which hosts the same contract
from the other side. Both come out **shorter**: the contract loses `tileset`,
`local_id`, `firstgid` and `gid` and gains `tile`, `orientation`, `solid?` and
`frame_tile`.

Rule 12 is an example, not a comment: walk a built map's instance variables and
assert nothing under them is a `Tiled::*`.

### Verify

```
bundle exec rspec                 # every example, incl. example_assets_spec
bundle exec rspec spec/rgame/no_graphics_spec.rb
```

and the invariant's driven runs, byte-identical to their output before the
branch.

Two greps, both of which must find exactly one directory:

```
grep -rl REXML lib/rgame/engine/          # only lib/rgame/engine/tiled/
grep -rln 'Tiled::' lib/rgame/            # only tiled/, and the transform file
```

The second is [decision 12](README.md#decisions-already-taken)'s guard. It is
what stops the parse types leaking back out once someone needs "just one field"
from them.

**Landed.** 4a and 4b are one commit each. `TileMap.from_tiled` lives in
`lib/rgame/engine/tile_map/from_tiled.rb` and is the only file outside
`tiled/` that turns parse types into runtime ones. `TileMap` holds
`Orientation`, `TileSource`, `Source`, `Layer` and `ImageLayer`, and
`Engine::MapObject` and `Engine::Properties` sit beside it. `Engine::Tileset`,
its spec, `TileMap.load` and `TileMap.parse` are gone, and so are the
temporary blocks steps 2 and 3 left in the Tiled specs. `tile_map_spec.rb` has
67 examples, one `describe` per rule, and hosts the contract from a `.tmx`
string with an embedded tileset. `rake spec` ran 2604 examples and
`rake spec:core` 430, both with no failures, and `rake docs:coverage` reports
nothing undocumented. The `pathfinding` and `scroll_map` drives, and
`collision_tiles` and `jump_topdown` beside them, report byte for byte what
they reported before the branch. Rule 8 is asserted against
`spec/fixtures/town_solidity.txt`, the solid grid the old parser wrote, cell
for cell. The `REXML` grep finds only `tiled/` and `tiled.rb`.

What the sketch got wrong:

- **`Properties` had to leave the `Tiled` namespace.** Rule 12 forbids any
  `Tiled::*` object reachable from a built map, and decision 13 has the tile
  table holding `Properties`. Both hold because the value class is now
  `Engine::Properties`. `Tiled::Properties` is a module that parses into it.
- **The `Tiled::` grep finds three files, not two.** The glue in `game.rb`
  names `Tiled::Map`, as step 5's own sketch does. The guard's allowance is
  `tiled/`, the transform and the glue.
- **Seconds needed care at the boundaries.** Subtracting Float durations one
  by one moved a frame boundary by a rounding error. `TileMap` keeps each frame
  as the second it ends at, summed in whole milliseconds. It shows the same
  frame as the old arithmetic on every tick of a minute at 60 Hz. At an exact
  boundary such as 0.5 s the two can differ, because the old code truncated to
  whole milliseconds first.
- **Every layer kind takes an index.** `layer_count` counts tile, image and
  object layers, and `tile` answers 0 in a layer with no tiles. The `Tensor`
  holds planes for tile layers only. `TileMapLayer.mount` therefore mounts a
  node for an object or image layer too, which draws an empty recording. Step
  6 inherits that.
- **`MapObject` gained three fields.** `layer` is the index the object sits
  in, `orientation` carries a tile object's flips, since a dense tile id
  cannot, and `visible` is kept. Rule 10's rotation is settled: `(x, y)` is the
  top-left for every shape and `rotation` turns about it. `points` are absolute
  and not rotated.
- **`source` has two attributes, not three**: `path` and `parser_version`.
  `Tiled::Map` gained `source_path`, and `Tiled::PARSER_VERSION` starts at 1.
- **The glue refuses what it cannot slice.** A collection of images, or a
  sheet with a margin or spacing, raises `FormatError` in the loader rather
  than slicing wrong. The renderer draws every tile unturned, hidden layers
  included, at full opacity. Step 5 lifts all of it.
- **An `above` property that is not a bool raises.** The old reader took the
  String `"true"` too.
- **Two things went without replacement.** `Tileset#solid_ids=` let a game
  change solidity in code, and nothing replaces it. `TileMapLayer.mount` still
  takes `under:` as an index only, although `layer_index` now makes a name
  cheap.
- **The contract did not come out shorter.** It lost the tileset, `local_id`
  and `gid` and gained `tile`, `orientation`, `solid?`, `animated_tiles`,
  `frame_tile` and `layer(i).above?`: 13 examples, where there were 11.

Documented in `docs/api/tile_maps.md`, rewritten, and `docs/api/assets.md`. The
CHANGELOG lists the breaking changes under Changed and Removed.

---

## Step 5 — the renderer, and slicing a real sheet

Everything that turns the parsed map into pixels, in one branch because the image
slicing and the oriented draw are one change seen from two sides.

**Smaller than it looks**, because the tile table absorbed the part that would
have touched the renderer's interface: `TileMapRenderer.new(map, tiles)` keeps
taking one flat Array, indexed by tile id with `nil` at 0.

### Shape

```ruby
# Core — signature unchanged
RGame::Core::TileMapRenderer.new(map, tiles)
RGame::Core::Image#tiles(w, h, margin: 0, spacing: 0, count: nil, columns: nil)

# Glue, in RGame::Game's :tilemap loader — the only place that names both layers
tiled = RGame::Engine::Tiled::Map.load(path)
map   = RGame::Engine::TileMap.from_tiled(tiled)
tiles = build_tiles(tiled, map.tile_table)   # slice each tileset, lay it out by tile id
RGame::Core::TileMapRenderer.new(map, tiles)
```

### The rules the tests pin

1. `tiles` with `margin: 0, spacing: 0` returns exactly what it returns today,
   through the same C path.
2. `tiles` with margin and spacing cuts each tile from
   `margin + col * (w + spacing)`, and `count:` bounds the result.
3. **A collection-of-images tileset produces the same flat Array as a sheet**,
   so the renderer cannot tell them apart. This is the rule that says the glue
   absorbed the difference rather than passing it down.
4. An oriented tile bakes to what Tiled shows, for all eight values. **This is
   the table to get right**, and it is pinned against the authored map in step 8
   as well as against a fixture here.
5. A hidden layer bakes nothing and draws nothing.
6. A layer with opacity `o` replays tinted with alpha `o`, and its animated tiles
   draw with the same colour.

### Tests

`spec_core/rgame/core/tile_map_renderer_spec.rb` for the draw calls and the
framebuffer read-back that only the real renderer can do.
`spec_core/rgame/core/image_spec.rb` for margin and spacing, including the
guard that a sub-image cannot fall outside the sheet —
`spec_core/support/stub_image.rb` already refuses exactly what `Image#subimage`
refuses, and must keep doing so.

Orientation is checked by reading pixels back, not by counting calls: a rotation
the wrong way issues exactly the same number of draws.

### Verify

```
make ext-core && rake spec:core
rake spec
ruby tools/drive_test_project.rb examples/scroll_map/main.rb --ticks 240
```

and the frame `town.tmx` draws is unchanged.

**Landed.** One commit. `Image#tiles` takes `margin:`, `spacing:`, `count:` and
`columns:`, and a packed sheet still goes through the C `tile` path. The glue
cuts a sheet with its margin and spacing and loads a collection one file per
tile, into the same flat Array. `TileMapRenderer` skips a hidden layer, tints a
layer and its animated tiles by its opacity, and draws a turned tile inside
`Renderer#rotated`, mirrored with `image_at(scale_x: -1)`. `rake spec` ran 2609
examples and `rake spec:core` 455, both with no failures, and
`rake docs:coverage` reports nothing undocumented. The `scroll_map`,
`pathfinding`, `collision_tiles` and `jump_topdown` drives report what `main`
reports, byte for byte. `town.tmx` drawn through the renderer and drawn tile by
tile the old way differ in 0 of 960×640 pixels.

Rule 4 is pinned against Tiled's own output ahead of step 8.
`spec/fixtures/orientations.tmx` was painted in Tiled 1.12: an F from
`f.png` in each of the eight orientations. `tile_map_spec.rb` pins what the parse reads from
it. `tile_map_renderer_spec.rb` draws those eight values and compares every
pixel with Tiled's flag rule applied to the F. The rule is diagonal flip
first, then horizontal, then vertical, which is not the arithmetic the
renderer uses. Turning mirrored tiles the wrong way fails two of the eight.

What the sketch got wrong:

- **No renderer primitive was needed.** `rotated` and a negative `scale_x`
  already draw all eight orientations, so no C changed and the renderer
  contract did not grow. A mirrored tile turns the other way. `Orientation`
  turns first and mirrors second, but a transform wrapped around
  `image_at(scale_x: -1)` mirrors first.
- **Tiles stand on the bottom-left of their cell.** The sketch said nothing about a
  tile of another size than the grid, which a collection makes ordinary. Tiled
  anchors such a tile at the cell's bottom-left, and so does the renderer now.
  A turned tile that is not square keeps that corner. The anchor is Tiled's
  documented behaviour, but no Tiled export has checked it; the fixture's
  tiles are square.
- **The tile map contract grew** by `layer(i).visible?` and `opacity`. Its
  canopy layer is now hidden at half opacity, and `StubTileMap` takes
  `visible:` and `opacity:`.
- **`StubImage` did not change.** It lives in `spec/support/`, not
  `spec_core/support/`, and the glue slices real images only. The glue is
  specced in `spec_core/rgame/game_tilemap_spec.rb` through a child process,
  like the locales.
- **A tileset's tile offset is still not applied.** `Tiled::Tileset` reads
  `offset_x` and `offset_y`, and nothing draws with them.

Documented in `docs/api/tile_maps.md` (a new "How the map is drawn" section),
`docs/api/images.md` and `docs/api/assets.md`. The CHANGELOG adds two entries under
Added.

---

## Step 6 — image layers, and a slot per gap *(rough)*

An `RGame::Engine::ImageLayer < Node2D` that draws one image with `repeat_x` and
`repeat_y`, and `TileMapLayer.mount` dispatching on layer kind. `mount` grows
`gaps:` and returns a slots object instead of one node
([design](03-design.md#2-a-slot-per-gap-not-one-gap)).

Settles [open question 2](README.md#open-questions): whether `mount` keeps its
name once it returns an assortment.

---

## Step 7 — nodes on a map *(rough)*

The tile↔world seam on `TileWorld`, absorbing the four copies in
[F8](01-current-state.md#f8); the `MapObjects` registry; and
`Components::OccupiesCell`. See
[the design](03-design.md#nodes-on-a-map).

`MapObject` itself is not here — step 4 builds it, because `map.objects` already
hands it out. What this step adds is the thing that turns one into a node.

The seam is the part to re-plan carefully: `Util::TileSweep` does the same
arithmetic in C and stays there, so the step has to say what "one seam" means
when one of the four occupants is a different language.

---

## Step 8 — the authored map, checked and played *(rough)*

Two halves.

**Checked.** A `describe` block in `spec/example_assets_spec.rb`, one example per
requirement from step 0, each failing with what to change in Tiled — "R5: layer
`orientations` is missing flip-bit combinations [3, 6]; paint the row again from
the table". That
file is already the precedent: its `town.tmx` block asserts the fence has exactly
one gap and says in a comment which mistake it caught.

**Played.** An example under `examples/` that draws the map, with a drive script
under `tools/drive/examples/`, following the
[write-example](../../../.claude/skills/write-example/SKILL.md) skill. This is
the tier where all three layers are present at once, and the only one that would
catch a map that parses and draws wrong.

Re-plan once step 5 lands and the map has arrived, because what the example
should *do* depends on what the map turns out to contain.

---

## Step 9 — fold the plan back and delete it

Move what is still true into the real documentation and remove
`docs/plans/tiled-format/`.

- **`docs/api/tile_maps.md`** is largely rewritten: the "What rgame reads from
  Tiled" table becomes the supported set, and the new surface — properties,
  multiple tilesets, flips, layers, objects — gets sections. `Properties` gets
  one, and the `@api private` tag on `RGame::Engine::Tiled` comes off with it. Follow
  [write-docs](../../../.claude/skills/write-docs/SKILL.md).
- **`docs/api/components.md`** gains `OccupiesCell` and the `TileWorld`
  additions; **`docs/api/scene_graph.md`** gains the slots; **`docs/api/assets.md`**
  gains the changed `:tilemap` loader.
- **`examples/assets/README.md`** carries a source and licence entry for every
  image the new map uses.
- **`CHANGELOG.md`** gets the breaking change stated plainly — a cell holds a
  tile id rather than a gid, `map.tileset` and `Engine::Tileset` are gone, and
  `TileMap.load` and `TileMap.parse` gave way to `Tiled::Map` plus
  `TileMap.from_tiled` — per
  [update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
- **`docs/plans/possible-todos.md`**: the "maps that change at runtime" entry
  loses the part `OccupiesCell` answered and keeps the `Navigator` question,
  which this plan does not settle.
- **`docs/c_engine_feature_specs.md`**: amend it where this plan contradicted it,
  rather than leaving it to disagree quietly.

### Verify

`rake` with no argument: `make test`, `rake spec`, `rake spec:core`. Every driven
example still reports what it reported. `docs/plans/tiled-format/` is gone, and
`grep -r tiled-format docs/` finds nothing.
