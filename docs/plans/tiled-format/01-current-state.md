# What rgame reads today

Measured at `b988500`. Every finding tagged *(measured)* was checked by reading
the file or running the code, not remembered.

## The supported slice

`docs/api/tile_maps.md` already states it, which is to its credit — the limits
are documented rather than discovered:

| | Today | Tiled offers |
|---|---|---|
| Orientation | orthogonal | orthogonal, isometric, staggered, hexagonal |
| Tilesets per map | 1, external `.tsx` only | any number, external or embedded |
| Layer data encoding | base64 + zlib | XML, CSV, base64 × (none, gzip, zlib, zstd) |
| Layer kinds | tile | tile, object, image, group |
| Map extent | fixed | fixed or infinite (chunked) |
| Flip and rotation | stripped, drawn unflipped | 3 flag bits, 8 orientations |
| Custom properties | `above` on a layer | 8 types on 5 kinds of element |
| Tileset geometry | `columns`, tile size | + margin, spacing, tilecount, tile offset, collections |
| Per-tile data | animation, "has a collision shape" | + class, properties, probability, real shapes |

Five of those rows are not "unsupported". They are **wrong output with no
error**, which is the worse failure: the checkout still works, and the map
someone else authored does not.

## Findings

### F1

**One encoding, and the others fail differently.** *(measured)*

