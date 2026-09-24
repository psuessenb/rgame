# Drawing

Everything on screen goes through `RGame::Core::Renderer`. **In an
`RGame::Game`, you never build one.** `Game` builds it and passes it to every
node's `_draw(renderer, view)`. The examples on this page build one on a plain
`App` instead, to show the calls without a scene graph:

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

Know two rules before anything else.

**Draw only inside `draw`**, or a node's `_draw`. A drawing call from `update`
or from a constructor raises. The frame is not open then, so the call would vanish without a trace.
A loud failure beats an invisible one. `renderer.drawing?` returns whether a frame
is open.

**The renderer draws nothing immediately.** It collects calls, sorts the frame
and sends it to the GPU once, after `draw` returns. The scene tree decides which
node lies over which, and within one node a later call lies over an earlier one
unless a `z:` says otherwise. See "Draw order" below.

## Coordinates, colours and z

| | |
|---|---|
| Origin | Top-left. x grows right, y grows **down**. |
| Angles | Degrees. A **positive angle turns clockwise** on screen. |
| `z:` | Where this call sits among **this node's own** drawing. −512…511. |
| `color:` | a `RGame::Util::Color`, or `nil` for white — an untinted draw. |

**`z:` is an offset inside the current layer**, not a global number. It puts a
node's panel under its label and its shadow under its sprite. It cannot reach
anything else. A value outside −512…511 raises.

**Every drawing method defaults to z `0`**, `Renderer::DEFAULT_Z`, and calls
with equal z keep their call order. So without a `z:`, a node draws as on
paper: a backdrop drawn first lies under the text drawn after it, and a health
bar drawn after the sprite lies over it. Call order among equal z is also what
keeps two sprites on one layer from swapping places between frames, which
players would see as flicker. Pass a `z:` only to draw something under what an
earlier call put down.

## Draw order

**The renderer orders a frame in three steps, coarsest first.** A drawing call
passes a number only for the last step.

1. **The band**: `:world` (the default), `:hud`, `:overlay` or `:debug`.
   Everything in one band lies under everything in the next.
2. **The slot.** The traversal walks the scene tree depth-first, siblings in `z`
   order. Each node takes the next slot in its band when the walk reaches it.
   Draw order is therefore **tree order**. A node's subtree forms one unbroken
   run and cannot straddle a sibling.
3. **The offset**: the `z:` above, inside one node's slot.

A scene graph arranges all of this. `RGame::Engine::Node2D#draw` opens a layer per
node, so a game sets `z` on nodes and a `band` on the few that start one. See
[scene_graph.md](scene_graph.md), "Draw order".

### Opening a layer by hand

Code that draws outside the scene tree opens its own layer. The debug overlay, a
spec and a script all do:

```ruby
renderer.layered(:hud) do
  renderer.nine_slice(:panel, x, y, w, h)
  renderer.text(score, x + 8, y + 6, z: 1)   # above this layer's own panel
end
```

`layered` takes the next slot in that band and measures every `z:` inside the
block from it. Afterwards it restores the previous base, even when the block
raises. Nesting *replaces* the base; it does not add to it. A node's slot depends
on where the traversal reached it, not on its ancestors' picks. Outside any block
the base is 0, so a bare script gets exactly the z it passes.

`renderer.layer` returns the base in effect.

### Why bands exist

A frame holds three kinds of content:

- **World**: inside a `WorldView`, drawn once per viewport, under a camera.
- **A player's own screen space**: their HUD and menu, drawn once and clipped to
  their viewport (`PlayerLayer`).
- **Global screen space**: a cutscene or a results panel, drawn once across the
  whole window.

The world is a different *space* from the other two, and the tree enforces that:
`WorldView` draws its subtree once per viewport. The other two share one space,
and the band tells them apart.

Two viewports may interleave in the sort without harm. Their commands carry
different clips and land on different pixels. Order *within* one viewport
matters, and drawing a HUD after the world does not put it on top. Its band
does. Bands lie `2**40` apart and a `z:` spans 1024, so no offset can carry a
call into the next band. See `RGame::Util::Z`.

## Shapes

