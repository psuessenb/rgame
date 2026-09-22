# Assets: sheets, atlases, maps and sounds

**The asset manager loads and caches every file a game uses**: images, sound
samples, songs, sprite sheets, UI atlases, tile maps and plain text. This page
covers the manager and the Ruby classes it builds from those files: a sprite sheet
sliced into frames, a nine-slice panel stretched to any size, a UI atlas and a
tile map. [Images](images.md) and [Audio](audio.md) cover the C-backed `Image`,
`Sample` and `Song`.

**These classes are pure Ruby, but live in `RGame::Core` because they hold GPU or
audio handles.** Game logic names assets by id and never holds one; see
[Testing what a scene draws](drawing.md#testing-what-a-scene-draws).

| Page section | Class |
|---|---|
| [The asset manager](#the-asset-manager) | `RGame::Core::AssetManager` |
| [Sprite sheets](#sprite-sheets) | `RGame::Core::SpriteSheet` |
| [Nine-slices](#nine-slices) | `RGame::Core::NineSlice` |
| [UI atlases](#ui-atlases) | `RGame::Core::UiAtlas` |
| [Tile maps](#tile-maps) | `RGame::Core::TileMapRenderer` |

## The asset manager

**The asset manager loads and caches every file-backed asset.** Every game has
one, and none builds it. `app.assets` does, rooted at the app's `media_root:`:

```ruby
app.assets.image('space.png')                # => RGame::Core::Image
app.assets.sound('sounds/boom.ogg')          # => RGame::Core::Sample
app.assets.song('music/theme.ogg')           # => RGame::Core::Song
app.assets.sheet('sheets/player.json')       # => RGame::Core::SpriteSheet
app.assets.ui_atlas('ui/ui_atlas.json')      # => RGame::Core::UiAtlas
app.assets.read('data/levels.txt')           # => String
```

Paths are relative to the media root; an absolute path is used as given. Every
accessor returns the same object each time. A file requested twice is read,
decoded and uploaded once. Several spellings of one file share one cache entry:
`'a/b.png'`, `'a/./b.png'` and the absolute form.

The manager gives a game one object that knows what is loaded. Setup code builds
no paths by hand and constructs no images inline.

### Listing what is there

```ruby
app.assets.glob('locales/**/*.yml')   # => ["locales/de.yml", "locales/en.yml"]
```

`glob(pattern)` returns the paths under the media root that match `pattern`,
relative to the root and sorted. The order is therefore the same on every
platform, whatever order the file system lists them in. A directory that does not
exist matches nothing and returns `[]`. An absolute pattern is used as given, and
its matches come back absolute. `glob` loads nothing and caches nothing; hand
each path to an accessor to load it.

### Adding an asset type

```ruby
app.assets.add_loader(:level) { |path| MyLevel.parse(File.read(path)) }
app.assets.level('levels/one.json')          # cached and grouped like any other
```

The built-in leaf types (`image`, `sound`, `song` and `read`) register through the
same method at construction, so an added type works exactly like them. `sheet` and
`ui_atlas` are composites built from those; see below. `add_loader` exists because `RGame::Core`
cannot build some types itself; see [Tile maps](#tile-maps).

### Groups, and what `release` frees

**Each cached asset remembers the set of groups that asked for it.** An
ungrouped load belongs to a permanent group and survives every `release`. A
grouped load is reference counted.

```ruby
app.assets.image('ui/buttons.png')                       # ungrouped: permanent
app.assets.preload(:level1, image: ['lvl1/bg.png'],
                            sound: ['lvl1/hit.ogg'],
                            sheet: ['lvl1/foes.json'])
app.assets.image('shared.png', :level2)                  # one group, by hand

app.assets.release(:level1)   # drops lvl1/* unless another group still holds it
app.assets.clear              # drops everything, permanent included
```

An asset that two levels loaded stays until **both** release it. Two scenes can
therefore share a texture safely. A cache *hit* under a new group also adds that
group. Otherwise the second group's claim would be lost without a trace.

Releasing drops this cache's reference. The garbage collector decides when the
GPU texture goes. Watch it with `Image.debug_live_textures`.

`release` refuses the permanent group. Releasing it would drop every ungrouped
asset, the opposite of "permanent". Use `clear` instead.

### Composites share their parts

**A sprite sheet is a descriptor plus an image, and the manager loads both
through its own cache.** These two calls therefore share one upload:

```ruby
sheet = app.assets.sheet('sheets/hero.json')   # names hero.png inside
image = app.assets.image('sheets/hero.png')    # the same texture, not a second one
```

The manager resolves the descriptor's image *next to the descriptor*. That gives
it the same cache key a standalone load would use. Releasing the sheet's group
releases its PNG too.

**One known gap remains.** A composite tags its parts with the group that first
built it. When a *second* group requests the cached composite, only the
composite's own key gains the new tag, not its parts. Releasing the first group
can then drop a PNG the second group still expects. The usual pattern, where each
level owns its assets, is unaffected. Closing the gap would need per-part
tracking.

### Failure

A loader's own error passes through unchanged and names the file:
`Image::LoadError`, `Sample::LoadError`, `Errno::ENOENT`. **A failed load leaves
nothing behind**: no cache entry and no group tag. A retry starts clean, with no
half-registered asset that can never be released.

### Testing without files

Every asset type maps to a loader proc, and you can inject your own:

```ruby
assets = RGame::Core::AssetManager.new(
  root: '/media', app: nil,
  loaders: { image: ->(path) { FakeImage.new(path) } }
)
```

The default loaders name `Image` and `Audio` only *inside* their bodies, never at
load time. Specs can therefore cover all the manager's logic with no window, no GL
context and no files: caching, path resolution and grouping.

## Sprite sheets

A sheet is one image plus a JSON descriptor. It slices the image into frames at
load time and draws one frame at a time.

```ruby
sheet = app.assets.sheet('hero.json')

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

The sheet resolves `image` **next to the descriptor**, so you can move both files
together without editing either. Only `frame_width` and `frame_height` are
required. A descriptor missing one raises `ArgumentError` naming the key.

### A frame can be smaller than its cell

Cells sit on a fixed `cell_width` x `cell_height` grid. The sheet *draws* a
`frame_width` x `frame_height` rectangle, offset by `origin_x` / `origin_y`
inside its cell:

```
cell (32x32)          frame (16x24) at origin (8, 4)
┌──────────────┐      ┌──────────────┐
│              │      │    ┌────┐    │
│              │      │    │    │    │
│              │      │    │    │    │
└──────────────┘      └────┴────┴────┘
```

Cells can fit the widest pose, such as an attack swing, while walking frames keep
a tight, centred box. A character then keeps its apparent size when its animation
changes. Without the four keys, frame equals cell, which suits a simple sheet.

Only whole cells count. A 70-pixel sheet with 16-pixel cells has four columns.
The sheet ignores the six leftover pixels instead of making a narrow fifth column.

### Facing

**`flip_x` mirrors the frame inside the same rectangle**, so a character covers
the same pixels whichever way it faces:

```ruby
sheet.draw(renderer, row, col, x, y, flip_x: moving_left)
```

You add no width back; [Mirroring](drawing.md#mirroring) explains why.

### Animations come back raw

**`#animations` returns the descriptor's table untouched.** The sheet knows
nothing about time. The scene layer decides which frame to show, and builds its
own animation state from that hash. The raw form lets each side change on its
own.

A sheet without an `animations` key returns `{}`, not `nil`. A sheet of static
tiles is a valid sheet, and callers should not have to branch.

### Slicing costs nothing

The sheet cuts every frame once, at construction, as a view onto the single
upload. Two hundred frames are two hundred small objects and **one** texture.
`#draw` is an array index plus one draw call. Nothing is cut again per frame.

### Loading

```ruby
app.assets.sheet(path)                     # what a game calls: cached and grouped
RGame::Core::SpriteSheet.new(image, atlas) # from an already-loaded image and parsed descriptor
RGame::Core::SpriteSheet.load(app, path)   # reads both files directly, bypassing the cache
```

**Load sheets through `app.assets.sheet`.** Every app has an asset manager. It
builds the sheet with `.new`, from an image it pulls through its own cache, so the
sheet's PNG is shared with `app.assets.image` of the same file. `.load` reads the
descriptor and decodes the image itself, outside any cache. A second `.load` of
the same file decodes and uploads it again. `UiAtlas` has the same three forms.

## Nine-slices

A nine-slice draws a bordered texture at any size. It cuts the texture into nine
pieces and treats each piece differently.

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

One small piece of art fills a button, a dialog or a health bar of any size, and
the corners never smear.

`(x, y, w, h)` is the source rectangle **inside** the image, so one sheet can hold
many nine-slices. A [UI atlas](#ui-atlases) relies on this.

### Tiled, not stretched

**Edges and the centre repeat.** Stretching a 7-pixel motif would blur the detail
the art was drawn for. Repeating it keeps pixel art crisp at every size. Each
band clips to itself, so the last tile in a row is cropped cleanly instead of
spilling into the corner. The loops always start one extra tile, because a gap at
the seam shows more than a cropped overhang.

### `border` and `scale`

`border` takes a uniform integer or a hash:

```ruby
border: 7
border: { left: 2, right: 6, top: 4, bottom: 4 }
```

**`scale` is an integer pixel scale for the border art itself.** Source art is
small, with corners often 7 pixels wide. A scale of 2 or 3 makes borders legible
on a 640x480 screen without blur, because each source pixel becomes a whole
square of screen pixels. `scale` multiplies both the pieces and the step between
tiles, so the tiling stays seamless.

### Edge cases

| | |
|---|---|
| A rectangle smaller than its own borders | draws its corners and no bands |
| A border with no room for a centre (`left + right == w`) | fine — a bar that stretches only vertically |
| Borders wider than the source rect | `ArgumentError`, naming the borders and the rect |
| `scale` of zero or less | `ArgumentError` — the tiling loop would never advance |

### What it costs

The nine-slice cuts its pieces once at construction, as views onto the one
upload, so `#draw` allocates nothing. It issues one call per tile. That is where
`scale` pays: a panel at 3x needs a ninth of the tiles of the same panel at 1x.

Inside a scene, draw a registered nine-slice by id with
`renderer.nine_slice(id, x, y, width, height, z: 0, tint: nil)`. Its `tint:` is
`NineSlice#draw`'s `color:`.

## UI atlases

A UI atlas cuts one sheet of UI art into named [nine-slices](#nine-slices) and
named images.

```ruby
atlas = app.assets.ui_atlas('ui/ui_atlas.json')
renderer.register_ui_atlas(atlas)

renderer.nine_slice(:button_idle, x, y, width, height)
renderer.image(:home, cx, cy)
```

A button has four states, a panel one, a scrollbar three pieces. All are small,
and sub-rectangles of one texture cost less than a dozen files.

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
  },
  "images": {
    "home": { "x": 0,  "y": 96, "w": 50, "h": 50 },
    "gear": { "x": 50, "y": 96, "w": 50, "h": 50 }
  }
}
```

The atlas resolves `image` next to the descriptor. Each `nine_slices` entry holds
a source rectangle and a `border`: a uniform integer or one value per side. An
optional `scale` overrides the sheet-wide one. A sheet without `scale` draws at 1.

Each `images` entry is a bare rectangle, cut from the sheet with
`Image#subimage`. An icon draws whole, so it needs no border. The draw call's
`scale:` sets its size, so it needs no scale either. `atlas.images` is a Hash of
name to `Image`. Either section may be missing or `null`, and one atlas may hold
both.

### Element names, not filenames

**Both sections are keyed by element name, and widgets ask for those names.** So
the renderer resolves nine-slices **by registration only**: `:button_focus` is
not a file and never can be. `register_ui_atlas` binds every element of both
kinds in one call. It registers nine-slices with `register_nine_slice` and images
with `register_image`:

```ruby
renderer.register_ui_atlas(atlas)                                  # all of them
renderer.register_nine_slice(:panel, atlas.nine_slices[:panel])   # or one
renderer.register_image(:home, atlas.images[:home])
```

### When an entry is wrong

**A broken entry names itself.** A descriptor holds a dozen elements. A nine-slice
whose border does not fit, or an image rectangle past the sheet's edge, raises
with the element's name:

```
ArgumentError: ui atlas element :button_idle: nine-slice borders (40, 40, 40, 40)
               do not fit in a 26x28 rect
```

Without the name, the error would be bare arithmetic from inside `NineSlice`.
Finding the culprit would mean bisecting the JSON by hand.

The atlas parses once, at load, and touches nothing again per frame.

## Tile maps

`TileMapRenderer` draws a Tiled map. It bakes the static layers once, and draws
animated tiles each frame, culled to a rectangle of the world. An image layer
draws each frame too, as many copies of its image as meet that rectangle.

```ruby
tiles = app.assets.tilemap('map/island.tmx')   # => RGame::Core::TileMapRenderer

renderer.tilemap('map/island.tmx', 0, cull_x, cull_y, cull_w, cull_h, elapsed: seconds)
# ... the scene draws its actors here ...
renderer.tilemap('map/island.tmx', 1, cull_x, cull_y, cull_w, cull_h, elapsed: seconds)
```

**A game rarely makes these calls.** [`TileMapLayer`](components.md#tileworld)
mounts one node per layer and draws it.

**Tiles draw in world coordinates.** A tile at column 3 lands at
`map.cell_x(3)`. The caller's transform, usually a `WorldView`'s camera, puts it
on screen. The rectangle is only a **cull rect**: the part of the world worth
drawing. A camera supplies it but does not move the result, so one map can be
drawn through several cameras in one frame.

### One call per layer, so actors fit between layers

**Each call draws one layer, in the order the caller chooses.** A scene can put
its actors between two layers: trunks under, canopies over. Which layers those
are depends on the scene, not the map, so the call takes no `z`. In a game,
[`TileMapLayer`](components.md#tileworld) mounts a node per layer, and the scene
tree orders them.

### What it costs

**The renderer bakes each layer's non-animated tiles into a
[recording](drawing.md#recordings-bake-once-replay-cheaply)** the first time it
draws that layer. Scrolling the layer then costs one call per texture, however
many thousand tiles it holds. The few animated tiles draw individually, **culled
to the viewport**. A map far larger than the screen costs only what is on screen.

Two maps that share a tileset share one GPU upload, because tiles load through the
asset manager, not through the map.

### You advance the animation

**`elapsed` is seconds, passed as an argument.** The renderer reads no clock:

```ruby
def _update(dt) = @elapsed += dt

def _draw(renderer, view)
  camera = view.camera
  renderer.tilemap(@id, @layer, camera.x, camera.y, view.width, view.height, elapsed: @elapsed)
end
```

Stop accumulating and the water freezes. Accumulate slower and it runs slow. A
spec passes `0.15` and gets the second frame. [The frame loop](app.md#the-frame-loop)
explains why nothing on a draw path reads a clock.

### Installed, not built in

**`RGame::Core` cannot parse a `.tmx`.** Parsing belongs to the engine layer, and
Core may not know that layer exists. `RGame::Game`, the one class that may name
both, installs the type:

```ruby
app.assets.add_loader(:tilemap) do |path|
  tiled = RGame::Engine::Tiled::Map.load(path)
  map = RGame::Engine::TileMap.from_tiled(tiled)
  RGame::Core::TileMapRenderer.new(map, tile_images(tiled, map), layer_images: layer_images(map))
end
```

`tile_images` loads each tileset's images through the asset manager and lays
them out by tile id as `map.tile_table` says. A sheet is cut with its margin and
spacing. A collection of images loads one file per tile. The renderer receives
the same flat Array either way.

`layer_images` loads the image of each image layer, indexed by layer, with `nil`
for every other layer. A file that is missing raises `Image::LoadError` naming
it, when the map loads rather than when the layer first draws.

Every `RGame::Game` installs this loader when it is built. A plain
`RGame::Core::App` has none: its `app.assets` has no `tilemap` accessor, and a
tilemap draw id raises `KeyError`. A clear error beats a half-working subsystem.

`TileMapRenderer#map` returns the parsed map, for the scene's own collision and
world-bounds queries. [Tile maps](tile_maps.md) documents `TileMap`, and which
Tiled features rgame reads.
