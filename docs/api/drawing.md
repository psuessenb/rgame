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
renderer.background(image, x = 0, y = 0, z: 0, color: nil)
```

`image` **centres** on the position given and rotates about that centre — the
sprite case. `background` places the image by its **top-left** corner at its
natural size — the backdrop case.

`color:` tints: the image's pixels are multiplied by it, so white leaves the
image alone and a colour with alpha fades it.

See [Images](images.md) for loading files and slicing sprite sheets.

**An image can only be drawn by the app that loaded it.** GPU textures belong to
one window's OpenGL context and are not shared with another, so drawing another
app's image would sample nothing and paint a plain white rectangle. Rather than
let that happen quietly, it raises `ArgumentError`. In a one-window game — which
is nearly all of them — this never comes up.

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

## Testing what a scene draws

The renderer is an interface, not a class your game should name. Game logic
receives one and calls methods on it; a headless spec passes a recording fake
instead and asserts on the calls:

```ruby
renderer = FakeRenderer.new
health_bar.draw(renderer)

expect(renderer.calls_to(:rect).map(&:args)).to eq([[10, 10, 64, 8]])
```

That runs with no window, no GPU and no clock. The fake and the real renderer
are both checked against one shared contract (`spec/support/shared_examples/
a_renderer.rb`), so the fake cannot drift into describing a renderer that does
not exist — which would leave a green test suite and a game that no longer runs.

## What is not here yet

Text, audio, and drawing by asset id (`sprite(:hero, row, col, …)`) are still to
come; so is `record`, which bakes a block of static draws into one retained
batch. Today an image is passed as an object rather than looked up in a
registry.
