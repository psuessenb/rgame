# rgame API guide

Reference documentation for using rgame from Ruby. The engine is written in C
and exposed as two Ruby extensions, with the scene graph a game is actually
written in sitting on top of them in pure Ruby; nothing here assumes you will
read or write any C.

| Page | Covers |
|---|---|
| This page | Loading the library, the three namespaces, a working program, testing |
| [The `rgame` command](cli.md) | `rgame new NAME` — starting a project, and the layout it gives you |
| [App](app.md) | `RGame::Core::App` — the window and the frame loop |
| [Game](game.md) | `RGame::Game` — the entry point that wires both halves together |
| [Input](input.md) | `RGame::Core::Input`, `RGame::Util::Controls`, `RGame::Core::Gamepad` |
| [Drawing](drawing.md) | `RGame::Core::Renderer` — shapes, images, transforms, clipping, recordings |
| [Images](images.md) | `RGame::Core::Image` — loading PNGs, subimages, sprite sheets |
| [Text](text.md) | `RGame::Core::Font` and `Renderer#text` |
| [Audio](audio.md) | `RGame::Core::Audio`, `Sample`, `Song` — samples and streamed music |
| [Sheets, atlases and maps](assets.md) | `RGame::Core::SpriteSheet` and the rest of the asset layer |
| [Values](values.md) | `RGame::Util::Color`, `RGame::Util::Tensor`, `RGame::Util::Z` |

The scene graph — `RGame::Engine`, the layer a game is actually written in:

| Page | Covers |
|---|---|
| [Scene graph](scene_graph.md) | `Node2D`, the tree, the lifecycle, transforms and the camera |
| [Components](components.md) | Reusable behaviour attached to a node |
| [Systems](systems.md) | Services a subtree shares — collision worlds, tile worlds |
| [UI](ui.md) | `PlayerLayer` and `UI::Menu` — a player's own screen, navigated by focus |
| [Signals](signals.md) | The typed observer pattern nodes talk through |
| [Toolbox](toolbox.md) | What a game author reaches for directly: pooling, timers, camera, i18n, the audio bus |
| [Internal building blocks](internals.md) | What components are built from: collision maths, the spatial index, animation playback |

**The engine is a work in progress.** A window opens, the loop runs, input
works, shapes, images and text can be drawn, sound plays, and a scene graph with
split-screen players runs on top of it — the games under `examples/` are built
on exactly what is documented here. What is missing is a UI *toolkit*: [UI](ui.md)
gives each player a region of the screen, focus and activation, and stops there —
no layout, no scrolling lists, no text entry. Pages here describe what exists
today and grow as more lands.

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

## The three namespaces

Everything lives under `RGame`, split three ways — two of them by what they
depend on, the third by what it is *for*:

| | `RGame::Util` | `RGame::Core` | `RGame::Engine` |
|---|---|---|---|
| Contains | shareable *values* — no window, no GPU, nothing to release | things owning a window, GPU or OS handle | game concepts: the scene graph a game is written in |
| Today | `Color`, `Tensor`, `Controls`, `Z` | `App`, `Input`, `Gamepad`, `Image`, `Renderer`, `Recording`, `Font`, `Audio`, `SpriteSheet`, `AssetManager` | `Node2D`, components, systems, signals, `TileMap`, `Player`, `InputMap`, `UI::Menu` |
| Loading it costs | nothing | SDL2 + OpenGL in your process | nothing |

The rule for splitting the bottom two: **a value goes in `Util`; only a
handle-owner goes in `Core`.** A colour is a value. A window is not.

`RGame::Engine` sits above both, and its rule is what makes the split worth
having:

- it may hold `Util` values freely as attributes — a `Color`, a `Tensor`;
- it may **not name `Core` at all** — no require, no constant, no attribute;
- it reaches `Core` only through objects handed to it. A node's `on_draw`
  receives a renderer and calls methods on it by name, never storing it and
  never asking what class it is.

This is not tidiness. It is what keeps a whole game — its rules, its scenes, its
collisions — runnable and testable with no window, which the testing section
below relies on. Two RuboCop cops enforce it in both directions, so a stray
reference is a failing lint rather than a discovery made later.

`RGame::Game` is the single exception, and the only class directly under
`RGame`: introducing the two halves to each other is exactly what it is for, and
confining that to one file is what keeps the rule checkable everywhere else.

## A complete program

A game is a tree of nodes plus `RGame::Game` to run it.

```ruby
require 'rgame/game'

# One game object: a square the player walks around. Pure Engine — it names no
# graphics class, so it runs just as happily in a spec with no window.
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

You subclass `Node2D` and override the hooks you care about — `on_control`,
`on_update`, `on_draw`, and the lifecycle hooks around them. Everything you do
not override is an inherited no-op, and the phase methods that do the
bookkeeping (pushing the node's transform, driving components, descending into
children) are not the ones you override — so there is no `super` to remember and
no way to break the tree by forgetting one. See [Scene graph](scene_graph.md)
for the full list, and [Game](game.md) for what `Game` assembles around it: the
window, the renderer, the asset manager, the sound device, the input mapper and
the players.

Pass no `input_map:` and you get the default one used above: eight-way `move_x`
/ `move_y` on the arrows, WASD, the d-pad or the left stick, plus `fire`. See
[Input](input.md).

## Testing a game built on this

The namespace split exists so that game logic can be tested without opening a
window. `require 'rgame'` gives you `Util` and the whole scene graph with no SDL
and no OpenGL in the process, and the nodes from the program above run there
unchanged — drive their phases directly and a simulated hour takes milliseconds:

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

Two things make that work:

- **`update` takes `dt` as an argument rather than reading a clock**, so a test
  passes whatever timestep it likes. That means tests are not dependent on real time and can simulate game behavior based on time in miliseconds.
- **A node never holds a renderer.** `on_draw` is given one, so drawing can be
  checked by passing a recording double and asserting on what the node asked
  for — see the renderer contract in `spec/support/shared_examples/`. All tests can be run completely headless.

`hero.x` is asserted rather than `world_x` because this node has no parent here.
The world transform accumulates from the parent, and a node with no parent
resolves to the origin. Put it under a root and `world_x` is what game logic
reads — though drawing reads neither, see
[Scene graph](scene_graph.md#drawing-happens-in-local-space).

Keep the parts of your game that decide *what happens* in `RGame::Engine` — the
layer cannot name `RGame::Core`, so it cannot accidentally acquire a dependency
on a window. Then the only code that needs one is the thin layer that puts
pixels on screen.
