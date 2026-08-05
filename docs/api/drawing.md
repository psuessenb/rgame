# Drawing

`RGame::Core::Renderer` is what a game draws with. It is created from an app and
used inside `draw`:

```ruby
require 'rgame'
require 'rgame/core'

class MyGame < RGame::Core::App
  Color = RGame::Util::Color

  def initialize
    super(width: 800, height: 600, caption: 'demo')
    @renderer = RGame::Core::Renderer.new(self)
    @hero = RGame::Core::Image.new(self, 'hero.png')
  end

  def draw
    @renderer.rect(40, 40, 160, 100, color: Color.new(224, 64, 64))
    @renderer.circle(620, 110, 70, color: Color.new(64, 96, 224))
    @renderer.image(@hero, 400, 300, angle: 45)
  end
end

MyGame.new.run
```

Two things about that are worth knowing before anything else.

**Drawing is only legal inside `draw`.** Calling one of these from `update` or
from a constructor raises. The frame is not open at those times, so the call
would be silently discarded — and an invisible failure is worse than a loud one.

**Nothing is drawn immediately.** Calls accumulate, and the frame is sorted and
sent to the GPU once, after `draw` returns. So the order you make calls in does
not decide what ends up on top — `z:` does.

## Coordinates, colours and z

| | |
|---|---|
| Origin | Top-left. x grows right, y grows **down**. |
| Angles | Degrees. A **positive angle turns clockwise** on screen. |
| `z:` | Higher is nearer the viewer. Equal z keeps call order. |
| `color:` | `nil` (white), `[r, g, b]`, `[r, g, b, a]`, or a `RGame::Util::Color`. |

`z` defaults to `50` for shapes and `0` for images, so a debug box or a health
bar drawn without a `z:` lands on top of the scene rather than under it.

Equal-z stability matters more than it sounds: without it, two sprites on the
same layer would swap places whenever the sort felt like it, which reads as
flicker.

### Colours and allocation

Passing a `Color` allocates nothing — it is a frozen value, and the same one can
be shared by every sprite that uses it. Passing an array allocates a colour per
call, which is fine at setup and wasteful sixty times a second:

```ruby
RED = RGame::Util::Color.new(224, 64, 64)   # once

def draw
  @renderer.rect(10, 10, 50, 50, color: RED) # every frame, allocation-free
end
```

## Shapes

```ruby
renderer.rect(x, y, width, height, z: 50, color: nil)
renderer.quad(x1, y1, x2, y2, x3, y3, x4, y4, z: 50, color: nil)
renderer.triangle(x1, y1, x2, y2, x3, y3, z: 50, color: nil)
renderer.line(x1, y1, x2, y2, thickness: 1.0, z: 50, color: nil)
renderer.circle(cx, cy, radius, z: 50, color: nil, segments: 64)
renderer.debug_box(x, y, width, height, z: 50)
```

A **quad's** four points are taken in loop order — top-left, top-right,
bottom-right, bottom-left for a rectangle. Listing them in Z order gives an
hourglass.

A **line** has real thickness because it is drawn as a quad. OpenGL's own line
width is a suggestion drivers are free to ignore above one pixel, so a line
worth seeing has to be a shape.

A **circle** is a fan of triangles, and the whole fan is one batch — there is no
cached circle texture to warm up and nothing to configure. `segments:` is there
for the rare case where 64 is too many or too few.

`debug_box` is a translucent red rectangle for visualising a collision box, so a
scene can ask for one without deciding what colour "debug" is.

## Images

```ruby
renderer.image(image, cx, cy, angle: 0, scale: 1, z: 0, color: nil)
renderer.image_at(image, x, y, scale_x: 1, scale_y: 1, z: 0, color: nil)
renderer.background(image, x = 0, y = 0, z: 0, color: nil)
```

Three anchors for three jobs. `image` **centres** on the position given and
rotates about that centre — the sprite case. `image_at` places the **top-left**
corner and scales each axis on its own — tiles, nine-slice corners, sheet
frames. `background` is `image_at` at natural size, named for its usual job.