`TileMap.parse` runs `layer_el.elements['data'].text.strip.unpack1('m')` and
then `Zlib::Inflate.inflate`, unconditionally
([tile_map.rb:53-55](../../../lib/rgame/engine/tile_map.rb#L53-L55)). CSV data
reaches `unpack1('m')` as a comma-separated string and decodes to garbage before
zlib raises. Uncompressed base64 raises out of zlib. XML-encoded data has no
text at all and raises on `nil`.

### F2

**One tileset, and it is assumed rather than checked.** *(measured)*

`root.elements['tileset']` takes the first and ignores the rest
([tile_map.rb:47](../../../lib/rgame/engine/tile_map.rb#L47)). A two-tileset map
parses without complaint, and every gid from the second tileset resolves through
the first tileset's `firstgid` into a local id that indexes the wrong tile — or
past the end of the array, where `@tiles[local]` is `nil` and `image_at` raises
mid-frame.

### F3

**`FLIP_MASK` keeps a bit Tiled says to clear.** *(measured against the spec)*

`FLIP_MASK = 0x1FFFFFFF` clears bits 30, 31 and 32 and leaves bit 29. Bit 29 is
`ROTATED_HEXAGONAL_120_FLAG`, and
[Tiled's reference](https://doc.mapeditor.org/en/stable/reference/global-tile-ids/)
says to clear it **even on non-hexagonal maps**, because Tiled preserves the
flag across an orientation change. The correct mask is `0x0FFFFFFF`. Harmless on
a map that was always orthogonal; a gid of 268 million on one that was not.

### F4

**An infinite map parses to nothing.** *(measured)*

`root.attributes['width'].to_i` is `0` for an infinite map, so the grid is
0×0, and `<data>` holds `<chunk>` children rather than text. Neither is checked.
The result is a map with no tiles and no error, or a `NoMethodError` on `nil`.

### F5

**`Image#tiles` ignores margin and spacing.** *(measured)*

`Image#tiles` walks whole tiles from the top-left with no padding
([image.rb:39-43](../../../lib/rgame/core/image.rb#L39-L43)), and there is no
parameter for it. Most downloaded sheets carry 1–2 px between tiles. Such a
sheet slices one pixel further off true with every column, so the map draws
smeared rather than failing. `examples/assets/tileset.png` has neither, which is
why nothing has caught it.

### F6

**A recording bakes the transforms inside it.** *(measured)*

`recording.h` states it plainly: "Transforms *inside* the recorded block are
baked with them — a rotated sprite records its rotated corners — and the
transform in effect at *replay* time is applied on top."

**This is what makes flip support nearly free.** A flipped tile costs a
transform push at bake time, once, and nothing per frame. Clips are the only
thing a recording refuses, and tiles push none.

### F7

**A recording can be tinted on replay.** *(measured)*

`Recording#draw(x, y, z:, color:)` multiplies every baked colour by the tint,
and "a colour with alpha fades the whole layer out at once"
([recording.rb:44-50](../../../lib/rgame/core/recording.rb#L44-L50)).

**This is what makes per-layer opacity one argument.** The animated tiles drawn
outside the bake take the same colour through `image_at(color:)`.

### F8

**Tile↔world arithmetic is written out four times.** *(measured)*

| Where | What |
|---|---|
| `TileMap#solid_at?` | `(world_x / @tile_width).floor` |
| `TileMapRenderer#draw_animated` | `cull_x.fdiv(tile_width).floor`, and `col * tile_width` |
| `Navigator#cell_at`, `#centre_x`, `#centre_y` | both directions, plus the half-tile centre |
| `Util::TileSweep` (C) | the same division, per axis |

No caller is wrong today, because all four agree that a cell is a square at
`col * tile_width`. **They stop agreeing the moment the grid is a diamond**, and
there is no one place to change. This is the seam decision 1 asks for, and it
already has four occupants.

### F9

**One custom property, and the parser knows its name.** *(measured)*

`TileMap.layer_flag?` walks `<properties>` looking for a property called
`above` and comparing its value to the string `"true"`
([tile_map.rb:71-80](../../../lib/rgame/engine/tile_map.rb#L71-L80)). Nothing
else in the file is read. A second property means a second method of the same
shape.

### F10

**`map.tileset` is singular in 15 places.** *(measured)*

Four in `lib/`, eleven in specs — including
`spec/support/shared_examples/a_tile_map.rb`, which is the contract both
`TileMap` and `StubTileMap` are checked against, and
`spec_core/rgame/core/tile_map_renderer_spec.rb`, which is the other half of it.
Making it plural is a mechanical sweep, but it crosses the `spec/` ↔
`spec_core/` boundary, so it lands in one commit or neither.

### F11

**Nothing in the repo could catch any of this.** *(measured)*

One `.tmx`, one `.tsx`, both hand-written for `examples/pathfinding` and drawn
by four examples. No multiple tilesets, no CSV, no flips, no groups, no margins,
no infinite map, no object layer. `test_projects/tiled_world` reads
`map/beach_large.tmx` out of `media/`, which `.gitignore` excludes, so it does
not run on a fresh checkout at all.

This is the "verified only in isolation" shape CLAUDE.md names: the parser's own
specs are green because `TiledFixture` writes exactly what the parser reads.
**The fixture writer is the parser's reading of the format, not Tiled's**, so
the two agree by construction and would keep agreeing while both were wrong.

### F12

**A solid tile is a solid square, and the shape is discarded.** *(measured)*

`Tileset.collision_shape?` returns true when a `<tile>` has an `<objectgroup>`
with at least one `<object>`, and nothing reads the object
([tileset.rb:47-50](../../../lib/rgame/engine/tileset.rb#L47-L50)). A carefully
drawn half-height ledge blocks the whole cell. This is a deliberate limit
(decision 7) and stays one; what changes is that the shape's **class and
properties** become readable, which is what a game needs to tell water from
wall.

## Before building: what this resembles

CLAUDE.md asks for three piles. Here they are.

### Reuse it

- **`Util::Tensor`** holds the gid grid and keeps doing so.
- **`Util::SolidGrid`** holds solidity and keeps doing so. Decision 7 exists
  partly to protect this.
- **`Core::Recording`** bakes each layer, and [F6](#f6) and [F7](#f7) say it
  already does more than the current code asks of it.
- **`Core::Image#subimage`** is what margin-and-spacing slicing is built on. The
  C side already answers it.
- **`AssetManager#add_loader`** is the shape the object factory registry copies:
  a name, a block, and an accessor defined from it. Nothing about it needs to
  change.
- **`TiledFixture`** grows encodings and shapes rather than being replaced.

### Extend or generalize it

- **`Image#tiles` and `Image#each_tile` grow `margin:` and `spacing:`.** The
  same question — "cut this sheet into tiles" — with two more numbers. Two
  methods for it would be two answers to one question.
- **`Components::TileWorld` becomes the tile↔world seam.** It already owns
  `tile_width` and `tile_height` and already answers "is this cell solid". The
  four copies in [F8](#f8) collapse into it. That is not a new concept; it is
  the concept that got copied.
- **`Components::World` / `WorldBounds`** is the precedent for naming a
  contract two systems answer. If isometric ever lands, the tile↔world seam is
  the same trick again.
- **`Tileset` splits in two.** A `.tsx` holds what the file says; a runtime
  tileset answers what the renderer asks. Today one class does both, which is
  why every new attribute has to be threaded through one constructor.
- **A byte-per-cell grid.** `Util::SolidGrid` is `uint8_t*`, 2D. The flip plane
  wants `uint8_t`, 3D. Those are one shape with two depths — and the honest
  answer is that nothing has measured a problem, so it stays in this pile as
  [open question 3](README.md#open-questions) rather than becoming work.

### Genuinely new

- **`Engine::Tiled::Properties`.** rgame has no typed key-value bag. `InputMap`
  is a table, but its values are binding descriptions, not arbitrary typed
  data. Nothing answers "what did the author attach to this".
- **`Engine::Tiled::*` element classes.** Nothing in the codebase reads a
  document format into a tree. The `.json` sprite-sheet descriptors are flat
  hashes consumed directly.
- **`Engine::MapObject` and the factory registry.** Modelled on
  `add_loader` (above) but answering a different question: `add_loader` builds an
  asset from a path, this builds a node from a record. Two callers, two
  lifetimes, no shared code worth having.
- **`Components::OccupiesCell`.** Nothing today changes solidity at runtime —
  `docs/plans/possible-todos.md` records that `TileWorld` deliberately exposes no
  bare `set_solid`, because "a solidity change without the drawn tile is an
  invisible wall". This is the answer to that, not a bypass of it.
