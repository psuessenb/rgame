# Example assets

Everything the examples draw and play. Twenty files besides this one, about
131 KB in total — of which the music is 93 KB, and the reason for `tools/shrink_ogg.c`.

## Why these files and not the ones in `media/`

`media/` is gitignored because its contents cannot be redistributed. These can:
**this directory ships inside the gem**, so every `gem install rgame`
redistributes each file below to somebody else. That is the test any asset here
has to pass — not "may I use it in my game" but *"may I hand copies of it to
everyone who installs this library"* — and it is why the rule is CC0 or
authored here, with nothing in between. A licence that merely permits use, or
asks for a credit line, would attach an obligation to rgame and to everyone
downstream of it.

CC0 waives copyright entirely, so none of the sources below require a licence
file to be shipped alongside them or a credit to be given. This README is
recorded anyway: provenance is the thing that becomes impossible to reconstruct
later, and "where did this PNG come from" is not a question anyone should have
to answer from memory.

## The files

### `tileset.png` — Kenney, *Tiny Town*

- Source: <https://kenney.nl/assets/tiny-town>
- Licence: CC0 1.0 (stated on the page and in the `License.txt` inside the
  download)
- Modification: none. This is `Tilemap/tilemap_packed.png` from the pack,
  copied unchanged.

16x16 tiles, 12 columns x 11 rows = 132 tiles, 192x176 pixels. Kenney asks for
a credit but does not require one; the licence is CC0 either way.

### `tileset.tsx` — ours

A Tiled tileset over `tileset.png`. Written here rather than taken from the
pack, because the pack has no Tiled metadata and because **collision lives in
this file**: `RGame::Engine::Tileset` treats a tile as solid when it carries an
`<objectgroup>` with at least one object, which is what Tiled's per-tile
collision editor writes. There is no solid-tile list in code to fall back on, so
a tile with no shape here is walkable no matter what it looks like.

Solid tiles are the trees and the fence pieces: **3, 4, 5, 15, 16, 27, 28** and
**44, 45, 46, 47**. Everything else — grass, sand, mushrooms, plants, buildings,
items — is walkable. That is a deliberate floor rather than an inventory: the
examples only need vegetation and fences to be obstacles, and marking a tile
solid that no example places is a claim nothing checks. Add shapes in Tiled as
new examples need them.

### `town.tmx` — ours

60x40 tiles = 960x640 pixels, deliberately larger than the 640x480 window on
both axes so a camera has somewhere to scroll. Two tile layers, `ground`
(entirely walkable) and `obstacles` (a tree border, a fence across the middle,
scattered trees), and an object layer, `doors`.

Layer data is **base64 + zlib**, which is what `RGame::Engine::TileMap.parse`
reads — it inflates the layer and unpacks little-endian `uint32` gids. CSV will
not load. Tiled writes this format when the layer format is set to "Base64
(zlib compressed)"; keep it that way when editing.

The fence has exactly one gap, at x=12..14, far west of both clearings. The
placement is the point, and it took two tries to get right:

- **A gap between the start and the goal is not an obstacle.** With the gap at
  x=29..31 the shortest route cost exactly the straight-line distance — 55 steps
  against a 55-step Manhattan distance — so a pathfinder would have drawn what
  looks like a straight line. Out west, the same trip is 84 steps against 22,
  and the walker has to head *away* from its goal to get through.
- **A fence has to span the whole interior.** Stopping it a tile short of the
  border left a second gap nobody planned, at x=58, and the route quietly used
  that one instead. It now runs x=1..58, and the fence row is solid everywhere
  except the three gap tiles.

The `doors` layer holds what `examples/doors` moves a hero through. Each object
has a class, and a door names where it goes in its properties:

| Object | Class | Properties |
|---|---|---|
| `start`, `square`, `gate_out` | `entrance` | |
| `garden_gate` | `door` | `to: garden`, `entrance: gate_in` |

