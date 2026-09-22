# rgame API guide

These pages document how to use rgame from Ruby. The engine is written in C and
ships as two Ruby extensions. The scene graph sits on top of them in pure Ruby,
and a game is written against that scene graph. Nothing here asks you to read
or write C.

| Page | Covers |
|---|---|
| This page | Loading the library, the three namespaces, a working program, testing |
| [The `rgame` command](cli.md) | `rgame new NAME` — starting a project, and the layout it gives you |
| [App](app.md) | `RGame::Core::App` — the window and the frame loop |
| [Game](game.md) | `RGame::Game` — the entry point that wires both halves together |
| [Input](input.md) | `RGame::Core::Input`, `RGame::Util::Controls`, `RGame::Core::Gamepad`, `RGame::Core::VirtualGamepad` |
| [Drawing](drawing.md) | `RGame::Core::Renderer` — shapes, images, transforms, clipping, recordings |
| [Images](images.md) | `RGame::Core::Image` — loading PNGs, subimages, tiles |
| [Text](text.md) | `RGame::Core::Font`, `Renderer#text`, `RGame::Util::Typeface` and `RGame::Engine::Paragraph` |
| [Audio](audio.md) | `RGame::Core::Audio`, `Sample`, `Song` — samples and streamed music — and `Engine::AudioOut`, the system a node plays them through |
| [Assets](assets.md) | `RGame::Core::AssetManager`, `SpriteSheet`, `NineSlice`, `UiAtlas`, `TileMapRenderer` |
| [Values](values.md) | `RGame::Util::Color`, `Tensor`, `SolidGrid`, `RouteSearch`, `TileSweep`, `Z`, `SaveFile` |
| [Examples](examples.md) | What each program under `examples/` demonstrates |

The scene graph is `RGame::Engine`, the layer a game is written in:

| Page | Covers |
|---|---|
| [Scene graph](scene_graph.md) | `Node2D`, the tree, the lifecycle, transforms and the camera |
| [Components](components.md) | Reusable behaviour attached to a node |
| [Systems](systems.md) | Services a subtree shares — collision worlds, tile worlds |
| [Tile maps](tile_maps.md) | `TileMap` — a Tiled map as data: loading, cells, tiles, solidity, layers, objects and the nodes built from them, custom properties |
| [UI](ui.md) | `PlayerLayer`, `UI::Menu`, `UI::Label` and `UI::DialogueBox` — a player's own screen, a list or wheel navigated by focus, a translated paragraph drawn a page at a time, and a box that shows a conversation |
| [Signals](signals.md) | The typed observer pattern nodes talk through |
| [Dialogue and state machines](dialogue.md) | `StateGraph` and `StateMachine` — states, transitions with conditions and effects, visit counts; `Components::Facts`, the flags they read, and saving both as one entry; `Dialogue::Script` and `Dialogue` — beats, responses and conversations; `Dialogue::Transcript`, what one said; `Exploration`, which checks every path in a spec |
| [Toolbox](toolbox.md) | What a game author reaches for directly: the text a node draws, pooling, paths and routes, timers, the camera, collision boxes |
| [Localization](localization.md) | `I18n` and translation tables — where they go, plurals, the fallback chain, the player's language, missing keys in specs |
| [Internal building blocks](internals.md) | What components are built from: collision maths, the spatial index, animation playback |

**The engine is a work in progress.** It opens a window, runs the loop, reads
input, draws shapes, images and text, and plays sound. A scene graph with
split-screen players runs on top. The games under `test_projects/` use exactly
what these pages document. The missing piece is a UI *toolkit*. [UI](ui.md)
gives each player a region of the screen, menus with focus and activation, and a
column, row or ring of equal-sized buttons. It has no general layout, no scrolling
lists and no text entry. These pages describe
what exists and grow with the engine.

## Loading it

rgame has three entry points. Each one loads everything the one before it does:

```ruby
require 'rgame'       # RGame::Util + RGame::Engine — no graphics libraries at all
require 'rgame/core'  # adds the window, the GPU and the sound device (SDL2 + OpenGL)
require 'rgame/game'  # all of it, wired together — what a game writes
```

A game requires the last one. Its entry point is `RGame::Game`; see
[Game](game.md).

`require 'rgame'` loads **everything that runs without a window**: the value
types and the whole scene graph. The process loads no SDL and no OpenGL, so game
logic and its specs run with no display. `spec/rgame/no_graphics_spec.rb` checks
this by reading the process's own memory map.

You can also require `rgame/util`, `rgame/engine` and `rgame/core` on their own.
The Core spec suite does this to load exactly one layer.

`rgame/core` also loads `RGame::Util::Controls`, the input id vocabulary,
because the input classes need it.

**Your install either compiled both extensions or arrived with them built.** On
Apple Silicon macOS, x86-64 Linux and 64-bit Windows, `gem install rgame` fetches
a gem that already holds `core_ext` and `util_ext`, with SDL2 inside `core_ext`,
and compiles nothing. Every other machine gets the gem that ships the C and
builds both on install, against a system SDL2. Either way the two land in the
same place and the three requires above behave the same.

In a checkout of the repository, compile them before you require anything:

```
make ext        # builds both, copies them into lib/rgame/
```

## The three namespaces

Everything lives under `RGame`. What a class depends on decides between `Util`
and `Core`. `Engine` holds what a game is written in.

