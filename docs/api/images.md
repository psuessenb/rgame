# Images

`RGame::Core::Image` is a picture on the GPU. Loading one decodes a PNG and
uploads it once. Subimages, tiles and whole sprite sheets are all *views* of that
single upload.

```ruby
require 'rgame/core'

img   = RGame::Core::Image.new(app, 'hero.png')
frame = img.subimage(0, 0, 16, 16)
walk  = RGame::Core::Image.load_tiles(app, 'hero.png', 16, 16)
```

[Drawing](drawing.md) covers putting images on screen.

**A game loads images through the [asset manager](assets.md)**, with
`app.assets.image(path)`. The manager resolves the path against `media_root` and
caches the image. `Image.new` and `Image.load_tiles` bypass that cache, and resolve a
relative path against the working directory.

## Loading

```ruby
image = RGame::Core::Image.new(app, 'assets/hero.png')
image.width    # => 64
image.height   # => 32
```

**The `app` argument is required and comes first.** A texture lives inside one
OpenGL context, so an image belongs to a window. Naming the app lets two windows
work side by side. It also lets the image keep its app alive as long as it needs.

rgame reads PNG only. A file it cannot read or decode raises
`RGame::Core::Image::LoadError`, with the path in the message:

```ruby
begin
  RGame::Core::Image.new(app, 'assets/typo.png')
rescue RGame::Core::Image::LoadError => e
  warn e.message   # => "could not read assets/typo.png"
end
```

Greyscale and palette PNGs load too. The loader converts them to RGBA, so the
engine handles one pixel format.

**Images always use nearest-neighbour sampling**, with no setting to change it.
The engine draws pixel art, and pixel art should never blur when scaled up.

## Slicing: subimages and tiles

```ruby
sheet = RGame::Core::Image.new(app, 'tiles.png')   # say 64x32

sheet.subimage(16, 0, 16, 16)   # one 16x16 region
sheet.tile_count(16, 16)        # => 8   (4 columns x 2 rows)
sheet.tile(16, 16, 5)           # the sixth tile
sheet.tiles(16, 16)             # => [Image, Image, ...] all eight
sheet.each_tile(16, 16) { |t| }  # the same, without building the Array
```

`Image.load_tiles(app, path, w, h)` combines `new` and `tiles`. It is the usual
way to open a sprite sheet:

```ruby
frames = RGame::Core::Image.load_tiles(app, 'explosion.png', 32, 32)
```

Three rules apply to all of these methods.

**Nothing is decoded or uploaded twice.** A hundred tiles are a hundred small Ruby
objects over one texture. Slice sheets at load time without worrying about cost.

**Tiles come back in reading order**: left to right, then top to bottom. Sprite
sheets number their frames the same way.

**A partial tile at the right or bottom edge is not a tile.** Slicing a 70-pixel
sheet into 16s yields four columns. The six leftover pixels count as padding,
because half a sprite is never wanted.

**`tiles` also cuts a sheet with gaps**, as a Tiled tileset describes one:

```ruby
sheet.tiles(16, 16, margin: 1, spacing: 2)            # 1 px border, 2 px between tiles
sheet.tiles(16, 16, count: 5)                         # only the first five
sheet.tiles(16, 16, margin: 1, spacing: 2, columns: 3)
```

`margin` is the border around the whole sheet and `spacing` the gap between two
tiles. `columns` sets how many tiles a row holds, and defaults to as many as fit.
`count` stops the Array early. A tile that would reach outside the sheet raises
`ArgumentError`, or `IndexError` for a packed sheet.

### Coordinates are relative to what you cut from

`subimage` on a subimage composes, and cannot escape its parent:

```ruby
row  = sheet.subimage(0, 16, 64, 16)   # the bottom row of the sheet
tile = row.subimage(32, 0, 16, 16)     # 32 pixels into *the row*, not the sheet
```

**Bad coordinates raise; they never return `nil`.** A rectangle that does not fit
raises `ArgumentError`. An out-of-range tile index raises `IndexError`:

```ruby
sheet.subimage(0, 0, 999, 999)   # ArgumentError: does not fit in a 64x32 image
sheet.tile(16, 16, 99)           # IndexError: 8 tiles of 16x16
```

A `nil` would travel a long way: into an asset table, and out again three scenes
later. It would finally fail as a `NoMethodError` that no longer points at the
wrong coordinates.

## Lifetime

**You never free an image.** The engine releases the texture when the last view
of it is garbage-collected, in any order. Tiles still in use keep the upload
alive after the sheet is dropped. Dropping the window first also works.

```ruby
sheet  = RGame::Core::Image.new(app, 'tiles.png')
ground = sheet.tile(16, 16, 0)
sheet  = nil     # the upload stays — `ground` is still a view of it
```

A leaked GPU texture shows no symptoms at first. Nothing slows down and nothing
looks wrong, while video memory fills over an hour of play.
`Image.debug_live_textures` returns how many uploads exist. Tests assert against
it; it is not part of the drawing API.
