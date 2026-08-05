# Sheets, atlases and maps

The classes between a file on disk and a draw call: a sprite sheet sliced into
frames, a nine-slice panel stretched to any size, a UI atlas, a tile map, and
the asset manager that loads and caches all of them.

They are pure Ruby, but they live in `RGame::Core` because they hold images, and
an image is a GPU handle. Game logic names them by id and never holds one — see
[Testing what a scene draws](drawing.md#testing-what-a-scene-draws).

| Page section | Class |
|---|---|
| [The asset manager](#the-asset-manager) | `RGame::Core::AssetManager` |
| [Sprite sheets](#sprite-sheets) | `RGame::Core::SpriteSheet` |
| [Nine-slices](#nine-slices) | `RGame::Core::NineSlice` |
| [UI atlases](#ui-atlases) | `RGame::Core::UiAtlas` |
| [Tile maps](#tile-maps) | `RGame::Core::TileMapRenderer` |

*This page grows as the rest lands.*

## The asset manager

The one place file-backed assets are loaded and cached. Every game has one, and
does not build it — `app.assets` does, rooted at the app's `media_root:`:

```ruby
app.assets.image('space.png')                # => RGame::Core::Image
app.assets.sound('example 09/boom.ogg')      # => RGame::Core::Sample
app.assets.song('example 09/theme.ogg')      # => RGame::Core::Song
app.assets.sheet('example 09/player.json')   # => RGame::Core::SpriteSheet
app.assets.ui_atlas('ui/ui_atlas.json')      # => RGame::Core::UiAtlas
app.assets.read('data/levels.txt')           # => String
```

Paths are relative to the media root; an absolute one is used as it stands. Two
spellings of the same file — `'a/b.png'`, `'a/./b.png'`, the absolute form —
are one cache entry, not three.

### Adding an asset type

```ruby
app.assets.add_loader(:level) { |path| MyLevel.parse(File.read(path)) }
app.assets.level('levels/one.json')          # cached and grouped like any other
```

The built-in types go through the same mechanism at construction, so an added
one is not a second-class citizen. It exists because some types cannot be built
from inside `RGame::Core` at all — see [Tile maps](#tile-maps).

Every path is **relative to the media root**, and every accessor returns the
same object each time it is asked — so a file wanted twice is read, decoded and
uploaded once. That is the point: loading stops being scattered across a game's
setup, building paths ad hoc and constructing images inline, and becomes one
object that knows what is loaded.

### Groups, and what `release` frees

Each cached asset remembers the **set of groups** that asked for it. An
ungrouped load belongs to a permanent sentinel and survives every `release`; a
grouped one is reference counted.

```ruby
app.assets.image('ui/buttons.png')                       # ungrouped: permanent
app.assets.preload(:level1, image: ['lvl1/bg.png'],
                            sound: ['lvl1/hit.ogg'],
                            sheet: ['lvl1/foes.json'])
app.assets.image('shared.png', :level2)                  # one group, by hand

app.assets.release(:level1)   # drops lvl1/* unless another group still holds it
app.assets.clear              # drops everything, permanent included
```

An asset two levels both loaded survives until **both** release it, so two
scenes can share a texture without either one pulling it out from under the
other. A cache *hit* under a new group is tagged with it too — the alternative
silently loses the second group's claim.

Releasing drops this cache's reference. When the GPU texture actually goes is
the collector's business; `Image.debug_live_textures` is there if you want to
watch it happen.

`release` refuses the permanent sentinel by name, because releasing it would
drop every ungrouped asset — the opposite of what "permanent" means. Use
`clear`.

### Composites share their parts

A sprite sheet is a descriptor plus an image, and **both are pulled through this
same cache**. So these hand back one upload between them:

```ruby
sheet = app.assets.sheet('sheets/hero.json')   # names hero.png inside
image = app.assets.image('sheets/hero.png')    # the same texture, not a second one
```

The descriptor's image is resolved *next to the descriptor*, which is what lands
it on the same cache key a standalone load would use. Release the sheet's group
and its PNG goes with it.

### Failure

A loader's own error comes through unchanged — `Image::LoadError`,
`Sample::LoadError`, `Errno::ENOENT` — naming the file. A load that failed
leaves **nothing** behind: no cache entry and no group tag, so a retry is a
clean retry rather than a half-registered asset that can never be released.

### Testing without files

Every asset type maps to a loader proc, and they are injectable:

```ruby
assets = RGame::Core::AssetManager.new(
  root: '/media', app: nil,
  loaders: { image: ->(path) { FakeImage.new(path) } }
)
```

The defaults name `Image` and `Audio` only *inside* their bodies, never at load
time. That is deliberate: it means the caching, path resolution and grouping —
which is all of the logic here — can be specced with no window, no GL context
and no files at all.

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
hold many of them — which is what a [UI atlas](#ui-atlases) does with it.

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

## UI atlases

One sheet of UI chrome, cut into named [nine-slices](#nine-slices).

```ruby
atlas = app.assets.ui_atlas('ui/ui_atlas.json')
renderer.register_ui_atlas(atlas)

renderer.nine_slice(:button_idle, x, y, width, height)
```

A button has four states, a panel has one, a scrollbar has three pieces — all
small, and all cheaper as sub-rectangles of one texture than as a dozen files.

### The descriptor

```json
{
  "image": "buttons.png",
  "scale": 3,
  "nine_slices": {
    "button_idle":  { "x": 11, "y": 59, "w": 26, "h": 28, "border": 7 },
    "button_focus": { "x": 43, "y": 59, "w": 26, "h": 28, "border": 7 },
    "panel":        { "x": 0, "y": 0, "w": 32, "h": 32, "scale": 2,
                      "border": { "left": 4, "right": 4, "top": 8, "bottom": 4 } }
  }
}
```

`image` is resolved next to the descriptor. Each entry is a source rectangle
plus a `border` — a uniform integer or one value per side — and an optional
`scale` that overrides the sheet-wide one. A sheet with no `scale` draws at 1.

### Element names, not filenames

`nine_slices` is keyed by whatever the descriptor calls each element, and those
names are what a widget asks for. That is why nine-slices are the one asset the
renderer resolves **by registration only** — `:button_focus` is not a file and
never can be. `register_ui_atlas` binds every element in one call:

```ruby
renderer.register_ui_atlas(atlas)          # all of them
renderer.register_nine_slice(:panel, atlas.nine_slices[:panel])   # or one
```

### When an entry is wrong

A descriptor holds a dozen of these, so a broken one **names itself**:

```
ArgumentError: ui atlas element :button_idle: nine-slice borders (40, 40, 40, 40)
               do not fit in a 26x28 rect
```

Without the element name the failure is arithmetic from inside `NineSlice`, and
finding the culprit means bisecting the JSON by hand.

Parsing happens once, at load. Nothing here is touched again per frame.

## Tile maps

Draws a Tiled map: the static layers baked once, the animated tiles drawn each
frame and culled to the viewport.

```ruby
tiles = app.assets.tilemap('map/island.tmx')

renderer.tilemap('map/island.tmx', camera_x, camera_y, view_w, view_h, elapsed: seconds)
# ... the scene draws its actors here ...
renderer.tilemap_overlay('map/island.tmx', camera_x, camera_y, view_w, view_h,
                         z: 20, elapsed: seconds)
```

### Two bands, with the actors between them

Layers split by Tiled's `above` custom property. The **below** band — ground and
same-level detail — is drawn under the actors; the **above** band — tree
canopies, roofs — over them, at a `z` the scene picks. Two calls rather than
one, because the scene draws its actors in between; collapsing them would put
every canopy behind every character.

### What it costs

Within each band, every tile that is **not** animated is baked into a
[recording](drawing.md#recordings-bake-once-replay-cheaply) the first time that
band is drawn. Scrolling it afterwards is one call per texture, however many
thousand tiles went into it. The handful that *are* animated are drawn
individually, **culled to the viewport** — so a map far larger than the screen
costs only what is on screen.

Two maps sharing a tileset share one GPU upload, because the tiles come through
the asset manager rather than being loaded by the map.

### Animation is advanced by you

`elapsed` is seconds, and it is an argument rather than a clock this reads:

```ruby
def update(dt) = @elapsed += dt
def draw(renderer)
  renderer.tilemap(@id, camera.x, camera.y, w, h, elapsed: @elapsed)
end
```

Stop accumulating and the water freezes; accumulate slower and it runs slow; a
spec passes `0.15` and gets the second frame. See
[the frame loop](app.md#the-frame-loop) for why nothing on a draw path reads a
clock.

### It is wired up, not built in

`RGame::Core` cannot parse a `.tmx` — that is the engine layer's job, and Core
is not allowed to know the engine layer exists. So the type is *installed*, by
the one class that may name both:

```ruby
app.assets.add_loader(:tilemap) do |path|
  map, image_path = RGame::Engine::TileMap.load(path)
  tiles = app.assets.image(image_path).tiles(map.tileset.tile_width,
                                             map.tileset.tile_height)
  RGame::Core::TileMapRenderer.new(map, tiles)
end
```

Until that runs, `app.assets` has no `tilemap` accessor and a tilemap draw id
raises `KeyError` — which is the honest answer, rather than a half-working
subsystem.

`TileMapRenderer#map` hands the parsed map back, for the scene's own collision
and world-bounds queries.
