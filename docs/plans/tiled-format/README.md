# Supporting Tiled's format

**Status: steps 0–6 of [the roadmap](04-roadmap.md) are implemented, and step 7 is planned in detail.** Step 8 is still rough and waits on the authored map.

## Goal

Read the parts of [Tiled](https://www.mapeditor.org/)'s `.tmx`/`.tsx` format a
2D orthogonal game needs, instead of the narrow slice rgame reads today. Along
the way, give a game a supported way to put nodes on a map — placed in code for
now, placed from an object layer later.

## Verdict

**Rebuild the parser as a faithful reading of the file, and keep `TileMap` as
the runtime view over it.** Everything the request asks for falls out of that
split, and nothing does without it.

The two features named — multiple tilesets and CSV — are each an afternoon on
their own. They are not the work. The work is that `TileMap.parse` is 25 lines
that assume one tileset, one encoding, one layer kind and one custom property,
and every one of those assumptions is load-bearing somewhere else: the
renderer holds one flat tile array, the shared contract states `map.tileset`
singular, and `above` is read by a private method that knows only that name.
Add multiple tilesets to the class as it stands and you get a second flat array
and a second special case. Add CSV and you get a branch. Add group layers and
the layer index stops meaning what four other files think it means.

So: a `RGame::Engine::Tiled` namespace that reads the file and asserts nothing
about how a game uses it, and a `TileMap` built from it that keeps answering the
questions actors ask. The parser grows a class per element. The runtime view
stays the size it is.

**The split only pays if the vocabulary stops at it.** The runtime view is built
for the game, not as a second presentation of the file, so the transform between
the halves absorbs every awkwardness the format has: the global id space becomes
[one tile table](03-design.md#tiles-one-table-and-no-gid-below-the-transform),
three flip bits become
[an orientation](03-design.md#orientation-eight-of-them-decoded-once), a tile
object measured from its bottom-left corner becomes
[one record in the game's coordinates](03-design.md#objects-one-record-in-the-games-coordinates).
A `TileMap` that still said `gid` would have moved the parse, not the problem.

Two findings make the rest cheaper than it looks.
[A recording bakes the transforms inside it](01-current-state.md#f6), so drawing
flipped and rotated tiles costs nothing per frame — only at bake time. And
[a recording can be tinted on replay](01-current-state.md#f7), so per-layer
opacity is one argument rather than a second draw path.

## What was measured before planning

Taken at `b988500`, on this checkout.

| | |
|---|---|
| `rake spec` | 2329 examples, 0 failures, 4 pending, 6.62 s |
| …of which cover the tile pipeline | 84 examples, 0.06 s |
| The whole tile pipeline | 716 lines across 6 files |
| `TileMap.parse` | 25 lines |
| `.tmx` files in the repo | **1** (`examples/assets/town.tmx`), shared by 4 examples |
| `.tsx` files in the repo | **1** (`examples/assets/tileset.tsx`), one tileset, no margin, no spacing |
| `map.tileset` call sites | 15, including the `a tile map` shared contract |
| Copies of tile↔world arithmetic | **4** ([F8](01-current-state.md#f8)) |
| Tiled custom properties read | **1** (`above`, on a layer) |
| Layer data encodings read | **1** of 6 |
| Layer kinds read | **1** of 4 |
| Test projects that could verify this | 0 — `test_projects/tiled_world` reads `media/`, which is gitignored |

## What was measured while designing the transform

Taken at `2a9e8e7`, on this checkout. These answer the second question: once the
split is settled, what does the transform cost? Every row *(measured)*.

`TileMap` already walks every cell writing into a `Util::Tensor`, so the tile
table adds an array lookup to a loop that runs today rather than adding a pass:

| Map | Tensor fill today | + tile table | Added |
|---|---|---|---|
| `town.tmx`, 60×40×2 = 4.8k cells | 0.20 ms | 0.24 ms | **+0.04 ms** |
| 250×250×6 = 375k cells | 15.1 ms | 17.9 ms | **+2.8 ms** |
| 500×500×8 = 2M cells | 80.2 ms | 96.3 ms | **+16 ms** |

The orientation plane costs four times what the table does — 17.9 ms to 29.5 ms
on the 375k map — and only on maps that use it. Decoding a whole 250×250×6 map
costs about 35 ms all in, once, on a scene load.

Two more numbers that decide what to optimise if it ever matters:

| | |
|---|---|
| `TileMap.parse('town.tmx')` today | 0.59 ms, of which REXML is 0.12 ms |
| Per-cell `Tensor#[]=` vs. one flat `Array#map`, 375k cells | 18.7 ms vs. 8.0 ms |

The second row is the finding. The load cost is dominated by per-cell Ruby-to-C
crossings, not by parsing and not by the transform, and `Tensor` exposes no bulk
fill — `initialize`, `[]`, `[]=`, `width`, `height`, `depth`, and nothing else
([tensor.c:180-185](../../../ext/rgame_util/tensor.c#L180-L185)).

## Hard constraints

1. **The engine layer may not name `RGame::Core`.** Parsing stays in
   `RGame::Engine`; an image path comes out and a GPU handle never goes in.
   `Game/NoCoreInEngineLayer` enforces it.
2. **Core may not name `RGame::Engine`.** `TileMapRenderer` keeps calling a map
   it cannot name, through the `a tile map` contract.
3. **`require "rgame"` loads no graphics library.** The parser must stay pure
   Ruby over stdlib, and `spec/rgame/no_graphics_spec.rb` says so.
4. **One runtime gem dependency, `rexml`, and no more.** Gzip is `Zlib::GzipReader`,
   Base64 is `unpack1('m')`. Zstd would be a second dependency, so zstd is out.
5. **Nothing on a draw path reads a clock.** Animation keeps taking `elapsed`.
6. **A fake must refuse what the real thing refuses.** Every method added to the
   renderer or the map contract lands in the shared example group and in the
   stand-in, in the same commit.
7. **`TileMap` stays spec-able with no window.** A `.tmx` must parse, and a map
   must answer every question, with no SDL in the process.

## Decisions already taken

Settled in conversation before this plan was written. Not up for
re-litigation inside it.

1. **Orthogonal only, with a seam.** Isometric, staggered and hexagonal raise a
   clear error. Every tile↔world conversion moves behind one named seam so the
   later plan fills it rather than sweeps for it. The reason is that
   `Util::SolidGrid`, `Util::TileSweep` and `Util::RouteSearch` are square-grid
   C, and a diamond grid rewrites all three.
2. **All three flip bits are honoured** — horizontal, vertical and diagonal, the
   eight orientations Tiled can express. Today they are stripped and the tile
   draws unflipped, which is a wrong picture rather than a missing feature.
3. **Custom properties become a typed bag everywhere** — map, layer, tileset,
   tile and object, with Tiled's own types. `above` becomes one ordinary
   property. This is also what an object layer will carry.
4. **Infinite maps flatten to a dense grid on load.** Read the chunks, bound
   them, write them into an ordinary grid, and record the origin shift in one
   place so object coordinates can use it. Nothing downstream learns the
   difference.
5. **Group layers, image layers, and per-layer `visible` and `opacity` are in.**
   Per-layer offset, parallax and tint are **out**: parallax needs the draw path
   to know the camera, which it deliberately does not, and the other two are not
   worth opening that door alone.
6. **Tilesets gain margin, spacing, collections of images, embedded tilesets,
   tile offset and per-tile class.** A downloaded sheet with 1 px spacing
   currently renders wrong, silently.
7. **Solidity stays whole-cell.** A tile's collision shapes are read for their
   class and properties, and their geometry is discarded. `SolidGrid` stays a
   byte per cell, which is what makes collision and A* fast.
8. **The parse/runtime split above.**
9. **The public API breaks, and the CHANGELOG says so.** A cell holds a tile id
   rather than a gid; `map.tileset` and `Engine::Tileset` go; `TileMap.load` and
   `TileMap.parse` give way to `Tiled::Map` plus `TileMap.from_tiled`; the shared
   contract is rewritten. rgame is 0.4.0 and every consumer is in this repo.
10. **The acceptance map is authored in Tiled by the user.** The roadmap hands
    out requirements early, at
    [step 0](04-roadmap.md#step-0--the-requirements-for-the-acceptance-map), and
    verifies the supplied map against them late, at
    [step 8](04-roadmap.md#step-8--the-authored-map-checked-and-played-rough) —
    naming what to change in Tiled when one is missed. Generated fixtures
    cover breadth; the authored map covers "a file Tiled itself wrote".
11. **The parser reads object layers into records, and stops there.**
    `Tiled::ObjectLayer` and `Tiled::Object` are parsed in
    [step 3](04-roadmap.md#step-3--enginetiledmap-and-the-layer-tree-pure) and
    flattened by `TileMap#objects`. **No node is ever built from a map**, which
    is what excluding the object layer asked for. What this buys is that the
    record type is real and something produces it, so the later feature is
    wiring rather than design — a registry with no producer is exactly the
    untested-composition smell CLAUDE.md warns about.
12. **The runtime view speaks none of Tiled's vocabulary.** A cell holds an
    rgame tile id, not a gid; an orientation, not three flip bits; `layer.above?`,
    not a property lookup; a `MapObject` in the game's coordinates, not a
    `Tiled::Object` in the file's. `Engine::Tileset` dissolves, because nothing
    a game asks at runtime is per-tileset. The guard is a grep:
    `RGame::Engine::Tiled` may be named inside `lib/rgame/engine/tiled/` and in
    the one transform file, nowhere else. See
    [what the runtime view may not say](03-design.md#what-the-runtime-view-may-not-say).
13. **A built map is plain data, produced by one thing.** `from_tiled` is the
    only transform, `initialize` takes flat Arrays rather than a `Tensor`,
    nothing reachable from a built map is a `Tiled::*` object, and `source`
    records what it was built from. All four are needed anyway; together they
    leave a cache of built maps possible later without one being built now. See
    [open question 4](#open-questions).

## What this plan does not deliver

- **Nodes built from an object layer.** The registry that builds them and the
  records that feed it are both here; the wiring that reads the map's objects
  and spawns them is not. See
  [the object layer, investigated](03-design.md#the-object-layer-parsed-not-wired).
- **Isometric, staggered and hexagonal maps.** Detected and refused.
- **Sub-tile collision shapes.** Half-height ledges and slopes stay unsupported.
- **Zstd-compressed layer data.** It needs a second runtime dependency.
- **Wang sets, terrains and tileset transformations.** Tiled uses them to help
  you paint; they say nothing about the painted result.
- **World files (`.world`).** Stitching several maps is a separate feature.
- **Per-layer parallax, offset and tint.** See decision 5.
- **Text objects.** Parsed as a shape and otherwise ignored.
- **A cache of built maps across process runs.** Within one run a map is
  transformed once, because `AssetManager` caches it. Across runs is open question
  4, and nothing measures as slow enough to open it.
- **A bulk `Util::Tensor` fill.** The measurements say it is the first thing to
  reach for if loading ever hurts. Nothing here needs it.

## Open questions

1. ~~**Does the parser read object layers?**~~ **Settled — yes, into records
   and no further.** See [decision 11](#decisions-already-taken). It lands in
   [step 3](04-roadmap.md#step-3--enginetiledmap-and-the-layer-tree-pure), not
   step 2 as this question first said.
2. ~~**Does `TileMapLayer.mount` keep its name?**~~ **Settled in the step 6
   re-plan — it keeps it.** The question assumed `mount` would hand out image
   layer nodes beside tile layer nodes. The re-plan draws an image layer through
   `TileMapRenderer`, so `mount` still mounts only `TileMapLayer`s and the name
   still says what it does. What changes is its return value: slots, not one
   node. See [step 6](04-roadmap.md#step-6--the-rest-of-what-tiled-shows-and-a-slot-per-gap).
3. **Does the orientation plane need a byte-per-cell store?** `Util::Tensor`
   holds a `VALUE` per cell, so a second plane costs 8 bytes per cell per layer.
   It is also the most expensive part of the transform where a map uses it —
   11.6 ms of the 29.5 ms a 250×250×6 map spends *(measured)*. A map with no
   flipped tile allocates none of it. **Waits on** a map big enough for either
   number to matter. See
   [the rejected packing](03-design.md#rejected-packing-the-flip-bits-into-the-tile-id).
4. **Should built maps be cached across process runs?** Not now. Within one run
   the cache already exists — `AssetManager#fetch` is `@cache[key] ||= yield`, so
   a map is transformed once per process. Across runs would need a format, a
   location and a rule for what invalidates it, and a 250×250×6 map transforms in
   about 35 ms on a scene load *(measured)*. The cheaper move comes first and is
   not a cache: a bulk fill in C for `Util::Tensor`, which halves the dominant
   cost. **Blocks nothing**, and
   [decision 13](#decisions-already-taken) is what keeps it answerable later.
5. ~~**Does an infinite map bound by chunk or by non-empty cell?**~~
   **Settled in step 3 — by chunk.** The box is bounded by whole chunks that
   hold a tile, across every layer. Tiled stores 16×16 chunks, and a chunk can
   be partly empty, so the two boxes differ. By chunk is simpler and pads the
   map; by cell is tighter and costs a scan. The acceptance map is built so
   both agree ([R16](map-requirements.md#r16)).
6. ~~**What does the parser do about a class member left at its default?**~~
   **Settled in step 1 — it reads what the file states, and documents the gap.**
   Tiled writes only the members that differ from the class's defaults, and
   keeps the defaults in the `.tiled-project` file, which nothing reads. So a
   member the designer never changed is absent from `Properties`, `fetch` with
   no default raises naming it, and a game reads it with `fetch(name, default)`.
   The class comment on `Tiled::Properties` says so. Reading the project file
   stays possible later and changes no caller.

7. **Should a game be able to change which tile *types* are solid?**
   `Tileset#solid_ids=` did that until step 4 removed it, and nothing replaced
   it. `Components::OccupiesCell` in step 7 covers a thing that blocks one cell.
   It does not cover "all water is now walkable". The design keeps a bare
   `set_solid` off `TileWorld`, because a solid cell with nothing drawn on it is
   an invisible wall. A per-type switch would redraw nothing either, but the
   designer drew the tile, so the wall would not be invisible. **Waits on** a
   game that wants it.

## Reading order

| | |
|---|---|
| [01-current-state.md](01-current-state.md) | what rgame reads today, what breaks, and what already resembles this work |
| [02-prior-art.md](02-prior-art.md) | how libGDX, Godot, Unity, Bevy and Phaser answer the same question |
| [03-design.md](03-design.md) | the proposed design, and what was rejected |
| [04-roadmap.md](04-roadmap.md) | the implementation order |
| [map-requirements.md](map-requirements.md) | what the acceptance map authored in Tiled must contain, and how step 8 checks it |