An entrance is a point, where a node arriving stands. A door draws itself, so
the layer changes no tile, and `spec/fixtures/town_solidity.txt` still pins
every solid cell.

### `garden.tmx` — ours

40x30 tiles = 640x480 pixels, the window exactly, for `examples/doors`. A
garden of grass and flowers, walled with trees (tile 16), with a few small trees
(tile 28) standing in it.

Written by a short Ruby script rather than in Tiled, as `puzzle.tmx` was, in
the same base64 + zlib format over the same `tileset.tsx`. Edit it in Tiled
like the others. Its `doors` layer:

| Object | Class | Properties |
|---|---|---|
| `start`, `gate_in`, `beside_a`, `beside_b` | `entrance` | |
| `gate` | `door` | `to: town`, `entrance: gate_out` |
| `pad_a`, `pad_b` | `warp` | `entrance: beside_b`, `entrance: beside_a` |
| `horn` | `door` | `to: town`, `entrance: square`, `party: true` |

A warp is a door into its own room, so it names only an entrance. A door marked
`party` moves every hero, and any other door moves the hero who touched it.
`spec/example_assets_spec.rb` holds both maps to three rules: a door's
entrance exists on the map it leads to, no entrance lies on a door, and every
door and entrance stands on walkable ground.

### `puzzle.tmx` — ours

40x30 tiles = 640x480 pixels, the window exactly, for `examples/block_puzzle`.
A room of grass sixteen tiles by twelve, walled with trees (tile 16) and set in
a forest of them, with a three-tile wall of trees standing inside. The blocks and
their squares are nodes the example places, not part of the map.

Written by a short Ruby script rather than in Tiled, in the same base64 + zlib
format as `town.tmx`, over the same `tileset.tsx`. Edit it in Tiled like the
other.

### `pits.png` + `pits.tsx` — ours

Two 16x16 tiles for a pit in Tiny Town, side by side, drawn by
`tools/draw_pit_tiles.rb` rather than by hand, so they can be drawn again. Run
it and it writes the same bytes. Tile 0 is the pit, near-black and flecked. Tile
1 is its north edge, for a gap cell with floor north of it: Tiny Town's dark
outline, then a striped face of earth in the tileset's dirt colours, darkening
into the pit. The colours are read off `tileset.png`.

`pits.tsx` is the Tiled tileset over it, and gives both tiles the class `gap`.
That class is what makes a cell a gap to `RGame::Engine::TileMap`: no floor, so
a walker falls in and a hop crosses. `spec/example_assets_spec.rb` holds every
tile in it to that class.

### `pits.tmx` — ours

40x30 tiles = 640x480 pixels, the window exactly, for `examples/pits`. A meadow
walled with trees (tile 16). Three trenches one tile wide run south from the
trees at x = 12, 18 and 24 tiles, close enough to hop, into a chasm eight tiles
deep across the south of the map. The gaps are on their own layer, `pits`, over
`pits.tsx`. The point object `start` in the `spawns` layer is where the hero
first stands, and `spec/example_assets_spec.rb` holds it to standing on floor.

Written by a short Ruby script rather than in Tiled, as `puzzle.tmx` was, in the
same base64 + zlib format over `tileset.tsx` and `pits.tsx`. Edit it in Tiled
like the others.

### `ui.png` + `ui.json` — Kenney, *UI Pack - Pixel Adventure*

- Source: <https://kenney.nl/assets/ui-pack-pixel-adventure>
- Licence: CC0 1.0 (stated on the page and in the `License.txt` inside the
  download)
- Modification: five 32x32 tiles were cut out of
  `Tilesheets/Large tiles/Thick outline/tilemap_packed.png` and laid side by
  side. The pixels are untouched; only the sheet is ours.

The pack is 91 tiles and we use five, so shipping the strip rather than the
sheet keeps this to 1 KB and makes the descriptor readable — each element is at
a round multiple of 32.

