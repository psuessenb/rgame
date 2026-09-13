# Roadmap

**Status:** step 1 is implemented. Step 2 is detailed; 3–5 are rough and are
re-planned when the step before them lands. Step 4 needs a hotkey path into
`Button#press` that ignores `activate_on:`, and the allocation in `Stepping#step`
(see step 1's landed note).

```
#28 (merged) ─→ 1 Button + Menu#add ─→ 2 bounds + PanelMenu ─→ 3 TextButton, IconButton, RadialMenu ─→ 4 Row, axis, hotkeys ─→ 5 fold back
                   │                        │
                   └─ closes: no other kind  └─ closes: ITEM_COUNT kept equal to add_item by hand
                      of button can exist
```

> **Every step that only moves code leaves the driven reports of `game_menu`,
> `menu_navigation` and the `tiled_world` inventory byte-identical** against the
> commit before it, with `--seed 1` and a fresh `RGAME_SAVE_DIR`.

Steps 1 and 2 are each worth landing if the rest of the plan is abandoned:

| Step | Defect it closes |
|---|---|
| 1 | A menu can only ever hold a nine-slice `MenuItem`; no game can add a button of its own |
| 2 | A panel sized from a hand-kept item count overflows silently when an item is added |

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

---

## Step 3 — `TextButton`, `IconButton`, `UI::RadialMenu` *(rough)*

- `TextButton`: label plus a focus marker from primitives; colours as arguments;
  `shape:` `:rect` / `:disc` to be decided when written.
- `IconButton`: image id (path or registered subimage), tint and scale per state,
  optional caption below the slot, and "a missing image draws nothing and the
  caption speaks".
- `RadialMenu < Menu`: `Ring` + `Pointing` preset, backdrop, dead zone and
  pointer from `examples/radial_menu`, colours as arguments.
- `examples/radial_menu` moves to `RadialMenu` with `IconButton`s over Kenney's
  *Game Icons* (open question 5, settled): download, measure, cut the white
  variant of the icons used into one image and `.json`, provenance in
  `examples/assets/README.md`, and an `example_assets_spec.rb` check that every
  cut frame fits the image.
- Re-plan against: whether `Pointing` should read button centres through a method
  on `Button` rather than `x + width / 2`, now that buttons may draw outside
  their slot (a caption below).

## Step 4 — `Row`, `Stepping` axis, hotkeys, `examples/skill_bar` *(rough)*

- `Row` layout, or `Column` with an axis — decide by writing both `bounds` first.
- `Stepping.new(axis:)`.
- `Button hotkey:`; `Menu#on_control` presses and activates any enabled button
  whose hotkey was pressed, under every navigation, without moving focus (open
  question 4, settled).
- `navigation: nil` (open question 3, settled): no focus, confirm does nothing.
  A WoW-style bar is this plus hotkeys.
- `examples/skill_bar`: a horizontal bar of round buttons, navigated *and*
  hotkeyed, with a drive script showing both — and that the hotkeyed button draws
  pressed while focus stays put, and that a skill fires on the press. Its art is
  Kenney's *Cursor Pack* tools (open question 7, settled): wand, wrench, torch,
  hammer, watering can, cut into one image and `.json` with provenance and an
  `example_assets_spec.rb` frame check, like asset **G**.

## Step 5 — fold back and delete the plan

`docs/api/ui.md` already carries the reference by then. What has to be rescued
from here: the text-width constraint (into `ui.md`, "What this is not"), the
rejected `look:` and factory alternatives (a sentence each in the `Button`
section, so they are not proposed again), the prior-art agreement that the button
owns its look. Update `basic-examples.md` if it still exists: asset **D**'s row
and the radial example's entry. Then delete `docs/plans/menu-and-buttons/`.
