# `RGame::Game`

`Game` is a game's entry point, and the one class that knows both halves of the
engine.

```ruby
require 'rgame/game'

class HelloScene < RGame::Engine::Node2D
  def on_draw(renderer, _view) = renderer.text('Hello world!', 250, 200)
end

RGame::Game.new(root: HelloScene.new, caption: 'Hello').start
```

A root node plus those lines make a complete game. `Game` builds what a running
game needs and drives the root node. It builds the window and its loop, the
renderer, the asset manager, the sound device, the input mapper and the debug
overlay.

```ruby
RGame::Game.new(root:, width: 640, height: 480, caption: 'RGame',
                media_root: 'media', input_map: nil, device: Controls::KEYBOARD,
                players: 1, input: nil, fullscreen: false, scale_mode: :letterbox,
                locales: 'locales')
```

| Reader | |
|---|---|
| `root` | the node tree |
| `renderer` | what scenes draw through |
| `players` | who is playing: their devices, bindings and cameras |
| `viewports` | how the screen is divided between players |
| `scale_mode`, `scale_mode=` | how the logical size maps onto the window; switchable while the game runs |
| `assets`, `audio`, `media_root`, `width`, `height`, `fps` | inherited from [App](app.md) |

A node reaches `players` and `viewports` as systems:
`node.system(RGame::Engine::Players)` and `node.system(RGame::Engine::Viewports)`.

`input:` replaces the input backend. A test harness passes a scripted backend
here to drive a game without hardware. A game passes nothing.

### `scale_mode:` — what `width` and `height` mean

**`width` and `height` are the logical size**: the resolution the game is
designed in. `Game` maps the whole frame onto the window, whatever its size. The
view a node draws into keeps the logical size. A layout written against fixed
numbers therefore works at any window size, fullscreen included.

| | |
|---|---|
| `:letterbox` | The default. Largest uniform scale that fits, centred, bars on two sides. |
| `:integer` | The same, rounded down to a whole number. |
| `:stretch` | Fill the window, distorting if the aspect ratios differ. |
| `:disabled` | No scaling at all: `width` and `height` are the window, and the view is too. |

**`:disabled` turns scaling off and changes what the numbers mean.** The view
becomes the window, so a bigger window hands every `draw` a bigger view. A layout
written against `view.width` grows into the space. A layout written against fixed
numbers stays in the top-left corner. Choose `:disabled` for a program that uses
whatever space it gets: a tool, an editor, a program that is all HUD. Do not
choose it for a game with a designed play area. It is the only mode that pushes
no clip, translate or scale.

```ruby
require 'rgame/game'

class Root < RGame::Engine::Node2D; end

RGame::Game.new(root: Root.new, width: 320, height: 180, scale_mode: :integer).start
```

**Choose `:integer` for pixel art.** A whole-number factor draws every source
pixel as the same square on screen. A fractional factor gives some pixels two
screen pixels and some three, and the unevenness crawls whenever anything moves.
The mode can waste a lot of screen. A 640x480 design gets only 1x on a 1600x900
window, because 2x needs 960 rows. `RGame::Engine::Presentation` holds the
arithmetic and documents the measurements. It is pure and has its own specs.

A resize refits the mode and changes nothing else. Viewports, split-screen rects
and camera clamps already use logical units.

`examples/fullscreen` runs in every mode, chosen by an environment variable.

