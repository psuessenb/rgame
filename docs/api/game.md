# `RGame::Game`

The entry point of a game, and the one class that knows both halves of the
engine.

```ruby
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'rgame/game'

class HelloScene < Engine::Node2D
  def on_draw(renderer) = renderer.text('Hello world!', 250, 200)
end

RGame::Game.new(root: HelloScene.new, caption: 'Hello').start
```

A complete game is a root node plus that. `Game` assembles what a running game
needs around it — the window and its loop, the renderer, the asset manager, the
sound device, the input mapper, the debug overlay — and drives the root node.

```ruby
RGame::Game.new(root:, width: 640, height: 480, caption: 'RGame',
                media_root: 'media', action_map: {})
```

| Reader | |
|---|---|
| `root` | the node tree |
| `renderer` | what scenes draw through |
| `action_mapper` | physical input → named actions |
| `assets`, `audio`, `media_root`, `width`, `height`, `fps` | inherited from [App](app.md) |

`start` brings the tree live — it hands the game to the root as its `context`,
calls `enter_tree`, and runs the loop until the window closes. `Esc` quits and
`F1` toggles the debug overlay.

## Why this class exists at all

[`RGame::Engine`](../../lib/engine) holds game concepts and may not name
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

`action_map` names the actions a game has, in terms of the physical ids
[Input](input.md) knows:

```ruby
RGame::Game.new(
  root: Root.new,
  action_map: {
    move_x: { axis: %i[left right] },   # -1.0 .. 1.0
    fire:   { button: %i[fire] }        # held / pressed / released
  }
)
```

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
    super                      # keeps Esc and F1 working
    @paused = !@paused if id == RGame::Util::Controls::KEY_SPACE
  end
end
```
