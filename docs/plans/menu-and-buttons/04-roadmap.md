# Roadmap

**Status:** steps 1–4 are implemented. Step 5 is planned in detail, at
`564e708`, and 5d was amended at `9c6eb00` so its press sources leave room for a
hold that is on the menu. Step 6, a menu held open by an action, was added after
step 4 and is **rough**; step 7 is the fold-back. The rough step 3 was split in
two when it was re-planned — the buttons (3), and the radial menu with the asset
work it needs (4) — and the old step 4 became step 5. Before starting step 5,
re-read the landed notes of 3 and 4: styles now name a content colour (README
question 9), which 5f's captioned icons on a disc draw in while pressed.

```
#28 ─→ 1 Button + Menu#add ─→ 2 bounds + PanelMenu ─→ 3 styles, TextButton, IconButton ─┬─→ 4 RadialMenu, atlas images, icon wheel ─┬─→ 6 a menu held ─→ 7 fold back
          │                        │                         │                           │                                           │     open by an
          │                        │                         │                           └─→ 5 Row, axis, nil navigation, hotkeys, ──┘     action (needs
          │                        │                         │                                 skill bar (5e–5f need 4b)                   4a and 5d)
          │                        │                         └─ closes: no button without art; a Color allocated per label per draw
          │                        └─ closes: ITEM_COUNT kept equal to add_item by hand
          └─ closes: no other kind of button can exist
```

5a–5d (layouts, axis, `navigation: nil`, hotkeys) depend on nothing after step 2
and could land before step 4; 5e–5f need step 4's atlas images. Step 6 needs
`RadialMenu` (4a) and 5d's instant press and generalized "seen up" rule, and
nothing from 5a–5c or 5e–5f.

## What was measured before re-planning steps 3–5

| | |
|---|---|
| Commit | `564e708` (step 2 merged) |
| `rake spec` | 1520 examples, 0 failures, 2.8 s |
| `spec/rgame/engine/ui/` | 161 examples |
| UI source | 10 files, 797 lines |
| `PanelButton#on_draw` allocations, 100,000 draws, renderer stub coercing colours as `Core::Renderer#packed` does | **100,002** — one `Color` per draw, from `LABEL_COLOR = [46, 34, 24]` |
| `OptionButton#on_draw`, same | **400,002** — four per draw: label, two chevrons, value |
| `Color.coerce`, 100,000 calls | Array **100,003**; `Color` 2; `nil` 2 |
| Layout constructions outside `lib/` and `spec/` | `Column.new` 4 (`game_menu`, `menu_navigation` ×2, inventory), `Ring.new` 1 (`radial_menu`) |
| `Pointing.new` / `Stepping.new` passed explicitly outside `lib/` and `spec/` | 1 / 0 |
| `f(layout: 1, **{ layout: 2 })` under `ruby -W` | takes **2**, no warning — a preset forwarding `**` is silently overridden |
| Draw-call `z` defaults | shapes **50**, images **0**, text **10**, per node — a shape style drawn with no `z:` covers the button's own label and icon |
| Kenney *Game Icons*, downloaded | 105 icons, every one **50×50** (1x) and **100×100** (2x); white variant is RGB 255 everywhere with alpha only; glyphs sit in about 32×32 of the 50 |
| 8 of those icons as separate 1x PNGs / as one 400×50 strip | **121,436 B** / **2,088 B** — each file carries Adobe XMP metadata; all of `examples/assets` is 126 KB |
| Image sampling | `GL_NEAREST` for min and mag (`graphics/image.c`), so only integer `scale:` is clean |

> **Every step that only moves code leaves the driven reports of `game_menu`,
> `menu_navigation` and the `tiled_world` inventory byte-identical** against the
> commit before it, with `--seed 1` and a fresh `RGAME_SAVE_DIR`.

Steps 1 to 3 are each worth landing if the rest of the plan is abandoned:

| Step | Defect it closes |
|---|---|
| 1 | A menu can only ever hold a nine-slice `MenuItem`; no game can add a button of its own |
| 2 | A panel sized from a hand-kept item count overflows silently when an item is added |
| 3 | A menu cannot be prototyped without a UI atlas; every shipped button allocates a `Color` per label per frame |

---

## Step 1 — `UI::Button`, and a menu that is handed its buttons

**Why first.** Every other requirement is blocked on it: nothing else can be put
in a menu until the menu stops constructing what goes in it.

### 1a. Extract `UI::Button` from `MenuItem`