**This is not optional chrome.** `RGame::Engine::UI::PanelButton` draws its
background with `renderer.nine_slice`, and a nine-slice id is resolved by
*registration* only — it names an element of an atlas, never a file — so
`UI::Menu` cannot draw at all without one of these registered. Which elements
are needed is not our choice either: `PanelButton::STYLE` names `button_idle`,
`button_focus`, `button_pressed` and `button_disabled`, and a menu draws each of
them when an item reaches that state.

Two things constrained which tiles could be used, both discovered by looking:

- **Several of the pack's panels are frames with transparent middles.** They
  read as solid panels on the sheet's dark background and then show the world
  through them. The five here are all filled.
- **`PanelButton`'s label colour defaults to** a dark brown, with a muted grey
  for a disabled item, so with the default the buttons have to be *light* or the
  label disappears into them. `label_color:` changes it.

`border` is 8 for every element: the largest decorated frame in the set is 8
pixels, the interiors are flat, and a uniform value keeps a button's inner
geometry from shifting as it changes state.

### `hero.png` + `hero.json` — sodri's *Character 4 directional walking*, repacked

- Source: <https://opengameart.org/content/character-4-directional-walking>
- Author: sodri
- Licence: CC0
- Modifications, both ours: the white background was keyed out, and the four
  separate strips were repacked into one uniform sheet.

The original is four PNGs — `walk_down`/`walk_up` at 14x22 per frame,
`walk_left`/`walk_right` at 13x22 — fully opaque, with a pure white background.
Two things had to change before `RGame::Core::SpriteSheet` could read it:

- **Transparency.** Pure white was replaced with alpha 0. Checked first rather
  than assumed: flood-filling from the borders showed white is only ever
  background — the handful of enclosed white pixels are the gaps between arm and
  torso — and the art uses 7 to 9 colours with no near-white among them, so a
  flat colour key cannot eat anything intended.
- **A uniform grid.** A sheet is one fixed cell size, so each frame was centred
  horizontally in a 16x22 cell (`(16 - w) // 2`, so the 13px-wide side frames
  sit one pixel left of true centre — half a pixel of asymmetry between facings,
  which nothing can see).

`walk_left` is not in the sheet. Every left frame is a pixel-exact mirror of its
right counterpart — verified frame by frame, not assumed — so the descriptor
reuses row 2 with `"flip_x": true` and the sheet is three rows instead of four.

Layout, 6 columns x 3 rows of 16x22:

| Row | Animation |
|---|---|
| 0 | `walk_down`, and `stand` is its first column |
| 1 | `walk_up` |
| 2 | `walk_right`, and `walk_left` mirrored |

There is no idle art in the original, so `stand` is a single frame off the walk
cycle rather than an animation of its own.

### `glyphs.png` + `glyphs.json` — Kenney, *Input Prompts*, repacked

- Source: <https://kenney.nl/assets/input-prompts>
- Licence: CC0 1.0 (stated on the page and in the `License.txt` inside the
  download)
- Modification: five 64x64 PNGs were laid side by side into one strip. The
  pixels are untouched; only the sheet and the descriptor are ours.

The pack is thousands of files across seventeen controller families, and
`examples/input_glyphs` names five buttons, so the strip is 3 KB where the
download is 5 MB.

Layout, 5 columns x 1 row of 64x64, and **the order is the example's table**:
`GLYPH_COLUMN` in `examples/input_glyphs/main.rb` maps a `Controls` button id to
a column here.

| Column | Button id | From the pack |
|---|---|---|
| 0 | `KEY_SPACE` | `Keyboard & Mouse/Default/keyboard_space.png` |
| 1 | `KEY_RETURN` | `Keyboard & Mouse/Default/keyboard_enter.png` |
| 2 | `KEY_ESCAPE` | `Keyboard & Mouse/Default/keyboard_escape.png` |
| 3 | `PAD_A` | `Xbox Series/Default/xbox_button_color_a.png` |
| 4 | `PAD_B` | `Xbox Series/Default/xbox_button_color_b.png` |

