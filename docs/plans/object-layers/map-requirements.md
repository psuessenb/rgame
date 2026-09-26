# Requirements for the Tiled acceptance map

**Status: being authored on `build-step-8-tiled-map`, 10 of 23 done.** These
requirements were step 0 of the Tiled format plan, and the check below was its
step 8. [Step 0 of this plan](04-roadmap.md#step-0--the-requirements-for-tourtmx)
added R20–R23, which building nodes from objects needs, and carried over the done
marks from the authoring branch. Links into the Tiled format plan point at it as
it stood in `dcb07f8`.

**A map authored in Tiled, saved by Tiled, and never edited by hand.** It is the
one input the parser cannot have written itself. `TiledFixture` emits what the
parser reads, so the parser and its fixtures agree by construction
([F11](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/01-current-state.md#f11)). A file Tiled wrote breaks that circle.

Each requirement below says **what to do in Tiled**, **why the code needs it**,
and **what the check reports when it is missing**.

## Where the map stands

A mark is the author's word. The check confirms it once it exists.

| | Requirement | Done |
|---|---|---|
| [R1](#r1) | two external tilesets | done |
| [R2](#r2) | an embedded tileset with a drawing offset | done |
| [R3](#r3) | a sheet with a margin and a spacing | |
| [R4](#r4) | a collection of images | done |
| [R5](#r5) | one tile in all eight orientations | done |
| [R6](#r6) | tile layers stored as CSV | done |
| [R7](#r7) | the gzip twin | |
| [R8](#r8) | a group layer, with opacity on it and on a child | done |
| [R9](#r9) | a hidden layer, and a translucent one | done |
| [R10](#r10) | two image layers | |
| [R11](#r11) | an animated tile | done |
| [R12](#r12) | solid tiles from two tilesets | done |
| [R13](#r13) | properties of all eight types | |
| [R14](#r14) | a multi-line string | |
| [R15](#r15) | every object shape | done |
| [R16](#r16) | the Infinite twin | |
| [R17](#r17) | 64×48, the ground filled | |
| [R18](#r18) | an object from a template | |
| [R19](#r19) | Tiled's own picture | |
| [R20](#r20) | a tile object that takes its tile's class | |
| [R21](#r21) | a tileset with an object alignment | |
| [R22](#r22) | both draw orders | |
| [R23](#r23) | the `actors` mark | |

## The check, and the example that plays the map

Two halves, still rough:

- **Checked.** A `describe` block in `spec/example_assets_spec.rb`, one example
  per requirement, each failing with what to change in Tiled: "R5: layer
  `orientations` is missing flip-bit combinations [3, 6]; paint the row again
  from the table". That file is already the precedent. Its `town.tmx` block
  asserts the fence has exactly one gap, and says in a comment which mistake it
  caught.
- **Played.** An example under `examples/` that draws the map, with a drive
  script under `tools/drive/examples/`, following the
  [write-example](../../../.claude/skills/write-example/SKILL.md) skill. It is
  the only tier where all three layers are present at once, and the only one
  that would catch a map that parses and draws wrong. What it should do depends
  on what the map contains, and on the nodes this plan builds from its objects.
  It plays the second map, the level, whose requirements step 8 writes once
  rgame exports its types (see the [roadmap](04-roadmap.md)).

## What to hand over

Everything goes in one new directory, `examples/assets/tiled_tour/`:

| File | What it is |
|---|---|
| `tour.tmx` | the map — fixed size, layer data in CSV |
| `tour_gzip.tmx` | the same map, layer data in base64 + gzip ([R7](#r7)) |
| `tour_infinite.tmx` | the same map, saved Infinite and shifted north-west ([R16](#r16)) |
| `tour_reference.png` | Tiled's own picture of the map ([R19](#r19)) |
| `*.tsx` | the external tilesets ([R1](#r1)) |
| `*.tx` | the object template ([R18](#r18)) |
| `*.png` | every image a tileset or image layer names |
| `tour.tiled-project` | the Tiled project holding the custom class definitions ([R13](#r13)) |

The directory name and the `tour` prefix can change. The check takes its
paths from one constant.

**`.gitignore` leaves out `*.tiled-session`.** Tiled writes one beside the
project, holding one person's open files, window state and absolute paths. A
session committed before the entry existed stays tracked until
`git rm --cached` removes it.

## Ground rules

These apply to every file above.

- **Tiled 1.12 or later.** 1.12 added the capsule [R15](#r15) asks for. And
  1.9 wrote a tile's class as `class` where later versions write `type`; the
  parser reads both, but the map should say which Tiled wrote it. The check
  prints the `tiledversion` attribute it found.
- **Every class starts with a lower-case letter**, such as `tree`: on the map,
  a layer, a tileset, a tile or an object, and in the Custom Types Editor. From
  [step 5](04-roadmap.md#step-5--mount-builds-the-object-layers-rough) on, a
  scene that mounts a map builds a node for each object whose class starts with
  a capital letter. This map is a format checklist, and it should build nothing.
- **Tiled saves every file, and nobody edits one afterwards.** A hand edit makes
  the file this parser's reading of the format again, which is the circle the
  map exists to break. `town.tmx` carries a hand-written header comment; this map
  does not, and `examples/assets/README.md` carries the explanation instead.
- **Orthogonal, right-down, 16×16 tiles.** Set these in **File › New › New Map…**.
  Every tileset uses 16×16 tiles too, collections included. Other orientations
  are refused by design ([decision 1](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/README.md#decisions-already-taken)), and
  mixed tile sizes are not supported.
- **Every image is CC0 or drawn here**, with nothing in between.
  `examples/assets/README.md` gets a source, author, licence and modification
  entry for each one. Its opening paragraph says why: this directory ships inside
  the gem. Kenney's *Tiny Town*, already used by `tileset.png`, is CC0 and ships
  its tiles as a packed sheet, a spaced sheet and single PNGs.
- **No file name starts with a dot.** The gemspec's glob would leave it out of
  the gem.
- **Leave `examples/assets/tileset.tsx` alone.** `tour.tmx` may use it — see
  [R1](#r1) — but `town.tmx` and four examples depend on it staying as it is.

## Order of work

Three of the files are copies of the first, so the order matters.

1. Build `tour.tmx` until it meets R1–R15, R17, R18 and R20–R23. Save it.
2. Export `tour_reference.png` from it ([R19](#r19)).
3. Change the layer format and **Save As** `tour_gzip.tmx` ([R7](#r7)).
4. Reopen `tour.tmx`, make it Infinite, shift it, and **Save As**
   `tour_infinite.tmx` ([R16](#r16)).

**Save As switches the open document to the new file.** Close each twin once it
is saved, and reopen `tour.tmx` before changing anything. Any later change to
the map means redoing steps 2–4, and the check catches a twin that has drifted.

---

## The requirements

### R1

**Two external tilesets, each used by at least one cell.**

- **In Tiled:** **Map › Add External Tileset…** for one, and **File › New › New
  Tileset…** with **Embed in map** unticked for the other. One of them may be
  `../tileset.tsx`.
- **Why:** a gid from the second tileset has to resolve through the second
  tileset. Today it resolves through the first and indexes the wrong tile
  ([F2](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/01-current-state.md#f2)). Using `../tileset.tsx` also resolves a path
  that climbs out of the map's directory.
- **The check reports:** "R1: found N external tilesets, and tileset X has no tile
  on the map — add a second .tsx with Map › Add External Tileset… and paint with
  it."

### R2

**A third tileset embedded in the `.tmx`, used by at least one cell, with a
drawing offset.**

- **In Tiled:** **File › New › New Tileset…** with **Embed in map** ticked. Then
  in its tileset properties set **Drawing Offset** to something other than
  `0, 0`, such as `0, -4`.
- **Why:** an embedded tileset has no `source` attribute and holds its `<image>`
  and `<tile>`s inline — the parser's other branch. The drawing offset is the
  `<tileoffset>` element [decision 6](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/README.md#decisions-already-taken) adds.
- **The check reports:** "R2: no embedded tileset in use — tick Embed in map when
  creating one" or "R2: the embedded tileset has no drawing offset — set Drawing
  Offset in Tileset Properties."

### R3

**One sheet tileset with a margin and a spacing, both non-zero and different
from each other.**

- **In Tiled:** set **Margin** and **Spacing** in the New Tileset dialog, or later
  in its tileset properties. Use a sheet that really has them — margin 2 and
  spacing 1, say. If no CC0 sheet has a margin, pad one with a transparent border
  and record the change in `examples/assets/README.md`. Paint at least one tile
  that sits neither in the sheet's first row nor in its first column.
- **Why:** `Image#tiles` ignores both today, so such a sheet draws smeared
  ([F5](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/01-current-state.md#f5)). The two must differ, or a slicer that swaps
  them passes. A tile in the first row or column hides an error that
  accumulates per column or per row.
- **The check reports:** "R3: no tileset has margin > 0 and spacing > 0 with
  margin ≠ spacing" or "R3: every tile used from tileset X sits in its first row
  or column — paint one further in."

### R4

**One tileset that is a collection of images, with at least two images placed
on a tile layer.**

- **In Tiled:** **File › New › New Tileset…**, type **Collection of Images**, then
  add 16×16 PNGs with the **Add Tiles** button in the tileset editor. The single
  tile PNGs from *Tiny Town* fit.
- **Why:** a collection has no sheet to slice. The glue loads one image per tile
  and must hand the renderer the same flat Array a sheet would give
  ([step 5, rule 3](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-5--the-renderer-and-slicing-a-real-sheet)).
- **The check reports:** "R4: no collection-of-images tileset" or "R4: collection X
  has N tiles on the map, needs 2."

### R5

**One asymmetric tile, painted in all eight orientations, in a tile layer named
`orientations` that holds nothing else.**

- **In Tiled:** pick a tile whose picture changes under every flip and every
  quarter turn — an arrow, a signpost, a letter; not a tree. With the **Stamp
  Brush**, **X** flips the stamp horizontally and **Z** turns it a quarter
  clockwise. Paint eight cells in a row, left to right:

  | Cell | Keys before painting |
  |---|---|
  | 1 | none |
  | 2 | Z |
  | 3 | Z Z |
  | 4 | Z Z Z |
  | 5 | X |
  | 6 | X Z |
  | 7 | X Z Z |
  | 8 | X Z Z Z |

  Reset the stamp between cells by picking the tile again.
- **Why:** those eight are every orientation a square can have, so the file
  holds every combination of Tiled's three flip bits. The bits never arrive
  one by one — a quarter turn sets the diagonal and horizontal bits together —
  which is why the row asks for turns and mirrors rather than for single bits.
  Decoding the bits into turns is the table
  [step 5](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-5--the-renderer-and-slicing-a-real-sheet) must get
  right, and a wrong entry draws a plausible picture. The reference image
  ([R19](#r19)) says what Tiled drew; the row says where to look.
- **The check reports:** "R5: layer `orientations` holds flip-bit combinations
  [0, 5, …] — missing [3, 6]; paint the row again from the table." Or, from the
  pixel check: "R5: cell 6 draws differently from tour_reference.png."

### R6

**`tour.tmx` stores every tile layer as CSV.**

- **In Tiled:** **Map › Map Properties…**, **Tile Layer Format** → **CSV**.
- **Why:** CSV reaches today's base64 decoder and decodes to garbage
  ([F1](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/01-current-state.md#f1)). `town.tmx` already covers base64 + zlib.
- **The check reports:** "R6: layer X in tour.tmx has encoding Y — set Tile Layer
  Format to CSV."

### R7

**`tour_gzip.tmx` is `tour.tmx` saved as base64 + gzip, and nothing else
differs.**

- **In Tiled:** with `tour.tmx` finished, set **Tile Layer Format** to
  **Base64 (gzip compressed)** and **File › Save As…** `tour_gzip.tmx`. Close it
  without further changes.
- **Why:** two encodings of one map must decode to one grid. Generated fixtures
  test each encoding against a grid this parser also wrote; the twins test them
  against each other, as Tiled wrote both.
- **The check reports:** "R7: tour_gzip.tmx differs from tour.tmx at layer X, cell
  (c, r) — save the twin again from the current tour.tmx."

### R8

**A group layer holding at least two tile layers, with an opacity below 1 on the
group and on one child.**

- **In Tiled:** **Layer › New › Group Layer**, then drag two tile layers into it
  in the Layers panel. Set **Opacity** on the group to 0.8 and on one child to 0.5,
  say. Give every layer a name that is unique within its group.
- **Why:** the transform flattens groups depth first, and a child's opacity is
  the product down the tree
  ([step 4, rule 4](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-4--tilemap-and-the-transform)). Only a
  group and a child that both have one show the product. The names exercise
  `layer_index('Group/child')`.
- **The check reports:** "R8: no group layer with two tile layers" or "R8: group X
  and its children all have opacity 1 — lower the group's and one child's."

### R9

**One hidden tile layer that holds a solid tile, and one visible tile layer with
opacity below 1.**

- **In Tiled:** untick the eye in the Layers panel for the first. Paint on it at
  least one tile marked solid ([R12](#r12)), over ground that looks different, so
  drawing it by mistake shows. For the second, set **Opacity** to 0.5, say, over a
  contrasting layer beneath.
- **Why:** a hidden layer bakes and draws nothing
  ([step 5, rule 5](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-5--the-renderer-and-slicing-a-real-sheet))
  but still counts for collision
  ([step 4, rule 7](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-4--tilemap-and-the-transform)). The solid
  tile on it is what tests the second half.
- **The check reports:** "R9: no hidden tile layer", "R9: hidden layer X holds no
  solid tile" or "R9: no visible layer has opacity below 1."

### R10

**Two image layers: one with a non-zero offset, one with Repeat X on.**

- **In Tiled:** **Layer › New › Image Layer**, then pick the file with **Image**
  in the Properties panel. Set **Offset** on one; tick **Repeat X** on the other.
- **Why:** `TileMapRenderer` draws an image layer from
  [step 6](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-6--the-rest-of-what-tiled-shows-and-a-slot-per-gap)
  on, at its offset and repeated. The
  offset is also one of the coordinates the Infinite twin must shift
  ([R16](#r16)).
- **The check reports:** "R10: no image layer with an offset" or "R10: no image
  layer with Repeat X."

### R11

**An animated tile of at least two frames with different durations, from a
tileset whose first gid is not 1, painted on the map.**

- **In Tiled:** in the tileset editor, select a tile and open the **Tile
  Animation Editor** from the toolbar. Drag in two or more frames and give them
  different durations — 200 ms and 400 ms, say. Use any tileset listed after
  the first.
- **Why:** frame durations convert from milliseconds to seconds once, at load
  ([step 4, rule 9](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-4--tilemap-and-the-transform)). Equal
  durations would hide a frame read with the wrong one's length. A tileset
  after the first catches frame ids resolved against the wrong offset.
- **The check reports:** "R11: no animated tile on the map from a tileset after the
  first" or "R11: tile X's frames all last N ms — give them different
  durations."

### R12

**Solid tiles, marked with collision shapes, from at least two tilesets — one
shape with a class and a property.**

- **In Tiled:** in the tileset editor, select a tile and open the **Tile Collision
  Editor** from the toolbar. Draw a rectangle over the whole tile. On one shape,
  set **Class** to `water` and add a property, say `depth` of type `int`.
- **Why:** solidity stays whole-cell, and a tile is solid when it has any shape
  ([decision 7](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/README.md#decisions-already-taken)). Two tilesets check
  solidity survives renumbering into one tile table. The class and property are
  what a game reads to tell water from wall
  ([F12](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/01-current-state.md#f12)).
- **The check reports:** "R12: solid tiles found only in tileset X" or "R12: no
  collision shape has a class and a property."

### R13

**Custom properties of all eight types, and at least one property on each of
the five kinds of element that carry them.**

- **In Tiled:** add properties with the **+** in the Properties panel, choosing
  the type in the dialog. Put them across the map, a layer, a tileset, a tile and
  an object. Across those, cover:

  | Type | What to put in it |
  |---|---|
  | `string` | anything one line long |
  | `int` | a negative number |
  | `float` | a number with a fraction |
  | `bool` | one `true` and one `false` |
  | `color` | one opaque and one semi-transparent |
  | `file` | a file in another directory, such as `../tileset.png` |
  | `object` | an object from [R15](#r15) |
  | `class` | a class with a member that is itself a class |

  Define the classes in **View › Custom Types Editor**, and name them in lower
  case. **Set every member of a class property to a non-default value.** Tiled
  writes only the members that differ from the class's defaults, and the
  defaults live in the project file, which the parser does not read. Save the
  project as `tour.tiled-project` so the next person to open the map has the
  classes. Also set a **Class** on the map, a layer, a tileset and a tile.
- **Why:** [step 1](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-1--enginetiledproperties-pure) casts each
  type at parse time. Tiled writes an opaque colour as `#RRGGBB` and a translucent
  one as `#AARRGGBB`, alpha first, so both forms must appear. A `false` bool is
  the one a String `"false"` would get wrong. A `file` in another directory is
  the only way to see which directory it resolves against. From
  [step 1b](04-roadmap.md#step-1--the-parse-and-the-transform-enginetiled-and-tilemap-pure)
  of this plan, a class value keeps its class's name, and so does a member that
  is itself a class. The check reads both names.
- **The check reports:** "R13: no property of type X", "R13: no custom property on
  any Y", or "R13: class property X (class `y`) has no member that is itself a
  class."

### R14

**A multi-line `string` property.**

- **In Tiled:** open the value of a string property in its multi-line editor and
  type two or more lines.
- **Why:** Tiled writes a multi-line value as the element's text instead of its
  `value` attribute
  ([step 1, rule 4](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#the-rules-the-tests-pin)).
- **The check reports:** "R14: no string property spans two lines."

### R15

**An object layer holding a rectangle, a point, an ellipse, a capsule, a
polygon, a polyline, a text object and two tile objects — one of them rotated.**

- **In Tiled:** **Layer › New › Object Layer**, then the **Insert Rectangle**,
  **Insert Point**, **Insert Ellipse**, **Insert Capsule**, **Insert Polygon**,
  **Insert Text** and **Insert Tile** tools. A polyline is the polygon tool
  finished without closing the shape. Rotate one tile object by 90° in the
  Properties panel, and flip the other with **X**. Give at least one object a
  name, a class and a property.
- **Why:** each shape is one branch of the object parse. The capsule is the
  branch this map found missing: rgame read it as a rectangle of the same size,
  which [step 1a](04-roadmap.md#step-1--the-parse-and-the-transform-enginetiled-and-tilemap-pure)
  of this plan fixes. From a tileset whose object alignment is *Unspecified*, a
  tile object's position is its **bottom-left** corner, and it rotates about
  that same corner
  ([the objects section](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/03-design.md#objects-one-record-in-the-games-coordinates)).
  Two traps compose there, and only a rotated tile object shows both. A text
  object is parsed and ignored, and a Tiled-written one checks the parser does
  not stop on it.
- **The check reports:** "R15: the object layers hold no X" or "R15: no tile object
  has a rotation."

### R16

**`tour_infinite.tmx` is `tour.tmx` saved Infinite, with everything moved 16
tiles west and 16 tiles north.**

- **In Tiled:** reopen `tour.tmx`. In **Map › Map Properties…** tick
  **Infinite**, and leave **Output Chunk Width** and **Height** at 16. Then
  **Map › Offset Map…** by `-16, -16` over all layers, with wrapping off. Check
  that the objects and image layers moved with the tiles, and **File › Save As…**
  `tour_infinite.tmx`.
- **Why:** an infinite map stores chunks, and some of them sit at negative
  coordinates. The transform flattens them and shifts every tile, object and
  image offset by one amount, in one place
  ([step 4, rule 11](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-4--tilemap-and-the-transform)). The
  twins must then build the same `TileMap`. That holds only if the chunk grid
  lines up with the map's edges — the map's size ([R17](#r17)) and the offset
  are both multiples of 16 for that reason.
- **The check reports:** "R16: tour_infinite.tmx has no tile at a negative column
  and row — use Map › Offset Map…", or "R16: tour_infinite.tmx builds a
  different TileMap from tour.tmx at X."

### R17

**64×48 tiles, with the ground filled edge to edge.**

- **In Tiled:** the size in **File › New › New Map…**, or later in **Map › Resize
  Map…**. Paint a ground layer that has a tile in every cell.
- **Why:** both sides are multiples of 16, which [R16](#r16) needs, and a full
  ground layer makes the Infinite twin's chunks cover the same rectangle. And
  1024×768 pixels is larger than the 640×480 window on both axes, so
  [R19](#r19)'s check draws the map in more than one view. The renderer culls
  animated tiles and repeated image layers to the view, and a map that fits one
  window never tests that.
- **The check reports:** "R17: the map is W×H — make it 64×48" or "R17: ground cell
  (c, r) is empty."

### R18

**One object placed from a template, with one attribute changed on the
placement.**

- **In Tiled:** right-click an object and choose **Save As Template**, saving the
  `.tx` beside the map. Place it again with the **Insert Template** tool, then
  change its name or a property on that placement only.
- **Why:** the parser resolves a `<template>` against its `.tx`, and the object's
  own attributes win
  ([step 3, rule 9](https://github.com/psuessenb/rgame/blob/dcb07f837d8f0c1861aa12832bdc91663d392374/docs/plans/tiled-format/04-roadmap.md#step-3--enginetiledmap-and-the-layer-tree-pure)).
  An overridden attribute is the only way to see which side won.
- **The check reports:** "R18: no object uses a template" or "R18: the templated
  object overrides nothing."

### R19

**`tour_reference.png`: Tiled's own picture of `tour.tmx`.**

- **In Tiled:** hide the object layers, then **File › Export As Image…** with
  **Only include visible layers** ticked, **Use current zoom level** and **Draw
  tile grid** unticked. Show the object layers again; whether they are visible
  in the saved `.tmx` does not matter.
- **Why:** the Tiled format plan pinned its orientation table and opacity
  against what Tiled shows, and this file is what Tiled showed. The check draws
  the tile and image layers and compares pixels, masking the animated tile's
  cells, whose frame the export does not fix. It leaves the object layers out,
  as the export does: Tiled draws every shape, and rgame draws none. rgame draws
  tile objects from
  [step 5](04-roadmap.md#step-5--mount-builds-the-object-layers-rough) of this
  plan on, and they are checked where they are played, in the level.
- **The check reports:** "R19: the drawn map differs from tour_reference.png at
  pixel (x, y), in cell (c, r) of layer X."

### R20

**A tile object with no class of its own, placed from a tile whose class is set
in its tileset, and a second tile object from the same tile with a class of its
own.**

- **In Tiled:** select a tile in the tileset editor and set its **Class** in the
  Properties panel, such as `tree`. Place it twice with **Insert Tile**. Leave
  the first object's **Class** empty, and give the second a different one, such
  as `stump`. R15's two tile objects will do, once their tile has a class.
- **Why:** Tiled says a tile's class "is inherited by tile objects", but writes
  the class only on the tile. A loader that reads the object alone finds none.
  [Step 1b](04-roadmap.md#step-1--the-parse-and-the-transform-enginetiled-and-tilemap-pure)
  gives such an object its tile's class, and from
  [step 5](04-roadmap.md#step-5--mount-builds-the-object-layers-rough) on the class
  decides what the object builds. The object's own class wins, and only the second
  object shows which side won, as the override does in [R18](#r18).
- **The check reports:** "R20: no tile object without a class comes from a tile
  with one — set Class on the tile in the tileset editor" or "R20: no tile object
  overrides its tile's class."

### R21

**A tileset whose Object Alignment is neither *Unspecified* nor *Bottom Left*,
with two tile objects placed from it, one of them rotated.**

- **In Tiled:** pick a tileset other than `../tileset.tsx`, which stays as it
  is, and other than the one R15's tile objects come from. In its **Tileset
  Properties**, set **Object Alignment**, such as *Center*. Place two tile
  objects from it, and rotate one by 90° in the Properties panel.
- **Why:** the alignment says which point of a tile object its position names.
  [Step 1b](04-roadmap.md#step-1--the-parse-and-the-transform-enginetiled-and-tilemap-pure)
  turns each of Tiled's nine into the top-left corner rgame uses. *Unspecified*
  means bottom-left on an orthogonal map, so *Bottom Left* would read right even
  if the alignment were ignored. Tiled turns an object about its position, so
  only a rotated object shows whether the corner moved before the turn or after
  it. R15's tileset stays *Unspecified*, and the map keeps both paths.
- **The check reports:** "R21: no tileset sets an object alignment other than
  bottom-left" or "R21: no tile object from tileset X has a rotation."

### R22

**Two object layers, one drawn *Top Down* and one *Manual*, each holding an
object.**

- **In Tiled:** select an object layer and set **Draw Order** in the Properties
  panel. *Top Down* is the default.
- **Why:** Tiled writes *Manual* as `draworder="index"` and leaves the attribute
  out for *Top Down*, so each layer takes a different branch of the parse.
  [Step 1c](04-roadmap.md#step-1--the-parse-and-the-transform-enginetiled-and-tilemap-pure)
  reads the order as `y_sort?`. From
  [step 5](04-roadmap.md#step-5--mount-builds-the-object-layers-rough) on, a *Top Down*
  layer sorts its nodes by y, and a *Manual* one keeps Tiled's list order.
- **The check reports:** "R22: no object layer is drawn Manual" or "R22: no object
  layer is drawn Top Down."

### R23

**The *Top Down* object layer from [R22](#r22) carries a bool property `actors`
set to `true`, and no other layer does.**

- **In Tiled:** select the layer and add a property with the **+** in the
  Properties panel. Name it `actors`, choose `bool`, and tick it.
- **Why:** the mark says where the heroes a scene spawns in code go. From
  [step 5](04-roadmap.md#step-5--mount-builds-the-object-layers-rough) on,
  `slots[:actors]` is the marked layer's node, so the heroes sort by y
  against the objects placed in it. That is why the mark belongs on a *Top Down*
  layer.
  [Step 1c](04-roadmap.md#step-1--the-parse-and-the-transform-enginetiled-and-tilemap-pure)
  reads the mark once, as it reads `above`.
- **The check reports:** "R23: no object layer carries a bool `actors` set to
  true." A mark that is not a bool, a mark on a layer that is not an object layer,
  and marks on two layers each fail the load, and the check reports that error.
