# Images

`RGame::Core::Image` is a picture on the GPU. Loading one decodes a PNG and
uploads it; everything after that — subimages, tiles, whole sprite sheets — is a
*view* of that single upload.

```ruby
require 'rgame/core'

img   = RGame::Core::Image.new(app, 'hero.png')
frame = img.subimage(0, 0, 16, 16)
walk  = RGame::Core::Image.load_tiles(app, 'hero.png', 16, 16)
```

There is nothing to draw them with yet — the renderer is the next piece of the
engine to land. What works today is loading, slicing and measuring.

## Loading

```ruby
image = RGame::Core::Image.new(app, 'assets/hero.png')
image.width    # => 64
image.height   # => 32
```

The `app` argument is required and comes first. A texture lives inside one
OpenGL context, so an image genuinely is an image *of* a window rather than a
free-floating object — and saying so is what makes two windows work, and what
lets the image keep its app alive for as long as it needs it.

PNG is the only format. A file that cannot be read or decoded raises
`RGame::Core::Image::LoadError` with the path in the message:

```ruby
begin
  RGame::Core::Image.new(app, 'assets/typo.png')
rescue RGame::Core::Image::LoadError => e
  warn e.message   # => "could not read assets/typo.png"
end
```

Greyscale and palette PNGs load fine; they are converted to RGBA on the way in,
so there is only ever one pixel format in play.

**Images are always sampled nearest-neighbour.** There is no setting for it.
The engine exists to draw pixel art, and blurring it on scale-up is never the
intent.

## Slicing: subimages and tiles

```ruby
sheet = RGame::Core::Image.new(app, 'tiles.png')   # say 64x32

sheet.subimage(16, 0, 16, 16)   # one 16x16 region
sheet.tile_count(16, 16)        # => 8   (4 columns x 2 rows)
sheet.tile(16, 16, 5)           # the sixth tile
sheet.tiles(16, 16)             # => [Image, Image, ...] all eight
sheet.each_tile(16, 16) { |t| }  # the same, without building the Array
```

`Image.load_tiles(app, path, w, h)` is `new` plus `tiles` in one step, and is
the usual way to open a sprite sheet:

```ruby
frames = RGame::Core::Image.load_tiles(app, 'explosion.png', 32, 32)
```

Three things are worth knowing about all of these:

**Nothing is decoded or uploaded twice.** A hundred tiles are a hundred small
Ruby objects over one texture. Slicing a sheet is cheap enough to do at load
time without thinking about it.

**Tiles come back in reading order** — left to right, then top to bottom — which
is how sprite-sheet frames are numbered everywhere else.

**A partial tile at the right or bottom edge is not a tile.** A 70-pixel-wide
sheet sliced into 16s yields four columns and leaves six pixels of padding
alone, because half a sprite is never what was meant.

### Coordinates are relative to what you cut from

`subimage` on a subimage composes, and cannot escape its parent:

```ruby
row  = sheet.subimage(0, 16, 64, 16)   # the bottom row of the sheet
tile = row.subimage(32, 0, 16, 16)     # 32 pixels into *the row*, not the sheet
```

A rectangle that does not fit raises `ArgumentError`, and an out-of-range tile
index raises `IndexError`, rather than either returning `nil`:

```ruby
sheet.subimage(0, 0, 999, 999)   # ArgumentError: does not fit in a 64x32 image
sheet.tile(16, 16, 99)           # IndexError: 8 tiles of 16x16
```

A `nil` here would travel a long way — into an asset table, out of it three
scenes later — before failing as a `NoMethodError` with nothing left pointing at
the coordinates that were wrong.

## Lifetime

You never free an image. The texture is released when the last view of it is
garbage-collected, and the order does not matter: dropping the sheet while its
tiles are still in use keeps the upload alive, and dropping the window first is
also fine.

```ruby
sheet  = RGame::Core::Image.new(app, 'tiles.png')
ground = sheet.tile(16, 16, 0)
sheet  = nil     # the upload stays — `ground` is still a view of it
```

That is worth stating because a leaked GPU texture is invisible while it
happens: nothing is slower, nothing looks wrong, and video memory fills up over
an hour of play. `Image.debug_live_textures` reports how many uploads exist, and
is there for tests to assert against; it is not part of the drawing API.