**Xbox rather than PlayStation or Switch**, because SDL's button names are
Xbox's — `PAD_A` is SDL's A — and a sheet whose faces disagree with the ids
would make every prompt a translation. A game that wants the pad in the player's
actual hands ships a second sheet per family and picks a table; the ids do not
change, only the pictures.

The keyboard glyphs are light and the pad glyphs are the pack's colour versions,
so both need a dark panel under them — which is what `examples/input_glyphs`
draws.

### `icons.png` + `icons.json` — Kenney, *Game Icons*, repacked

- Source: <https://kenney.nl/assets/game-icons>, mirrored with the same licence
  at <https://opengameart.org/content/game-icons>
- Licence: CC0 1.0 (stated on the page and in the `license.txt` inside the
  download)
- Modification: eight 50x50 PNGs were laid side by side into one strip. The
  pixels are untouched; only the sheet and the descriptor are ours.

Layout, 8 columns x 1 row of 50x50, named in the descriptor's `images` section
in `snake_case`:

| Column | Name | From the pack |
|---|---|---|
| 0 | `home` | `PNG/White/1x/home.png` |
| 1 | `gear` | `PNG/White/1x/gear.png` |
| 2 | `save` | `PNG/White/1x/save.png` |
| 3 | `star` | `PNG/White/1x/star.png` |
| 4 | `trophy` | `PNG/White/1x/trophy.png` |
| 5 | `audio_on` | `PNG/White/1x/audioOn.png` |
| 6 | `music_on` | `PNG/White/1x/musicOn.png` |
| 7 | `locked` | `PNG/White/1x/locked.png` |

**White, because a tint is a multiply.** The white variant is RGB 255 with the
shape in alpha only, so `renderer.image(..., color:)` — and `UI::IconButton`'s
per-state tints — colour it exactly; the black variant would stay black under
any tint.

**1x, because images sample nearest-neighbour.** A 50-pixel icon in
`examples/radial_menu`'s 64-pixel slots draws at scale 1 and the chosen one in
the middle at scale 2, both whole numbers; a 2x icon would need scale 0.5 or
thereabouts, which drops pixel rows unevenly.

**A strip, because the separate files carry metadata.** Each PNG in the pack
holds Adobe XMP, so the eight files are 121 KB; the strip is 2 KB. It is a UI
atlas rather than a sprite sheet so the icons are cut and registered by name —
`renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))` makes
`UI::IconButton.new(image: :home)` draw.

### `skills.png` + `skills.json` — Kenney, *Cursor Pack*, repacked

