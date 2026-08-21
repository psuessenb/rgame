# UI

A menu you navigate with a keyboard or a controller, and the region one player's
UI lives in.

**There is no pointer**, deliberately — `RGame::Core::Input` has no mouse and the
id range one would occupy is left unused. So there is no hover, and the thing a
mouse-driven control takes from the cursor being over it, a control here takes
from being the **focused** one. That is the whole design; the rest follows.

## A player's own screen

`RGame::Engine::PlayerLayer` is the region. Its subtree is drawn once, clipped
to that player's viewport, translated to its corner, and driven by their
controller:

```ruby
layer = scene.add_node(RGame::Engine::PlayerLayer.new(player: game.players[1]))
layer.add_node(inventory)
```

See [Scene graph](scene_graph.md#a-players-own-screen) for what it does and how
it decides there is nothing to draw.

## `RGame::Engine::UI::Menu`

A vertical list of things to choose from.

```ruby
menu = layer.add_node(RGame::Engine::UI::Menu.new(item_width: 220, item_height: 44))
menu.add_item('Resume').on_activated { close }
menu.add_item('Save').on_activated   { save }
menu.add_item('Quit', enabled: false)
```

| | |
|---|---|
| `ui_up` / `ui_down` | move focus, wrapping at the ends |
| `ui_confirm` | activate the focused item |
| `add_item(label, enabled: true)` | append an item and return it |
| `items`, `focused`, `focused_index` | what it holds and where focus is |
| `focus(index)`, `focus_by(delta)` | move focus directly |

Those three actions come from the [universal set](input.md#the-universal-ui-set)
that every `InputMap` is merged over, so a menu works without a game declaring
anything.

### Focus is per player, and it costs nothing

A menu inside a `PlayerLayer` inherits that player as its `input_owner`, and
ownership is inherited down the tree — so the `actions` its `on_control`
receives are already that player's. **Two players with a menu open at once are
independent, and neither menu mentions players at all.**

That is not a feature of the menu; it is [ownership
routing](scene_graph.md#who-a-node-answers-to) doing its job one layer down.

### `RGame::Engine::UI::MenuItem`

One entry: a label on a nine-slice, and an `on_activated` signal. It draws
itself from its **state**, which is why the shipped atlas has an element for
each:

| State | Element |
|---|---|
| focused | `button_focus` |
| focused, confirm held | `button_pressed` |
| not focused | `button_idle` |
| `enabled: false` | `button_disabled` |

A disabled item is skipped by focus movement and cannot be activated by any
route, so a caller never has to check first.

The element names are `MenuItem::STYLE`, and a menu can be built with a
different hash — a game with its own art is not obliged to name it the way the
shipped atlas does.

### Getting the art on screen

Nine-slice ids name an *element of an atlas*, not a file, so there is nothing
for the asset manager to resolve on demand. Register the atlas once:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui/ui_atlas.json'))
```

`media/ui/ui_atlas.json` ships with `panel` and the four button elements above.
See [Sheets, atlases and maps](assets.md).

## What this is not

It is a menu, not a widget library. Items are stacked vertically at a fixed
size, and that is the whole of its layout — no nesting, no scrolling lists, no
text entry, and no general answer to how UI should be laid out.

The package this replaces positioned everything absolutely and hit-tested a
mouse cursor. It was deleted with the mouse, none of it is a reference, and its
API is deliberately not preserved.
