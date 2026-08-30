# Example assets

Everything the examples draw. Five files, about 10 KB in total.

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
both axes so a camera has somewhere to scroll. Two layers, `ground` (entirely
walkable) and `obstacles` (a tree border, a fence across the middle, scattered
trees).

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

## Adding an asset here

1. CC0, or drawn in this repo. If the licence says anything about redistribution
   at all, it does not go here — see the top of this file.
2. Record it above: source URL, author, licence, and every modification made.
3. No leading dots in filenames. `Dir.glob` does not match them, so the gemspec
   would silently leave the file out of the gem while the checkout kept working
   — `spec/packaging_spec.rb` has an example that catches it.