`lib/rgame/engine/ui/button.rb`, the skeleton in
[03-design.md](03-design.md#uibutton). `MenuItem < Button` keeps only its drawing
and `STYLE`; `state` becomes public on `Button`. `label:` becomes optional.
`focused=` calls `on_focus_changed` only on a change. No caller changes.

Rules the tests pin:

1. `state` is `:disabled` whenever disabled, whatever else is true; `:pressed`
   only when focused and pressed; `:focused`; otherwise `:idle`.
2. `activate` on a disabled button returns nil and emits nothing.
3. `on_focus_changed` is called once per change, never on a repeated assignment.
4. `adjust` answers nil.

Tests: `spec/rgame/engine/ui/button_spec.rb` — the four rules, each a case;
`menu_item_spec.rb` keeps only its drawing examples.

### 1b. `Menu#add(button)`, and the callers move to it

`add` raises `TypeError` for anything that is not a `UI::Button`. `add_item`,
`add_option` and `style:` are removed; `items` becomes `buttons`. `Menu#focus`
assigns only where focus changed. `MenuItem` is renamed `PanelButton` and
`OptionItem` `OptionButton`, in the same commit as the callers, including
`spec/example_assets_spec.rb`, which reads `MenuItem::STYLE`. The five menus under
`examples/` and `test_projects/` build their buttons.

Tests: `menu_spec.rb` — `add` returns the button; `add` refuses a plain `Node2D`
and a String; a subclass of `Button` written in the spec, with its own
`on_draw`, is focused and activated like a shipped one; `pointing_spec.rb` and
`option_item_spec.rb` build their buttons.

### 1c. Press, release, and a visible pressed state

`Button#activate_on:`, the press-must-start-here rule, `PRESS_FEEDBACK`, and
`state` reporting `:pressed` without requiring focus — as settled under open
question 6. This is the one sub-step
of step 1 that **changes** driven reports on purpose, so the invariant is checked
against 1b's commit, not `main`, and each difference is stated: activation a tick
later on a tap under `:release`, and `:button_pressed` appearing where a one-tick
press used to leave none.

Rules the tests pin:

1. Under `:release`, a tap presses on the down tick and activates on the up tick;
   moving focus while held activates nothing.
2. Under `:press`, a tap activates on the down tick and stays pressed for
   `PRESS_FEEDBACK`, then returns to focused; a longer hold stays pressed until
   released.
3. **A menu added by an activation does not activate from the same press**, and
   does not draw pressed while that key stays down — the measured double
   activation, as a spec.
4. Time enters through `update(dt)` only; a spec advances it by passing seconds.
5. Pressing does not move focus.
6. Whatever a paused menu does to a running countdown is decided and pinned: a
   menu hidden in `on_activated` and shown again does not reappear pressed.

Tests: `button_spec.rb` and `menu_spec.rb`, for each rule. `game_menu` and
`menu_navigation` are driven again, and their scripts re-read: a `press` is one
tick down and one up, so under `:release` every activation they assert moves by
one tick.

### 1d. Documentation

`docs/api/ui.md`: `Button` gets the section `MenuItem` has, with "a button of your
own" shown as a subclass; the menu table loses `add_item`/`add_option`.
CHANGELOG: under the existing `UI::Menu` entry.

**Verify.** `rake spec` green; RuboCop clean; the invariant above; a spec-defined
button drawing through `FakeRenderer` in a menu. `Menu#on_control` still 0
allocations under `Stepping`.

**Landed.** Four commits, one per sub-step, on branch `menu-buttons`.

- **1a** `UI::Button` (`lib/rgame/engine/ui/button.rb`): `label` optional,
  `enabled`, `focused?`, public `state`, `focused=` calling a blank
  `on_focus_changed` only on a change, `activate`, `adjust → nil`. `MenuItem < Button`
  kept `STYLE` and its drawing.
- **1b** `Menu#add(button)` raising `TypeError`; `add_item`, `add_option`,
  `style:` gone; `items` → `buttons`; `Navigation#on_items_changed` →
  `on_buttons_changed`; `Menu#focus` assigns only to the buttons whose focus
  changed. `MenuItem` → `PanelButton`, `OptionItem` → `OptionButton`, files and
  specs renamed with them. The four callers construct `PanelButton`s.
- **1c** `activate_on: :release | :press` (anything else raises),
  `PRESS_FEEDBACK = 0.1` counted in `Button#update`, and `Button#press`,
  `#release`, `#cancel_press` as the menu's side. `state` is *disabled, else
  pressed, else focused, else idle*.
- **1d** `docs/api/ui.md` (`Button`, "A button of your own", "When a press
  activates", `PanelButton`, `OptionButton`), the CHANGELOG's `UI::Menu` entry,
  and the old names in `docs/api/examples.md`, `docs/project_structure.md` and
  the write-example skill.

Suites: `rake spec` **1499 examples, 0 failures** (1447 before); `spec/rgame/engine/ui/`
**140** (88 before). RuboCop clean on all 20 changed Ruby files. No C and no Core
file changed, so `make test` and `rake spec:core` were not rerun.

Invariant, `--seed 1`, fresh `RGAME_SAVE_DIR`: after 1a and after 1b, `game_menu`,
`menu_navigation`, the `tiled_world` inventory and both `radial_menu` scripts are
**byte-identical** to `main`. After 1c, measured against 1b:

| Report | Change | Why |
|---|---|---|
| `game_menu` | `nine_slice` 160 → 164, `text` 520 → 523, hud layers 960 → 964 | Resume activates on the up tick, so the panel and three buttons draw one more frame |
| `menu_navigation` | `nine_slice` 2350 → 2348, `text` 4529 → 4520, `circle` 44 → 43, `line` 88 → 86 | Settings and Play each activate one tick later: one frame less of settings, one fewer frame of play |
| inventory, `radial_menu` ×2 | none | their scripts never confirm, or the drive ends before a difference reaches the report |

`:button_pressed` counted with a probe on `Renderer#nine_slice` over 600 ticks:
`game_menu` **0 → 1** (Resume is now seen pressed on its down tick), and
`menu_navigation` **138 → 2**. That second number was a bug nobody had measured:
on `main` the title's Settings button stayed frozen `pressed` under the settings
screen for its whole stay, because a covered scene is not controlled and `pressed`
was only ever cleared by the next control.

Rules pinned, and each guard mutation-checked (deleting it fails the examples
written for it): the `armed` check fails 4 submenu examples, `cancel_press` fails
2 hide-and-show examples, the focus-loss release fails 2.

What the sketch got wrong:

- **`pressed=` did not survive.** The design's `pressed=(value)` setter cannot
  express "a press this button saw start". The menu now calls `press`, `release`
  and `cancel_press`, and the button owns `@held` and the feedback. Step 4's
  hotkey "always activates on press, ignoring `activate_on:`" needs a way into
  `press` that ignores `activate_on`, which does not exist yet.
- **"A press this button saw start" is two rules, one per menu and one per button.**
  A submenu's button *is* focused when the press edge arrives in the same
  traversal, so focus alone could not tell. The menu takes no press until it has
  seen `ui_confirm` up (initially false). One consequence: a menu refuses a press
  on the very first tick it is controlled, and specs poll once before pressing.
- **Pausing, open question 6's remaining detail, is decided by input edges, not
  time.** A paused subtree gets no `control` and no `update`, and there is no tick
  counter, so a gap cannot be detected directly. What can be seen is a key that
  is up with no release edge: that press is dropped, feedback and all. Two cases
  stay undetectable and are documented in `ui.md`: a `:press` button hidden
  *after* its release was seen but within `PRESS_FEEDBACK` keeps the rest of its
  feedback; and a covered menu draws whatever state it was covered in.
- **`Menu#on_control` is not 0 allocations under `Stepping` — and was not on
  `main` either.** Over 200,000 control+update ticks with a focus step every 7:
  28,596 objects here, 28,591 on `main`. The `return` inside
  `buttons.size.times do … end` in `Stepping#step` allocates once per step.
  With no focus movement: 21 (`:release`) and 2 (`:press`); `Pointing` 1. Not
  fixed here, being unrelated; step 4 rewrites `Stepping` for its axis and should
  close it.
- **`tiled_world` drops a frame now and then on `main` too** (599 of 600), so the
  invariant was compared on runs reporting ticks equal to frames.
- `STYLE`'s `focus:` key became `focused:` to match `state`; the element names
  are unchanged. `PanelButton` keeps `label:` required, because it draws it.

---

## Step 2 — bounds, and `UI::PanelMenu`

**Why now.** The requirement's "the menu draws its backdrop" cannot be met
without an extent, and the two hand-computed panels are a live misuse that step 1
does not touch.

### 2a. `bounds` on `Column` and `Ring`, read by `Menu`

```ruby
Column#bounds(buttons)  # → [0, 0, item_width, n * item_height + (n - 1) * spacing]
Ring#bounds(buttons)    # → [-radius - w/2, -radius - h/2, 2 * radius + w, 2 * radius + h]
Menu#bounds_x / _y / _width / _height   # copied once per add
```

Rules: an empty menu has zero width and height; `Ring` bounds contain every
slot's rectangle for 1, 2, 3, 5 and 8 buttons (the case where a slot sits off the
axes is the one a naive radius-only box gets wrong).

Tests: `column_spec.rb`, `ring_spec.rb` — the rules; `menu_spec.rb` — readers
follow an `add`, and reading them allocates nothing.

### 2b. `UI::PanelMenu`

```ruby
class PanelMenu < Menu
  def initialize(panel: :panel, padding: 16, **)
  def on_draw(renderer, _view)
    renderer.nine_slice(@panel, bounds_x - @padding, bounds_y - @padding,
                        bounds_width + (@padding * 2), bounds_height + (@padding * 2))
  end
end
```

Tests: `panel_menu_spec.rb` — draws one `nine_slice` enclosing the bounds;
grows when a button is added; draws before its buttons.

### 2c. `game_menu` and the inventory use it

Both delete `panel_width`, `panel_height`, and `game_menu` deletes `ITEM_COUNT`.
Their menus move by `padding` so the drawn result is unchanged — which is what the
invariant checks, and the one place a wrong sign would show.

**Verify.** The invariant, and a mutation: a fourth button added to `game_menu`
grows the panel (the last `nine_slice :panel` height in the report changes), where
before it would not have.

**Landed.** Three commits, one per sub-step, on branch `menu-panel`.

- **2a** `Column#bounds` and `Ring#bounds`, both `[0, 0, 0, 0]` for no buttons;
  `Menu#bounds_x/_y/_width/_height`, zero until the first `add` and copied from
  the layout after `arrange` on each one. `ui.md`'s layout contract names both
  methods.
- **2b** `UI::PanelMenu` (`lib/rgame/engine/ui/panel_menu.rb`) as sketched, with
  `panel` and `padding` readers; a `ui.md` section, and the CHANGELOG's
  `UI::Menu` entry.
- **2c** `game_menu` and the inventory build a `PanelMenu` with
  `padding: PADDING`; `on_draw`, `panel_width`, `panel_height` and `ITEM_COUNT`
  are gone.

Suites: `rake spec` **1520 examples, 0 failures** (1499 before);
`spec/rgame/engine/ui/` **161** (140 before). RuboCop clean on all 11 changed Ruby
files. No C and no Core file changed, so `make test` and `rake spec:core` were not
rerun.

Invariant, `--seed 1`, fresh `RGAME_SAVE_DIR`, 600 ticks: after 2a and 2b,
`game_menu`, `menu_navigation`, the inventory and `radial_menu` are
**byte-identical** to `main`. After 2c, `menu_navigation` and `radial_menu` still
are; `game_menu` and the inventory differ on one line each, and only in the
panel's position arguments:

| Report | `main` | 2c |
|---|---|---|
| `game_menu` | `first(:panel, 0, 0, 212, 150)` | `first(:panel, -16, -16, 212, 150)`, spans for args 1–2 now `-16..0` |
| inventory | `first(:panel, 0, 0, 204, 138)` | `first(:panel, -12, -12, 204, 138)`, spans `-12..0` |

Call counts, sizes, bands and the translates section are unchanged. The panel is
now drawn one translate deeper, inside the menu's own `(padding, padding)`, so to
check the sign a probe accumulated translates and recorded each `:panel` in
screen space: `[40, 40, 212, 150]` ×41 in `game_menu` and `[20, 260, 204, 138]`
×527 in the inventory, **identical on `main` and on 2c**.

Mutation, a fourth `PanelButton` added to `game_menu`: on `main` the panel stays
`212 × 150` behind four buttons, overflowing; on 2c it is `212 × 192`.

What the sketch got wrong:

- **"Byte-identical" could not hold for 2c, and "the menus move by padding" was
  backwards.** The report records a draw's arguments, not where it lands, and
  the panel now draws at `-padding` inside a menu that stays where it was. The
  menus did not move; the panel did, by `-padding`, into the menu's translate.
  The invariant was checked in screen space instead, above.
- **`Ring#bounds` is the whole circle, not the tightest box**, as the sketch's
  formula already implied: a single button in a ring gets a `2r + w` square.
  Kept deliberately and documented, so a backdrop behind a wheel keeps its size
  as buttons are added; step 3's `RadialMenu` backdrop disc wants exactly that.
- **Found, not fixed:** `test_projects/tiled_world/inventory.rb` wraps `def close`
  in `if @open` at class level, where `@open` is nil, so `close` is never defined
  and activating an inventory item would raise `NoMethodError`. No drive script
  confirms in that menu, which is why it has gone unseen. Unrelated to this step.

---

## Step 3 — styles, `UI::TextButton`, `UI::IconButton`

**Why now.** The requirement's three radial variants and its "just text for
prototyping" all need a button that is not a nine-slice, and there is none. Doing
the buttons before `RadialMenu` means step 4's example has something to put in the
wheel.

**What it resembles**, sorted per CLAUDE.md:

- **Generalize.** `PanelButton` is *a background per state, then a centred label*.
  The prototyping button is exactly that with shapes where the nine-slice is. So
  the background becomes a **style** object on the button — Godot draws `Button`
  from a stylebox per state and Unity gives each `Selectable` a transition (see
  [02-prior-art.md](02-prior-art.md)) — and `PanelButton` becomes a `TextButton`
  with a nine-slice style. One label-centring, not two.
- **Generalize.** `IconButton` draws its background from the same style, so a
  round image-only entry is an `IconButton` with a disc `ShapeStyle`, not a third
  shape implementation.
- **Reuse.** `Button` state, `Color.coerce` (once, at construction), the
  `allocate_nothing` matcher.
- **Considered and not merged:** a *menu's* backdrop (`PanelMenu`'s panel,
  `RadialMenu`'s disc) is also "a shape or a nine-slice filling a rect". It has no
  state, so a style would be handed a state it does not have. Left separate.
- **Not a revival of `look:`.** That put the look on the menu (rejected in
  [03-design.md](03-design.md#considered-and-rejected)). A style is held by one
  button, and a button of a game's own still just writes `on_draw`.

### 3a. `UI::NineSliceStyle` and `UI::ShapeStyle` *(pure values)*

A style is anything answering `draw(renderer, state, width, height)`, in the
button's local space. Two ship:

```ruby
class NineSliceStyle
  attr_reader :elements                       # { idle:, focused:, pressed:, disabled: } → element name

  def initialize(idle:, focused:, pressed:, disabled:)
  def with(**changes)                         # a copy with some elements replaced
  def draw(renderer, state, width, height)    # nine_slice(elements.fetch(state), 0, 0, width, height)
end

class ShapeStyle
  SHAPES = %i[rect disc].freeze
  COLORS = { idle: Color.new(52, 48, 62), focused: Color.new(72, 66, 88),
             pressed: Color.new(240, 200, 96), disabled: Color.new(40, 38, 46) }.freeze
  OUTLINE = Color.new(240, 200, 96)
  DEFAULT = new

  def initialize(shape: :rect, colors: COLORS, outline: OUTLINE, border: 3)
  def draw(renderer, state, width, height)
end
```

`ShapeStyle` draws the fill inset by `border` in every state, so a button does not
change size as its state does, and the outline — the whole shape in `outline` —
under it only when focused or pressed. A disc is centred in the slot with radius
`min(width, height) / 2`.

Rules the tests pin:

1. **A style draws at `z: 0` or below**, and names it explicitly: shapes default
   to `z: 50`, which would cover the label and icon every shipped button draws at
   `z: 1` (measured above).
2. `ShapeStyle` refuses a `shape:` outside `SHAPES` with `ArgumentError`, and a
   `colors:` missing a state with `KeyError` naming it — **at construction**, not
   the first frame a button is disabled, which is the late failure `ui.json`'s
   spec already guards against for nine-slices.
3. Colours are coerced once: `colors:` accepts arrays, and `draw` then allocates
   nothing (`allocate_nothing`, a plain renderer stub, all four states).
4. A `nil` colour in `colors:` draws no fill in that state; `outline: nil` draws no
   outline. Not `color: nil`, which the renderer reads as white.
5. The fill's geometry is the same in all four states: `rect(3, 3, w - 6, h - 6)`,
   `circle(w / 2, h / 2, min / 2 - 3)`.
6. `NineSliceStyle#draw` issues exactly `nine_slice(name, 0, 0, width, height)`,
   with no `z:` or `tint:` — the call `PanelButton` makes today, which is what
   keeps 3b's reports byte-identical.

Tests: `spec/rgame/engine/ui/nine_slice_style_spec.rb`,
`spec/rgame/engine/ui/shape_style_spec.rb` — the rules, through `FakeRenderer`.

### 3b. `UI::TextButton`, and `PanelButton` becomes one

```ruby
class TextButton < Button
  LABEL_COLOR = Color.new(240, 236, 224)
  DISABLED_LABEL_COLOR = Color.new(120, 116, 128)

  attr_reader :style

  def initialize(label:, style: ShapeStyle::DEFAULT, label_color: LABEL_COLOR,
                 disabled_label_color: DISABLED_LABEL_COLOR, **)

  def on_draw(renderer, _view)
    @style&.draw(renderer, state, width, height)
    draw_content(renderer)                   # the centred label, at z: 1
  end
end

class PanelButton < TextButton
  STYLE = NineSliceStyle.new(idle: :button_idle, focused: :button_focus,
                             pressed: :button_pressed, disabled: :button_disabled)
  LABEL_COLOR = Color.new(46, 34, 24)
  DISABLED_LABEL_COLOR = Color.new(120, 110, 100)

  def initialize(label:, style: STYLE, label_color: LABEL_COLOR,
                 disabled_label_color: DISABLED_LABEL_COLOR, **) = super
end
```

`OptionButton` keeps its parent and overrides `draw_content` rather than
`on_draw`, so it cannot drop the style by forgetting to draw it. Colours become
`Color`s, which closes the measured 1 and 4 allocations per draw.
`spec/example_assets_spec.rb` reads `PanelButton::STYLE.elements.values`;
`panel_button_spec.rb`'s custom style uses `STYLE.with(idle: :mine)`.

Rules the tests pin:

1. `TextButton.new(label: 'Play')` draws with no atlas registered — the
   prototyping promise, as a spec against a `FakeRenderer` with nothing
   registered.
2. `style: nil` draws only the label.
3. The label is centred in the slot and drawn above everything the style draws.
4. `PanelButton#on_draw` and `OptionButton#on_draw` allocate nothing — measured
   today at 1 and 4 per draw.
5. `PanelButton`'s draw calls, positional arguments and order are unchanged:
   its existing specs pass untouched apart from the two constant reads above.

Tests: `text_button_spec.rb` (new); `panel_button_spec.rb`,
`option_button_spec.rb` gain the allocation examples.

### 3c. `UI::IconButton`

```ruby
class IconButton < Button
  TINTS = { idle: Color.new(200, 200, 212), focused: Color.new(255, 255, 255),
            pressed: Color.new(240, 200, 96), disabled: Color.new(90, 88, 100) }.freeze
  SCALES = { idle: 1, focused: 1, pressed: 1, disabled: 1 }.freeze

  attr_reader :image, :style

  # image: an image id — a registered Symbol or a path String — or nil.
  # label: optional; drawn as a caption along the bottom of the slot.
  def initialize(image:, style: nil, tints: TINTS, scales: SCALES,
                 label_color: TextButton::LABEL_COLOR,
                 disabled_label_color: TextButton::DISABLED_LABEL_COLOR, **)

  def on_draw(renderer, _view)
    @style&.draw(renderer, state, width, height)
    # image(@image, width / 2.0, icon_centre_y, scale: @scales.fetch(state), color: @tints.fetch(state), z: 1)
    # text(@label, centred, height - text_height, z: 1)
  end
end
```

Scales default to 1 because images sample with `GL_NEAREST`: 1.15 of a 50-pixel
icon doubles some pixel rows and not others. Focus shows through tint and style
instead; a game can still pass scales.

**The caption is drawn inside the slot**, and that settles the question the rough
step left for re-planning — whether `Pointing` should read a button's centre
through a method on `Button` rather than `x + width / 2`. It should not. Every
shipped button draws inside the slot its layout gave it, so the slot's centre is
where the button is; `Ring` bounds and a backdrop sized from them stay true. The
icon sits `text_height / 2` above the slot centre when captioned — about 4° off
the button's direction at radius 150, against a 22.5° half-sector for eight
buttons.

Rules the tests pin:

1. With no label the image is centred on the slot; with one, it is centred in the
   space above the caption, and the caption is centred along the bottom edge,
   inside the slot.
2. Tint and scale follow `state`, one case per state.
3. **`image: nil` draws no image and the caption still speaks** — an entry whose
   art is not in yet. An id nobody registered is *not* that case: it is the
   renderer's `KeyError` on the first draw, as for any other image.
4. `tints:` and `scales:` missing a state raise `KeyError` at construction.
5. The style is drawn first and below; image and caption at `z: 1`.
6. `on_draw` allocates nothing, captioned and not.

Tests: `icon_button_spec.rb`, drawing through `FakeRenderer` with a `StubImage`
registered.

### 3d. Documentation

`docs/api/ui.md`: a "Styles" section (the duck type, both shipped styles, a style
of your own in a few lines); `TextButton` and `IconButton` sections; `PanelButton`
rewritten as "a `TextButton` with a nine-slice style". `examples/assets/README.md`:
the line saying `PanelButton`'s label colour is a constant becomes "defaults to".
CHANGELOG under the `UI::Menu` entry.

**Verify.** `rake spec` green; RuboCop clean on changed files. Driven reports of
`game_menu`, `menu_navigation`, the inventory and both `radial_menu` scripts
**byte-identical** to `main` after each of 3a–3c (`--seed 1`, fresh
`RGAME_SAVE_DIR`). The allocation examples above. And the composition the
requirement names — *one* `Column` menu holding a `PanelButton`, a `TextButton`,
an `IconButton` and a spec-defined `Button` subclass, stepped through with
`Stepping` and drawn through `FakeRenderer`: every button draws in its own slot,
the focused one in its focused look.

**What this step does not deliver.** Buttons sized to their label (see the
verdict), a toggle or checked state, and animated state changes.

**Landed.** Four commits, one per sub-step, on branch `menu-button-styles`.

- **3a** `UI::NineSliceStyle` (`elements`, `with`, `draw`) and `UI::ShapeStyle`
  (`shape`, `colors`, `outline`, `border`, `DEFAULT`), both in
  `lib/rgame/engine/ui/`. Fill at `z: 0`, outline at `z: -1`.
- **3b** `UI::TextButton`, with `style`, `label_color` and `disabled_label_color`
  readers. `PanelButton < TextButton` keeps only `STYLE`, its two colours, and an
  `initialize` that changes the defaults. `OptionButton` overrides
  `draw_foreground`. `spec/support/quiet_renderer.rb` is the allocation-free
  renderer the draw measurements run against.
- **3c** `UI::IconButton` as sketched, and the composition spec in
  `menu_spec.rb`, "buttons of every kind in one menu".
- **3d** `docs/api/ui.md` ("Styles", "A style of your own", `TextButton`,
  `PanelButton` rewritten, `IconButton`, "Getting the art on screen"), the
  CHANGELOG's `UI::Menu` entry, `examples/assets/README.md`, and a line in
  `docs/plans/basic-examples.md` marking its label-colour constraint as gone.

Suites: `rake spec` **1585 examples, 0 failures** (1520 before);
`spec/rgame/engine/ui/` **226** (161 before). RuboCop clean on all 18 changed Ruby
files. No C and no Core file changed, so `make test` and `rake spec:core` were not
rerun.

Invariant, `--seed 1`, fresh `RGAME_SAVE_DIR`: `game_menu`, `menu_navigation` and
the inventory at 600 ticks, `radial_menu` at 600 and `radial_menu_pad` with
`--gamepad` at 112 are **byte-identical** to `main` after each of 3a, 3b and 3c.
`main` was driven twice first and matched itself.

Allocations, `allocate_nothing` over 1,000 draws against `QuietRenderer`, which
coerces colours as `Core::Renderer#packed` does: `PanelButton#on_draw` **1 → 0**
per draw, `OptionButton#on_draw` **4 → 0** — the new examples run against the
old implementation report exactly the plan's numbers. `TextButton`, `IconButton`
(captioned and not) and `ShapeStyle` (both shapes, all four states) **0**.

Guards mutation-checked, each deletion failing the examples written for it:
the colour coercion in `ShapeStyle` (3) and in `IconButton`'s tints (1), the
outline's `z:` (2), `outline: nil` (1), `style&.` in `TextButton` (3),
`image: nil` (1), and the caption's height being reserved only with a label (1).

What the sketch got wrong:

- **`draw_content` is taken.** `Node2D` already has a private
  `draw_content(renderer, view)` — the machinery that runs components and then
  `on_draw` — so a `TextButton#draw_content(renderer)` replaced it and every draw
  raised `ArgumentError`. The hook is `draw_foreground(renderer)`. A private
  method on `Node2D` is a name any subclass can shadow silently; this one failed
  loudly only because the arity differed.
- **Three constant reads, not two.** `spec/rgame/engine/ui/panel_menu_spec.rb`
  also read `PanelButton::STYLE.values`. All three now read `STYLE.elements`.
- **The four state names had no home.** `ShapeStyle` and `IconButton` both check
  a table against the list, so it became `Button::STATES`, next to `state`,
  which answers them. `NineSliceStyle` spells them as keywords instead, so a
  missing one is an `ArgumentError` from Ruby itself.
- **`docs/api/ui.md`'s "A button of your own" example was a class named
  `TextButton`**, which would now shadow the shipped one for anyone pasting it.
  Renamed `EdgeButton`.
- Rule 6 of 3a is pinned with an `instance_double(FakeRenderer)` rather than
  through a registered nine-slice, because what it asserts is the call and its
  absent keywords.

---

## Step 4 — `UI::RadialMenu`, atlas images, and a wheel of icons

**Why now.** The wheel's backdrop and pointer are the reusable half of
`examples/radial_menu`, and a wheel of pictures is what the requirement calls
"very common in games". Step 3 supplies the round image-only button; this step
supplies the menu and a way to get the pictures on screen.

### 4a. `UI::RadialMenu`, and the example moves to it with its current buttons

```ruby
class RadialMenu < Menu
  BACKDROP = Color.new(44, 40, 52)
  DEAD_ZONE = Color.new(76, 72, 88)
  POINTER = Color.new(240, 236, 224)

  def initialize(radius:, button_width:, button_height: button_width,
                 dead_zone: Pointing::DEAD_ZONE, padding: 16,
                 backdrop: BACKDROP, dead_zone_color: DEAD_ZONE, pointer: POINTER, **)
    # raises ArgumentError if ** holds :layout or :navigation
    # super(layout: Ring.new(...), navigation: Pointing.new(dead_zone:), **)

  def on_draw(renderer, _view)
    # backdrop disc: max(bounds_width, bounds_height) / 2 + padding
    # dead-zone disc: navigation.dead_zone * layout.radius
    # pointer: line from the origin and a tip, clamped to the ring
  end
end
```

The drawing moves out of `ColourWheel#on_draw` verbatim, colours included. The
swatch stays the example's: it is drawn by a node added *after* the menu, because
between nodes tree order decides and a parent draws under its menu's backdrop.

Rules the tests pin:

1. **`layout:` or `navigation:` passed to it raises `ArgumentError`** — forwarded
   through `**` they would silently replace the ring and the pointing (measured).
2. `layout` is a `Ring` with the given radius and sizes; `navigation` a `Pointing`
   with the given dead zone.
3. Backdrop, dead zone, pointer, in that order, all before its buttons.
4. Each colour set to `nil` omits that part.
5. A stick at (1, 1) puts the tip at (106.1, 106.1) with radius 150 — the clamp,
   and the number the drive script already records.
6. The backdrop's radius is the same with one button as with eight, because
   `Ring#bounds` is the whole circle (step 2's landed note).
7. `on_draw` allocates nothing with the stick deflected.

Tests: `radial_menu_spec.rb`.

**Invariant for 4a**, which cannot be byte-identical because the backdrop now
comes from bounds and the swatch moved: both `radial_menu` scripts report the same
caption at every budget their headers list, the same per-frame counts (four
`circle`, one `line`, eight `nine_slice`, ten `text`), and the same tip span
(−106.1..150.0). The backdrop radius changes from 194 to `198 + padding`; the
example passes `padding: 0` and the header records 198.

### 4b. `UiAtlas` grows `images` *(Core)*

```json
{
  "image": "icons.png",
  "images": {
    "home": { "x": 0,  "y": 0, "w": 50, "h": 50 },
    "gear": { "x": 50, "y": 0, "w": 50, "h": 50 }
  }
}
```

`UiAtlas#images` is a Hash of Symbol → `Image#subimage`, beside `nine_slices`, and
`register_ui_atlas` registers each with `register_image`. So
`renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))` makes
`IconButton.new(image: :home)` draw, with no loop in the game. Decided — see
"Named icons reach the renderer through a UI atlas" in the
[README](README.md#decisions-already-taken), and open question 8 there for the
alternatives that were rejected.

Rules the tests pin:

1. One subimage per entry, cut from its own rectangle; no `images` key, or `null`,
   is no images; an atlas may have both kinds.
2. A rectangle the sheet refuses raises `ArgumentError` naming the entry, like a
   nine-slice element already does.
3. Both renderers register every image under its own name: after
   `register_ui_atlas`, `renderer.image(:name, 0, 0)` draws on the real one and on
   `FakeRenderer`.

Tests: `spec_core/rgame/core/ui_atlas_spec.rb` (1, 2); the contract in
`spec/support/shared_examples/a_renderer.rb` gains 3, next to "registers every
element of a UI atlas under its own name", so it runs against both;
`FakeRenderer#register_ui_atlas` gains the loop.

### 4c. `examples/assets/icons.png` + `icons.json`

Eight white 1x icons from Kenney's *Game Icons*, laid in a 400×50 strip:
`home`, `gear`, `save`, `star`, `trophy`, `audioOn`, `musicOn`, `locked`, named
in the descriptor in snake case (`audio_on`). 1x rather than 2x because a 50-pixel
icon in a 64-pixel slot draws at scale 1, and the chosen icon in the middle at
scale 2 — both integers, which `GL_NEAREST` needs. The strip is about 2 KB against
121 KB for the eight files as shipped (measured).

Provenance in `examples/assets/README.md`: source URL, CC0 `license.txt`, the eight
source paths, and that only the sheet and descriptor are ours.

Tests, in `spec/example_assets_spec.rb`, `describe 'icons.json'`:

1. Every image's rectangle lies inside `icons.png`.
2. Every icon `examples/radial_menu/main.rb` names is declared — read from its
   `ICONS` table with an anchored match, as `glyphs.json`'s example reads
   `GLYPH_COLUMN`.

### 4d. `examples/radial_menu` becomes a quick menu of icons

The colour wheel becomes the quick menu the icons were chosen for, keeping its
eight directions and its disabled entry in the same slots, so each drive script's
path through the wheel is unchanged:

| Slot | Was | Becomes |
|---|---|---|
| 0 N | Red | Home |
| 1 NE | Orange | Settings |
| 2 E | **Yellow** | **Save** |
| 3 SE | Green | Favourite |
| 4 S | **Teal** | **Trophies** |
| 5 SW | **Blue** | **Sound** |
| 6 W | Purple | Music |
| 7 NW | Locked | Locked (disabled) |

`IconButton`s, image-only, sharing one disc `ShapeStyle`, in 64×64 slots; the
chosen icon drawn at scale 2 in the middle; `ui.json` no longer registered, since
nothing draws a nine-slice. The header's "What this example does not solve: Icons"
paragraph goes.

Both drive scripts keep their inputs. Their headers are rewritten from the run:
`Chosen: Save` where they said Yellow, `Chosen: Trophies` where Teal, and the
per-frame counts — eight `image`, nine once something is chosen; no `nine_slice`;
and the circles of eight discs, an outline while one is focused, plus backdrop,
dead zone and tip.

### 4e. Documentation

`docs/api/ui.md`: a `RadialMenu` section, and "Getting the art on screen" gains
images. `docs/api/assets.md`, "UI atlases": the `images` key.
`docs/api/examples.md`: the radial entry. CHANGELOG. `docs/plans/basic-examples.md`,
if it still exists: asset **D**'s row and the radial example's entry are done.

**Verify.** `rake spec` and `rake spec:core` green, the latter because 4b changes
Core; RuboCop clean. 4a's invariant above. After 4d, both scripts driven at every
listed budget with the new captions, and `examples/radial_menu` run by hand once
to look at the icons on the disc — tint is a multiply, so the pack's white must
read as the tint colours and not as white.

**What this step does not deliver.** A wheel centred on the view (the example's
existing limit), captions on a wheel, and any icon beyond the eight.

**Landed.** Five commits, one per sub-step, on branch `menu-radial`, and a sixth
that settles README question 9, which this step raised.

- **4a** `UI::RadialMenu` (`lib/rgame/engine/ui/radial_menu.rb`) as sketched,
  with `padding`, `backdrop`, `dead_zone_color`, `pointer` and `backdrop_radius`
  readers; `spec/support/quiet_renderer.rb` gained `line`. `examples/radial_menu`
  drew its wheel through it with `padding: 0`, the swatch moving into a `Swatch`
  node added after the menu.
- **4b** `UiAtlas#images`, and both `register_ui_atlas`es register them. The
  contract's "registers every element of a UI atlas" gained a sibling for images.
- **4c** `examples/assets/icons.png` (2,088 B) + `icons.json`, provenance in
  `examples/assets/README.md`, and an `icons.json` group in
  `spec/example_assets_spec.rb`.
- **4d** `examples/radial_menu` as a quick menu: `QuickMenu` with an `ICONS`
  table, `IconButton`s on one disc `ShapeStyle`, a `ChosenIcon` node drawing the
  choice at scale 2, `icons.json` registered in place of `ui.json`, and default
  `padding` (backdrop radius 198.0 again, from 182 + 16).
- **Question 9** `content_color(state)` on styles: `ShapeStyle` takes
  `content:` (`ShapeStyle::CONTENT`, dark while pressed), `NineSliceStyle`
  answers `nil`, and `TextButton` (so `OptionButton`) and `IconButton` draw in
  it where it names a colour. The example's dark-tint workaround is gone.
- **4e** `docs/api/ui.md` (`RadialMenu`; `Pointing` and `IconButton` pointing at
  it; "Getting the art on screen" gains images; "Styles" gains the content
  colour), `docs/api/assets.md` (the
  `images` section), `docs/api/examples.md`, the CHANGELOG (an "Added" entry for
  atlas images, `RadialMenu` in the `UI::Menu` entry), and asset **D** in
  `docs/plans/basic-examples.md`.

Suites: `rake spec` **1645 examples, 0 failures** (1585 before; 1628 before
question 9); `spec/rgame/engine/ui/` **262** (226 before); `rake spec:core` **375, 0
failures**, rerun because 4b changes Core. RuboCop clean on every changed Ruby
file. No C changed, so `make test` was not rerun.

4a's invariant, `--seed 1`, fresh `RGAME_SAVE_DIR`, against `main`: every budget
of both scripts (35, 65, 100, 130, 180 and 600; pad 38, 60, 112) reports the same
caption, the same call counts and the same tip spans (−106.1..150.0, and
0..35.3 for the pad nudge). The lines that differ, and why:

| Line | `main` | 4a |
|---|---|---|
| `circle first(...)` | `(0, 0, 194)` | `(0, 0, 198.0)` — backdrop from bounds |
| `circle last(...)` | the pointer's tip | `(0, 0, 34)` — the swatch, now drawn after the menu |
| `layers per band` at 600 | `7200 × world` | `7800 × world` — one more node per frame, the `Swatch` |

After 4d, from the run: captions `Save` where `Yellow` was and `Trophies` where
`Teal`, at every budget. At 600 ticks: 2 `text` per frame; 5377 `image` (8 per
frame, plus the chosen icon on 577 frames); 6660 `circle` (11 per frame —
backdrop, dead zone, tip, eight discs — plus the outline on the 60 frames
something is focused); 600 `line`; no `nine_slice`. Both script headers record
these. `game_menu`, `menu_navigation` and the inventory, 600 ticks, are
**byte-identical** to `main`.

Allocations: `RadialMenu#on_draw` with the stick deflected passes
`allocate_nothing`; by hand, 200,000 draws and 20,000 draws of eight wheel buttons
against `QuietRenderer` each count 1 object, the loop's own.

Guards mutation-checked: the `layout:`/`navigation:` refusal (2 examples), the
tip clamp (1), `if @backdrop` (1), `if @pointer` (1), `+ @padding` (1); the images
loop in the real `register_ui_atlas` (1 contract example), in `FakeRenderer`'s (1),
and the element name on a refused image rectangle (2).

**Looked at by hand**, as the Verify block asked: a screenshot under Xvfb with
Enter held on Trophies. The white art does read as the tints — grey at rest,
white focused, dim on Locked, the chosen gear doubled and sharp in the middle —
and, after question 9, the pressed trophy is dark on the gold disc with nothing
overridden by the example. Question 9's change leaves every driven report above
byte-identical (colours are keywords, which the report does not keep), and was
mutation-checked: dropping the content colour from `TextButton` fails 2
examples, from the icon's tint 1, from the caption 1, the `respond_to?` guard 12
(forced true) and 2 (true for any style), and the coercion in `ShapeStyle` 3.
Drawing pressed on a content-naming style allocates nothing, for both buttons.

What the sketch got wrong:

- **A pressed icon on a `ShapeStyle` disc was invisible, and step 3 had shipped
  it.** `ShapeStyle::COLORS` filled a pressed shape with `(240, 200, 96)` and
  `IconButton::TINTS` tinted a pressed image the same gold. Rendering the
  candidate fixes showed a second case nobody had measured: `TextButton`'s light
  label on that fill is 1.4:1. No report can show either, because a tint and a
  fill are keywords, which is exactly why the step asked for a look. The first
  fix was a dark tint passed by the example. It was replaced by README question
  9's answer, content colours on styles, which changes step 3's API. **For 5f:** a
  caption on a disc also takes the content colour, and part of a caption at the
  bottom of a round slot sits outside the disc, over the ground, so the pressed
  caption is worth a look there.
- **"The same per-frame counts" held; the report did not.** Moving the swatch to
  a node of its own adds a layer per frame and makes it the last `circle`, as the
  table above shows. The sketch's padding plan held: `padding: 0` gave 198 in 4a,
  and 4d took the default back to 198 with 64-pixel slots.
- **4c's second asset example could not land in 4c.** It reads `ICONS` out of
  the example, which only exists after 4d, so it went in with 4d.
- **Anything passed to `register_ui_atlas` must now answer `images`.** The
  contract's existing nine-slice example built a `Struct.new(:nine_slices)`,
  which raised `NoMethodError` after 4b; it gained the member. `UiAtlas` is the
  only atlas in the project, so nothing else broke.
- `examples/assets/README.md` first said "in snake case", which
  `spec/game_references_spec.rb` reads as the name of a test project. It says
  `snake_case`, the spelling that spec allows.

---

## Step 5 — `Row`, a stepping axis, `navigation: nil`, hotkeys, `examples/skill_bar`

**Why this can be detailed now.** 5a–5d rest only on `Menu`, `Button`, `Column`
and `Stepping`, which have landed, and the two inputs the rough step was waiting
on are known: a way into `press` that ignores `activate_on:`, and the allocation
in `Stepping#step` (step 1's landed note). 5e–5f use step 3 and 4's API, so
re-read those landed notes first.

### 5a. `UI::Row`, and a layout's `axis`

Writing both `bounds` side by side, as the rough step asked, shows one
computation with width and height and x and y swapped. Godot's `HBoxContainer` and
`VBoxContainer` are one `BoxContainer`, and Unity's two groups one
`HorizontalOrVerticalLayoutGroup`, for the same reason. So:

```ruby
class Stack
  AXES = %i[vertical horizontal].freeze
  attr_reader :axis, :item_width, :item_height, :spacing
  def initialize(axis:, item_width:, item_height:, spacing: 8)
  def arrange(buttons)    # index * (extent + spacing) along the axis, 0 across it
  def bounds(buttons)     # [0, 0, w, n*h + (n-1)*s] or [0, 0, n*w + (n-1)*s, h]
end

class Column < Stack
  def initialize(item_width:, item_height:, spacing: 8)   # axis: :vertical
end

class Row < Stack
  def initialize(item_width:, item_height:, spacing: 8)   # axis: :horizontal
end

Ring#axis   # → :vertical, which is what Stepping round a ring does today
```

`Column` and `Row` spell out their keywords rather than forwarding `**`, so
`Column.new(axis: :horizontal)` is an unknown keyword, not a silently ignored one.

Rules: `Row` is `Column` mirrored, including `[0, 0, 0, 0]` for no buttons; a
`Stack` refuses an axis outside `AXES`; every shipped layout answers `axis`.

Tests: `column_spec.rb` unchanged and green; `row_spec.rb` (new), `ring_spec.rb`
gains `axis`.

### 5b. `Stepping` steps along the layout's axis

```ruby
class Stepping < Navigation
  def initialize(axis: nil)   # nil: the layout's
  attr_reader :axis           # resolved in attach
end
```

**The default follows the layout**, so `Menu.new(layout: UI::Row.new(...))` steps
left and right with nothing else said. An axis the navigation has to be told
separately is a `Row` stepped by up and down the day somebody forgets it.
`attach` reads `menu.layout.axis` once and keeps the four action names in ivars;
a layout that has no `axis` is a `NoMethodError` when the menu is built. `step`
becomes a `while` loop, which closes the measured allocation.

Rules the tests pin:

1. Vertical is today's behaviour: the existing examples pass untouched.
2. Horizontal: `ui_left`/`ui_right` move focus and wrap; `ui_up`/`ui_down` go to
   `adjust`.
3. `Stepping.new(axis:)` overrides the layout's; anything outside
   `Stack::AXES` raises `ArgumentError` on attach.
4. A `Row` with the default navigation steps with left and right — the pair, as
   one example.
5. `Menu#on_control` under `Stepping` allocates nothing with a focus step every 7
   ticks over 200,000 — measured **28,596** at step 1.

Tests: `stepping_spec.rb` (new — `Stepping` is covered only through
`menu_spec.rb` today), and the allocation example in `menu_spec.rb`.

### 5c. `navigation: nil`

`Menu` calls its navigation in three places, each becoming `&.`. No null class
(see [03-design.md](03-design.md#navigation-changes)).

Rules: built with `navigation: nil` a menu focuses nothing on `add`, and
`ui_confirm` activates nothing; `menu.navigation` is `nil`; leaving the keyword
out is still a `Stepping`; `focus(index)` called by the game still focuses, and a
confirm then acts on that button — a game calling `focus` has said something, the
same way passing `nil` has.

Tests: `menu_spec.rb`, `describe 'with no navigation'`.

### 5d. Hotkeys: `Button hotkey:`, and a press knows its source

A hotkey needs everything confirm already does — a press it saw start, release,
cancel on a missed release, feedback — so it goes through the *same* rule rather
than a second copy. What the button needs to know is **who is holding it**,
because two sources on one button must not end each other's hold:

```ruby
class Button < Node2D
  def initialize(label: nil, enabled: true, activate_on: :release, hotkey: nil, **)
  attr_reader :hotkey                 # an action name, or nil

  def press(source = :confirm)        # :confirm or :hotkey; ignored while already held
  def release(source = :confirm)      # only ends a hold `source` started
  def cancel_press(source = :confirm) # likewise
end
```

A press is **instant** when `source == :hotkey` or `activate_on == :press`: it
activates and starts `PRESS_FEEDBACK`. Otherwise it waits for `release`. The
button records whether an activation is still pending, so a hotkey's release on
a `:release` button activates nothing a second time.

`Menu#on_control` becomes navigation → hotkeys → confirm. The per-source "seen up"
bit becomes one method taking the button, the action, the source and the stored
bit: confirm keeps its single flag, and each button's hotkey gets one in an array
grown on `add`, so the hot path allocates nothing.

**Amended at `9c6eb00`, for step 6.** Step 6 adds a third press, a menu's
`trigger`, whose hold is on the *menu*: it starts with nothing focused, survives
focus moving, and on release hands the focused button an instant press (see
[03-design.md](03-design.md#a-hold-belongs-to-whoever-it-was-started-on)). 5d
does not build it, but must not close the door on it:

- **The instant press is its own entry point**, not a branch reachable only
  through `source == :hotkey` — step 6 calls it for a trigger's release. How it
  is spelt (`press(:hotkey)` reused, or a separate `activate_with_feedback`) is
  5d's call; what it must not do is require the button to be holding anything.
- **The "seen up" method takes no button.** Its question — has this action been
  up since this menu could see it — is about the menu and the action, and a
  trigger has a bit and no button. The button is passed where the press lands,
  not where the bit is kept.
- **The shared example group "a press source" covers holds on a button.** Its
  rules 7 and 8 are about two holds on one button, which a trigger never is, so
  the trigger gets its own examples in step 6 rather than a third run of the
  group.

Rules the tests pin:

1. **A hotkey activates its button on the press edge**, whatever `activate_on:`
   says, and focus does not move.
2. The hotkeyed button reports `:pressed` for at least `PRESS_FEEDBACK`, or while
   held, whether or not it is focused.
3. A hotkey's release activates nothing, under either `activate_on:`.
4. **A menu added by a hotkey activation does not fire from the same press**, and
   a button added while its hotkey is down never presses from it — confirm's
   double-activation rule, for the second source.
5. A hotkey that comes up with no release edge — the menu was paused — cancels its
   press and its feedback.
6. A disabled button ignores its hotkey.
7. **Two sources on one button:** confirm holding a `:release` button, then its
   hotkey pressed and released — nothing activates and the button stays pressed;
   confirm released — it activates, once.
8. Losing focus drops a confirm hold and keeps a hotkey hold.
9. A hotkey and confirm pressed on the focused button on the same tick activate
   it once.
10. Hotkeys work under `Stepping`, `Pointing` and `nil`.
11. An undeclared action raises on the first control, naming it (`Actions`
    already does; pinned here so a menu cannot swallow it).
12. `Menu#on_control` with five hotkeyed buttons allocates nothing.

Tests: rules 1–9 as a shared example group, "a press source", run once for confirm
and once for a hotkey — so the two cannot drift, which is the point of routing
both through one method. `button_spec.rb` for the source bookkeeping,
`menu_spec.rb` for 10–12.

### 5e. Skill-bar art

Kenney's *Cursor Pack* tools, open question 7: `tool_wand`, `tool_wrench`,
`tool_torch`, `tool_hammer`, `tool_watering_can`, laid in one strip as
`examples/assets/skills.png` with a `skills.json` of `images` (step 4b), provenance
in the README, and the same two `example_assets_spec.rb` examples as `icons.json`.
Which style — `Basic`, tinted directly, or `Outline`, whose black border survives a
tint — and which size, 32 or 64, is picked by drawing both on the example's
background, and recorded. A separate atlas from `icons.json`: one pack per file
keeps each file's provenance one paragraph.

### 5f. `examples/skill_bar`

A farming-sim bar of the five tools: a `Menu` with a `Row` and the default
`Stepping`, `IconButton`s with captions — the requirement's "images with an
explaining text below", which step 4's wheel does not show — on a disc
`ShapeStyle`, built `activate_on: :press` (the Xenoblade case), with hotkeys
`:skill_1`…`:skill_5` declared on `KEY_1`…`KEY_5` through
`InputMap.default.merge`. Two captions, from frozen tables keyed by state as
`examples/save_load` does: which tool is focused and which was last used.

`tools/drive/examples/skill_bar.rb`, and what its header asserts:

- `ui_right` twice, Enter: `Used: Torch` on the press tick, `Focused: Torch`.
- `KEY_5`: `Used: Watering can`, and **still `Focused: Torch`**.
- `KEY_2` held for 20 ticks: used once, not twenty times.
- `KEY_1` while the bar is focused on the Wand: one use, not two.
- That the hotkeyed Watering can drew pressed while unfocused, for at least six
  frames (0.1 s at 60 Hz), counted with a probe as step 1c counted
  `:button_pressed` — the report keeps positional arguments only, and a style's
  colours are keywords.

### 5g. Documentation

`docs/api/ui.md`: `Row` beside `Column`, the layout contract gains `axis`,
`Stepping`'s axis, "A menu with no navigation", "Hotkeys" (including the
two-source rule), and "What this is not" loses nothing — grids are still out.
`docs/api/examples.md`: `skill_bar`. CHANGELOG.

**Verify.** `rake spec` green; RuboCop clean. `game_menu`, `menu_navigation`, the
inventory and both `radial_menu` scripts byte-identical after 5a, 5b, 5c and 5d
against the commit before each — none of them has a hotkey or a `Row`. The
allocation numbers in 5b and 5d. `skill_bar` driven with the assertions above,
and once with `--gamepad` for the d-pad and A.

**What this step does not deliver.** Grids and two-dimensional stepping, cooldown
sweeps, a hotkey glyph drawn on a button (`examples/input_glyphs` is the
reference if it is wanted), and rebinding hotkeys at runtime.

---

## Step 6 — a menu held open by an action *(rough)*

**Why.** The hold, point, release wheel is the common console quick menu, and
it cannot be built today (measured in
[01-current-state.md](01-current-state.md#a-wheel-held-open-by-a-button-cannot-be-built--measured-at-9c6eb00-after-step-4)).
After step 5d there is a way to activate a button instantly and a "seen up" rule
that is not tied to a button, which are the two pieces it needs from the menu.
The behaviour is decided (README, "A wheel held open by a button"); the shape
is in [03-design.md](03-design.md#a-menu-held-open-by-an-action) and is to be
re-planned once step 5 has landed.

**What it resembles**, to sort properly at re-planning:

- **Generalize.** Open and closed: `game_menu` and the inventory each hand-write
  it with `paused` and a `draw_children` override. A menu that owns `open?`
  serves them and the trigger both. Whether they move to it in this step, or
  only get a note, is the re-plan's call — it would change their driven reports.
- **Extend.** `Pointing` grows a grace window. The dead-zone rule stays; the
  window only delays it.
- **Reuse.** 5d's instant press and "seen up" method; `PRESS_FEEDBACK`'s
  countdown shape for the grace window, time entering through `update(dt)`.

**Rough sub-steps.**

- **6a** `Pointing grace:` — focus survives the dead zone for `grace` seconds,
  then clears; 0 is today's behaviour, and `examples/radial_menu` stays on it.
- **6b** `Menu trigger:`, `open?` / `open` / `close`, `on_opened` / `on_closed`.
  `RadialMenu` forwards `trigger:` and gives its `Pointing` a grace when one is
  set.
- **6c** An example of a held wheel — a second mode of `examples/radial_menu` or
  a sibling example, decided at re-planning — with a drive script per case below,
  and once with `--gamepad` on a shoulder button.
- **6d** Documentation: `docs/api/ui.md`'s `RadialMenu` and `Pointing` sections,
  "A menu held open by an action", CHANGELOG.

**Rules the tests will pin**, from the decisions:

1. Closed until the trigger's press edge; open while held.
2. Release with a button focused activates it, once, and closes — whether the
   press started with nothing focused, or focus moved while held.
3. Stick released within the grace window before the trigger: the last focused
   button activates.
4. Stick centred for longer than the grace window: the release activates
   nothing, not the last button, and closes.
5. `ui_confirm` while the trigger is held activates nothing.
6. A trigger already down when the menu starts watching opens nothing; one that
   comes up unseen (paused mid-hold) closes the menu and activates nothing.
7. Opening resets the navigation: the first open frame draws no stale aim.
8. A closed menu draws neither its backdrop nor its buttons, and still sees the
   trigger.
9. The world is not touched: `on_opened` and `on_closed` fire, and nothing else
   outside the menu changes.
10. `Menu#on_control` allocates nothing, open or closed.

**Open at re-planning:** the grace window's default length, from prior art
([02-prior-art.md](02-prior-art.md#a-wheel-held-open-by-a-button--not-yet-researched));
whether a game may `open` a trigger menu by hand; and what a `trigger:` menu with
`navigation: nil` (5c) means, if anything.

---

## Step 7 — fold back and delete the plan

`docs/api/ui.md` already carries the reference by then. What has to be rescued
from here: the text-width constraint (into `ui.md`, "What this is not"), the
rejected `look:` and factory alternatives (a sentence each in the `Button`
section, so they are not proposed again), the prior-art agreement that the button
owns its look, and that a style is the stylebox / transition of Godot and Unity
rather than a look on the container. Then delete `docs/plans/menu-and-buttons/`.
