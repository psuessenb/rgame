# Design

## Who owns what

| | Owns | Asks of the other |
|---|---|---|
| **`UI::Button`** | label, `enabled`, `focused`, `pressed`, `state`, `on_activated`, `hotkey`, its `on_draw` | nothing |
| **`UI::Menu`** | the buttons, `layout`, `navigation` (or none), bounds, confirm and hotkey dispatch, its `on_draw` (backdrop) | `focused=`, `press`/`release`/`cancel_press`, `enabled?`, `adjust`, `hotkey`, `x`/`y`/`width`/`height` |
| **layout** | where a slot is, and the extent of all of them | writes `x`/`y`/`width`/`height` |
| **navigation** | which button is focused this frame | `menu.focus(index)`, `buttons`, `enabled?`, positions |

The right-hand column is the whole interface a button presents to the menu.
Everything in it lives on `UI::Button`, so a subclass cannot miss part of it.

## `UI::Button`

```ruby
class Button < Node2D
  signal :on_activated

  attr_accessor :label, :enabled
  attr_reader :hotkey

  def initialize(label: nil, enabled: true, hotkey: nil, **)

  def enabled? ; def focused? ; def pressed?

  # :disabled, :pressed, :focused or :idle — public, because it is what a
  # subclass's on_draw reads.
  def state

  # Machinery, called by the menu. Each calls its hook only on a change.
  def focused=(value)   # → on_focus_changed(value)
  def pressed=(value)

  # Fires on_activated and returns self, or nil when disabled.
  def activate

  # What horizontal input does to the focused button under Stepping. nil: nothing.
  def adjust(_delta) = nil

  # Hooks.
  def on_focus_changed(focused); end
  # on_draw(renderer, view) — inherited blank from Node2D; the look.
end
```

A `Button` with no `on_draw` draws nothing. That is the one silent case, and it
is accepted: it is also what an invisible hotkey slot legitimately wants.

## `UI::Menu`

```ruby
class Menu < Node2D
  def initialize(layout:, navigation: Stepping.new, **)

  attr_reader :buttons, :focused_index, :layout, :navigation
  attr_reader :bounds_x, :bounds_y, :bounds_width, :bounds_height

  def add(button)        # raises TypeError unless button.is_a?(Button); returns it
  def focused
  def focus(index)       # only assigns on buttons whose focus actually changes

  # navigation.on_control → hotkeys → confirm on the focused button
  def on_control(actions)

  # on_draw(renderer, view) — blank; a subclass draws its backdrop here, and it
  # lands under the buttons because children draw after their parent.
end
```

`items` becomes `buttons`. `add_item`, `add_option` and `style:` go (open
question 2, settled). `navigation:` may be `nil` (open question 3, settled): the
menu then never focuses anything and skips confirm.

### Pressed is reached two ways

Open question 4, settled. A button has three looks while enabled — **idle,
focused, pressed** — plus disabled, and the menu presses a button from either
source:

| Source | Presses | Activates | Changes focus |
|---|---|---|---|
| `ui_confirm` | the focused button | on the press | no |
| the button's `hotkey` | that button, focused or not | on the press | **no** |

So `state` stops requiring focus for `:pressed`: a hotkeyed button that is not
focused still draws pressed. The rule becomes *disabled, else pressed, else
focused, else idle*.

When activation happens, and how long pressed lasts after an instant one, is
open question 6, settled as follows:

```ruby
class Button < Node2D
  PRESS_FEEDBACK = 0.1   # seconds pressed stays visible after an activation on press

  def initialize(label: nil, enabled: true, hotkey: nil, activate_on: :release, **)
```

| Source | `activate_on: :release` (default) | `activate_on: :press` |
|---|---|---|
| `ui_confirm` on the focused button | pressed while held; activates on release, if focus did not move | activates on press; pressed for `PRESS_FEEDBACK`, or while held if longer |
| the button's `hotkey` | **activates on press** either way; pressed for `PRESS_FEEDBACK`, or while held | same |

Both sources go through one rule in the menu, and the button records which one
holds it — `press(source)`, `release(source)`, `cancel_press(source)` — so a
hotkey's release cannot end a hold confirm started, or the reverse.

