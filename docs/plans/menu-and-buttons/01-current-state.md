# Current state

What `RGame::Engine::UI` does on `main` after PR #28 (`53f5392`), and each
requirement checked against it.

## What was measured before planning

| | |
|---|---|
| Commit | `53f5392` (PR #28, squash-merged; the tree measured is identical to its branch head `154fb9b`) |
| `rake spec` | 1447 examples, 0 failures, 2.8 s |
| `spec/rgame/engine/ui/` | 88 examples, 0.02 s |
| UI source | 8 files, 595 lines: `menu` 113, `menu_item` 88, `option_item` 116, `pointing` 93, `stepping` 59, `navigation` 49, `ring` 41, `column` 36 |
| UI specs | 6 files, 846 lines |
| Menus built outside `lib/` | **5**: `examples/game_menu` (1), `examples/menu_navigation` (2), `examples/radial_menu` (1), `test_projects/tiled_world/inventory.rb` (1) |
| `add_item` / `add_option` call sites outside `lib/` and `spec/` | 9 `add_item` (two inside loops), 1 `add_option` (inside a loop over three settings) |
| Callers passing `style:` | **0** |
| Button classes | 2 (`MenuItem`, `OptionItem < MenuItem`), both nine-slice |
| Hand-computed panel sizes | **2** (`game_menu`, `inventory`) — see below |
| `Menu#on_control` allocations, 200,000 calls | `Stepping` 0, `Pointing` 1 |

## How it is shaped today

```
Menu < Node2D                 holds @items, builds them, confirm handling
  layout:     Column | Ring    arrange(items): x, y, width, height per item
  navigation: Stepping | Pointing   on_control(actions) → menu.focus(index)
  style:      Hash             element names, forwarded to every MenuItem it builds

MenuItem < Node2D             label, enabled, focused=, pressed=, activate, adjust → nil
                              on_draw: nine_slice(@style[state]) + centred label, LABEL_COLOR constant
OptionItem < MenuItem         values, index, adjust(delta) → on_changed; nine_slice + label + < value >
```

## Each requirement, checked

### "The button knows how it looks, how it's drawn, holds its own state" — *(measured: already true of `MenuItem`, but only for one look)*

`MenuItem` holds `enabled`, `focused`, `pressed`, computes its `state`, and draws
itself. So the ownership in the requirement is already the ownership in the code.
What is missing is the **seam**: there is no class that has the state without
the nine-slice. `state` is private, and `OptionItem` gets it only by inheriting
the nine-slice drawing as well. A second look today means copying the state
logic or subclassing a drawing it then has to override entirely.

### "Also its label, the associated action" — *(measured: half exists)*

`label` is an accessor. `on_activated` is the action in the sense of *what
happens*. There is no action in the sense of *which input triggers it*: the only
trigger is `ui_confirm` on the focused item, handled in `Menu#on_control`. A
hotkey-driven bar (the WoW case) cannot be built.

An image-only button has no use for a required `label:`. It still wants one —
a caption, a tooltip later, a debug name — so it should become optional rather
than disappear.

### "The menu holds the buttons and knows how to place them" — *(measured: true since #28, except it also builds them)*

`layout.arrange(items)` places. But `Menu#add_item` and `#add_option` construct
`MenuItem.new` / `OptionItem.new` themselves, forwarding `style:`. So the menu
decides the button class, and a game cannot put any other kind of button in a
menu at all. This is the one structural fault, and every requirement bullet
about "any kind of button" is blocked on it.

### "It sends signals to the buttons: you're focused, you're not any more" — *(measured: true, as setters)*

`Menu#focus(index)` sets `item.focused = (i == index)` on every item, every
frame under `Pointing`. A button has no hook to *react* to gaining focus (a
sound, starting an animation) because it is told by assignment and never asked.
A blank hook called only on change is the shape CLAUDE.md prescribes, and
checking for change also stops the per-frame reassignment.

### "It draws the menu backdrop" — *(measured: nothing draws it; two callers compute it by hand)*

`Menu` draws nothing. `examples/game_menu` draws its panel in a parent node:

```ruby
ITEM_COUNT  = 3
def panel_height = (ITEM_HEIGHT * ITEM_COUNT) + (SPACING * (ITEM_COUNT - 1)) + (PADDING * 2)
```

and three `add_item` calls further up. `ITEM_COUNT` has to be kept equal to that
count by whoever edits the menu, and a fourth item silently overflows the panel —
precisely the remembered rule "Design out misuse" refuses.
`test_projects/tiled_world/inventory.rb` does the same arithmetic from
`ITEMS.size`. Both are re-deriving `Column`'s own placement.

So the menu cannot draw a backdrop until something reports the extent the layout
produced. Neither layout does.

### "For the radial menu also the arrow" — *(measured: drawn by the example)*

`examples/radial_menu` draws the backdrop disc, the dead-zone disc and the
pointer in a parent node, reading `Pointing#aim_x`/`aim_y` and `#dead_zone`. That
is exactly the reusable part a game wanting a wheel would copy, and it is in an
example rather than the engine.

### "A radial of round, image-only entries / images with a caption / text" — *(measured: renderer ready, buttons missing)*

See "What the renderer already offers" below: nothing new is needed to draw
them. What is missing is the button classes, and the menu accepting them.

### "A horizontal skill bar" — *(measured: layout trivial, navigation hardcoded)*

`Stepping#on_control` reads `ui_up`/`ui_down` for focus and sends
`ui_left`/`ui_right` to the focused row's `adjust`. A horizontal bar needs the
reverse. A `Row` layout is a copy of `Column` along the other axis.

### "Triggered with hotkeys only and not navigated" — *(measured: impossible today)*

Activation only happens through confirm on the focused item, and every shipped
navigation either always focuses something (`Stepping`) or focuses by stick
(`Pointing`). Needs a per-button input action and a navigation that focuses
nothing.

## Pressed is drawn only while confirm is held

*(measured at `53f5392`, driving a `Menu` headless tick by tick)*

| Tick | `ui_confirm` | Focused item's state | `on_activated` fires |
|---|---|---|---|
| 0 | up | `:focus` | |
| 1 | **down** | **`:pressed`** | **yes** |
| 2 | down | `:pressed` | |
| 3 | up | `:focus` | |

`Menu#on_control` sets `pressed = actions.held?(:ui_confirm)` on the focused
item and activates on the press edge in the same call. Two consequences:

- **A tap is one frame of pressed**, about 16 ms — technically drawn, practically
  invisible.
- **A button whose activation closes its menu never shows pressed at all.**
  `examples/game_menu`'s Resume sets the menu hidden inside `on_activated`, which
  runs in `control`, before that tick's draw. Read from the code rather than
  driven, because the drive report keeps only the first and last argument of
  each call kind and cannot show one frame in the middle.

And a button pressed any other way than confirm has no pressed look, because
there is no other way. Open question 6.

## Text width is a draw-time fact

`renderer.text_width` is the only way to measure a string, and the renderer is
only handed to `draw`. Layout happens on `add`, long before. Every measuring call
site today (`MenuItem#label_x`, `OptionItem#draw_value`, `DebugOverlay`) is inside
a draw method for that reason. So a layout **cannot** size a text button to its
label, and uniform slots stay. A game that wants wider buttons sets a wider slot.

## What the renderer already offers

| A button that needs | Uses | Tint / scale for focus |
|---|---|---|
| a panel | `nine_slice(id, x, y, w, h, tint:)` | tint |
| an image (icon) | `image(id, cx, cy, scale:, color:)`, `image_at(id, x, y, scale_x:, scale_y:, color:)` | both |
| a round prototype | `circle(cx, cy, r, color:)` | colour |
| a label or caption | `text`, `text_width`, `text_height` | colour |

One thing it does **not** offer: `sprite(id, row, col, ...)` — a frame of a
sheet — takes neither a tint nor a scale. So an icon button takes an **image id**
(a path, or a registered `Image#subimage`, which `examples/sprite` shows) rather
than a sheet frame, and constraint 2 holds.

## What already resembles the thing being planned

The three piles from CLAUDE.md, "Before building".

**Reuse it.**

- `Column`, `Ring`, `Stepping`, `Pointing`, `Navigation` — the menu half of the
  requirement, exactly as #28 built it.
- `Signal` DSL — `on_activated`, `on_changed`, and any new focus notification.
- `Engine::CachedLabel` — a caption that changes (a skill's charges) without
  allocating per frame.
- `Actions#pressed?` raising on an undeclared action — a misspelled hotkey is
  already loud.

**Extend or generalize it.**

- `MenuItem` → the state half becomes `UI::Button`; the nine-slice half stays a
  subclass. Same question ("what state am I in, and draw it"), about different
  looks.
- `Column` → `Row` is the same answer along the other axis. Worth checking at
  step 4 whether they are one class with an axis, the way `Stepping` gets one.
- `Stepping` → an axis parameter, so vertical and horizontal lists are one
  navigation.
- `Layout#arrange` → also reports bounds, which is the thing two callers compute
  by hand.
- `examples/radial_menu`'s backdrop and pointer drawing → the body of a shipped
  radial menu.
- `examples/input_glyphs`' `Prompts` rows draw an icon beside a label with a
  sprite — the same picture an icon-with-caption button draws, except not
  focusable. Not to be merged (a prompt is not a button), but its "missing glyph
  draws nothing and the label speaks" rule is the right rule for an icon button
  whose image is absent.

**Genuinely new.**

- Hotkey activation. Nothing in the UI package triggers an item without focus.
  `Components::ActionTrigger` resembles it — an input action mapped to a signal
  — but it is a held-with-cooldown auto-repeat on one node, where a hotkey is a
  single press dispatched by a container to one of its children. Checked and
  rejected as the same shape: its cooldown semantics are exactly what a menu
  button must not have.
- The per-state look of an image-only button (tint and scale).
