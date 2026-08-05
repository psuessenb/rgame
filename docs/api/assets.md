# Sheets, atlases and maps

The classes between a file on disk and a draw call: a sprite sheet sliced into
frames, a nine-slice panel stretched to any size, a UI atlas, a tile map, and
the asset manager that loads and caches all of them.

They are pure Ruby, but they live in `RGame::Core` because they hold images, and
an image is a GPU handle. Game logic names them by id and never holds one — see
[Testing what a scene draws](drawing.md#testing-what-a-scene-draws).

| Page section | Class |
|---|---|
| [Sprite sheets](#sprite-sheets) | `RGame::Core::SpriteSheet` |
| [Nine-slices](#nine-slices) | `RGame::Core::NineSlice` |

*This page grows as the rest lands.*

## Sprite sheets

A sheet is one image plus a JSON descriptor, sliced into frames at load time and
drawn one frame at a time.

```ruby
sheet = RGame::Core::SpriteSheet.load(app, 'media/hero.json')

sheet.frame_width    # => 16
sheet.grid           # => [rows, columns]
sheet.animations     # => the raw table from the descriptor

sheet.draw(renderer, row, col, x, y, flip_x: false, z: 0)
```

### The descriptor

```json
{
  "image": "hero.png",
  "frame_width": 16,
  "frame_height": 24,
  "cell_width": 32,
  "cell_height": 32,
  "origin_x": 8,
  "origin_y": 4,
  "animations": {
    "walk_left": { "row": 1, "frames": 4, "fps": 8 },
    "stand":     { "row": 0, "col": 1, "frames": 1, "fps": 1 }
  }
}
```

`image` is resolved **next to the descriptor**, so a sheet can be moved as a
pair of files without editing either. `frame_width` and `frame_height` are the
only required keys; a descriptor missing one raises `ArgumentError` naming it.

### A frame can be smaller than its cell

Cells sit on a fixed `cell_width` x `cell_height` grid. What gets *drawn* is a
`frame_width` x `frame_height` rectangle offset by `origin_x` / `origin_y`
inside its cell:

```
cell (32x32)          frame (16x24) at origin (8, 4)
┌──────────────┐      ┌──────────────┐
│              │      │    ┌────┐    │
│              │      │    │    │    │
│              │      │    │    │    │
└──────────────┘      └────┴────┴────┘
```

That is what lets a sheet whose cells are sized for the widest pose — an attack,
a swing — still expose a tight, centred box for walking, so a character does not
appear to change size when its animation changes. Leave the four keys out and
frame == cell, which is what a simple sheet wants.

Only whole cells count: a sheet 70 pixels wide with 16-pixel cells has four
columns, and the six leftover pixels are ignored rather than becoming a narrow
fifth.

### Facing

`flip_x` mirrors the frame **inside the same rectangle**, so a character
occupies the same pixels whichever way it faces:

```ruby
sheet.draw(renderer, row, col, x, y, flip_x: moving_left)
```

There is no width to add back — see
[Mirroring](drawing.md#mirroring) for why, if you are coming from Gosu.

### Animations are handed back raw

`#animations` returns the descriptor's table untouched. This class knows nothing
about time: which frame to show at a given moment is the scene layer's job, and
it builds its own animation state from that hash. Keeping the raw form here is
what lets the two sides evolve separately.

A sheet with no `animations` key gets `{}`, not `nil` — a sheet of static tiles
is a legitimate sheet, and a caller should not have to branch.

### Slicing costs nothing

Every frame is cut once, at construction, as a view onto the single upload. A
sheet of two hundred frames is two hundred small objects and **one** texture, and
`#draw` is an array index plus one draw call. Nothing is re-cut per frame.

### Loading

```ruby
RGame::Core::SpriteSheet.load(app, path)   # standalone
RGame::Core::SpriteSheet.new(image, atlas) # from an already-loaded image
```

Use `.load` for a game with a sheet or two and no asset manager. The asset
manager uses the second form, with an image it has already cached, so a sheet's
PNG is shared with a standalone load of the same file rather than decoded twice.

## Nine-slices

A bordered texture drawn at any size, by cutting it into nine pieces and
treating each differently.

```ruby
panel = RGame::Core::NineSlice.new(image, x: 0, y: 0, w: 26, h: 28,
                                   border: 7, scale: 3)

panel.draw(renderer, x, y, width, height, z: 0, color: nil)
```

```
  ┌──┬────────┬──┐   corners: fixed size
  │tl│  top   │tr│   top / bottom: tiled across
  ├──┼────────┼──┤   left / right: tiled down
  │l │ centre │ r│   centre: tiled both ways
  ├──┼────────┼──┤
  │bl│ bottom │br│
  └──┴────────┴──┘
```

One small piece of art fills a button, a dialog or a health bar of any size,
without the corners smearing.

`(x, y, w, h)` is the source rectangle **inside** the image, so one sheet can
hold many of them — which is what a UI atlas does with it.

### Tiled, not stretched

Edges and the centre **repeat**. Stretching a 7-pixel motif would blur exactly
the detail the art was drawn for; repeating it keeps pixel art crisp at every
widget size. Each band is clipped to itself, so the last tile in a row is
cropped cleanly rather than spilling into the corner beside it — and the loops
always start one more tile rather than stopping short, because a gap at the seam
is more visible than an overhang that gets cropped.

### `border` and `scale`

`border` is either a uniform integer or a hash:

```ruby
border: 7
border: { left: 2, right: 6, top: 4, bottom: 4 }
```

`scale` is an **integer pixel scale for the chrome itself**. Source art is
small — corners are often 7 pixels — so a scale of 2 or 3 gives legible borders
on a 640x480 screen with no blurring at all, because every source pixel becomes
a whole square of screen pixels. It scales the pieces *and* the step between
tiles, so the tiling stays seamless.

### Edge cases, and what they do

| | |
|---|---|
| A rectangle smaller than its own borders | draws its corners and no bands |
| A border with no room for a centre (`left + right == w`) | fine — a bar that stretches only vertically |
| Borders wider than the source rect | `ArgumentError`, naming the borders and the rect |
| `scale` of zero or less | `ArgumentError` — the tiling loop would never advance |

### What it costs

The nine pieces are cut once at construction, as views onto the one upload, so
`#draw` allocates nothing. It issues one call per tile, which is what makes
`scale` worth having: a panel drawn at 3x is a ninth of the tiles of the same
panel drawn at 1x.
