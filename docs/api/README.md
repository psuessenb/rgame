# rgame API guide

These pages document how to use rgame from Ruby. The engine is written in C and
ships as two Ruby extensions. The scene graph sits on top of them in pure Ruby,
and a game is written against that scene graph. Nothing here asks you to read
or write C.

| Page | Covers |
|---|---|
| This page | Loading the library, the three namespaces, a working program, a game's own module, testing |
| [The `rgame` command](cli.md) | `rgame new NAME` — starting a project, and the layout it gives you |
| [App](app.md) | `RGame::Core::App` — the window and the frame loop |
| [Game](game.md) | `RGame::Game` — the entry point that wires both halves together |
| [Input](input.md) | `RGame::Core::Input`, `RGame::Util::Controls`, `RGame::Core::Gamepad`, `RGame::Core::VirtualGamepad`, and `Players#everyone` for input every player shares |
| [Drawing](drawing.md) | `RGame::Core::Renderer` — shapes, images, transforms, clipping, blending and fading, recordings |
| [Images](images.md) | `RGame::Core::Image` — loading PNGs, subimages, tiles |
| [Text](text.md) | `RGame::Core::Font`, `Renderer#text`, `RGame::Util::Typeface` and `RGame::Engine::Paragraph` |
| [Audio](audio.md) | `RGame::Core::Audio`, `Sample`, `Song` — samples, streamed music and category volumes — and `Engine::AudioOut`, the system a node plays them through and fades music with |
| [Assets](assets.md) | `RGame::Core::AssetManager`, `SpriteSheet`, `NineSlice`, `UiAtlas`, `TileMapRenderer` |
| [Values](values.md) | `RGame::Util::Color`, `ColorRamp`, `Tensor`, `SolidGrid`, `RouteSearch`, `TileSweep`, `Z`, `Blend`, `SaveFile` |
| [Examples](examples.md) | What each program under `examples/` demonstrates |

The scene graph is `RGame::Engine`, the layer a game is written in:

| Page | Covers |
|---|---|
| [Scene graph](scene_graph.md) | `Node2D`, the tree, the lifecycle, transforms and the camera, the scene stack with its transitions, and the rooms players stand apart in |
| [Components](components.md) | Reusable behaviour attached to a node |
| [Systems](systems.md) | Services a subtree shares — collision worlds, tile worlds |
| [Tile maps](tile_maps.md) | `TileMap` — a Tiled map as data: loading, cells, tiles, solidity, layers, objects and the nodes built from them, custom properties |
| [UI](ui.md) | `PlayerLayer`, `UI::Menu`, `UI::Tabs`, `UI::Label` and `UI::DialogueBox` — a player's own screen, a list or wheel navigated by focus, pages shown one at a time under a bar of tabs, a translated paragraph drawn a page at a time, and a box that shows a conversation |
| [Signals](signals.md) | The typed observer pattern nodes talk through |
| [Dialogue and state machines](dialogue.md) | `StateGraph` and `StateMachine` — states, transitions with conditions and effects, visit counts; `Components::Facts`, the flags they read, and saving both as one entry; `Dialogue::Script` and `Dialogue` — beats, responses and conversations; `Dialogue::Transcript`, what one said; `Exploration`, which checks every path in a spec |
| [Toolbox](toolbox.md) | What a game author reaches for directly: the text a node draws, pooling, paths and routes, timers and tweens, a fade over the screen, a cutscene's steps, the camera, collision boxes |
| [Localization](localization.md) | `I18n` and translation tables — where they go, plurals, the fallback chain, the player's language, missing keys in specs |
| [Internal building blocks](internals.md) | What components are built from: collision maths, the spatial index, animation playback, and building a node from a map's object |

**The engine is a work in progress.** It opens a window, runs the loop, reads
input, draws shapes, images and text, and plays sound. A scene graph with
split-screen players runs on top. The games under `test_projects/` use exactly
what these pages document. The missing piece is a UI *toolkit*. [UI](ui.md)
gives each player a region of the screen, menus with focus and activation, a
column, row, grid or ring of equal-sized buttons, lists that scroll whole rows, and
pages under a bar of tabs. It has no general layout and no text entry. These pages describe
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
- It reaches `Core` only through objects it receives. A node's `_draw`
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