| | `RGame::Util` | `RGame::Core` | `RGame::Engine` |
|---|---|---|---|
| Contains | shareable *values* — no window, no GPU, nothing to release | things owning a window, GPU or OS handle | game concepts: the scene graph a game is written in |
| Classes | `Color`, `Tensor`, `Controls`, `Z`, `SolidGrid`, `RouteSearch`, `TileSweep`, `SaveFile` | `App`, `Input`, `Gamepad`, `VirtualGamepad`, `Image`, `Renderer`, `Recording`, `Font`, `Audio`, `SpriteSheet`, `NineSlice`, `UiAtlas`, `TileMapRenderer`, `AssetManager` | `Node2D`, components, systems, signals, `TileMap`, `Player`, `InputMap`, `UI::Menu` |
| Loading it costs | nothing | SDL2 + OpenGL in your process | nothing |

**A value goes in `Util`; only a handle-owner goes in `Core`.** A colour is a
value. A window is not.

`RGame::Engine` sits above both and follows three rules:

- It may hold `Util` values as attributes, such as a `Color` or a `Tensor`.
- It may **not name `Core` at all**: no require, no constant, no attribute.
- It reaches `Core` only through objects it receives. A node's `on_draw`
  receives a renderer and calls its methods by name. The node never stores the
  renderer and never checks its class.

These rules keep a whole game runnable and testable with no window: its rules,
its scenes, its collisions. The testing section below relies on that. RuboCop
cops enforce the rules in both directions inside rgame's own repository, and a
project from `rgame new` runs the first of them over its `nodes/` and `spec/`.
See [the generated RuboCop configuration](cli.md#the-generated-rubocop-configuration).

`RGame::Game` is the one exception: the only class that names both `Engine` and
`Core`. It exists to connect the two halves. Keeping that in one file lets the
rule hold everywhere else.

## A complete program

A game is a tree of nodes, run by `RGame::Game`.

```ruby
require 'rgame/game'

# One game object: a square the player walks around. Pure Engine — it names no
# graphics class, so it runs unchanged in a spec with no window.
class Hero < RGame::Engine::Node2D
  SPEED = 200.0

  def initialize
    super(x: 400, y: 300, width: 16, height: 16)
    @vx = 0.0
    @vy = 0.0
  end

  # Intent, read once per simulation tick. Never a key: `move_x` is whatever
  # this player's input map binds it to — arrows, WASD or a stick.
  def on_control(actions)
    @vx = actions.axis(:move_x) * SPEED
    @vy = actions.axis(:move_y) * SPEED
  end

  # `dt` is always the same fixed step, never wall-clock frame time, so
  # movement is deterministic. `x`/`y` are relative to the parent.
  def on_update(dt)
    self.x += @vx * dt
    self.y += @vy * dt
  end

  # The renderer is handed in and never stored; `view` is the viewport being
  # drawn into, which most nodes ignore. Draw in the node's own space: the
  # traversal has already put the renderer on this node, so (0, 0) is here.
  # See docs/api/scene_graph.md, "Drawing happens in local space".
  def on_draw(renderer, _view)
    renderer.rect(0, 0, width, height)
  end
end

# The root of the tree. Children are added in `on_add`, once the node is in a
# tree and can reach the game around it.
class Scene < RGame::Engine::Node2D
  def on_add
    add_node(Hero.new)
  end
end

RGame::Game.new(root: Scene.new, width: 800, height: 600, caption: 'My Game').start
```

Subclass `Node2D` and override the hooks you need: `on_control`, `on_update`,
`on_draw`, and the lifecycle hooks around them. A hook you do not override does
nothing. Separate phase methods do the bookkeeping: they push the node's
transform, drive components and descend into children. You never override
those, so there is no `super` to forget. [Scene graph](scene_graph.md) lists
every hook. [Game](game.md) describes what `Game` builds around the tree: the
window, the renderer, the asset manager, the sound device, the input mapper and
the players.

Without an `input_map:`, `Game` uses the default map shown above. It binds
eight-way `move_x` / `move_y` to the arrows, WASD, the d-pad and the left stick,
and adds `fire`. See [Input](input.md).

## Testing a game built on this

`require 'rgame'` loads `Util` and the whole scene graph with no SDL and no
OpenGL. The nodes from the program above run there unchanged. A spec drives
their phases directly, so a simulated hour takes milliseconds:

<!-- doc-example: skip — an RSpec file for the Hero above, run by rspec -->
```ruby
require 'rgame'

RSpec.describe Hero do
  it 'walks right at 200 units a second' do
    hero = Hero.new
    # The same snapshot object the input mapper hands a node at runtime, built
    # by hand with the stick pushed fully right.
    actions = RGame::Engine::Actions.new(axes: { move_x: 1.0, move_y: 0.0 })

    # One simulated second, sixty ticks, no window and no clock.
    60.times do
      hero.control(actions)
      hero.update(1.0 / 60.0)
    end

    expect(hero.x).to be_within(0.01).of(600.0)
  end
end
```

Two properties make this work:

- **`update` takes `dt` as an argument and reads no clock.** A test passes any
  timestep it likes, so it can simulate minutes of play in milliseconds.
- **A node never holds a renderer.** `on_draw` receives one. A spec passes a
  recording double and asserts on what the node asked it to draw. rgame's own
  suite checks its fake renderer against the real one with a shared contract in
  `spec/support/shared_examples/`. The whole suite runs headless.

The spec asserts `hero.x`, not `world_x`, because this hero has no parent. The
world transform accumulates from the parent, and a node without one resolves to
the origin. Under a root, game logic reads `world_x`. Drawing reads neither; see
[Scene graph](scene_graph.md#drawing-happens-in-local-space).

Keep the code that decides *what happens* in `RGame::Engine`. That layer cannot
name `RGame::Core`, so it cannot come to depend on a window. Only the thin layer
that puts pixels on screen then needs one.