- Source: <https://kenney.nl/assets/cursor-pack>, version 1.1
- Licence: CC0 1.0 (the `License.txt` inside the download reads "License:
  (Creative Commons Zero, CC0)")
- Modification: five 64x64 PNGs were laid side by side into one strip and saved
  as RGBA. The pixels are untouched; only the sheet and the descriptor are ours.

Layout, 5 columns x 1 row of 64x64, named in the descriptor's `images` section
in `snake_case`:

| Column | Name | From the pack |
|---|---|---|
| 0 | `wand` | `PNG/Basic/Double/tool_wand.png` |
| 1 | `wrench` | `PNG/Basic/Double/tool_wrench.png` |
| 2 | `torch` | `PNG/Basic/Double/tool_torch.png` |
| 3 | `hammer` | `PNG/Basic/Double/tool_hammer.png` |
| 4 | `watering_can` | `PNG/Basic/Double/tool_watering_can.png` |

`torch` is the pack's flashlight, named for the British word. The pack has
`tool_hoe`, `tool_shovel`, `tool_axe` and `tool_pickaxe` in the same styles, if
the bar ever wants more.

**`Basic`, not `Outline`.** Both were drawn on `examples/skill_bar`'s discs in
all four states. `Basic` is a light-grey silhouette with no border, so a tint
colours all of it: grey at rest, white focused, dim disabled, dark on the gold
pressed disc. `Outline` adds a black border, which a multiply leaves black —
a disabled tool barely dims, and a pressed one is a dark shape on gold with its
edges lost.

**`Double` (64 pixels), not `Default` (32).** The glyph sits in about half its
square, so a 32-pixel cursor on an 80-pixel disc is a thumbnail. Either draws at
scale 1, which nearest-neighbour sampling needs.

**One pack per atlas.** These are not in `icons.png` so that each file's
provenance stays one paragraph; one more `register_ui_atlas` call is the whole
cost.

### `blip.ogg` — Kenney, *Interface Sounds*

- Source: <https://kenney.nl/assets/interface-sounds>
- Licence: CC0 1.0 (stated on the page and in the `License.txt` inside the
  download)
- Modification: none. This is `Audio/click_001.ogg` from the pack, renamed.

4.8 KB. The pack has 100 of these, 4 to 29 KB each, so if an example ever wants
a second sound it costs nothing to take another.

### `music.ogg` — hernandack's *Short Loops Background Music Pack*, re-encoded

- Source: <https://opengameart.org/content/short-loops-background-music-pack>
- Author: hernandack
- Licence: CC0
- Modification: the track *Just Saying Tho* downmixed to mono and re-encoded at
  Vorbis quality -0.1, with `tools/shrink_ogg.c`. **The length is unchanged.**

24.05 seconds, 93 KB, down from 388 KB. The original is stereo, 44.1 kHz,
~128 kbps — encoded for listening rather than for a library gem — and mono at a
low quality setting is background music in a teaching example.

**Length was deliberately not touched.** A seamless loop is seamless at exactly
its own length, because the author arranged for the end to lead back into the
start. Trimming it to save more bytes would put a seam in the middle of the one
property the file is shipped to demonstrate.

#### Why this is the second track here

The first one shipped was *A Brand New Wisdom* from the same pack, chosen on a
seam measurement of 2.6% — and it loops audibly badly, because **it ends with
0.79 seconds of silence.** The wrap has no click. It has a *gap*.

That is a hole in the measurement, not bad luck. A seam figure asks "does the
last sample join smoothly onto the first", and silence joins onto silence
perfectly. Fading out to nothing is the ordinary way to end a piece of music and
the ordinary way to ruin a loop, and the number said 0.7% the whole time.

`tools/shrink_ogg.c` now reports both, and the whole pack looks different under
the second one:

| track | seam | tail silence | |
|---|---|---|---|
| A Brand New Wisdom | 2.6% | **0.79s** | shipped first, wrong |
| Swinging Sweet | 4.5% | **1.48s** | worse |
| Winter Dust | 34.9% | 0.00s | no gap, bad seam |
| **Just Saying Tho** | 2.8% | **0.00s** | shipped now |
| 8BitBattleLoop (other pack) | 0.0% | 0.01s | cleanest, but 108 KB and chiptune |

Measured back off the shipped file: seam 2.3%, no silence at either end.

**A loop wants both numbers.** A small seam alone is not evidence.

## Adding an asset here

1. CC0, or drawn in this repo. If the licence says anything about redistribution
   at all, it does not go here — see the top of this file.
2. Record it above: source URL, author, licence, and every modification made.
3. **Audio is Ogg Vorbis or WAV, and nothing else.** MP3 and FLAC are compiled
   out of miniaudio (`ext/rgame_core/vendor/miniaudio_impl.c`), so a file that
   plays in every desktop player can still fail to load here.
4. No leading dots in filenames. `Dir.glob` does not match them, so the gemspec
   would silently leave the file out of the gem while the checkout kept working
   — `spec/packaging_spec.rb` has an example that catches it.