# The game's own module. `Engine`, `Util`, `UI` and `Components` inside it stand
# for rgame's namespaces of the same names; see "A game's own module" below.
module MyGame
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  # One game object: a square the player walks around. Pure Engine — it names no
  # graphics class, so it runs unchanged in a spec with no window.
  class Hero < Engine::Node2D
    SPEED = 200.0
    TINT = Util::Color.new(240, 200, 80)

    def initialize
      super(x: 400, y: 300, width: 16, height: 16)
      @vx = 0.0
      @vy = 0.0
    end

    # Intent, read once per simulation tick. Never a key: `move_x` is whatever
    # this player's input map binds it to — arrows, WASD or a stick.
    def _control(actions)
      @vx = actions.axis(:move_x) * SPEED
      @vy = actions.axis(:move_y) * SPEED
    end

    # `dt` is always the same fixed step, never wall-clock frame time, so
    # movement is deterministic. `x`/`y` are relative to the parent.
    def _update(dt)
      self.x += @vx * dt
      self.y += @vy * dt
    end

    # The renderer is handed in and never stored; `view` is the viewport being
    # drawn into, which most nodes ignore. Draw in the node's own space: the
    # traversal has already put the renderer on this node, so (0, 0) is here.
    # See docs/api/scene_graph.md, "Drawing happens in local space".
    def _draw(renderer, _view)
      renderer.rect(0, 0, width, height, color: TINT)
    end
  end

  # The root of the tree. Children are added in `_enter_tree`, once the node is in a
  # tree and can reach the game around it.
  class Scene < Engine::Node2D
    def _enter_tree
      add_node(Hero.new)
    end
  end
end

RGame::Game.new(root: MyGame::Scene.new, width: 800, height: 600, caption: 'My Game').start
```

Subclass `Node2D` and override the hooks you need: `_control`, `_update`,
`_draw`, and the lifecycle hooks around them. A hook you do not override does
nothing. Separate phase methods do the bookkeeping: they push the node's
transform, drive components and descend into children. You never override
those, so there is no `super` to forget. [Scene graph](scene_graph.md) lists
every hook. [Game](game.md) describes what `Game` builds around the tree: the
window, the renderer, the asset manager, the sound device, the input mapper and
the players.

Without an `input_map:`, `Game` uses the default map shown above. It binds
eight-way `move_x` / `move_y` to the arrows, WASD, the d-pad and the left stick,
and adds `fire`. See [Input](input.md).

## A game's own module

**A game keeps its classes in a module of its own, and names rgame's namespaces
at the top of it:**

```ruby
module MyGame
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components
end
```

Inside `MyGame`, and inside every class written within it, `Engine::Node2D`
means `RGame::Engine::Node2D`, `Util::Color` means `RGame::Util::Color`,
`UI::Menu` means `RGame::Engine::UI::Menu` and `Components::Sprite` means
`RGame::Engine::Components::Sprite`. The game's own names stay off the top level,
where Ruby's and every gem's live.

A game's class may share a name with an engine class. `MyGame::Scene` is the
game's, and `Engine::Scene` is the engine's module beside it. Five names exist
both directly under `Engine` and under `Components`, and the prefix says which is
meant: a node's own code advances an `Engine::Timer`, while a
`Components::Timer` rides the node's update and emits `on_elapsed`. The other four
are `CircleCollider`, `Cutscene`, `Pool` and `Tween`. A module may add shorthands of its own the same
way, such as `Controls = Util::Controls`.

**rgame's own classes and modules are closed to the `class` and `module`
keywords.** Inside `MyGame`, `UI` and `Components` are rgame's, so a module of the
game's own with one of those names reopens rgame's rather than making a new one.
A class inside it named like one of rgame's, such as `Timer`, would replace
rgame's methods. So a constant, method or singleton method written in a class or
module body outside rgame, onto a class or module under `RGame::Engine` or
`RGame::Util`, raises `NameError` naming the file and the line. Give the game's
module another name, such as `Hud`. Subclassing is unaffected, and so are a spec
that stubs a method on an rgame module, `define_method` and `class_eval`.

The shorter spellings each break somewhere:

| Spelling | What goes wrong |
|---|---|
| `include RGame::Engine` in the module | `Text` inside `class Hero` raises `NameError`. Ruby looks a constant up in the modules written around the code, then in the ancestors of the innermost class, and an enclosing module's includes are in neither. |
| every engine name assigned at the top level | `Signal` replaces Ruby's own. A game's `class Scene < Node2D` raises `TypeError`, since `Scene` is the engine's module. A game's `class Timer` with no superclass adds its methods to the engine's `Timer`, and nothing warns. |
| every engine name copied into the game's module | the same collisions, one level down |

**Assign the four constants once.** Ruby warns when a constant is assigned again.
A game in several files defines the module and its constants in one file, and
every other file requires that file first. `rgame new` writes it and names it
after the game; see [the `rgame` command](cli.md#what-rgame-new-tictactoe-writes).

**Write each class inside `module MyGame`, not as `class MyGame::Hero`.** The
compact form leaves `MyGame` out of the modules written around the class, so
`Engine` does not resolve in its superclass or its body.

The programs under `examples/` follow the same shape, each in a module named
after its directory, such as `WalkExample`.

## Testing a game built on this

`require 'rgame'` loads `Util` and the whole scene graph with no SDL and no
OpenGL. The nodes from the program above run there unchanged. A spec drives
their phases directly, so a simulated hour takes milliseconds:

<!-- doc-example: skip — an RSpec file for the Hero above, run by rspec -->
```ruby
require 'rgame'

RSpec.describe MyGame::Hero do
  it 'walks right at 200 units a second' do
    hero = MyGame::Hero.new
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
- **A node never holds a renderer.** `_draw` receives one. A spec passes a
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