```ruby
renderer.rect(x, y, width, height, z: 0, color: nil)
renderer.quad(x1, y1, x2, y2, x3, y3, x4, y4, z: 0, color: nil)
renderer.triangle(x1, y1, x2, y2, x3, y3, z: 0, color: nil)
renderer.line(x1, y1, x2, y2, thickness: 1.0, z: 0, color: nil)
renderer.circle(cx, cy, radius, z: 0, color: nil, segments: 64)
renderer.debug_box(x, y, width, height, z: 0)
renderer.debug_circle(cx, cy, radius, z: 0)
```

A **quad** takes its four points in loop order: top-left, top-right,
bottom-right, bottom-left for a rectangle. Points in Z order give an hourglass.

A **line** has real thickness, because the renderer draws it as a quad. Drivers
may ignore OpenGL's own line width above one pixel.

A **circle** is a fan of triangles in one batch. It needs no cached texture and
no configuration. Adjust `segments:` if 64 is too many or too few.

`debug_box` draws a translucent red rectangle to show a collision box, and
`debug_circle` the same colour as a disc. A scene can ask for either without
choosing a debug colour, and the colliders draw themselves with them when the
debug layer's `:shapes` channel is on — see
[Systems](systems.md#debug--a-switch-per-channel).

## Images

```ruby
renderer.image(image, cx, cy, angle: 0, scale: 1, z: 0, color: nil)
renderer.image_at(image, x, y, scale_x: 1, scale_y: 1, z: 0, color: nil)
renderer.background(image, x = 0, y = 0, z: 0, color: nil)
```

Each method anchors the image differently:

- `image` **centres** the image on the position and rotates it about that
  centre. Use it for sprites.
- `image_at` places the **top-left** corner and scales each axis separately. Use
  it for tiles, nine-slice corners and sheet frames.
- `background` is `image_at` at natural size.

### Mirroring

**A negative scale on `image_at` mirrors the image inside the same rectangle.**
It does not move the image:

```ruby
renderer.image_at(frame, x, y, scale_x: facing_left ? -1 : 1)
```

Both calls cover the same pixels; only the picture is reversed. `(x, y)` stays
the top-left corner whatever the scale's sign, so a mirrored sprite stays put.
Mirroring about the anchor would shift the image one width to the left. Every
flipped draw would then have to add that width back.

A scale of `0` draws nothing.

`color:` tints the image by multiplying its pixels. White leaves the image
unchanged, and a colour with alpha fades it.

[Images](images.md) covers loading files and slicing tiles; [Assets](assets.md#sprite-sheets) covers sprite sheets.

**Only the app that loaded an image can draw it.** A GPU texture belongs to one
window's OpenGL context. Drawing another app's image would sample nothing and
paint a plain white rectangle, so the renderer raises `ArgumentError` instead. A
one-window game never meets this.

## Drawing by id

**Game logic names an asset; it does not hold one.** The scene layer may hold
`RGame::Util` values but no `RGame::Core` handle. A Symbol or a path is the only
thing a node *can* carry.

An id is normally a **root-relative path**. The renderer resolves it through the
app's [asset manager](assets.md) and remembers the result:

```ruby
renderer.sprite('hero.json', row, col, x, y, flip_x: false, z: 0)
renderer.image('space.png', cx, cy, angle: 0, scale: 1)
renderer.background('space.png')
renderer.tilemap('map/island.tmx', layer, cull_x, cull_y, cull_w, cull_h, elapsed: 0.0)  # draws in world coordinates
renderer.nine_slice(:panel, x, y, width, height, z: 0, tint: nil)
```

Paths need no setup. `Renderer.new(app)` uses the app's own manager.
`Renderer.new(app, assets: other)` uses a different one.

### Registering

`register_*` binds an id to an object you choose, and takes priority over the
asset manager. Use it for what a path cannot name: an id that is not a file, and
an object the game built itself.

```ruby
renderer.register_image(:space, app.assets.image('space.png'))
renderer.register_sheet(:hero, app.assets.sheet('hero.json'))
renderer.register_tilemap(:level1, app.assets.tilemap('island.tmx'))
renderer.register_nine_slice(:panel, atlas.nine_slices[:panel])
renderer.register_ui_atlas(atlas)   # every element under its own name

renderer.image(:space, 100, 100)
```

**Nine-slices must be registered.** Their ids name an *element of an atlas*, not
a file, so an asset manager has nothing to resolve.

### How the renderer resolves an id

| Given | |
|---|---|
| An `Image` | drawn directly — `#image`, `#image_at` and `#background` all take one |
| A registered id | the registered object |
| A `String` | resolved through the asset manager, then remembered |
| A `Symbol` that is not registered | `KeyError`, naming the id and the type |
| `nil` | `TypeError` |

The renderer never offers a Symbol to the asset manager, because only a String
can be a path. A mistyped Symbol therefore raises "no sheet registered for
`:heor`". A broken *file* raises its own `LoadError` naming the file. The two
errors point at two different fixes.

The renderer resolves each id once and keeps the answer. Per-frame drawing
neither resolves again nor allocates a lookup key.

## Transform blocks

Each block applies to everything drawn inside it and undoes itself afterwards,
even when the block raises.

```ruby
renderer.translated(dx, dy) { ... }
renderer.rotated(angle, pivot_x, pivot_y) { ... }
renderer.scaled(sx, sy = sx) { ... }
renderer.clipped(x, y, width, height) { ... }
renderer.layered(band) { ... }               # see "Draw order" above
```

Blocks nest and compose in the order you open them:

```ruby
renderer.translated(-camera.x, -camera.y) do   # world space -> screen space
  renderer.rotated(ship.angle, ship.x, ship.y) do
    renderer.image(hull, ship.x, ship.y)
  end
end
```

**A camera is a `translated` block.** Because the offset applies at draw time,
the same world can be drawn twice under two different offsets. That is
split-screen.

`rotated(0, …)`, `translated(0, 0)` and `scaled(1)` cost nothing. They skip the
transform and run the block, so unrotated drawing pays nothing.

**Inside a scene graph you rarely open a transform block yourself.** The examples
on this page drive the renderer from an `App`, in window coordinates. For a
`Node2D`, the traversal pushes the node's transform before it calls `_draw`. A
node therefore draws at *its own* origin, and passing its position would apply it
twice. See [Scene graph](scene_graph.md#drawing-happens-in-local-space).

### Clipping and split-screen

**A clip narrows.** A nested clip intersects with its parent, so a child never
draws outside the region its parent allowed. Two clipped blocks make a split
screen:

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

**A game does not write that.**
[`RGame::Engine::WorldView`](scene_graph.md#view-transforms-and-the-camera) does it
once per active player, with the layout's rectangles and each player's camera.
Call `clipped` directly for a region of your own, such as a minimap or a list
that scrolls by the pixel.

## Blending and fading

Two more blocks change how what is drawn inside them combines with what is
already on screen. Both undo themselves afterwards, as the transform blocks do.

```ruby
renderer.blended(mode) { ... }     # :alpha or :add
renderer.faded(opacity) { ... }    # 0 hides it, 1 changes nothing
```

**`blended(:add)` adds light to what is behind it.** Each pixel adds its colour,
scaled by its alpha, to the one beneath. A spark over a torch makes it brighter,
and one over black shows as it is:

```ruby
renderer.blended(:add) { renderer.circle(0, 0, 4, color: spark) }
```

`:alpha` draws over what is behind, as everything outside a `blended` block
does. A mode inside another replaces it, so `blended(:alpha)` inside
`blended(:add)` draws one part plainly. Any other mode raises `ArgumentError`,
with the list in the message; `RGame::Util::Blend::MODES` holds it.

**`faded` multiplies the alpha of everything drawn inside it** and keeps its
colour. A fade inside another multiplies again, so `faded(0.5)` inside
`faded(0.5)` draws at a quarter. An opacity outside 0..1, NaN included, raises
`ArgumentError`, and anything but a number raises `TypeError`.

```ruby
renderer.faded(0.4) { renderer.image(:hero, 0, 0) }
```

`faded` is how something fades without a new colour every frame. A `Color` is a
frozen value, so building one a tick allocates an object a tick. Keep one colour
and change the opacity instead:

```ruby
def _update(dt) = @fade.update(dt)
def _draw(renderer, view) = renderer.faded(@fade.value) { renderer.rect(0, 0, view.width, view.height, color: BLACK) }
```

`faded(1)` skips the push, as `rotated(0, …)` does. **A scene node rarely
calls `faded` itself.** `Node2D#opacity` fades a node and everything under it;
see [Scene graph](scene_graph.md#opacity).

**Neither changes draw order.** The renderer keeps each draw's mode and opacity
with the draw itself, so `z` alone decides what is drawn over what. An additive
spark at a lower `z` than a wall is still drawn under the wall.

## Recordings: bake once, replay cheaply

**`record` bakes a block of drawing, and a replay costs one call per texture.** A
tile layer holds a few thousand quads that stay the same once the level loads, so
it is the typical case:

```ruby
def draw
  @ground ||= @renderer.record do
    @tiles.each { |tile| @renderer.image(tile.image, tile.x, tile.y) }
  end

  @ground.draw(-@camera.x, -@camera.y)
end
```

Baking draws nothing; the block's output goes into the recording, not the frame.
`record` must run inside `draw` like every other call. The example therefore
bakes on the first frame, not in `initialize`.

```ruby
baked.draw(x = 0, y = 0, z: 0, color: nil)
baked.batch_count   # GL calls one replay costs
baked.vertex_count  # vertices baked in
baked.width         # the size of what was baked, with #height
baked.empty?
```

**A recording bakes in positions, texture coordinates, colours and any
transforms inside the block.** The transform in effect at replay applies on top.
A baked layer scrolls under a camera without a rebuild, and one recording can be
stamped in several places:

```ruby
5.times { |i| @bush.draw(i * 120, 300) }
```

**`color:` tints the replay.** The renderer multiplies each recorded colour by
it, so you can fade a whole baked layer at once.

**A recording cannot contain a clip.** Clipping happens at rasterisation, so a
clip captured in one place would be wrong everywhere else the recording is drawn.
Pushing a clip inside a `record` block raises. Clip the replay instead:

```ruby
@renderer.clipped(0, 0, 400, 600) { @ground.draw(-@camera.x, -@camera.y) }
```

**A blend mode cannot be recorded either**, and `blended` inside a `record`
block raises for the same reason. Blend the replay. A `faded` block inside
`record` is baked in, because opacity is part of each vertex's colour. A replay
inside `faded` is faded, after its `color:` tint.

Recordings do not nest. A block that raises leaves no half-built recording
behind. A recording keeps its baked images alive, so dropping a sprite sheet
after baking does not free its texture.

## Testing what a scene draws

**Treat the renderer as an interface, not a class your game names.** Game logic
receives a renderer and calls its methods. A headless spec passes a recording
fake instead and asserts on the calls. rgame's own suite uses `FakeRenderer`
from `spec/support/`:

```ruby
renderer = FakeRenderer.new
health_bar._draw(renderer, nil)

expect(renderer.calls_to(:rect).map(&:args)).to eq([[10, 10, 64, 8]])
```

The fake also records recordings, and keeps two questions apart: what was baked,
and where it was replayed.

```ruby
ground = renderer.record { ... }   # => a FakeRecording

expect(ground.calls.size).to eq(tiles.size)   # baked once, not per frame
expect(ground.draws.map(&:args)).to eq([[-camera.x, -camera.y]])
```

**The fake measures text with the real font.** Its `text_width` and
`text_height` come from `RGame::Util::Typeface.default`, the face the real
renderer draws with unless told otherwise. So a spec can assert the exact
position of a centred label.

These specs run with no window, no GPU and no clock. One shared contract,
`spec/support/shared_examples/a_renderer.rb`, checks both the fake and the real
renderer. A fake that drifted from the real renderer would keep the suite green
while the game stopped drawing.

## Text

`renderer.text(string, x, y)` draws a line of text, and `text_width` measures
one. Both take a String or an [`Engine::Text`](toolbox.md#text--the-string-a-node-draws). [Text](text.md) covers fonts, the shipped default and the characters it
covers.