`fullscreen:` opens the window fullscreen, so the game shows no windowed frame
at startup. `width` and `height` then give the size the window returns to, if
the game offers a way back. See [Fullscreen](app.md#fullscreen) and
`examples/fullscreen`.

`start` brings the tree live. It hands the game to the root as its `context`,
mounts `Players` and `Viewports` on the root, and subscribes an `AudioDirector` to
the [`AudioBus`](toolbox.md#audiobus--decoupled-audio-facts). It then calls
`enter_tree` and runs the loop until the window closes. When the loop ends, it
unsubscribes the director. `F1` toggles the debug overlay and `F2` quits.

Each tick, `Game` polls input, runs `control` and `update` on the tree, and sweeps
freed nodes. It redraws only when a tick ran or the debug overlay is visible.

**Both development keys are function keys, and `Esc` stays free.** Players expect
Escape to back out of a menu, so it belongs to the game. A debug shortcut on it
would take it away from every game built on `Game`.

## Why this class exists

`RGame::Engine` holds game concepts and may not name `RGame::Core`.
`RGame::Core` owns windows, textures and sound devices, and may not know Engine
exists. **`Game` connects the two.** Keeping that connection in one file lets the
rule hold everywhere else. Inside rgame's own repository, two RuboCop cops enforce
it.

The tile map shows why. Engine parses a `.tmx`; Core draws it; neither may call
the other. `Game` installs the loader that joins them, so
`app.assets.tilemap('map/island.tmx')` works.

## Translations and the player's language

**`Game.new` loads every translation table and picks the player's language**, so
a game writes no i18n setup. It lists every `.yml` under `locales:` with
`AssetManager#glob`, sorted by path, and loads each through the asset manager's
`:locale` loader into [`RGame::Engine::I18n`](toolbox.md#rgameenginei18n--localization).
Two files that define one locale merge in that order, so a key the later file
sets wins. It then sets `I18n.locale` to
`I18n.choose(RGame::Core.preferred_locales)`: the first locale the OS prefers
that a table covers, unshortened, or the default.

`locales:` is relative to `media_root` unless it is absolute. A directory that
does not exist loads nothing, and every key then shows as itself.

```ruby
game = MyGame.new(root: Root.new, media_root: 'media')   # loads media/locales/**/*.yml
RGame::Engine::I18n.locale = saved_language if saved_language
game.start
```

A language the player chose and the game saved belongs between `new` and
`start`, as above: `new` has already chosen from the OS by then. Loading the same
file again through `assets.locale(path)` returns the cached result and parses
nothing.

## Reaching the game from a node

A node anywhere in the tree reaches the asset manager through the root's
context. No constructor has to pass it along:

```ruby
sheet = node.context.assets.sheet('player.json')   # node.context is node.root.context
```

A component reaches the same object as `context`.

## Input

`input_map:` names a game's actions in terms of physical ids from
[`RGame::Util::Controls`](input.md):

```ruby
require 'rgame/game'

Controls = RGame::Util::Controls

class Root < RGame::Engine::Node2D; end

RGame::Game.new(
  root: Root.new,
  input_map: RGame::Engine::InputMap.new(
    move_x: { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT],  # -1.0 .. 1.0
              stick: Controls::AXIS_LEFT_X },
    fire:   { buttons: [Controls::KEY_SPACE, Controls::PAD_A] } # held / pressed / released
  )
).start
```

Without it, `Game` uses [`InputMap.default`](input.md). The default binds
eight-way `move_x` / `move_y` to the arrows, WASD, the d-pad and the left stick,
and adds `fire`. Every map merges over the universal UI set, so `ui_confirm` and
`ui_cancel` work without a declaration.

`device:` picks the device that drives player one. It defaults to the keyboard;
pass `Controls.gamepad(slot)` for a controller.

`players:` sets how many seats the game has (default 1). Extra seats start
empty. A seat fills when someone picks up a controller and presses confirm. An
empty seat draws no viewport, so one person playing a two-seat game sees an
ordinary full-screen game. See
[Players, seats and joining](input.md#players-seats-and-joining).

A scene reads the resulting snapshot in `on_control(actions)`, with calls like
`actions.axis(:move_x)` and `actions.pressed?(:fire)`. It never sees a key.

**`Game` polls input once per simulation tick**, not once per rendered frame.
Edge queries depend on this. `pressed?` means "held now, not held at the previous
poll", so the poll rate decides what a press *is*. Polling per frame would let a
fast-rendering loop consume a press between two ticks. Menus would then ignore
input, but only on fast machines.

Polling per tick costs nothing and loses nothing. The C layer snapshots the
keyboard once per frame, so every tick inside one frame reads identical state.
The edge lands on the first tick. One press gives one `pressed?`.

## Subclassing it

`Game` is an [`App`](app.md), so a subclass can override any `App` hook. The
engine owns the loop, the fixed timestep and the catch-up cap. A subclass adds
behaviour around the tree; it does not replace the shell.

```ruby
require 'rgame/game'

class MyGame < RGame::Game
  def button_down(id)
    super                      # keeps F1 and F2 working
    @paused = !@paused if id == RGame::Util::Controls::KEY_SPACE
  end
end
```
