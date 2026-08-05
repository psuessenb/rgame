# rgame API guide

Reference documentation for using rgame from Ruby. The engine is written in C
and exposed as two Ruby extensions; nothing here assumes you will read or write
any C.

| Page | Covers |
|---|---|
| This page | Loading the library, the two namespaces, a working program, testing |
| [App](app.md) | `RGame::Core::App` — the window and the frame loop |
| [Input](input.md) | `RGame::Core::Input`, `RGame::Util::Controls`, `RGame::Core::Gamepad` |
| [Drawing](drawing.md) | `RGame::Core::Renderer` — shapes, images, transforms, clipping, recordings |
| [Images](images.md) | `RGame::Core::Image` — loading PNGs, subimages, sprite sheets |
| [Text](text.md) | `RGame::Core::Font` and `Renderer#text` |
| [Values](values.md) | `RGame::Util::Color`, `RGame::Util::Tensor` |

**The engine is a work in progress.** A window opens, the loop runs, input
works, and shapes, images and text can be drawn. Audio and a scene graph are
still to come. Pages here describe what exists today and grow as more lands.

## Loading it

Two requires, and the difference between them matters:

```ruby
require 'rgame'       # RGame::Util — no graphics libraries loaded at all
require 'rgame/core'  # adds RGame::Core, and pulls in SDL2 + OpenGL
```

`require 'rgame'` gives you the value types — colours, grids — in a process
with **no SDL and no OpenGL loaded**, which is what lets game logic and its
tests run with no display present. `require 'rgame/core'` is an explicit
opt-in for the parts that own a window.

For convenience, `rgame/core` also defines `RGame::Util::Controls` (the input
id vocabulary), because the input classes need it. `Color` and `Tensor` still
need `require 'rgame'`.

Both extensions must be compiled before they can be required:

```
make ext        # builds both, copies them into lib/rgame/
```

## The two namespaces

Everything lives under `RGame`, split in two by what it depends on:

| | `RGame::Util` | `RGame::Core` |
|---|---|---|
| Contains | shareable *values* — no window, no GPU, nothing to release | things owning a window, GPU or OS handle |
| Today | `Color`, `Tensor`, `Controls` | `App`, `Input`, `Gamepad`, `Image`, `Renderer`, `Recording`, `Font` |
| Loading it costs | nothing | SDL2 + OpenGL in your process |

The rule for deciding where something belongs: **a value goes in `Util`; only a
handle-owner goes in `Core`.** A colour is a value. A window is not.

This is not tidiness. Game logic is expected to hold `Util` types freely as
attributes, and to reach `Core` only through objects handed to it — a node's
`draw` receives a renderer and calls methods on it, rather than naming a class.
That is what keeps game code runnable with no window, which the testing section
below relies on.

## A complete program

```ruby
require 'rgame'
require 'rgame/core'

class MyGame < RGame::Core::App
  Controls = RGame::Util::Controls

  def initialize
    super(width: 800, height: 600, caption: 'My Game')
    @input = RGame::Core::Input.new(self)
    @renderer = RGame::Core::Renderer.new(self)
    @x = 400.0
    @y = 300.0
  end

  # One fixed simulation tick. `dt` is always the same fixed step, never
  # wall-clock frame time, so movement is deterministic.
  def update(dt)
    speed = 200.0 * dt
    @x -= speed if @input.down?(:left)
    @x += speed if @input.down?(:right)
    @y -= speed if @input.down?(:up)
    @y += speed if @input.down?(:down)
  end

  # Everything is drawn here, through a renderer built in initialize. See
  # docs/api/drawing.md.
  def draw
    @renderer.rect(@x - 8, @y - 8, 16, 16)
  end

  def button_down(id)
    close if id == Controls::KEY_ESCAPE
  end
end

MyGame.new.run
```

You subclass `App` and override the hooks you care about. Everything you do not
override is an inherited no-op — there is no `super` to remember, and no way to
break the loop by forgetting one. See [App](app.md) for the full list.

## Testing a game built on this

The namespace split exists so that game logic can be tested without opening a
window. Drive `update` directly and it runs as fast as the CPU allows:

```ruby
# A plain object holding your game's rules — no RGame::Core anywhere.
class Player
  attr_reader :x

  def initialize = @x = 0.0

  def update(dt, moving_right:)
    @x += 200.0 * dt if moving_right
  end
end

RSpec.describe Player do
  it 'walks right at 200 units a second' do
    player = Player.new
    # One simulated second, sixty ticks, no window and no clock.
    60.times { player.update(1.0 / 60.0, moving_right: true) }

    expect(player.x).to be_within(0.01).of(200.0)
  end
end
```

The engine deliberately makes this easy: `update` takes `dt` as an argument
rather than reading a clock, so a test can pass whatever timestep it likes and
simulate an hour in milliseconds.

Keep the parts of your game that decide *what happens* free of `RGame::Core`,
and hand them a renderer at draw time rather than storing one. Then the only
code that needs a window is the thin layer that puts pixels on screen.
