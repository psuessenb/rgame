# rgame API guide

Reference documentation for using rgame from Ruby. The engine is written in C
and exposed as two Ruby extensions; nothing here assumes you will read or write
any C.

| Page | Covers |
|---|---|
| This page | Loading the library, the two namespaces, a working program, testing |
| [App](app.md) | `RGame::Core::App` — the window and the frame loop |
| [Game](game.md) | `RGame::Game` — the entry point that wires both halves together |
| [Input](input.md) | `RGame::Core::Input`, `RGame::Util::Controls`, `RGame::Core::Gamepad` |
| [Drawing](drawing.md) | `RGame::Core::Renderer` — shapes, images, transforms, clipping, recordings |
| [Images](images.md) | `RGame::Core::Image` — loading PNGs, subimages, sprite sheets |
| [Text](text.md) | `RGame::Core::Font` and `Renderer#text` |
| [Audio](audio.md) | `RGame::Core::Audio`, `Sample`, `Song` — samples and streamed music |
| [Sheets, atlases and maps](assets.md) | `RGame::Core::SpriteSheet` and the rest of the asset layer |
| [Values](values.md) | `RGame::Util::Color`, `RGame::Util::Tensor` |

The scene graph — `RGame::Engine`, the layer a game is actually written in:

| Page | Covers |
|---|---|
| [Scene graph](scene_graph.md) | `Node2D`, the tree, the lifecycle, transforms and the camera |
| [Components](components.md) | Reusable behaviour attached to a node |
| [Systems](systems.md) | Services a subtree shares — collision worlds, tile worlds |
| [Signals](signals.md) | The typed observer pattern nodes talk through |
| [Toolbox](toolbox.md) | What a game author reaches for directly: pooling, timers, camera, i18n, the audio bus |
| [Internal building blocks](internals.md) | What components are built from: collision maths, the spatial index, animation playback |

**The engine is a work in progress.** A window opens, the loop runs, input
works, shapes, images and text can be drawn, sound plays, and a scene graph runs
on top of it — the two games under `examples/` are built on exactly what is
documented here. What is missing is a UI toolkit and split-screen; pages here
describe what exists today and grow as more lands.

## Loading it

Three requires, each a strict superset of the last:

```ruby
require 'rgame'       # RGame::Util + RGame::Engine — no graphics libraries at all
require 'rgame/core'  # adds the window, the GPU and the sound device (SDL2 + OpenGL)
require 'rgame/game'  # all of it, wired together — what a game writes
```

A game wants the last one. `RGame::Game` is the entry point; see
[Game](game.md).

The first is **everything that runs without a window**: the value types and the
whole scene graph, in a process with no SDL and no OpenGL loaded. That is what
lets game logic and its specs run with no display present, and it is asserted
rather than assumed — `spec/rgame/no_graphics_spec.rb` reads the process's own
memory map.

Nothing is forced through those files: `rgame/util`, `rgame/engine` and
`rgame/core` are separately requirable, which is how the Core spec suite loads
exactly one layer.

For convenience, `rgame/core` also defines `RGame::Util::Controls` (the input
id vocabulary), because the input classes need it.

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
