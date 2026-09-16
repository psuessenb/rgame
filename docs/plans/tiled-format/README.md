# Supporting Tiled's format

**Status: planned, nothing implemented.** Steps 0–5 of
[the roadmap](04-roadmap.md) are detailed. Steps 6–9 are deliberately rough and
get re-planned once the layer beneath them exists.

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
9. **The public API breaks, and the CHANGELOG says so.** `map.tilesets` replaces
   `map.tileset`; the renderer takes images per tileset; the shared contract is
   rewritten. rgame is 0.3.1 and every consumer is in this repo.
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

## Open questions

1. ~~**Does the parser read object layers?**~~ **Settled — yes, into records
   and no further.** See [decision 11](#decisions-already-taken). It lands in
   [step 3](04-roadmap.md#step-3--enginetiledmap-and-the-layer-tree-pure), not
   step 2 as this question first said.
2. **Does `TileMapLayer.mount` keep its name?** It will mount image-layer nodes
   too, and a class method on `TileMapLayer` that returns an assortment no
   longer describes itself. `MapLayers.mount` is the alternative. **Waits on
   step 6**, where the mixed set first exists.
3. **Does the flip plane need a byte-per-cell store?** `Util::Tensor` holds a
   `VALUE` per cell, so a second plane costs 8 bytes per cell per layer.
   Nothing measured says that hurts. **Waits on** a map big enough to measure.
   See [the rejected packing](03-design.md#rejected-packing-the-flip-bits-into-the-gid).

## Reading order

| | |
|---|---|
| [01-current-state.md](01-current-state.md) | what rgame reads today, what breaks, and what already resembles this work |
| [02-prior-art.md](02-prior-art.md) | how libGDX, Godot, Unity, Bevy and Phaser answer the same question |
| [03-design.md](03-design.md) | the proposed design, and what was rejected |
| [04-roadmap.md](04-roadmap.md) | the implementation order |
