# Roadmap

**Steps 0–5 are detailed. Steps 6–9 are deliberately rough** and get re-planned
once the step beneath each exists. Nothing is implemented.

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
| 5 | Flipped tiles draw flipped; hidden layers stop drawing |

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
    coordinates the file states, bottom-left origin and all — converting them is
    the caller's job, and there is no caller yet.

### Tests

`spec/rgame/engine/tiled/map_spec.rb`, with `TiledFixture` grown to emit each
encoding, chunks, groups, image layers and object layers. One `describe` per
rule above. The encoding examples share one expected grid, written once —
five encodings asserted against five hand-written Arrays would drift.

### Verify

New specs green, and `examples/assets/town.tmx` reads through `Tiled::Map.load`
to the same two layers, the same 60×40 size and the same gids the current parser
produces — again as a temporary example, deleted in step 4.

---

## Step 4 — `TileMap` and `Engine::Tileset` rebuilt on the parser

The breaking step. It is one branch because
[F10](01-current-state.md#f10)'s sweep crosses `spec/` and `spec_core/`, and a
contract that lands in two commits is a red suite in between.

### Shape

The full `TileMap` and `Engine::Tileset` sketches are in
[03-design.md](03-design.md#the-runtime-view). What changes for callers:

| Was | Becomes |
|---|---|
| `map.tileset` | `map.tilesets`, `map.tileset_for(gid)` |
| `TileMap.load` → `[map, image_path]` | → `[map, image_paths]` |
| `map.above_layer?(i)` | `map.layer(i).properties['above']` |
| `map.gid(l, c, r)` carries no flags | unchanged, and `map.flip(l, c, r)` is new |
| — | `map.layer(i)`, `map.layer_index(name)`, `map.objects`, `map.image_layers` |

### The rules the tests pin

1. `gid` never returns a value carrying a flag, and `flip` returns 0..7.
2. A map with no flipped tile allocates no flip plane, and `flip` still answers
   0 everywhere.
3. `tileset_for` picks the last tileset whose `firstgid` does not exceed the gid,
   and `nil` for gid 0.
4. Layers flatten depth first, groups contributing no index of their own.
5. `layer_index` takes a name or a `'Group/child'` path, and raises naming the
   available layers when it misses.
6. A hidden layer still counts for `solid_tile?`.
7. `solid_tile?` and `solid_at?` answer exactly as they do today for
   `town.tmx` — this is the invariant, asserted directly.
8. `TileMap.parse` still takes a String and touches no files.

### Tests

Rewrite `spec/rgame/engine/tile_map_spec.rb` and
`spec/rgame/engine/tileset_spec.rb`. Rewrite
`spec/support/shared_examples/a_tile_map.rb` and grow `StubTileMap` to match, in
the same commit ([constraint 6](README.md#hard-constraints)) — and
`spec_core/rgame/core/tile_map_renderer_spec.rb`, which hosts the same contract
from the other side.

### Verify

```
bundle exec rspec                 # every example, incl. example_assets_spec
bundle exec rspec spec/rgame/no_graphics_spec.rb
```

and the invariant's driven runs, byte-identical to their output before the
branch. `RGame::Engine::Tiled` is the only thing that parses XML, asserted by
grepping `lib/rgame/engine/` for `REXML` and finding it in one directory.

---

## Step 5 — the renderer, and slicing a real sheet

Everything that turns the parsed map into pixels, in one branch because the
renderer's tile lookup, the image slicing and the flip draw are one change seen
from three sides.

### Shape

```ruby
# Core
RGame::Core::TileMapRenderer.new(map, images)   # images: one Array per tileset
RGame::Core::Image#tiles(w, h, margin: 0, spacing: 0, count: nil, columns: nil)

# Glue, in RGame::Game's :tilemap loader
map, image_paths = RGame::Engine::TileMap.load(path)
images = map.tilesets.zip(image_paths).map { |tileset, paths| slice(tileset, paths) }
RGame::Core::TileMapRenderer.new(map, images)
```

### The rules the tests pin

1. `tiles` with `margin: 0, spacing: 0` returns exactly what it returns today,
   through the same C path.
2. `tiles` with margin and spacing cuts each tile from
   `margin + col * (w + spacing)`, and `count:` bounds the result.
3. A tile's image resolves through its **own** tileset — a gid from the second
   tileset never indexes the first.
4. A flipped tile bakes to the orientation Tiled shows, for all eight
   combinations. **This is the table to get right**, and it is pinned against the
   authored map in step 8 as well as against a fixture here.
5. A hidden layer bakes nothing and draws nothing.
6. A layer with opacity `o` replays tinted with alpha `o`, and its animated tiles
   draw with the same colour.
7. A collection-of-images tileset draws the same as a sheet with the same tiles.

### Tests

`spec_core/rgame/core/tile_map_renderer_spec.rb` for the draw calls and the
framebuffer read-back that only the real renderer can do.
`spec_core/rgame/core/image_spec.rb` for margin and spacing, including the
guard that a sub-image cannot fall outside the sheet —
`spec_core/support/stub_image.rb` already refuses exactly what `Image#subimage`
refuses, and must keep doing so.

Flip orientation is checked by reading pixels back, not by counting calls: a
rotation the wrong way issues exactly the same number of draws.

### Verify

```
make ext-core && rake spec:core
rake spec
ruby tools/drive_test_project.rb examples/scroll_map/main.rb --ticks 240
```

and the frame `town.tmx` draws is unchanged.

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
[F8](01-current-state.md#f8); `MapObject` and the `MapObjects` registry; and
`Components::OccupiesCell`. See
[the design](03-design.md#nodes-on-a-map).

The seam is the part to re-plan carefully: `Util::TileSweep` does the same
arithmetic in C and stays there, so the step has to say what "one seam" means
when one of the four occupants is a different language.

---

## Step 8 — the authored map, checked and played *(rough)*

Two halves.

**Checked.** A `describe` block in `spec/example_assets_spec.rb`, one example per
requirement from step 0, each failing with what to change in Tiled — "R5: no
diagonally flipped tile found; flip one with Shift+X in the stamp brush". That
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
  multiple tilesets, flips, layers, objects — gets sections. Follow
  [write-docs](../../../.claude/skills/write-docs/SKILL.md).
- **`docs/api/components.md`** gains `OccupiesCell` and the `TileWorld`
  additions; **`docs/api/scene_graph.md`** gains the slots; **`docs/api/assets.md`**
  gains the changed `:tilemap` loader.
- **`examples/assets/README.md`** carries a source and licence entry for every
  image the new map uses.
- **`CHANGELOG.md`** gets the breaking change stated plainly — `map.tileset`
  became `map.tilesets`, `TileMap.load` returns paths — per
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