And for both: a press counts only if its edge arrived while this button could see
it. That closes the double activation measured in
[01-current-state.md](01-current-state.md#one-confirm-activates-two-menus).

Whatever it settles to, time is counted in the button's `update(dt)`, never read
from a clock, per CLAUDE.md "`draw` renders state".

### Bounds

A layout grows one method, called by the menu after `arrange`:

```ruby
layout.bounds(buttons)   # → [x, y, width, height], relative to the menu
```

The menu copies the four numbers into readers, once per `add`, so drawing a
backdrop reads four ivars and allocates nothing. `Column` answers the stacked
rectangle; `Ring` the square that encloses every slot.

## The menus that draw themselves

```ruby
class PanelMenu < Menu          # nine_slice(panel) around bounds, grown by padding:
  def initialize(panel: :panel, padding: 16, **)

class RadialMenu < Menu         # a Ring and a Pointing, built for you
  def initialize(radius:, button_width:, button_height: button_width,
                 dead_zone: Pointing::DEAD_ZONE, padding: 16,
                 backdrop: BACKDROP, dead_zone_color: DEAD_ZONE, pointer: POINTER, **)
                 # colours default to the example's; nil omits that part.
                 # layout: or navigation: in ** raises, rather than silently replacing the preset.
```

`RadialMenu` is the reusable half of `examples/radial_menu`: backdrop disc, dead
zone, pointer clamped to the ring. It returns as a *preset* over `Menu`, not as
the separate focus implementation #28 removed.

## The buttons that ship

| Class | Draws | Needs art |
|---|---|---|
| `PanelButton` (renamed from `MenuItem`) | nine-slice per state + centred label | the UI atlas |
| `OptionButton` (renamed from `OptionItem`) | the above + `< value >` | the UI atlas |
| `TextButton` | its style, then a centred label | no — its default style is shapes |
| `IconButton` | its style (none by default), an image tinted/scaled per state, optional caption along the bottom of the slot | an image — white art, so a tint can colour it |

`PanelButton` becomes a `TextButton` whose default style is a nine-slice one, and
`OptionButton` stays a `PanelButton`.

`TextButton` is the prototyping button in the requirement. Round or square is a
property of the style (`ShapeStyle shape: :rect | :disc`), so a round image-only
entry is an `IconButton` with a disc style rather than a shape option on each
button class.

Every shipped button draws inside its slot — including the caption — so a
navigation reading `x + width / 2` and a backdrop sized from bounds stay right
without asking a button where its centre is.

Label colours become constructor arguments with the current values as defaults,
held as `Util::Color`s so a draw allocates nothing, and the "button art must be
light because the label colour is a constant" constraint recorded in
`basic-examples.md` goes away.

### Styles

What sits behind a button's content, per state. The button holds one; the menu
never sees it.

```ruby
style.draw(renderer, state, width, height)   # the whole duck type, in the button's local space

NineSliceStyle.new(idle:, focused:, pressed:, disabled:)          # element names
ShapeStyle.new(shape: :rect, colors: COLORS, outline: OUTLINE, border: 3)
```

A style draws at `z: 0` or below and the button's own content at `z: 1`: shapes
default to `z: 50` and would otherwise cover it. This is Godot's per-state
stylebox and Unity's per-selectable transition (see
[02-prior-art.md](02-prior-art.md)) — held by the button, which is what separates
it from the rejected `look:` below.

## Navigation changes

- Every layout answers `axis`. `Column` and `Row` are one `Stack` with the axis
  fixed; `Ring` answers `:vertical`.
- `Stepping.new(axis: nil)` — nil takes the layout's axis, so a `Row` steps with
  left and right without being told; an explicit axis overrides. `:horizontal`
  swaps which pair of actions moves focus and which goes to `adjust`.
- `navigation: nil` (open question 3, settled) — no class. Hotkey dispatch is the
  menu's and works under every navigation, including none, so a navigation
  object would only have existed to say "there is no navigation".

## Considered and rejected

### A `look:` on the menu

Proposed in the prompt before this plan: the menu takes a look object (nine-slice,
disc) and the items it builds draw through it.

Its attractions were real: one constructor argument restyles a whole menu, it
matched the `layout:` / `navigation:` pattern, and it made a menu art-free in one
line.

**Rejected because it puts the look in the container**, which no engine in
[02-prior-art.md](02-prior-art.md) does, and it fails the requirement directly: a
menu mixing an icon button with a text button is impossible, a look has to know
every kind of item it might be asked to draw (`OptionItem`'s value, a caption),
and a game's bespoke button would have to be expressed as a look plus a menu that
builds the right item class — two objects to write for one button.

### `add_item(label, class:)` — a factory on the menu

Keeps the sugar and lets a game pick the class. Rejected: every button class has
different constructor arguments (an image id, values, a shape), so the factory's
signature either grows each of them or forwards `**` blindly and reports a typo
as an error in a class the caller never named.

### A button as a `Component` on a plain `Node2D`

Rejected by the checks CLAUDE.md lists: a button has a position, a size and
children-drawn-after-parent ordering, and is itself a child of the menu. It is a
node pretending to be a component. It would also need a sibling-lookup from the
menu to find it.

### Buttons sized by their content

Not rejected — deferred. It needs the engine layer to measure text, which it
cannot today although Core can, and that is C work across both extensions. See
[01-current-state.md](01-current-state.md#the-engine-layer-cannot-measure-text)
and "Text measurement for the engine layer" in `docs/plans/possible-todos.md`.
When it lands, the layouts here grow a way to ask a button for its preferred size,
and a label change has to re-arrange the menu.
