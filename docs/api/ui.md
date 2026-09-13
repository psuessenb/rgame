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
| `layout:` | where each button goes, its size, and the [bounds](#layouts-column-row-and-ring) of them all | [`Column`](#layouts-column-row-and-ring), [`Row`](#layouts-column-row-and-ring), [`Ring`](#layouts-column-row-and-ring) |
| `navigation:` | which button this frame's input focuses | [`Stepping`](#stepping) (the default), [`Pointing`](#pointing), or [`nil`](#a-menu-with-no-navigation) |

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
| each button's `hotkey` | press that button, focused or not — see [Hotkeys](#hotkeys) |
| `add(button)` | append a button, re-arrange them all, and return it; `TypeError` for anything that is not a `UI::Button` |
| `buttons`, `focused`, `focused_index` | what it holds and what is focused — `nil` when nothing is |
| `focus(index)` | focus a button directly, or nothing with `nil`; only buttons whose focus changes are told |
| `layout`, `navigation` | the two parts it was built with |
| `open?`, `open`, `close` | whether it is shown and takes input — see [Open and closed](#open-and-closed) |
| `trigger:`, `trigger` | an action that holds the menu open — see [A menu held open by an action](#a-menu-held-open-by-an-action) |
| `on_opened`, `on_closed` | signals; `on_closed` passes the button a trigger's release activated, or `nil` |
| `bounds_x`, `bounds_y`, `bounds_width`, `bounds_height` | the rectangle enclosing every button, relative to the menu, as its layout reports it — all zero while empty |

The actions come from the [universal set](input.md#the-universal-ui-set) that
every `InputMap` is merged over, so a menu works without a game declaring
anything.

**Confirming is the menu's, not the navigation's.** A navigation only says which
button is focused, so a new one cannot forget to activate it, and every
combination of layout and navigation confirms the same way. Each frame the menu
runs its navigation, then every hotkey, then confirm — or, on a menu with a
trigger, the trigger's press first and its release last.

### Layouts: `Column`, `Row` and `Ring`

| | Places buttons | `axis` | Built with |
|---|---|---|---|
| `Column` | downwards from the menu's origin | `:vertical` | `item_width:`, `item_height:`, `spacing: 8` |
| `Row` | rightwards from the menu's origin | `:horizontal` | `item_width:`, `item_height:`, `spacing: 8` |
| `Ring` | round a circle **centred on** the menu's origin, the first straight up, then clockwise | `:vertical` | `radius:`, `item_width:`, `item_height:` |

```ruby
bar = layer.add_node(UI::Menu.new(layout: UI::Row.new(item_width: 64, item_height: 64)))
```

`Column` and `Row` are one `UI::Stack` with its `axis:` fixed, because they are
the same computation with x and y swapped. Neither takes `axis:` — a column that
is not vertical is a row — so passing one is an unknown keyword rather than
something quietly ignored. `Stack.new(axis:, item_width:, item_height:,
spacing: 8)` takes either axis in `Stack::AXES` and raises `ArgumentError` for
anything else.

A layout is anything answering three methods, the first two relative to the
menu:

- `arrange(buttons)` sets each button's `x`, `y`, `width` and `height`;
- `bounds(buttons)` returns `[x, y, width, height]`, the rectangle enclosing
  them — `[0, 0, 0, 0]` for none;
- `axis` is `:vertical` or `:horizontal`, the direction [`Stepping`](#stepping)
  moves focus along unless it is told otherwise. A layout of a game's own that
  does not answer it raises `NoMethodError` when a menu is built with it and the
  default navigation, and works with an explicit `Stepping.new(axis:)` or any
  other navigation.

The menu calls both after every `add`, which is how a ring re-spaces itself as
it grows, and copies the bounds into its own readers, so a backdrop drawn from
them allocates nothing. A layout keeps no state about a menu, so one instance
may serve several.

`Column`'s and `Row`'s bounds are their slots, exactly. `Ring`'s are the square round
the whole circle of slots, `2 * radius + item_width` wide and
`2 * radius + item_height` tall, whatever the count — so a backdrop behind a
wheel does not change size as buttons are added.

### `Stepping`

Focus moves one button at a time, in the order they were added, along an axis.
The default.

| | Vertical axis | Horizontal axis |
|---|---|---|
| move focus, skipping disabled buttons, wrapping at the ends | `ui_up` / `ui_down` | `ui_left` / `ui_right` |
| `adjust` the focused button | `ui_left` / `ui_right` | `ui_up` / `ui_down` |

| | |
|---|---|
| `Stepping.new(axis: nil)` | `nil` takes the layout's `axis`; `:vertical` or `:horizontal` overrides it |
| `axis` | the axis in use — resolved when the menu is built |
| `step(delta)` | move focus forwards along the axis, `delta` times |

**The axis follows the layout**, so `Menu.new(layout: UI::Row.new(...))` steps
with left and right with nothing else said. An axis the navigation had to be told
separately would be a row stepped by up and down the day somebody forgot it. An
axis outside `Stack::AXES` raises `ArgumentError` when the menu is built.

Focus starts on the first enabled button and is never empty while the menu has
one.

**The axis belongs to the navigation, the other pair to the focused button.** It
does not know what kind of button it is talking to — it calls `adjust` and a
plain button answers `nil`. That is what makes an `OptionButton` work, and why a
settings menu wants `Stepping`.

### `Pointing`

Focus is the button a stick points at — with a `Ring`, a radial menu.

| | |
|---|---|
| `ui_radial_x` / `ui_radial_y` | the direction; focuses the button nearest to it by angle |
| `dead_zone` | the shortest deflection that selects, on the combined vector (default 0.5) |
| `grace` | how long focus survives the stick entering the dead zone, in seconds — see below |
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

**A grace window delays that, on a wheel chosen by letting go.** `grace:` keeps
focus for that many seconds after the stick enters the dead zone, counted in
`update(dt)`, and then clears it. Left out, it is `Pointing::GRACE` (0.15 s) on
a menu with a [trigger](#a-menu-held-open-by-an-action) and 0 on any other, so an
always-open wheel behaves as described above and a held one gets the window
without asking. The stick leaving the dead zone starts a fresh window; pointing
at a disabled button still clears focus at once.

**A disabled button is never focused**, so pointing at one selects nothing. Left
and right are directions here, so an `OptionButton` under `Pointing` cannot be
adjusted.

A plain `Menu` draws nothing of a wheel; [`RadialMenu`](#rgameengineuiradialmenu)
draws the backdrop, the dead zone and a pointer from `aim_x` / `aim_y`, and a
wheel of a game's own reads the same two.

### A navigation of your own

Subclass `RGame::Engine::UI::Navigation` and override its two hooks:

```ruby
class FirstEnabled < RGame::Engine::UI::Navigation
  def on_control(_actions) = menu.focus(menu.buttons.index(&:enabled?))
end
```

| Hook | Called |
|---|---|
| `on_control(actions)` | every frame the menu is open, before the menu handles `ui_confirm` |
| `on_buttons_changed` | after a button is added |
| `update(dt)` | every update while the menu is not paused — where a navigation counts time |
| `on_opened` | when the menu opens; `Pointing` forgets its aim and focus here |

`menu` is the menu it drives. **A navigation drives exactly one menu** —
`Pointing` keeps the last direction it read — so handing one instance to a second
menu raises `ArgumentError` rather than letting two menus share a pointer. The
constructor default builds a fresh `Stepping` for every menu.

### A menu with no navigation

`navigation: nil` says input never moves focus:

```ruby
bar = layer.add_node(UI::Menu.new(layout: UI::Row.new(item_width: 48, item_height: 48), navigation: nil))
bar.add(UI::IconButton.new(image: :potion, hotkey: :skill1)).on_activated { drink }
```

Nothing is focused when a button is added, and nothing focuses one afterwards, so
`ui_confirm` has nothing to act on and [hotkeys](#hotkeys) are the only way in —
the action bar of a game played on hotkeys alone. Leaving the keyword out is a
`Stepping`, so `nil` is always something the caller said, never a forgotten
argument. A game that calls `focus` on such a menu has said something too, and
confirm acts on the button it focused.

### Open and closed

A menu is open or closed. **A closed menu draws nothing** — neither its own
backdrop nor its buttons — and its navigation, hotkeys and confirm do nothing.
A menu without a trigger starts open, and a pause menu is built once and toggled:

```ruby
class PauseMenu < RGame::Engine::Node2D
  UI = RGame::Engine::UI

  def on_add
    @menu = add_node(UI::PanelMenu.new(x: 56, y: 56, layout: UI::Column.new(item_width: 180, item_height: 34)))
    @menu.add(UI::PanelButton.new(label: 'Resume')).on_activated { @menu.close }
    @menu.close
  end

  def on_control(actions)
    return unless actions.pressed?(:ui_cancel)

    @menu.open? ? @menu.close : @menu.open
  end
end
```

`open` and `close` do nothing when the menu is already that way, and each emits
`on_opened` or `on_closed` (with `nil`) only on a change. Opening calls the
navigation's `on_opened`; focus under `Stepping` stays where it was.

**Closed is not paused.** A closed menu still gets `control` and `update`, which
is what lets a trigger reopen it, and a button's pressed feedback runs out while
it is shut instead of being there when it reappears. Pausing a menu's node still
stops everything, as for any node. What the rest of the game does while a menu is
open — pausing the hero, dimming the world — is the game's, from the two signals
or from wherever it calls `open`.

### A menu held open by an action

The console quick menu: hold a button to open a wheel, point, and let go to
choose.

```ruby
UI = RGame::Engine::UI

input_map = RGame::Engine::InputMap.default.merge(
  quick_menu: { buttons: [RGame::Util::Controls::KEY_TAB, RGame::Util::Controls::PAD_LEFT_SHOULDER] }
)

wheel = layer.add_node(UI::RadialMenu.new(x: 320, y: 240, radius: 150, button_width: 64, trigger: :quick_menu))
disc = UI::ShapeStyle.new(shape: :disc)
wheel.add(UI::IconButton.new(image: :home, style: disc)).on_activated { go_home }
wheel.on_opened { world.time_scale = 0.25 }
wheel.on_closed { |_chosen| world.time_scale = 1.0 }
```

`trigger:` names an action, and with one:

| When | The menu |
|---|---|
| built | is closed |
| the trigger goes down | opens, and the navigation forgets the last opening |
| it is held | moves focus as its navigation says; hotkeys work |
| it comes up | activates the focused button, if any, and closes; `on_closed` passes that button, or `nil` |
| `ui_confirm` is pressed | nothing — letting go is the only way to choose |

**A release with nothing focused chooses nothing**, not the last button the
stick passed. That is how a player changes their mind: centre the stick and let
go. Because a stick is back in the middle a frame or two before a shoulder
button comes up, a `Pointing` on a menu with a trigger keeps focus for its
[grace window](#pointing) first — without it, letting go of both at once would
nearly always choose nothing.

**Only a press it saw start opens it**, as with every other press: a trigger
already down when the menu appears opens nothing until it is let go and pressed
again. A trigger that comes up while the menu is paused closes it without
choosing.

**`open` raises on a menu with a trigger**; a menu opened by hand would wait for
the release of a press it never saw. `close` works, and is the cancel for a
player who is hit while holding the wheel: the release that follows neither
chooses nor reopens.

The trigger works under every navigation. With `navigation: nil`, the release
activates whatever the game focused, typically in `on_opened`.

The release activates the button with `activate`, not with pressed feedback: the
menu closes on that frame, so nothing would show it.

One limit: a stick that overshoots the middle as it springs back can point at
the opposite button for a frame or two. The grace window only delays the dead
zone and does not cover that.

### Focus is per player, and it costs nothing

A menu inside a `PlayerLayer` inherits that player as its `input_owner`, and
ownership is inherited down the tree — so the `actions` its `on_control`
receives are already that player's. **Two players with a menu open at once are
independent, and neither menu mentions players at all.**

That is not a feature of the menu; it is [ownership
routing](scene_graph.md#who-a-node-answers-to) doing its job one layer down.

### `RGame::Engine::UI::PanelMenu`

A `Menu` that draws its own backdrop: one nine-slice round its buttons, grown by
`padding` on every side.

```ruby
UI = RGame::Engine::UI

column = UI::Column.new(item_width: 180, item_height: 34)
menu = layer.add_node(UI::PanelMenu.new(x: 56, y: 56, layout: column))
menu.add(UI::PanelButton.new(label: 'Resume')).on_activated { close }
menu.add(UI::PanelButton.new(label: 'Quit')).on_activated   { quit }
```

| | |
|---|---|
| `panel:` | the nine-slice id to draw (default `:panel`) |
| `padding:` | how far the panel reaches beyond the bounds on each side (default 16) |

**The panel is sized from the menu's bounds**, which its layout recomputes on
every `add` — so a button added later grows the panel, and nothing has to be kept
equal to the number of buttons.

**The menu's origin is still the layout's.** With a `Column` that is the first
button's top-left corner, and the panel starts `padding` above and to the left of
it: to put a panel's corner at (40, 40), place the menu at (40 + padding,
40 + padding). The buttons are the menu's children, so they draw over the panel
with no `z`.

A backdrop of any other kind is the same shape: subclass `Menu` and draw it in
`on_draw` from `bounds_x`, `bounds_y`, `bounds_width` and `bounds_height`.

### `RGame::Engine::UI::RadialMenu`

A wheel: a `Menu` that builds its own `Ring` and `Pointing`, and draws a backdrop
disc, the dead zone to scale, and a pointer from the centre towards where the
stick aims.

```ruby
UI = RGame::Engine::UI

game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))

wheel = layer.add_node(UI::RadialMenu.new(x: 320, y: 240, radius: 150, button_width: 64))
disc = UI::ShapeStyle.new(shape: :disc)
wheel.add(UI::IconButton.new(image: :home, style: disc)).on_activated { go_home }
wheel.add(UI::IconButton.new(image: :save, style: disc)).on_activated { save }
```

| | |
|---|---|
| `radius:` | from the centre to each button's middle, as `Ring`'s |
| `button_width:`, `button_height:` | the slot size; `button_height` defaults to `button_width` |
| `dead_zone:` | as `Pointing`'s (default `Pointing::DEAD_ZONE`, 0.5) |
| `grace:` | as `Pointing`'s: `Pointing::GRACE` with a `trigger:`, 0 without, unless given |
| `padding:` | how far the backdrop reaches beyond the bounds (default 16) |
| `backdrop:`, `dead_zone_color:`, `pointer:` | a colour for each part, `RadialMenu::BACKDROP`, `DEAD_ZONE` and `POINTER` by default; `nil` omits that part |

**The menu's origin is the centre of the wheel.** The backdrop's radius is half
the larger side of the bounds plus `padding` — and because `Ring`'s bounds are
the whole circle, it is the same with one button as with eight. The dead zone is
drawn at `dead_zone * radius`, which is exactly where a pointer tip inside it
selects nothing. **The pointer's tip is clamped to the ring**: two arrow keys
read as (1, 1), longer than a stick can reach, and would otherwise poke past it.
All three are drawn before the buttons, which are the menu's children.

Every other keyword goes to `Menu`, `trigger:` included — a `RadialMenu` with a
trigger is the [held wheel](#a-menu-held-open-by-an-action).

**`layout:` and `navigation:` raise `ArgumentError`.** A preset forwarding them
would let either silently replace the ring or the pointing it is made of. A ring
stepped through with `Stepping` is a plain `Menu` built with a `Ring`.

Something drawn in the middle of the wheel — the chosen item, say — belongs to
a node added *after* the menu. Between nodes the tree decides what lands on top,
so anything the wheel's parent draws itself sits under the backdrop.
`backdrop_radius` is the disc's radius, for a game sizing something to it.

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
| `hotkey` | an action name that presses this button, focused or not, or `nil` — see [Hotkeys](#hotkeys) |
| `activate` | fire `on_activated` and return the button, or `nil` when disabled |
| `activate_with_feedback` | `activate`, and draw pressed for `PRESS_FEEDBACK` — the instant press, needing nothing held |
| `adjust(delta)` | what horizontal input does to it under `Stepping`; `nil` — nothing to change |
| `on_focus_changed(focused)` | hook, called only when focus actually changes |

`focused=`, `press(source)`, `release(source)` and `cancel_press(source)` are
the menu's side of the same interface; `source` is `:confirm` (the default) or
`:hotkey`. A disabled button is skipped by focus movement and cannot be
activated by any route, so a caller never has to check first.

#### A button of your own

Subclass it and draw. Focus, pressing, activation and placement are all
inherited, so the class is only its look:

```ruby
class EdgeButton < RGame::Engine::UI::Button
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

menu.add(EdgeButton.new(label: 'Continue')).on_activated { resume }
```

A `Button` with no `on_draw` draws nothing, which is also what an invisible slot
legitimately wants.

A look that differs from a shipped button only in what sits behind the label is
not a subclass at all: it is a [style](#styles) handed to a `TextButton`.

- **A `look:` on the menu**, applied to every button in it. One argument would
  restyle a whole menu, but a menu could then never mix an icon button with a
  text button, the look would have to know how to draw every kind of button it
  might meet, and a game's own button would be a look *and* a menu subclass.
- **A factory on the menu**, `add_item(label, class:)`. Every button class takes
  different arguments — an image, a list of values, a style — so the factory
  either grows all of them or forwards them blindly and reports a typo from a
  class the caller never named.
- **A button as a component** on a plain node. A button has a position, a size
  and children that draw over it, and is itself a child of the menu: it is a
  node, and as a component the menu would have to look it up on a sibling.

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

#### Hotkeys

`hotkey:` names an action that presses the button from wherever focus is:

```ruby
controls = RGame::Util::Controls
input_map = RGame::Engine::InputMap.default.merge(
  skill1: { buttons: [controls::KEY_1] },
  skill2: { buttons: [controls::KEY_2] }
)

bar.add(UI::IconButton.new(image: :torch, label: 'Torch', hotkey: :skill1)).on_activated { light }
bar.add(UI::IconButton.new(image: :hammer, label: 'Hammer', hotkey: :skill2)).on_activated { build }
```

| | |
|---|---|
| activates | as the key goes down, **whatever `activate_on:` says** |
| drawn pressed | at least `PRESS_FEEDBACK`, or while held if longer — focused or not |
| its release | activates nothing |
| focus | does not move |

A hotkey is a second way to press a button, not a way to move to it: pressed is
reached by being the focused button while confirm goes down, or by the button's
own key. It follows the same rules as confirm — a menu takes a hotkey's press only
once it has seen that key up since the button was added, so a menu opened by a
hotkey does not fire from the same press, and a press whose release was never
seen is dropped. A disabled button ignores its hotkey. Hotkeys work under every
navigation, and under none.

The action has to be declared in the player's `InputMap`. The menu reads it every
frame, so an undeclared one raises `KeyError`, naming it, on the first frame
rather than doing nothing.

**A press belongs to the source that started it.** The button records whether
confirm or its hotkey is holding it, and while one does, a press from the other
is ignored and its release ends nothing:

- confirm held on a `:release` button, its hotkey pressed and released: nothing
  activates and the button stays pressed; confirm let go: it activates, once;
- a hotkey and confirm going down on the same tick on the focused button: it
  activates once;
- focus moving away: ends a confirm hold, as always, and leaves a hotkey hold
  alone.

### Styles

What sits behind a button's content, per state. A style is anything answering
one method, in the button's local space, and optionally a second:

```ruby
style.draw(renderer, state, width, height)
style.content_color(state)   # optional: the colour content takes on this state's fill, or nil
```

The button holds its style and calls it before drawing its own content; the menu
never sees it. **A style draws at `z: 0` or below**, because the button's label or
icon is drawn at `z: 1` — and shapes default to `z: 50`, so a style that left
its `z` out would cover them.

**What reads on a fill is the style's to say.** A style that answers
`content_color(state)` sets the colour of the button's label or icon in any state
where it returns a colour. `TextButton`, `OptionButton` and `IconButton`'s
picture all follow it, and fall back to their own `label_color:` or `tints:` wherever it
returns `nil`, and for a style without the method. The style is the object that
picks the fill, so it is the only one that can pick what shows up on it. A
`ShapeStyle`'s pressed fill is the same gold as `IconButton`'s pressed tint, so
without this a pressed icon on a disc would vanish. Two styles ship.

`UI::NineSliceStyle` stretches one element of a UI atlas over the slot:

```ruby
style = RGame::Engine::UI::NineSliceStyle.new(idle: :plank, focused: :plank_lit,
                                              pressed: :plank_down, disabled: :plank_grey)
style.with(focused: :plank_glow)   # a copy with one element replaced
```

| | |
|---|---|
| `idle:`, `focused:`, `pressed:`, `disabled:` | the element drawn in each state; all four required |
| `elements` | the four, as a Hash keyed by state |
| `with(**changes)` | a copy with some elements replaced |
| `content_color(state)` | always `nil`: the art is the game's, so the button's own colours are chosen for it — `PanelButton`'s dark label for the shipped atlas |

`UI::ShapeStyle` draws a rectangle or a disc, and needs nothing registered:

```ruby
UI = RGame::Engine::UI

round = UI::ShapeStyle.new(shape: :disc)
flat = UI::ShapeStyle.new(colors: UI::ShapeStyle::COLORS.merge(idle: nil), outline: nil)
```

| | |
|---|---|
| `shape:` | `:rect` (default) or `:disc`; anything else raises `ArgumentError` |
| `colors:` | the fill per state, a `Color` or `[r, g, b]`; `nil` draws no fill in that state; a state missing raises `KeyError` |
| `outline:` | drawn under the fill while focused or pressed; `nil` for none |
| `border:` | how far the fill is inset (default 3) |
| `content:` | the colour content takes over each state's fill, or `nil` for the button's own (default `ShapeStyle::CONTENT`: dark `(46, 34, 24)` while pressed, `nil` otherwise); a state missing raises `KeyError` |

The fill is inset by `border` in every state and the outline is the whole shape
under it, so a button does not change size as its state changes — focus
uncovers the ring the fill leaves. A disc is centred in the slot, as wide as its
shorter side. `UI::ShapeStyle::DEFAULT` is one built with every default, and is
what a `TextButton` draws unless told otherwise.

Both check every state when they are built, not on the first frame a button
reaches it, and coerce their colours then too, so drawing one allocates nothing.

#### A style of your own

```ruby
class Underline
  LIT = RGame::Util::Color.new(255, 255, 255)
  DIM = RGame::Util::Color.new(90, 90, 90)

  def draw(renderer, state, width, height)
    return if state == :idle

    renderer.rect(0, height - 2, width, 2, z: 0, color: state == :disabled ? DIM : LIT)
  end
end

menu.add(RGame::Engine::UI::TextButton.new(label: 'Continue', style: Underline.new))
```

The colours are `Color`s built once rather than `[r, g, b]` literals, which the
renderer would turn into a new `Color` on every draw. `Underline` has no
`content_color`, so the label keeps the button's own colour in every state. A
style that fills behind the label should say what reads on that fill.

### `RGame::Engine::UI::TextButton`

A label centred on a style. It needs no art, which makes it the button to build a
menu with before the art exists:

```ruby
UI = RGame::Engine::UI

menu.add(UI::TextButton.new(label: 'Play')).on_activated { start }
menu.add(UI::TextButton.new(label: 'Credits', style: UI::ShapeStyle.new(shape: :disc)))
menu.add(UI::TextButton.new(label: 'Quit', style: nil))
```

| | |
|---|---|
| `label:` | required, because it is drawn |
| `style:` | a [style](#styles); `UI::ShapeStyle::DEFAULT` unless given, `nil` for the label alone |
| `label_color:`, `disabled_label_color:` | a `Color` or `[r, g, b]`; defaults `TextButton::LABEL_COLOR` and `DISABLED_LABEL_COLOR`; a style's [content colour](#styles) takes precedence in the states it names |

The style draws first and the label over it at `z: 1`. A subclass that draws
more than a label overrides the private `draw_foreground(renderer)` rather than
`on_draw`, so it keeps its style without having to remember to draw it —
`OptionButton` is one.

### `RGame::Engine::UI::PanelButton`

A `TextButton` with a nine-slice style: the shipped atlas's button, with a dark
label. Its style is `PanelButton::STYLE`, which is why the shipped atlas has an
element for each state:

| `state` | Element |
|---|---|
| `:focused` | `button_focus` |
| `:pressed` | `button_pressed` |
| `:idle` | `button_idle` |
| `:disabled` | `button_disabled` |

Everything else is `TextButton`'s, and every default can still be passed — a game
with its own art is not obliged to name it the way the shipped atlas does:

```ruby
UI = RGame::Engine::UI

menu.add(UI::PanelButton.new(label: 'Load', style: UI::PanelButton::STYLE.with(idle: :my_idle)))
```

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

### `RGame::Engine::UI::IconButton`

A picture, tinted by state, with an optional caption — the round entry of a
quick-select wheel, or a skill with its name underneath.

```ruby
UI = RGame::Engine::UI

game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))

disc = UI::ShapeStyle.new(shape: :disc)
bar.add(UI::IconButton.new(image: :star, style: disc)).on_activated { favourite }
bar.add(UI::IconButton.new(image: 'icons/hoe.png', label: 'Hoe', style: disc))
```

| | |
|---|---|
| `image:` | an image id — a registered Symbol or a path String — or `nil` |
| `label:` | optional; a caption along the bottom of the slot |
| `style:` | a [style](#styles); none unless given |
| `tints:` | the `color:` the image is drawn with, per state (default `IconButton::TINTS`) |
| `scales:` | the image's scale per state (default 1 in every state) |
| `label_color:`, `disabled_label_color:` | the caption's, as `TextButton`'s |

The image is drawn at its natural size, centred in the slot — or, with a
caption, centred in the space above it, with the caption centred along the
bottom edge. **With a caption the style is drawn in that space above it too**,
so a disc sits round the picture and the caption reads below it, on whatever is
behind the button. A caption is often wider than the disc — "Watering can" under
a tool — and one drawn across the disc's edge would sit half on the fill and
half off it, legible on neither. **Everything stays inside the slot**, so a navigation reading the
slot's centre and a backdrop sized from the menu's bounds are right for an icon
button as for any other.

**Tint is a multiply**, so the art should be white: white shows each tint
exactly, and dark art takes none of them. **Scales default to 1** because images
are sampled nearest-neighbour, and any scale that is not a whole number doubles
some rows of pixels and not others; focus shows through the tint and the style
instead. `tints:` and `scales:` must name every state, and raise `KeyError` when
the button is built if one is missing.

On a style that names a content colour, that colour replaces the tint in the
states it names. On the default `ShapeStyle` that means pressed only, where a
dark icon shows on the gold fill. The caption keeps `label_color:` and
`disabled_label_color:` whatever the style says, because it is not on the
style's fill. With no style, the
pressed tint stays gold, which reads on a dark ground.

`image: nil` draws the caption alone, for an entry whose art is not in yet. An id
that nothing was registered under is not that case: it raises on the first draw,
as it would for any other image.

### Getting the art on screen

Nine-slice ids name an *element of an atlas*, not a file, so there is nothing
for the asset manager to resolve on demand. Register the atlas once:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui/ui_atlas.json'))
```

`media/ui/ui_atlas.json` ships with `panel` and the four button elements above.
See [Sheets, atlases and maps](assets.md).

The same call registers **images**. An atlas descriptor with an `images`
section — rectangles cut whole from the sheet — puts each one in the renderer's
image registry under its name, so one strip of icons becomes
`IconButton.new(image: :home)` with nothing else to write:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))
```

`examples/assets/icons.json` names eight, used by `examples/radial_menu`. See
[UI atlases](assets.md#ui-atlases) for the descriptor.

A `TextButton` on a `ShapeStyle` needs none of this, and an `IconButton` needs
only its image: a path String resolves through the asset manager, a Symbol
through a UI atlas or `renderer.register_image` — see [Drawing](drawing.md).

`examples/game_menu` is the smallest complete use of all of this: a menu that
opens over a running world, pauses only the node that opened it, and closes
again. `examples/menu_navigation` is the next step up — a title screen, a
settings screen pushed over it, and rows that change fullscreen, the scale mode
and the volume for real and write them to a file. `examples/radial_menu` is a
`RadialMenu` of `IconButton`s, its icons from a UI atlas, and
`examples/quick_wheel` the same wheel held open by Tab or a shoulder button. `examples/skill_bar` is
a `Row` of captioned `IconButton`s, stepped with left and right and each fired by
a hotkey.

## What this is not

It is a menu, not a widget library. Every button is the same size and placed by a
column, a row or a ring, and that is the whole of its layout — no grid, no nesting, no
scrolling lists, and no general answer to how UI should be laid out. There is no text entry, and no
continuous control: `OptionButton` covers a setting with a handful of values, and
anything wanting a free-moving slider needs a control that does not exist yet.

**Buttons are not sized to their text**, and cannot be yet. A layout places
buttons when they are added, and engine code has nothing to measure a label with
at that point: the renderer, the only measuring object a node is handed, arrives
in `draw`, and `RGame::Core::Font#text_width` — which works at any time — is a
Core type the engine layer may not hold. So every slot is the size its layout
was built with, and a longer label needs a wider slot. What it would take is
"Text measurement for the engine layer" in `docs/plans/possible-todos.md`; when
it lands, a layout also has to re-arrange its menu whenever a label changes.

The package this replaces positioned everything absolutely and hit-tested a
mouse cursor. It was deleted with the mouse, none of it is a reference, and its
API is deliberately not preserved.