### Mirroring

A negative scale on `image_at` mirrors the image **inside the same rectangle**.
It does not move it:

```ruby
renderer.image_at(frame, x, y, scale_x: facing_left ? -1 : 1)
```

Both calls cover the same pixels; only the picture is reversed. That is worth
knowing if you are coming from Gosu, where a negative scale mirrors *about* the
anchor and the caller adds a width back to compensate. Here `(x, y)` is the
top-left corner whatever the sign, so there is nothing to compensate for — and
nothing to forget.

A scale of `0` draws nothing.

`color:` tints: the image's pixels are multiplied by it, so white leaves the
image alone and a colour with alpha fades it.

See [Images](images.md) for loading files and slicing sprite sheets.

**An image can only be drawn by the app that loaded it.** GPU textures belong to
one window's OpenGL context and are not shared with another, so drawing another
app's image would sample nothing and paint a plain white rectangle. Rather than
let that happen quietly, it raises `ArgumentError`. In a one-window game — which
is nearly all of them — this never comes up.

## Drawing by id

Game logic names an asset; it does not hold one. That is not a convenience —
the scene layer may hold `RGame::Util` values but no `RGame::Core` handle at
all, so a Symbol or a path is the only thing a node *can* carry.

An id is normally a **root-relative path**, resolved through the app's
[asset manager](assets.md) and then remembered:

```ruby
renderer.sprite('example 09/player.json', row, col, x, y, flip_x: false, z: 0)
renderer.image('space.png', cx, cy, angle: 0, scale: 1)
renderer.background('space.png')
renderer.tilemap('map/island.tmx', camera_x, camera_y, viewport_w, viewport_h)
renderer.tilemap_overlay('map/island.tmx', camera_x, camera_y, viewport_w, viewport_h, z: 20)
```

Nothing has to be set up for that: `Renderer.new(app)` takes the app's own
manager, so a path just works. `Renderer.new(app, assets: other)` overrides it.

### Registering

`register_*` pre-binds an id to an object you chose, and wins over the asset
manager. It is for the two things a path cannot name: an id that is not a file,
and an object the game assembled itself.

```ruby
renderer.register_image(:space, app.assets.image('space.png'))
renderer.register_sheet(:hero, app.assets.sheet('hero.json'))
renderer.register_tilemap(:level1, app.assets.tilemap('island.tmx'))
renderer.register_nine_slice(:panel, atlas.nine_slices[:panel])
renderer.register_ui_atlas(atlas)   # every element under its own name

renderer.image(:space, 100, 100)
```

**Nine-slices are registration-only.** Their ids name an *element of an atlas*,
not a file, so there is nothing for a manager to resolve them to.

### What resolution does

| Given | |
|---|---|
| An `Image` | drawn directly — `#image`, `#image_at` and `#background` all take one |
| A registered id | the registered object |
| A `String` | resolved through the asset manager, then remembered |
| A `Symbol` that is not registered | `KeyError`, naming the id and the type |
| `nil` | `TypeError` |

A Symbol is never offered to the asset manager, because only a String can be a
path. So a typo'd Symbol says "no sheet registered for `:heor`" rather than
whatever a loader makes of being handed a Symbol for a filename — and a broken
*file* still raises its own `LoadError` naming it, which is a different bug
wanting a different fix.

Resolution happens once per id and the answer is kept, so per-frame drawing
neither re-resolves nor allocates a lookup key.

## Transform blocks

Each of these applies to everything drawn inside it, and undoes itself
afterwards — including when the block raises.

```ruby
renderer.translated(dx, dy) { ... }
renderer.rotated(angle, pivot_x, pivot_y) { ... }
renderer.scaled(sx, sy = sx) { ... }
renderer.clipped(x, y, width, height) { ... }
```

They nest, and they compose in the order they are opened:

```ruby
renderer.translated(-camera.x, -camera.y) do   # world space -> screen space
  renderer.rotated(ship.angle, ship.x, ship.y) do
    renderer.image(hull, ship.x, ship.y)
  end
end
```

