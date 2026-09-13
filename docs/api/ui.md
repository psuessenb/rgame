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

Buttons to choose from, one of them focused.

```ruby
UI = RGame::Engine::UI

column = UI::Column.new(item_width: 220, item_height: 44)
menu = layer.add_node(UI::Menu.new(layout: column))
menu.add(UI::PanelButton.new(label: 'Resume')).on_activated { close }
menu.add(UI::PanelButton.new(label: 'Save')).on_activated   { save }
menu.add(UI::PanelButton.new(label: 'Quit', enabled: false))
```

**The menu holds buttons; it never builds them.** What a button looks like is
the button's — any [`UI::Button`](#rgameengineuibutton) subclass goes in through
`add`, shipped or written by the game, and one menu may mix them.

A list and a radial wheel are the same class. What differs between them is
**where the buttons sit** and **how input moves focus**, and a menu is built
with one of each:

| | Answers | Shipped |
|---|---|---|
| `layout:` | where each button goes, and its size | [`Column`](#layouts-column-and-ring), [`Ring`](#layouts-column-and-ring) |
| `navigation:` | which button this frame's input focuses | [`Stepping`](#stepping) (the default), [`Pointing`](#pointing) |

```ruby
ring = UI::Ring.new(radius: 120, item_width: 96, item_height: 30)
wheel = layer.add_node(UI::Menu.new(x: 320, y: 240, layout: ring, navigation: UI::Pointing.new))
wheel.add(UI::PanelButton.new(label: 'Sword')).on_activated { equip(:sword) }
wheel.add(UI::PanelButton.new(label: 'Bow')).on_activated   { equip(:bow) }
```

What the menu keeps is what is the same for every combination:

| | |
|---|---|
| `ui_confirm` | press the focused button on the way down, release it on the way up — see [When a press activates](#when-a-press-activates) |
| `add(button)` | append a button, re-arrange them all, and return it; `TypeError` for anything that is not a `UI::Button` |
| `buttons`, `focused`, `focused_index` | what it holds and what is focused — `nil` when nothing is |
| `focus(index)` | focus a button directly, or nothing with `nil`; only buttons whose focus changes are told |
| `layout`, `navigation` | the two parts it was built with |
| `bounds_x`, `bounds_y`, `bounds_width`, `bounds_height` | the rectangle enclosing every button, relative to the menu, as its layout reports it — all zero while empty |

The actions come from the [universal set](input.md#the-universal-ui-set) that
every `InputMap` is merged over, so a menu works without a game declaring
anything.

**Confirming is the menu's, not the navigation's.** A navigation only says which
button is focused, so a new one cannot forget to activate it, and every
combination of layout and navigation confirms the same way.

### Layouts: `Column` and `Ring`

| | Places buttons | Built with |
|---|---|---|
| `Column` | downwards from the menu's origin | `item_width:`, `item_height:`, `spacing: 8` |
| `Ring` | round a circle **centred on** the menu's origin, the first straight up, then clockwise | `radius:`, `item_width:`, `item_height:` |

A layout is anything answering two methods, both relative to the menu:

- `arrange(buttons)` sets each button's `x`, `y`, `width` and `height`;
- `bounds(buttons)` returns `[x, y, width, height]`, the rectangle enclosing
  them — `[0, 0, 0, 0]` for none.

The menu calls both after every `add`, which is how a ring re-spaces itself as
it grows, and copies the bounds into its own readers, so a backdrop drawn from
them allocates nothing. A layout keeps no state about a menu, so one instance
may serve several.

`Column`'s bounds are the stacked slots, exactly. `Ring`'s are the square round
the whole circle of slots, `2 * radius + item_width` wide and
`2 * radius + item_height` tall, whatever the count — so a backdrop behind a
wheel does not change size as buttons are added.

### `Stepping`

Focus moves one button at a time, in the order they were added. The default.

| | |
|---|---|
| `ui_up` / `ui_down` | move focus, skipping disabled buttons, wrapping at the ends |
| `ui_left` / `ui_right` | `adjust` the focused row |
| `step(delta)` | move focus as `ui_down` would, `delta` times |

Focus starts on the first enabled button and is never empty while the menu has
one.

**Vertical belongs to the navigation, horizontal to the focused row.** It does
not know what kind of button it is talking to — it calls `adjust` and a plain
button answers `nil`. That is what makes an `OptionButton` work, and why a settings menu
wants `Stepping`.

### `Pointing`

Focus is the button a stick points at — with a `Ring`, a radial menu.

| | |
|---|---|
| `ui_radial_x` / `ui_radial_y` | the direction; focuses the button nearest to it by angle |
| `dead_zone` | the shortest deflection that selects, on the combined vector (default 0.5) |
| `index_at(x, y)` | the index a vector points at, or `nil` inside the dead zone |
| `aim_x`, `aim_y` | the last direction read, for a game drawing a pointer |

**The direction is the selection.** There is no "next". Each button's centre, seen
from the menu's origin, is a direction, and whichever is closest to the stick's
is focused. On a ring that cuts the circle into one sector per button, centred on
it — and because the angles come from where the buttons actually are, no layout
can disagree with it. Eight buttons on a ring line up with the eight directions
the arrow keys make, so a keyboard works too.

**Below the dead zone nothing is focused**, and a confirm then activates nothing.
A stick springs back through the middle when it is let go of, so a wheel that
kept its last selection would hand a player who releases the stick and presses A
whatever the stick passed on its way home.

That dead zone is measured on the combined vector *after* `ActionMapper`'s own
per-axis one (0.15) is taken off and the rest rescaled. The two do different
jobs: the per-axis one stops a worn stick drifting, and is far too small to
decide that a player means a direction.

**A disabled button is never focused**, so pointing at one selects nothing. Left
and right are directions here, so an `OptionButton` under `Pointing` cannot be
adjusted.

Nothing about a wheel is drawn by the menu: a backdrop or a pointer is the
game's, and `aim_x` / `aim_y` are what that pointer reads. `examples/radial_menu`
draws both.

### A navigation of your own

Subclass `RGame::Engine::UI::Navigation` and override its two hooks:

```ruby
class FirstEnabled < RGame::Engine::UI::Navigation
  def on_control(_actions) = menu.focus(menu.buttons.index(&:enabled?))
end
```

| Hook | Called |
|---|---|
| `on_control(actions)` | every frame, before the menu handles `ui_confirm` |
| `on_buttons_changed` | after a button is added |

`menu` is the menu it drives. **A navigation drives exactly one menu** —
`Pointing` keeps the last direction it read — so handing one instance to a second
menu raises `ArgumentError` rather than letting two menus share a pointer. The
constructor default builds a fresh `Stepping` for every menu.

### Focus is per player, and it costs nothing

A menu inside a `PlayerLayer` inherits that player as its `input_owner`, and
ownership is inherited down the tree — so the `actions` its `on_control`
receives are already that player's. **Two players with a menu open at once are
independent, and neither menu mentions players at all.**

That is not a feature of the menu; it is [ownership
routing](scene_graph.md#who-a-node-answers-to) doing its job one layer down.

### `RGame::Engine::UI::Button`

What every button is: its state, its label, and an `on_activated` signal — and
no look. A subclass supplies the look in `on_draw`, reading `state`:

| `state` | When |
|---|---|
| `:disabled` | `enabled: false`, whatever else is true |
| `:pressed` | a press is held on it, or its pressed feedback is still running |
| `:focused` | the menu's navigation focused it |
| `:idle` | none of those |

| | |
|---|---|
| `label`, `enabled`, `enabled?` | optional — an image-only button still has somewhere to keep a name |
| `focused?`, `pressed?`, `state` | read by `on_draw` |
| `activate_on` | `:release` (the default) or `:press`; anything else raises `ArgumentError` |
| `activate` | fire `on_activated` and return the button, or `nil` when disabled |
| `adjust(delta)` | what horizontal input does to it under `Stepping`; `nil` — nothing to change |
| `on_focus_changed(focused)` | hook, called only when focus actually changes |

`focused=`, `press`, `release` and `cancel_press` are the menu's side of the
same interface. A disabled button is skipped by focus movement and cannot be
activated by any route, so a caller never has to check first.

#### A button of your own

Subclass it and draw. Focus, pressing, activation and placement are all
inherited, so the class is only its look:

```ruby
class TextButton < RGame::Engine::UI::Button
  COLORS = {
    idle: [200, 200, 200], focused: [255, 255, 255],
    pressed: [255, 220, 120], disabled: [110, 110, 110]
  }.freeze

  def on_draw(renderer, _view)
    color = COLORS.fetch(state)
    renderer.rect(0, 0, 4, height, color: color) unless state == :idle
    renderer.text(label, 12, (height - renderer.text_height) / 2, color: color)
  end
end

menu.add(TextButton.new(label: 'Continue')).on_activated { resume }
```

A `Button` with no `on_draw` draws nothing, which is also what an invisible slot
legitimately wants.

#### When a press activates

`ui_confirm` reaches the focused button as a press and a release, and
`activate_on:` decides which one activates:

| | `activate_on: :release` (default) | `activate_on: :press` |
|---|---|---|
| activates | when confirm is let go, if focus did not move while held | as confirm goes down |
| drawn pressed | while held | at least `Button::PRESS_FEEDBACK` (0.1 s), or while held if longer |

A settings menu keeps the default: holding confirm shows the press, and
moving away before letting go cancels it. `:press` is for buttons that should
answer instantly, like a skill bar. The feedback counts down in `update(dt)`, so
a paused button keeps it and a spec advances it by passing seconds.

**A button acts only on a press it saw start.** Two rules make that hold:

- **A menu takes no press until it has seen `ui_confirm` up.** A submenu added
  from `on_activated` is controlled later in the same tick, while the key that
  opened it is still down; without this it would read that press again and
  activate its own focused button with it.
- **A press whose release the button never saw is dropped**, feedback and all,
  activating nothing. A menu that closes itself from `on_activated` stops being
  controlled, so it never sees the key come up; the next time it is controlled
  it finds the key up with no release edge, and lets go. It does not reopen
  pressed.

What neither rule can see is a pause that starts *after* the release was seen.
A `:press` button closed within `PRESS_FEEDBACK` of being let go keeps the rest
of its feedback, and shows it when reopened. A menu covered by a pushed scene is
not controlled either, so it keeps drawing whatever state it was in when it was
covered.

### `RGame::Engine::UI::PanelButton`

The shipped button: a label centred on a nine-slice, one element per state,
which is why the shipped atlas has an element for each:

| `state` | Element |
|---|---|
| `:focused` | `button_focus` |
| `:pressed` | `button_pressed` |
| `:idle` | `button_idle` |
| `:disabled` | `button_disabled` |

The element names are `PanelButton::STYLE`, and a button can be built with a
different hash through `style:` — a game with its own art is not obliged to name
it the way the shipped atlas does. `label:` is required here, because it is
drawn.

### `RGame::Engine::UI::OptionButton`

A row whose value is chosen from a list. It draws `Label   < value >`, and the
chevrons appear only where there is somewhere to go, which is the only feedback
a player gets that they have reached an end.

```ruby
volume = menu.add(RGame::Engine::UI::OptionButton.new(label: 'Volume', values: [0, 25, 50, 75, 100],
                                                      display: ->(percent) { "#{percent}%" }))
volume.on_changed { |value| game.audio.volume = value / 100.0 }
```

| | |
|---|---|
| `values`, `index`, `value`, `caption` | the list, where it sits, and what is drawn |
| `value = something` | select by value; a value the list does not offer is ignored |
| `adjust(delta)` | move the selection, clamped; the button if it moved, `nil` if not |
| `on_changed` | emits the new value, and only when it actually changed |

It is a `PanelButton`, so focus, the four state elements and `enabled: false`
all work exactly as they do on any other row.

**Values clamp while focus wraps.** A list of menu buttons has no magnitude, so
joining its ends only makes a short list quicker to get around. A list of values
usually does have one, and wrapping would turn "one louder" at the top of a
volume range into silence.

**`display` runs once per value, when the row is built.** It turns a value into
the text drawn for it, so the values themselves stay whatever the game acts on.
Doing it at draw time would allocate a String every frame for every row on
screen — see [Drawing](drawing.md) and `Game/NoInterpolationInHotPath`.

`value=` ignoring a value the list does not offer is for restoring a setting
from a file: a save written by an older version of the game, or edited by hand,
leaves the row where it is instead of raising.

### Getting the art on screen

Nine-slice ids name an *element of an atlas*, not a file, so there is nothing
for the asset manager to resolve on demand. Register the atlas once:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui/ui_atlas.json'))
```

`media/ui/ui_atlas.json` ships with `panel` and the four button elements above.
See [Sheets, atlases and maps](assets.md).

`examples/game_menu` is the smallest complete use of all of this: a menu that
opens over a running world, pauses only the node that opened it, and closes
again. `examples/menu_navigation` is the next step up — a title screen, a
settings screen pushed over it, and rows that change fullscreen, the scale mode
and the volume for real and write them to a file. `examples/radial_menu` is the
same menu built with a `Ring` and `Pointing`.

## What this is not

It is a menu, not a widget library. Every button is the same size and placed by a
column or a ring, and that is the whole of its layout — no grid, no nesting, no
scrolling lists, and no general answer to how UI should be laid out. There is no text entry, and no
continuous control: `OptionButton` covers a setting with a handful of values, and
anything wanting a free-moving slider needs a control that does not exist yet.

The package this replaces positioned everything absolutely and hit-tested a
mouse cursor. It was deleted with the mouse, none of it is a reference, and its
API is deliberately not preserved.
