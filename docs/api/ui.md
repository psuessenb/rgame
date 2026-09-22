# UI

This page covers menus navigated by keyboard or controller, the region of the
screen where one player's UI lives, and a label that draws a translated paragraph.

**The UI has no pointer.** `RGame::Core::Input` has no mouse, and the id range a
mouse would use stays empty. Nothing hovers. A mouse-driven control reacts to the
cursor being over it; a control here reacts to being the **focused** one. The rest
of the design follows from that.

## A player's own screen

**`RGame::Engine::PlayerLayer` is the region.** It draws its subtree once, clipped
to that player's viewport and translated to its corner, and that player's
controller drives it:

```ruby
layer = scene.add_node(RGame::Engine::PlayerLayer.new(player: game.players[1]))
layer.add_node(inventory)
```

[Scene graph](scene_graph.md#a-players-own-screen) describes what it does, and when
it draws nothing.

## `RGame::Engine::UI::Menu`

A `Menu` holds buttons to choose from, with one of them focused.

```ruby
UI = RGame::Engine::UI

column = UI::Column.new(item_width: 220, item_height: 44)
menu = layer.add_node(UI::Menu.new(layout: column, scope: 'pause_menu'))
menu.add(UI::PanelButton.new(label: 'resume')).on_activated { close }
menu.add(UI::PanelButton.new(label: 'save')).on_activated   { save }
menu.add(UI::PanelButton.new(label: 'quit', enabled: false))
```

Each `label:` is a translation key, and `scope:` puts `pause_menu.` in front of it,
so the buttons draw `pause_menu.resume`, `pause_menu.save` and `pause_menu.quit`
from the loaded tables. See [Labels are translation keys](#labels-are-translation-keys).

**The menu holds buttons; it never builds them.** The button decides its own look.
Any [`UI::Button`](#rgameengineuibutton) subclass goes in through `add`, shipped or
written by the game, and one menu may mix them.

**A list and a radial wheel are the same class.** They differ in **where the
buttons sit** and **how input moves focus**. A menu is built with one answer to
each:

| | Answers | Shipped |
|---|---|---|
| `layout:` | where each button goes, its size, and the [bounds](#layouts-column-row-and-ring) of them all | [`Column`](#layouts-column-row-and-ring), [`Row`](#layouts-column-row-and-ring), [`Ring`](#layouts-column-row-and-ring) |
| `navigation:` | which button this frame's input focuses | [`Stepping`](#stepping) (the default), [`Pointing`](#pointing), or [`nil`](#a-menu-with-no-navigation) |

```ruby
ring = UI::Ring.new(radius: 120, item_width: 96, item_height: 30)
wheel = layer.add_node(UI::Menu.new(x: 320, y: 240, layout: ring, navigation: UI::Pointing.new))
wheel.add(UI::PanelButton.new(label: 'sword')).on_activated { equip(:sword) }
wheel.add(UI::PanelButton.new(label: 'bow')).on_activated   { equip(:bow) }
```

The menu keeps everything that stays the same across combinations:

| | |
|---|---|
| `ui_confirm` | press the focused button on the way down, release it on the way up — see [When a press activates](#when-a-press-activates) |
| each button's `hotkey` | press that button, focused or not — see [Hotkeys](#hotkeys) |
| `add(button)` | append a button, re-arrange them all, and return it; `TypeError` for anything that is not a `UI::Button` |
| `clear` | remove every button from the menu and the tree, focus nothing, and return the menu; a closed menu may be cleared |
| `buttons`, `focused`, `focused_index` | what it holds and what is focused — `nil` when nothing is |
| `focus(index)` | focus a button directly, or nothing with `nil`; only buttons whose focus changes are told |
| `layout`, `navigation` | the two parts it was built with |
| `scope:`, `scope` | a scope for its buttons' label keys, or `nil` — see [Labels are translation keys](#labels-are-translation-keys) |
| `open?`, `open`, `close` | whether it is shown and takes input — see [Open and closed](#open-and-closed) |
| `trigger:`, `trigger` | an action that holds the menu open — see [A menu held open by an action](#a-menu-held-open-by-an-action) |
| `on_opened`, `on_closed` | signals; `on_closed` passes the button a trigger's release activated, or `nil` |
| `bounds_x`, `bounds_y`, `bounds_width`, `bounds_height` | the rectangle enclosing every button, relative to the menu, as its layout reports it — all zero while empty |

The actions come from the [universal set](input.md#the-universal-ui-set) that every
`InputMap` merges over, so a menu works without the game declaring anything.

**The menu confirms, not the navigation.** A navigation only decides which button
is focused. A new navigation therefore cannot forget to activate, and every
combination confirms the same way. Each frame the menu runs its navigation, then
every hotkey, then confirm. A menu with a trigger handles the trigger's press first
and its release last.

### Labels are translation keys

**A button's `label:` is a key**, looked up in the tables `RGame::Game` loads. The
button holds it as an [`Engine::Text`](toolbox.md#text--the-string-a-node-draws)
and passes it to `text` as it is. A switch of `I18n.locale` therefore redraws every label on
the next frame, with no button rebuilt, and an unchanged label allocates nothing.

```ruby
require 'rgame'

UI = RGame::Engine::UI
i18n = RGame::Engine::I18n
i18n.load_hash(en: { title_menu: { play: 'Play' }, common: { quit: 'Quit' } },
               de: { title_menu: { play: 'Spielen' }, common: { quit: 'Beenden' } })

menu = UI::Menu.new(layout: UI::Column.new(item_width: 200, item_height: 40), scope: 'title_menu')
play = menu.add(UI::TextButton.new(label: 'play'))
quit = menu.add(UI::TextButton.new(label: RGame::Engine::Text.new('quit', scope: 'common')))
name = menu.add(UI::TextButton.new(label: RGame::Engine::Text.literal('Ada')))

play.label.to_s   # => "Play" — the key title_menu.play
quit.label.to_s   # => "Quit" — its own scope
i18n.locale = :de
play.label.to_s   # => "Spielen"
name.label.to_s   # => "Ada" — a literal, in every locale
```

What a button does with `label:`:

| Given | Holds |
|---|---|
| a String or Symbol | a `Text` for that key, under the button's `label_scope` |
| a `Text` | that `Text`, scope and all |
| `Text.literal(string)` | `string`, never translated — a player's name, a number |
| `nil` | nothing; `IconButton` then draws no caption |

**A label with variables shows the values its last `with` was given.** The button
draws the label without knowing the values. The node that owns them sets them in
`update`, and the label follows on the next draw:

```ruby
require 'rgame'

RGame::Engine::I18n.load_hash(en: { continue: 'Continue (%{saves} saves)' })

saves = RGame::Engine::Text.new('continue', :saves)
button = RGame::Engine::UI::PanelButton.new(label: saves)

saves.with(saves: 3)      # in the owner's update, whenever the count may change
button.label.to_s         # => "Continue (3 saves)"
saves.with(saves: 4)
button.label.to_s         # => "Continue (4 saves)"
```

A `with` whose values are unchanged renders nothing and allocates nothing, so
calling it every `update` costs nothing. A label given no `with` yet raises
`ArgumentError` on its first draw, naming the keywords it needs.

**`scope:` on a menu reaches only keys.** The menu sets each button's
`label_scope` as the button is added, unless the button already has one. A button
applies it to a label it built from a key, including one assigned later with
`label=`. A label given as a `Text` is never re-scoped, so one `Text` shared by two
menus reads the same in both. The scope reaches the menu's own buttons, not nodes
deeper in the tree.

With no table loaded, a key shows as itself under the default missing policy, so
`label: 'Play'` draws the word Play in a game with no locale files. A spec suite
that sets `I18n.missing = :raise` fails on it instead. See
[Missing keys](localization.md#missing-keys).

### Layouts: `Column`, `Row` and `Ring`

| | Places buttons | `axis` | Built with |
|---|---|---|---|
| `Column` | downwards from the menu's origin | `:vertical` | `item_width:`, `item_height:`, `spacing: 8` |
| `Row` | rightwards from the menu's origin | `:horizontal` | `item_width:`, `item_height:`, `spacing: 8` |
| `Ring` | round a circle **centred on** the menu's origin, the first straight up, then clockwise | `:vertical` | `radius:`, `item_width:`, `item_height:` |

```ruby
bar = layer.add_node(UI::Menu.new(layout: UI::Row.new(item_width: 64, item_height: 64)))
```

**`Column` and `Row` are one `UI::Stack` with a fixed `axis:`.** They compute the
same thing with x and y swapped. Neither accepts `axis:`, since a column that is
not vertical is a row. Passing one raises an unknown-keyword error instead of being
ignored. `Stack.new(axis:, item_width:, item_height:, spacing: 8)` takes either
axis in `Stack::AXES`, and raises `ArgumentError` for anything else.

A layout is any object that answers three methods. The first two work relative to
the menu:

- `arrange(buttons)` sets each button's `x`, `y`, `width` and `height`.
- `bounds(buttons)` returns `[x, y, width, height]`, the rectangle enclosing the
  buttons, or `[0, 0, 0, 0]` for none.
- `axis` returns `:vertical` or `:horizontal`. [`Stepping`](#stepping) moves focus
  along it unless told otherwise. A game's own layout without `axis` raises
  `NoMethodError` when a menu is built with it and the default navigation. It works
  with an explicit `Stepping.new(axis:)` or any other navigation.

The menu calls `arrange` and `bounds` after every `add`, so a ring re-spaces itself
as it grows. The menu copies the bounds into its own readers, so a backdrop drawn
from them allocates nothing. A layout keeps no state about a menu, so one instance
may serve several menus.

`Column` and `Row` bounds match their slots exactly. `Ring` bounds are the square
around the whole circle of slots: `2 * radius + item_width` wide and
`2 * radius + item_height` tall, whatever the count. A backdrop behind a wheel
therefore keeps its size as buttons are added.

### `Stepping`

**`Stepping`, the default, moves focus one button at a time** along an axis, in
the order the buttons were added.

| | Vertical axis | Horizontal axis |
|---|---|---|
| move focus, skipping disabled buttons, wrapping at the ends | `ui_up` / `ui_down` | `ui_left` / `ui_right` |
| `adjust` the focused button | `ui_left` / `ui_right` | `ui_up` / `ui_down` |

| | |
|---|---|
| `Stepping.new(axis: nil)` | `nil` takes the layout's `axis`; `:vertical` or `:horizontal` overrides it |
| `axis` | the axis in use — resolved when the menu is built |
| `step(delta)` | move focus forwards along the axis, `delta` times |

**The axis follows the layout.** `Menu.new(layout: UI::Row.new(...))` steps with
left and right, with nothing else said. If the axis had to be set separately,
someone would eventually forget, and a row would step with up and down. An axis
outside `Stack::AXES` raises `ArgumentError` when the menu is built.

Focus starts on the first enabled button. It is never empty while the menu has one.

**The axis moves focus; the other pair goes to the focused button.** `Stepping`
does not know what kind of button it addresses. It calls `adjust`, and a plain
button returns `nil`. That makes an `OptionButton` work, and is why a settings menu
uses `Stepping`.

### `Pointing`

**With `Pointing`, focus is the button a stick points at.** On a `Ring`, that makes
a radial menu.

| | |
|---|---|
| `ui_radial_x` / `ui_radial_y` | the direction; focuses the button nearest to it by angle |
| `dead_zone` | the shortest deflection that selects, on the combined vector (default 0.5) |
| `grace` | how long focus survives the stick entering the dead zone, in seconds — see below |
| `index_at(x, y)` | the index a vector points at, or `nil` inside the dead zone |
| `aim_x`, `aim_y` | the last direction read, for a game drawing a pointer |

**The direction is the selection.** There is no "next". Seen from the menu's
origin, each button's centre is a direction, and the one closest to the stick's
direction takes focus. On a ring, that cuts the circle into one sector per button,
centred on it. The angles come from where the buttons sit, so no layout
can disagree. Eight buttons on a ring match the eight directions of the arrow keys,
so a keyboard works too.

**Inside the dead zone, nothing is focused**, and confirm activates nothing. A
released stick springs back through the middle. A wheel that kept its last
selection would hand a player who lets go and presses A whatever the stick passed
on its way back.

This dead zone applies to the combined vector, *after* `ActionMapper` removes its
own per-axis dead zone (0.15) and rescales the rest. The two do different jobs. The
per-axis one stops a worn stick from drifting. It is far too small to decide that a
player means a direction.

**A grace window delays clearing, for a wheel chosen by letting go.** `grace:` keeps
focus for that many seconds after the stick enters the dead zone, counted in
`update(dt)`, then clears it. By default it is `Pointing::GRACE` (0.15 s) on a menu
with a [trigger](#a-menu-held-open-by-an-action), and 0 on any other. An
always-open wheel therefore behaves as described above, and a held wheel gets the
window automatically. The stick leaving the dead zone starts a fresh window.
Pointing at a disabled button still clears focus at once.

**A disabled button is never focused**, so pointing at one selects nothing. Left
and right are directions here, so `Pointing` cannot adjust an `OptionButton`.

A plain `Menu` draws no wheel. [`RadialMenu`](#rgameengineuiradialmenu) draws the
backdrop, the dead zone and a pointer from `aim_x` / `aim_y`. A game's own wheel
reads the same two.

### A navigation of your own

Subclass `RGame::Engine::UI::Navigation` and override the methods its menu calls.
They take plain names, not hook names: a navigation is a separate object the menu
holds, not a subclass of a node.

```ruby
class FirstEnabled < RGame::Engine::UI::Navigation
  def control(_actions) = menu.focus(menu.buttons.index(&:enabled?))
end
```

| Method | Called |
|---|---|
| `control(actions)` | every frame the menu is open, before the menu handles `ui_confirm` |
| `buttons_changed` | after a button is added |
| `update(dt)` | every update while the menu is not paused — where a navigation counts time |
| `opened` | when the menu opens; `Pointing` forgets its aim and focus here |

`menu` returns the menu it drives. **A navigation drives exactly one menu**, because
`Pointing` keeps the last direction it read. Passing one instance to a second menu
raises `ArgumentError` instead of letting two menus share a pointer. The
constructor default builds a fresh `Stepping` for every menu.

### A menu with no navigation

`navigation: nil` means input never moves focus:

```ruby
bar = layer.add_node(UI::Menu.new(layout: UI::Row.new(item_width: 48, item_height: 48), navigation: nil))
bar.add(UI::IconButton.new(image: :potion, hotkey: :skill1)).on_activated { drink }
```

Adding a button focuses nothing, and nothing focuses a button later. `ui_confirm`
has nothing to act on, and [hotkeys](#hotkeys) are the only way in: the action bar
of a game played on hotkeys alone. Omitting the keyword gives a `Stepping`, so `nil`
is always a deliberate choice, never a forgotten argument. A game can still call
`focus` on such a menu, and confirm then acts on that button.

### Open and closed

**A closed menu draws nothing**, neither its backdrop nor its buttons, and its
navigation, hotkeys and confirm do nothing. A menu without a trigger starts open. A
pause menu is built once and toggled:

```ruby
class PauseMenu < RGame::Engine::Node2D
  UI = RGame::Engine::UI

  def _enter_tree
    @menu = add_node(UI::PanelMenu.new(x: 56, y: 56, layout: UI::Column.new(item_width: 180, item_height: 34)))
    @menu.add(UI::PanelButton.new(label: 'resume')).on_activated { @menu.close }
    @menu.close
  end

  def _control(actions)
    return unless actions.pressed?(:ui_cancel)

    @menu.open? ? @menu.close : @menu.open
  end
end
```

`open` and `close` do nothing when the menu is already in that state. Each emits
`on_opened` or `on_closed` (with `nil`) only on a change. Opening calls the
navigation's `opened`. Under `Stepping`, focus stays where it was.

**Closed is not paused.** A closed menu still receives `control` and `update`. A
trigger can therefore reopen it, and a button's pressed feedback runs out while the
menu is shut instead of showing when it reappears. Pausing a menu's node still stops
everything, as for any node. The game decides what else happens while a menu is
open, such as pausing the hero or dimming the world. It acts from the two signals,
or wherever it calls `open`.

### A menu held open by an action

A quick menu: hold a button to open a wheel, point, and let go to choose.

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

`trigger:` names an action. With a trigger, the menu behaves like this:

| When | The menu |
|---|---|
| built | is closed |
| the trigger goes down | opens, and the navigation forgets the last opening |
| it is held | moves focus as its navigation says; hotkeys work |
| it comes up | activates the focused button, if any, and closes; `on_closed` passes that button, or `nil` |
| `ui_confirm` is pressed | nothing — letting go is the only way to choose |

**A release with nothing focused chooses nothing**, not the last button the stick
passed. A player changes their mind by centring the stick and letting go. A stick
returns to the middle a frame or two before a shoulder button comes up. So on a
menu with a trigger, `Pointing` keeps focus for its [grace window](#pointing) first.
Without it, releasing both at once would nearly always choose nothing.

**Only a press the menu saw start opens it**, as with every other press. A trigger
already down when the menu appears opens nothing until released and pressed again.
A trigger that comes up while the menu is paused closes it without choosing.

**`open` raises on a menu with a trigger.** A menu opened by hand would wait for the
release of a press it never saw. `close` works. It cancels for a player who is hit
while holding the wheel: the release that follows neither chooses nor reopens.

The trigger works under every navigation. With `navigation: nil`, the release
activates whatever the game focused, typically in `on_opened`.

The release activates the button with `activate`, without pressed feedback. The menu
closes on that frame, so nothing would show the feedback.

One limit remains. A stick that overshoots the middle as it springs back can point
at the opposite button for a frame or two. The grace window only delays the dead
zone and does not cover that.

### Focus is per player, and it costs nothing

**Two players can each have a menu open, independently, and neither menu mentions
players.** A menu inside a `PlayerLayer` inherits that player as its
`input_owner`, and children inherit ownership. The `actions` its `_control`
receives already belong to that player.

The menu does nothing special for this.
[Ownership routing](scene_graph.md#who-a-node-answers-to) does the work one layer
down.

### `RGame::Engine::UI::PanelMenu`

**A `Menu` that draws its own backdrop**: one nine-slice around its buttons,
extended by `padding` on every side.

```ruby
UI = RGame::Engine::UI

column = UI::Column.new(item_width: 180, item_height: 34)
menu = layer.add_node(UI::PanelMenu.new(x: 56, y: 56, layout: column))
menu.add(UI::PanelButton.new(label: 'resume')).on_activated { close }
menu.add(UI::PanelButton.new(label: 'quit')).on_activated   { quit }
```

| | |
|---|---|
| `panel:` | the nine-slice id to draw (default `:panel`) |
| `padding:` | how far the panel reaches beyond the bounds on each side (default 16) |

**The menu's bounds size the panel**, and its layout recomputes them on every
`add`. A button added later grows the panel, and nothing has to track the button
count.

**The menu's origin remains the layout's.** With a `Column`, that is the first
button's top-left corner, and the panel starts `padding` above and to the left of
it. To put a panel's corner at (40, 40), place the menu at (40 + padding,
40 + padding). The buttons are the menu's children, so they draw over the panel
with no `z`.

Any other backdrop works the same way: subclass `Menu` and draw it in `_draw` from
`bounds_x`, `bounds_y`, `bounds_width` and `bounds_height`.

### `RGame::Engine::UI::RadialMenu`

**A wheel**: a `Menu` that builds its own `Ring` and `Pointing`. It draws a backdrop
disc, the dead zone to scale, and a pointer from the centre towards where the stick
aims.

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

**The menu's origin is the centre of the wheel.** The backdrop's radius is half the
larger side of the bounds, plus `padding`. `Ring` bounds cover the whole circle, so
the radius is the same with one button as with eight. The dead zone is drawn at
`dead_zone * radius`, exactly where a pointer tip inside it selects nothing. **The
pointer's tip is clamped to the ring.** Two arrow keys read as (1, 1), longer than a
stick can reach, and would otherwise poke past it. All three parts draw before the
buttons, which are the menu's children.

Every other keyword goes to `Menu`, `trigger:` included. A `RadialMenu` with a
trigger is the [held wheel](#a-menu-held-open-by-an-action).

**`layout:` and `navigation:` raise `ArgumentError`.** Forwarding them would let
either replace the ring or the pointing the wheel is made of, without warning. For a
ring stepped with `Stepping`, build a plain `Menu` with a `Ring`.

Anything drawn in the middle of the wheel, such as the chosen item, belongs to a node
added *after* the menu. Between nodes, the tree decides what lands on top, so
whatever the wheel's parent draws itself sits under the backdrop.
`backdrop_radius` returns the disc's radius, for a game sizing something to it.

### `RGame::Engine::UI::Button`

**A `Button` has state, a label and an `on_activated` signal, but no look.** A
subclass supplies the look in `_draw`, reading `state`:

| `state` | When |
|---|---|
| `:disabled` | `enabled: false`, whatever else is true |
| `:pressed` | a press is held on it, or its pressed feedback is still running |
| `:focused` | the menu's navigation focused it |
| `:idle` | none of those |

| | |
|---|---|
| `label`, `label=` | the `Engine::Text` drawn, or `nil`; set from a key, a `Text` or `nil` — see [Labels are translation keys](#labels-are-translation-keys) |
| `label_scope`, `label_scope=` | the scope a label given as a key resolves under; a [menu's `scope:`](#labels-are-translation-keys) sets it |
| `enabled`, `enabled?` | whether it can be activated; `Stepping` and `Pointing` skip a disabled button |
| `focused?`, `pressed?`, `state` | read by `_draw` |
| `activate_on` | `:release` (the default) or `:press`; anything else raises `ArgumentError` |
| `hotkey` | an action name that presses this button, focused or not, or `nil` — see [Hotkeys](#hotkeys) |
| `activate` | fire `on_activated` and return the button, or `nil` when disabled |
| `activate_with_feedback` | `activate`, and draw pressed for `PRESS_FEEDBACK` — the instant press, needing nothing held |
| `adjust(delta)` | what horizontal input does to it under `Stepping`; `nil` — nothing to change |
| `_gain_focus`, `_lose_focus` | hooks, each called only when focus changes |

`focused=`, `press(source)`, `release(source)` and `cancel_press(source)` form the
menu's side of the interface. `source` is `:confirm` (the default) or `:hotkey`.
Focus movement skips a disabled button, and no route can activate one, so a caller
never checks first.

#### A button of your own

**Subclass `Button` and draw.** The class inherits focus, pressing, activation and
placement, so it only defines its look:

```ruby
class EdgeButton < RGame::Engine::UI::Button
  COLORS = {
    idle: RGame::Util::Color.new(200, 200, 200), focused: RGame::Util::Color.new(255, 255, 255),
    pressed: RGame::Util::Color.new(255, 220, 120), disabled: RGame::Util::Color.new(110, 110, 110)
  }.freeze

  def _draw(renderer, _view)
    color = COLORS.fetch(state)
    renderer.rect(0, 0, 4, height, color: color) unless state == :idle
    renderer.text(label, 12, (height - renderer.text_height) / 2, color: color)
  end
end

menu.add(EdgeButton.new(label: 'continue')).on_activated { resume }
```

A `Button` without `_draw` draws nothing, which suits an invisible slot.

A look that differs from a shipped button only in what sits behind the label needs
no subclass. Pass a [style](#styles) to a `TextButton`.

Three other designs would not work:

- **A `look:` on the menu**, applied to every button in it. One argument would
  restyle a whole menu. But the menu could never mix an icon button with a text
  button. The look would have to draw every kind of button it met. A game's own
  button would need a look *and* a menu subclass.
- **A factory on the menu**, `add_item(label, class:)`. Every button class takes
  different arguments: an image, a list of values, a style. The factory would have
  to grow all of them, or forward them blindly and report a typo from a class the
  caller never named.
- **A button as a component** on a plain node. A button has a position, a size and
  children that draw over it, and it is a child of the menu. It is a node. As a
  component, the menu would have to look it up on a sibling.

#### When a press activates

`ui_confirm` reaches the focused button as a press and a release. `activate_on:`
decides which one activates:

| | `activate_on: :release` (default) | `activate_on: :press` |
|---|---|---|
| activates | when confirm is let go, if focus did not move while held | as confirm goes down |
| drawn pressed | while held | at least `Button::PRESS_FEEDBACK` (0.1 s), or while held if longer |

**A settings menu keeps the default.** Holding confirm shows the press, and moving
away before letting go cancels it. `:press` suits buttons that answer instantly,
such as a skill bar. The feedback counts down in `update(dt)`, so a paused button
keeps it, and a spec advances it by passing seconds.

**A button acts only on a press it saw start.** Three rules ensure that:

- **A menu accepts no press until it has seen `ui_confirm` up.** A submenu added
  from `on_activated` is controlled later in the same tick, while the key that opened
  it is still down. Without this rule, the submenu would read that press again and
  activate its own focused button.
- **A change to the buttons starts that wait again.** After `add` or `clear`, the
  menu accepts no confirm press until it has seen `ui_confirm` up. A parent node's
  `_control` runs before the menu's. A parent that adds buttons on a confirm press
  therefore adds them before the menu reads that press, and the new buttons ignore
  it. A menu whose buttons change from a button's `on_activated` reads no more
  input that tick, hotkeys included.
- **A press whose release the button never saw is dropped**, feedback included, and
  activates nothing. A menu that closes itself from `on_activated` stops being
  controlled, so it never sees the key come up. Next time it is controlled, it finds
  the key up with no release edge and lets go. It does not reopen pressed.

Neither rule sees a pause that starts *after* the release. A `:press` button closed
within `PRESS_FEEDBACK` of release keeps the rest of its feedback, and shows it when
reopened. A menu covered by a pushed scene is not controlled either, so it keeps
drawing the state it had when covered.

#### Hotkeys

**`hotkey:` names an action that presses the button, wherever focus is:**

```ruby
controls = RGame::Util::Controls
input_map = RGame::Engine::InputMap.default.merge(
  skill1: { buttons: [controls::KEY_1] },
  skill2: { buttons: [controls::KEY_2] }
)

bar.add(UI::IconButton.new(image: :torch, label: 'torch', hotkey: :skill1)).on_activated { light }
bar.add(UI::IconButton.new(image: :hammer, label: 'hammer', hotkey: :skill2)).on_activated { build }
```

| | |
|---|---|
| activates | as the key goes down, **whatever `activate_on:` says** |
| drawn pressed | at least `PRESS_FEEDBACK`, or while held if longer — focused or not |
| its release | activates nothing |
| focus | does not move |

A hotkey is a second way to press a button, not a way to move to it. A button is
pressed by being focused while confirm goes down, or by its own key. Hotkeys follow
the same rules as confirm. A menu accepts a hotkey's press only after seeing that key
up since the button was added, so a menu opened by a hotkey does not fire from the
same press. A press whose release was never seen is dropped. A disabled button
ignores its hotkey. Hotkeys work under every navigation, and under none.

The player's `InputMap` must declare the action. The menu reads it every frame, so
an undeclared action raises `KeyError`, naming it, on the first frame.

**A press belongs to the source that started it.** The button records whether
confirm or its hotkey holds it. While one does, a press from the other is ignored,
and that source's release ends nothing:

- Confirm held on a `:release` button, then its hotkey pressed and released: nothing
  activates, and the button stays pressed. Letting go of confirm activates it, once.
- A hotkey and confirm going down on the same tick on the focused button: it
  activates once.
- Focus moving away ends a confirm hold, as always, and leaves a hotkey hold alone.

### Styles

**A style draws what sits behind a button's content, per state.** It is any object
answering one method in the button's local space, and optionally a second:

```ruby
style.draw(renderer, state, width, height)
style.content_color(state)   # optional: the colour content takes on this state's fill, or nil
```

The button holds its style and calls it before drawing its own content; the menu
never sees it. **A style draws at `z: 0` or below.** The button draws its label or
icon at `z: 1`, so a style that drew higher would cover the content.

**The style decides what reads on its fill.** A style that answers
`content_color(state)` sets the colour of the button's label or icon in every state
where it returns a colour. `TextButton`, `OptionButton` and `IconButton`'s picture
all follow it. They fall back to their own `label_color:` or `tints:` wherever it
returns `nil`, and for a style without the method. The style picks the fill, so only
the style can pick what shows on it. A `ShapeStyle`'s pressed fill is the same gold
as `IconButton`'s pressed tint. Without `content_color`, a pressed icon on a disc
would vanish. Two styles ship.

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

**The fill is inset by `border` in every state**, and the outline covers the whole
shape beneath it. A button therefore keeps its size across states; focus uncovers
the ring the fill leaves. A disc is centred in the slot, as wide as the slot's
shorter side. `UI::ShapeStyle::DEFAULT` uses every default, and a `TextButton` draws
it unless told otherwise.

Both styles check every state when built, not on the first frame a button reaches
it. They also coerce their colours then, so drawing allocates nothing.

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

menu.add(RGame::Engine::UI::TextButton.new(label: 'continue', style: Underline.new))
```

The colours are `Color`s built once. An `[r, g, b]` literal would make the renderer
build a new `Color` on every draw. `Underline` has no `content_color`, so the label
keeps the button's own colour in every state. A style that fills behind the label
should say what reads on that fill.

### `RGame::Engine::UI::TextButton`

**A label centred on a style.** It needs no art, so build menus with it before the
art exists:

```ruby
UI = RGame::Engine::UI

menu.add(UI::TextButton.new(label: 'play')).on_activated { start }
menu.add(UI::TextButton.new(label: 'credits', style: UI::ShapeStyle.new(shape: :disc)))
menu.add(UI::TextButton.new(label: 'quit', style: nil))
```

| | |
|---|---|
| `label:` | required, because it is drawn: a key or a `Text` |
| `style:` | a [style](#styles); `UI::ShapeStyle::DEFAULT` unless given, `nil` for the label alone |
| `label_color:`, `disabled_label_color:` | a `Color` or `[r, g, b]`; defaults `TextButton::LABEL_COLOR` and `DISABLED_LABEL_COLOR`; a style's [content colour](#styles) takes precedence in the states it names |

The style draws first, and the label over it at `z: 1`. A subclass that draws more
than a label overrides the private `draw_foreground(renderer)`, not `_draw`. It
then keeps its style without having to draw it. `OptionButton` works this way.

### `RGame::Engine::UI::PanelButton`

**A `TextButton` with a nine-slice style**: the shipped atlas's button, with a dark
label. Its style is `PanelButton::STYLE`, which uses one atlas element per state:

| `state` | Element |
|---|---|
| `:focused` | `button_focus` |
| `:pressed` | `button_pressed` |
| `:idle` | `button_idle` |
| `:disabled` | `button_disabled` |

Everything else comes from `TextButton`, and you can override every default. A game
with its own art need not follow the shipped atlas's names:

```ruby
UI = RGame::Engine::UI

menu.add(UI::PanelButton.new(label: 'load', style: UI::PanelButton::STYLE.with(idle: :my_idle)))
```

### `RGame::Engine::UI::OptionButton`

**A row whose value is chosen from a list.** It draws `Label   < value >`. A chevron
appears only where there is somewhere to go, which is how a player learns they
reached an end.

```ruby
UI = RGame::Engine::UI

volume = menu.add(UI::OptionButton.new(label: 'volume', values: [0, 25, 50, 75, 100],
                                       display: ->(percent) { RGame::Engine::Text.literal("#{percent}%") }))
volume.on_changed { |value| game.audio.volume = value / 100.0 }
shadows = menu.add(UI::OptionButton.new(label: 'shadows', values: %i[off low high]))
```

| | |
|---|---|
| `values:`, `index:`, `display:` | construction: the list, the starting position (default 0, clamped into the list), and how a value becomes its caption |
| `values`, `index`, `value` | the list, where it sits, and the value there |
| `caption` | the `Engine::Text` drawn for the current value, or `nil` for an empty list |
| `value = something` | select by value; a value the list does not offer is ignored |
| `adjust(delta)` | move the selection, clamped; the button if it moved, `nil` if not |
| `on_changed` | emits the new value, and only when it changed |

It is a `PanelButton`, so focus, the four state elements and `enabled: false` work
as on any other row.

**Values clamp, while focus wraps.** Menu buttons have no magnitude, so joining a
list's ends only makes a short list quicker to navigate. Values usually do have a
magnitude. Wrapping would turn "one louder" at the top of a volume range into
silence.

**`display` runs once per value, when the row is built.** It turns each value into
a caption, while the values stay whatever the game acts on. Running it at draw time
would allocate a String every frame for every row on screen; see
[Drawing](drawing.md).

**A caption is a key, like the label.** `display` returns a key, which the row makes
a `Text` of under its `label_scope`, or a `Text`, kept as it is. A caption `Text`
with variables shows the values its last `with` was given, as a label does. The
default,
`OptionButton::DISPLAY`, reads a Symbol value as its own key and draws any other
value as a literal of its `to_s`. So `%i[off low high]` looks up `off`, `low` and
`high`, and `[0, 50, 100]` draws the numbers. In a menu with `scope: 'settings'`,
the keys become `settings.off` and so on. YAML reads unquoted `on`, `off`, `yes` and
`no` as booleans, so a table spells those keys in quotes: `'off': Off`.

**The value column is as wide as the widest caption**, and centres the current one.
The row measures it again whenever a caption's String changes: after a locale
switch, a new scope, or a `with` with new values. A `Text` never edits its String,
so each draw compares every caption's String with the one last measured, by object
identity rather than by content. A switch to longer captions widens the column, and
a draw where nothing changed measures nothing.

`value=` ignores values the list does not offer so that restoring a setting from a
file is safe. A save written by another version of the game, or edited by hand,
leaves the row unchanged instead of raising.

### `RGame::Engine::UI::IconButton`

**A picture, tinted by state, with an optional caption.** It suits the round entry
of a quick-select wheel, or a skill with its name underneath.

```ruby
UI = RGame::Engine::UI

game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))

disc = UI::ShapeStyle.new(shape: :disc)
bar.add(UI::IconButton.new(image: :star, style: disc)).on_activated { favourite }
bar.add(UI::IconButton.new(image: 'icons/hoe.png', label: 'hoe', style: disc))
```

| | |
|---|---|
| `image:` | an image id — a registered Symbol or a path String — or `nil` |
| `label:` | optional; a key or a `Text`, drawn as a caption along the bottom of the slot |
| `style:` | a [style](#styles); none unless given |
| `tints:` | the `color:` the image is drawn with, per state (default `IconButton::TINTS`) |
| `scales:` | the image's scale per state (default 1 in every state) |
| `label_color:`, `disabled_label_color:` | the caption's, as `TextButton`'s |

**The image draws at natural size, centred in the slot.** With a caption, it centres
in the space above the caption, and the caption centres along the bottom edge.
**With a caption, the style also draws in that space above it.** A disc then sits
around the picture, and the caption reads below it on whatever lies behind the
button. A caption is often wider than the disc, like "Watering can" under a tool.
Drawn across the disc's edge, it would sit half on the fill and half off, legible on
neither. **Everything stays inside the slot.** A navigation reading the slot's
centre and a backdrop sized from the menu's bounds therefore work for icon buttons
as for any other.

**Tint multiplies**, so draw the art in white. White shows each tint exactly; dark
art takes none. **Scales default to 1** because images use nearest-neighbour
sampling. A scale that is not a whole number doubles some pixel rows and not others.
Focus shows through the tint and the style instead. `tints:` and `scales:` must name
every state, and raise `KeyError` at construction if one is missing.

With a style that names a content colour, that colour replaces the tint in the
states it names. On the default `ShapeStyle`, that is the pressed state only, where a
dark icon shows on the gold fill. The caption keeps `label_color:` and
`disabled_label_color:` whatever the style says, because it does not sit on the
style's fill. Without a style, the pressed tint stays gold, which reads on a dark
background.

`image: nil` draws the caption alone, for an entry whose art is not ready. An id
with nothing registered under it is a different case: it raises on the first draw, as
for any other image.

### Getting the art on screen

**Register a UI atlas once.** Nine-slice ids name an *element of an atlas*, not a
file, so the asset manager has nothing to resolve on demand:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('ui/ui_atlas.json'))
```

The repository's `media/ui/ui_atlas.json` holds `panel` and the four button elements
above. See [Assets](assets.md).

The same call registers **images**. An atlas descriptor with an `images` section,
rectangles cut whole from the sheet, puts each one in the renderer's image registry
under its name. A strip of icons then becomes `IconButton.new(image: :home)` with
nothing else to write:

```ruby
game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))
```

`examples/assets/icons.json` names eight icons, used by `examples/radial_menu`. See
[UI atlases](assets.md#ui-atlases) for the descriptor.

A `TextButton` on a `ShapeStyle` needs none of this, and an `IconButton` needs only
its image. A path String resolves through the asset manager, and a Symbol through a
UI atlas or `renderer.register_image`; see [Drawing](drawing.md).

The examples build up in steps:

- `examples/game_menu` is the smallest complete use. A menu opens over a running
  world, pauses only the node that opened it, and closes again.
- `examples/menu_navigation` adds a title screen and a settings screen pushed over
  it. Its rows change fullscreen, the scale mode and the volume, and write them to a
  file.
- `examples/radial_menu` is a `RadialMenu` of `IconButton`s, with icons from a UI
  atlas.
- `examples/quick_wheel` holds the same wheel open with Tab or a shoulder button.
- `examples/skill_bar` is a `Row` of captioned `IconButton`s, stepped with left and
  right and each fired by a hotkey.

## `RGame::Engine::UI::Label`

**A label draws a translated text as lines that fit its width, one page at a
time.** It is a node, with no focus and no activation:

```ruby
@intro = add_node(RGame::Engine::UI::Label.new(
  text: 'intro.story', x: 100, y: 150, width: 440,
  typeface: RGame::Util::Typeface.default(24), lines_per_page: 3, align: :center
))
```

`text:` is a translation key or an [`Engine::Text`](toolbox.md#text--the-string-a-node-draws),
as a button's `label:` is. `width:` is required and must be positive. The label
holds an [`Engine::Paragraph`](text.md#a-paragraph-that-follows-the-language),
so it breaks the text again when a variable, the language or the width changes.
Nothing has to call it. An unchanged draw allocates nothing.

It draws the lines of the current page from its top-left corner. Each line sits
`typeface.height` below the one before, drawn with `font: typeface`. The
typeface that broke the lines draws them, so a line never overflows the width it
was measured against.

| Keyword or method | |
|---|---|
| `typeface:` | the face it measures and draws with; `Util::Typeface.default` by default |
| `lines_per_page:` | how many lines a page holds; without it the whole text is one page |
| `align:` | `:left` (the default), `:center` or `:right`, each line against the width; anything else raises `ArgumentError` |
| `color:` | the text colour; `UI::Label::COLOR` by default, the colour a `TextButton` draws its label in |
| `text=` | changes the text, taking what `text:` takes; starts again on page 0, with nothing revealed |
| `with(...)` | gives the text its variables, and returns the label |
| `width=` | sets the width the text breaks at and aligns against; zero or less raises `ArgumentError` |
| `page`, `page=` | the page drawn, from 0 |
| `page_count` | how many pages the text fills, at least 1 |
| `last_page?` | whether the page drawn is the last |
| `reveal:` | characters a second to reveal each page at, or nil (the default) to draw it whole; anything but a positive number raises `ArgumentError` |
| `revealed?` | whether the whole page is shown |
| `reveal_all` | shows the rest of the page at once, and returns the label |
| `page_length` | how many characters the page drawn holds, in grapheme clusters; counts afresh on every call, so not for a draw path |

**A label reads no input. Its owner turns the page.** `page=` clamps to the
pages there are, so `page += 1` on the last page stays there. A language switch
can change how many pages there are. When it leaves fewer than the page set,
`page` reads as the last one.

```ruby
def _control(actions)
  @intro.page += 1 if actions.pressed?(:ui_confirm)
end
```

### Revealing a page a character at a time

**With `reveal:`, a label types each page out.** It counts in `update(dt)`, so
it shows `reveal` characters for every second of `dt`, carried from one line to
the next in reading order. A character is a grapheme cluster: a letter built
from a base and a combining mark appears whole. Without `reveal:`, a label draws
each page whole, whatever time passes.

```ruby
@line = add_node(RGame::Engine::UI::Label.new(
  text: 'smith.greeting', width: 440, lines_per_page: 3, reveal: 40
))

def _control(actions)
  return unless actions.pressed?(:ui_confirm)

  @line.revealed? ? @line.page += 1 : @line.reveal_all
end
```

- **A page starts from nothing** when the label enters the tree, when the page
  turns, when `with` or `width=` changes the lines, and on every `text=`, even
  one handing over the `Text` already shown. A `page=` that stays on the same
  page, such as `page += 1` on the last one, does not start again.
- **A language switch or a variable changed on the `Engine::Text` itself starts
  the page again on the label's next update.** A draw before that update draws
  the new page whole, rather than building anything on the draw path.
- **A paused label does not reveal.** Time reaches it only through `update`.
- **Each prefix sits where its whole line will stand**, so a centred line grows
  in place instead of moving as it lengthens.
- **Drawing allocates nothing, mid-reveal or not.** The label builds every
  prefix of a page's lines once, when the page appears, as frozen Strings.

`revealed?` is true once the whole page is shown, and always without `reveal:`.
What confirm does on a page still typing is the owner's decision, as turning the
page is.

`examples/intro` turns the pages on Enter and on a one-shot timer, and types
each one out. Enter shows the rest of a page still typing. The timer holds a
shown page for a second plus a little for each character `page_length` counts,
so a short page does not stay up as long as a full one.

## `RGame::Engine::UI::DialogueBox`

**A dialogue box shows one [`Engine::Dialogue`](dialogue.md#dialogue).** It draws
the speaker's name, types the line out a page at a time, and lists the responses
to pick from. It is a node, and the game adds it where the conversation should
appear:

```ruby
UI = RGame::Engine::UI

talk = RGame::Engine::Dialogue.new(SMITH, context: hero, facts: facts)
talk.on_ended { |transcript| @journal.concat(transcript.to_a) }
layer.add_node(UI::DialogueBox.new(dialogue: talk, unavailable: :disable, width: 600, x: 20, y: 300))
```

It is one way to draw a conversation. A game that draws its own drives the
`Dialogue` itself, and nothing in `Dialogue` depends on the box.

**Confirm does the next thing:**

1. On a page still typing, it shows the rest of the page.
2. On a page fully shown that is not the last, it turns the page.
3. On the last page of a beat that continues, it calls `Dialogue#continue`.

On a beat that waits for a response, the responses replace the ▼ marker once the
last page is fully shown, by the reveal or by confirm. The next confirm picks the
focused response, and `ui_up` and `ui_down` move focus, as in any
[`Menu`](#rgameengineuimenu).

**Every confirm goes through the box's menu.** The ▼ marker is the menu's one
button while a line is shown, and it activates on the press. The box reads no
confirm itself. So the menu's [press rules](#when-a-press-activates) apply to all of
it: a box added while confirm is held does nothing until confirm is let go and
pressed again, and the confirm that finishes a line picks no response.

**`unavailable:` is required.** It decides what happens to a response whose
condition fails. The box asks each response's condition once, when the responses
appear, and not on the frames after.

| `unavailable:` | the response |
|---|---|
| `:hide` | is left out of the list |
| `:disable` | is listed, drawn disabled, and skipped as focus moves |

Anything else raises `ArgumentError`, and so does a dialogue that has already
ended, or a `log_entry:` whose variables are not `:speaker` and `:line`.

| Keyword or method | |
|---|---|
| `dialogue:`, `dialogue` | the conversation shown |
| `unavailable:`, `unavailable` | `:hide` or `:disable`; see above |
| `width:` | the box's width; its height follows from the other keywords |
| `lines_per_page:` | the line's lines per page, 3 by default |
| `reveal:` | characters a second the line types out at, 40 by default; nil draws each page whole |
| `typeface:` | the face the speaker's name and the line are measured and drawn with; `Util::Typeface.default` by default |
| `panel:` | drawn behind the whole box as `panel.draw(renderer, :idle, width, height)`; `ShapeStyle::DEFAULT` by default |
| `button_style:` | drawn behind each response, as a [`TextButton`](#rgameengineuitextbutton)'s `style:`; `ShapeStyle::DEFAULT` by default |
| `padding:` | the gap round the edge and between the parts, 12 by default |
| `portrait_width:` | a column kept free at the left for `_draw_portrait`, 0 by default |
| `_draw_portrait(renderer, speaker)` | a hook that draws nothing; see below |
| `log:`, `log` | the action that opens [the log](#the-log), or nil for none, the default |
| `log_entry:` | an `Engine::Text` with the variables `:speaker` and `:line`, formatting one line of the log; nil for the default |
| `log_open?` | whether the log is showing |
| `DialogueBox::UNAVAILABLE` | `[:hide, :disable]` |
| `DialogueBox::COLOR` | the colour of the speaker's name and the marker |

**The box keeps one size for the whole conversation.** The speaker's name sits at
the top, the line's `lines_per_page` lines below it, and the responses below
those. The box is tall enough for the most responses any beat of the script has.
The line breaks at the width left over after the padding and the portrait column.
The responses are `TextButton`s, which draw their labels in the renderer's font.
Any style works as `panel:` or `button_style:`, a
[`NineSliceStyle`](#styles) included.

**A subclass draws a portrait in `_draw_portrait`.** The box calls it on every
draw, in its own space, with the beat's speaker Symbol. The portrait column
starts at `(padding, padding)` and is `portrait_width` wide:

```ruby
class PortraitBox < RGame::Engine::UI::DialogueBox
  def _draw_portrait(renderer, speaker)
    renderer.image(PORTRAITS.fetch(speaker), 12 + 32, 12 + 32)
  end
end
```

**When the conversation ends, the box frees itself** with `queue_free`. The game
hears the end from `Dialogue#on_ended`, which hands over the transcript. The box
reads the dialogue back after each move it makes, so the box should be the only
thing moving its dialogue.

**Drawing allocates nothing**, typing or not. The speaker's name is the
dialogue's `Engine::Text`, drawn as it is.

### The log

**`log:` names an action that opens the log**, a paged
[`UI::Label`](#rgameengineuilabel) over the dialogue's
[transcript](dialogue.md#the-transcript). The action must be declared in the
game's `InputMap`:

```ruby
input_map = RGame::Engine::InputMap.default.merge(log: { buttons: [Controls::KEY_L, Controls::PAD_Y] })
game = RGame::Game.new(root: Village.new, input_map: input_map)

# in a scene
layer.add_node(UI::DialogueBox.new(dialogue: talk, unavailable: :hide, width: 600, log: :log))
```

The log replaces the speaker's name, the line and the responses. It takes the
line's width and the box's whole height inside the padding. It opens on its last page. `ui_up` turns back a page and
`ui_down` forward; the log action or `ui_cancel` closes it. With `log: nil` the
box reads no action for it.

**While the log is open, the conversation does not move.** The line leaves the
tree, so its reveal holds where it was, and the menu closes, so confirm picks
nothing. Closing the log puts both back as they were, with the same response
focused.

**Each line reads `Speaker: line`, and each response its label alone.** Both
are punctuation, not words. A language that wants another form passes its own
`log_entry:`, a translation with the two variables:

```ruby
UI::DialogueBox.new(dialogue: talk, unavailable: :hide, width: 600, log: :log,
                    log_entry: RGame::Engine::Text.new('log.entry', :speaker, :line))
```

The log renders its text again only while open, and only when an entry has
arrived or the language has changed since it last rendered. Drawing it otherwise
allocates nothing. A
transcript restored with `Dialogue.new(transcript:)` shows in the log as it was
saved, in the current language.

The log is one way to show a transcript. A game with its own log reads
`Dialogue#transcript`, or the transcript `on_ended` hands over.

### Whose conversation it is

**The box answers to its `input_owner`**, as every node does. Inside a
`PlayerLayer` that is the layer's player, so two players can hold two
conversations in their own halves of the screen, each moved only by its own
controller. Outside one, with no owner set, it is the primary player.

**During `solo!`, add the box in the `:overlay` band.** A `PlayerLayer` draws
nothing while the split is collapsed, so a box inside one would disappear. Set
`input_owner` to the player who drives the conversation:

```ruby
viewports.solo!(cutscene_camera)
scene.add_node(UI::DialogueBox.new(dialogue: talk, unavailable: :hide, width: 600,
                                   band: :overlay, input_owner: game.players[1]))
```

**To let every player drive it, set `input_owner` to
[`players.everyone`](input.md#everyone-at-once).** Any player's confirm then
moves the conversation. A confirm pressed while another player holds confirm is
no press, so one line never skips twice.

## What this is not

**This is a menu, not a widget library.** Every button in a menu has the same size,
placed by a column, a row or a ring. That is the whole layout system: no grid, no
nesting, no scrolling lists, and no general layout model. It has no text entry and no
continuous control. `OptionButton` covers a setting with a handful of values; a
free-moving slider needs a control that does not exist.

**Buttons are not sized to their text.** Every slot has the size its layout was
built with, so a longer label needs a wider slot, in the longest language the game
ships. A game's menus are laid out by hand rather than generated, and a menu that
re-arranged itself whenever a language switch changed every label would move the
button the player has focused. Engine code can measure a label: `RGame::Util::Typeface#text_width`
works anywhere, with no window. See [Measuring without a window](text.md#measuring-without-a-window).
Text longer than a slot belongs in a [`UI::Label`](#rgameengineuilabel), which
breaks it to its width.

**`scope:` does not inherit down the tree.** It is a `Menu` option. A HUD or a
dialog that is not a menu scopes each of its own `Text`s.