`translated` is how a camera works, and the reason it is a *draw-time* transform
rather than something baked into positions is that the same world can then be
drawn twice, under two different offsets — which is what split-screen is.

`rotated(0, …)`, `translated(0, 0)` and `scaled(1)` are free: they skip the
transform entirely and just run the block, so unrotated drawing pays nothing.

### Clipping and split-screen

A clip **narrows**. Nesting one inside another intersects them, so a child can
never draw outside the region its parent allowed. Two clipped blocks are a
split screen:

```ruby
def draw
  @renderer.clipped(0, 0, 400, 600) do
    @renderer.translated(-@player_one.x, -@player_one.y) { draw_world }
  end

  @renderer.clipped(400, 0, 400, 600) do
    @renderer.translated(400 - @player_two.x, -@player_two.y) { draw_world }
  end
end
```

## Recordings: bake once, replay cheaply

A tile layer is a couple of thousand quads that have not changed since the level
loaded. `record` bakes a block of drawing so that replaying it costs one call
per texture, however many draws went into it:

```ruby
def draw
  @ground ||= @renderer.record do
    @tiles.each { |tile| @renderer.image(tile.image, tile.x, tile.y) }
  end

  @ground.draw(-@camera.x, -@camera.y)
end
```

Nothing is drawn at bake time — the block's output goes into the recording
instead of into the frame. `record` must be called inside `draw` like everything
else, which is why the example bakes on the first frame rather than in
`initialize`.

```ruby
baked.draw(x = 0, y = 0, z: 0, color: nil)
baked.batch_count   # GL calls one replay costs
baked.width         # the size of what was baked
baked.empty?
```

**Positions, texture coordinates, colours and any transforms inside the block
are baked in.** The transform in effect when the recording is *drawn* applies on
top, so a baked layer scrolls under a camera without being rebuilt, and the same
recording can be stamped in several places:

```ruby
5.times { |i| @bush.draw(i * 120, 300) }
```

**`color:` tints the replay** — each recorded colour is multiplied by it, so a
whole baked layer can be faded out at once. (Gosu's recorded images could only
draw white; there was no reason to inherit that.)

**Clipping cannot be baked.** Clipping happens when pixels are rasterised, so a
clip rectangle captured in one place would be wrong everywhere else the
recording is drawn. Pushing a clip inside a `record` block raises; clip the
replay instead, which is what was meant anyway:

```ruby
@renderer.clipped(0, 0, 400, 600) { @ground.draw(-@camera.x, -@camera.y) }
```

Recordings do not nest, and a block that raises leaves nothing half-recorded
behind. A recording keeps the images baked into it alive, so a sprite sheet
dropped after baking does not take its texture with it.

## Testing what a scene draws

The renderer is an interface, not a class your game should name. Game logic
receives one and calls methods on it; a headless spec passes a recording fake
instead and asserts on the calls:

```ruby
renderer = FakeRenderer.new
health_bar.draw(renderer)

expect(renderer.calls_to(:rect).map(&:args)).to eq([[10, 10, 64, 8]])
```

Recordings are faked too, and the fake keeps the two questions apart — what was
baked, and where it was replayed:

```ruby
ground = renderer.record { ... }   # => a FakeRecording

expect(ground.calls.size).to eq(tiles.size)   # baked once, not per frame
expect(ground.draws.map(&:args)).to eq([[-camera.x, -camera.y]])
```

That runs with no window, no GPU and no clock. The fake and the real renderer
are both checked against one shared contract (`spec/support/shared_examples/
a_renderer.rb`), so the fake cannot drift into describing a renderer that does
not exist — which would leave a green test suite and a game that no longer runs.

## Text

`renderer.text(string, x, y)` draws a line of text, and `text_width` measures
one. See [Text](text.md) for fonts, the shipped default and what it covers.

## What is not here yet

Audio and drawing by asset id (`sprite(:hero, row, col, …)`) are still to come.
Today an image is passed as an object rather than looked up in a registry.
