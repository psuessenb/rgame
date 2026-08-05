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
