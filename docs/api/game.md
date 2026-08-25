# `RGame::Game`

The entry point of a game, and the one class that knows both halves of the
engine.

```ruby
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rgame/game'

class HelloScene < RGame::Engine::Node2D
  def on_draw(renderer, _view) = renderer.text('Hello world!', 250, 200)
end

RGame::Game.new(root: HelloScene.new, caption: 'Hello').start
```

A complete game is a root node plus that. `Game` assembles what a running game
needs around it — the window and its loop, the renderer, the asset manager, the
sound device, the input mapper, the debug overlay — and drives the root node.

```ruby
RGame::Game.new(root:, width: 640, height: 480, caption: 'RGame',
                media_root: 'media', input_map: nil, device: Controls::KEYBOARD)
```

| Reader | |
|---|---|
| `root` | the node tree |
| `renderer` | what scenes draw through |
| `players` | who is playing: their devices, bindings and cameras |
| `assets`, `audio`, `media_root`, `width`, `height`, `fps` | inherited from [App](app.md) |

`start` brings the tree live — it hands the game to the root as its `context`,
calls `enter_tree`, and runs the loop until the window closes. `F1` toggles the
debug overlay and `F2` quits.

**Both development keys are function keys, and `Esc` is deliberately left
alone.** Escape is the button a player expects to back out of a menu, so it
belongs to the game rather than to the engine's debug shortcuts — binding it
here would take it away from every game built on this one.

## Why this class exists at all

`RGame::Engine` holds game concepts and may not name
`RGame::Core`; `RGame::Core` owns windows, textures and sound devices and may
not know Engine exists. Two RuboCop cops enforce that. Something still has to
introduce them, and **this is that something** — keeping the introduction in one
file is what makes the rule checkable everywhere else.

The tile map is the clearest case: parsing a `.tmx` is Engine's job, drawing one
is Core's, and neither may call the other. So `Game` installs the loader that
joins them, and `app.assets.tilemap('map/island.tmx')` works from then on.

## Reaching the game from a node

A node deep in the tree gets at the asset manager through the root's context,
so nothing has to be threaded through constructors:

```ruby
sheet = node.root.context.assets.sheet('player.json')
```

## Input

`input_map:` names the actions a game has, in terms of physical ids from
[`RGame::Util::Controls`](input.md):

```ruby
Controls = RGame::Util::Controls

RGame::Game.new(
  root: Root.new,
  input_map: RGame::Engine::InputMap.new(
    move_x: { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT],  # -1.0 .. 1.0
              stick: Controls::AXIS_LEFT_X },
    fire:   { buttons: [Controls::KEY_SPACE, Controls::PAD_A] } # held / pressed / released
  )
)
```

Pass nothing and you get [`InputMap.default`](input.md): eight-way `move_x` /
`move_y` on the arrows or the left stick, plus `fire`. Either way the map is
merged over the universal UI set, so `ui_confirm` and `ui_cancel` work without
being declared.

`device:` picks what drives player one — the keyboard by default, or
`Controls.gamepad(slot)` for a controller.

`players:` is how many seats the game has (default 1). Extra seats start empty
and fill when somebody picks up a controller and presses confirm; an empty seat
draws no viewport, so a two-seat game played by one person is an ordinary
full-screen game. See [Players, seats and joining](input.md#players-seats-and-joining).

A scene reads the resulting snapshot in `on_control(actions)` — `actions.axis(:move_x)`,
`actions.pressed?(:fire)` — and never sees a key.

**Input is polled once per simulation tick**, not once per rendered frame. That
matters for edge queries: `pressed?` means "held now, not held at the previous
poll", so whatever polls decides what a press *is*. A loop that renders faster
than it simulates would otherwise consume the press between two ticks, and
menus would stop responding on fast machines only.

Polling per tick costs nothing and loses nothing, because the C layer snapshots
the keyboard once per frame: several ticks inside one frame read identical
state, and the edge lands on the first of them. One press, one `pressed?`.

## Subclassing it

`Game` is an [`App`](app.md), so anything an App can override it can too. The
loop, the fixed timestep and the catch-up cap are the engine's; a subclass adds
behaviour around the tree rather than replacing the shell.

```ruby
class MyGame < RGame::Game
  def button_down(id)
    super                      # keeps F1 and F2 working
    @paused = !@paused if id == RGame::Util::Controls::KEY_SPACE
  end
end
```
