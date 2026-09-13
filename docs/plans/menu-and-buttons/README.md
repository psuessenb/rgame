# Plan — the menu is a shell, the button is the look

**Status:** steps 1–4 implemented. Step 5 planned in detail at `564e708`,
step 6 is the fold-back. Open question 9, raised by step 4, blocks 5f. Builds on PR #28
(`UI::Menu` with `layout:` and `navigation:`), merged to `main` as `53f5392`.

| | |
|---|---|
| [01-current-state.md](01-current-state.md) | what the UI package does today, measured, and each requirement checked against it |
| [02-prior-art.md](02-prior-art.md) | how Godot, Unity and Unreal split containers from buttons |
| [03-design.md](03-design.md) | `UI::Button`, `Menu#add`, bounds, the shipped buttons and menus |
| [04-roadmap.md](04-roadmap.md) | the steps |

## Verdict

**The requirements hold, and they are mostly a correction of where one line
was drawn.** PR #28 already gives the menu its layout and its navigation. What
is wrong is that the menu also *builds* its buttons (`add_item`, `add_option`)
and so decides what they look like, and that there is no base class for a
button that is not a nine-slice with a centred label. Fix those two and every
case in the requirement — a radial of round image-only entries, a list of text
buttons for prototyping, a horizontal skill bar — is one menu class with a
different layout, navigation and button class.

Three requirements needed more than the code already had, and are the reason
this is six steps rather than one:

1. **"The menu draws its backdrop"** needs the menu to know its own extent. Today
   two callers compute a panel size by hand, one from a constant that has to be
   kept equal to the number of `add_item` calls. A layout reporting **bounds**
   closes that, and a menu subclass then draws its own backdrop.
2. **A skill bar** needs left/right to move focus. `Stepping` hardcodes up/down
   for focus and left/right for the focused row's value, so it needs an axis.
3. **"The associated action"** has two readings, and a skill bar needs both: the
   thing that happens (`on_activated`, exists) and the input that triggers it
   without focus (a hotkey, as a WoW action bar or Xenoblade's arts are
   triggered). The second does not exist.

One thing stays out of scope: buttons **sized to their text**. Measuring text
outside `draw` already works in Core, but the engine layer — where buttons and
layouts live — has no way to reach it, and giving it one is C work in both
extensions. It is recorded in `docs/plans/possible-todos.md` with its options,
triggered by the next look at i18n. Until then layouts keep assigning every
button the same slot. See
[01-current-state.md](01-current-state.md#the-engine-layer-cannot-measure-text).

## The requirement, verbatim

> The coupling should be:
>
> * the button knows how it looks like, how it's drawn, hold its own state
>   (focused, deactivated, currently pressend)
> * also of course its label, the associated action etc.
>
> The menu holds the buttons, knows how to place the (the layout) and sends
> signals to the buttons: User selects this, so you're now focused, you're not
> any more. It draws the menu backdrop, for the radial menu also the arrow when
> selecting. It's a functional container for the butons.
>
> This means the "menu as a shell" then works with any kind of buttons and
> layouts:
>
> * a radial menu works with circular entries that are only images (very common
>   in games), or buttons that are images with an explaining text blow, your just
>   text for prototyping before the assets are implemented
> * a menu can work with classic buttons, buttons that include images, or just
>   text (as long as this "just text button" implements some way of focus etc.)
> * a skill list (like the skills/arts you select in a game like Xenoblades
>   Chronicles in the combar) is a menu with a horizontal layout and round
>   buttons. A skill list in a game like WoW can also be implemented that way,
>   although that is commonly triggered with hotkeys only and not navigated.

## Goal

A game builds any focus-driven menu — list, wheel, bar — by choosing a menu, a
layout, a navigation and a button class, and writes a new look by subclassing
`UI::Button` and implementing `on_draw`, without touching focus, activation or
placement.

## Hard constraints

1. **Menus, buttons, layouts, navigations and styles are `RGame::Engine::UI`**,
   pure Ruby, specced headless in `spec/`, and name no `RGame::Core` — they reach
   the renderer only through the object `draw` hands them, and name images and
   nine-slices by id. That is CLAUDE.md's layering rule applied, nothing more:
   Core may change where a step needs it, as long as Engine still cannot tell.
2. **A change to the renderer's surface lands with its contract.** The renderer
   has three implementations to keep in step (CLAUDE.md, "Fakes must be checked
   against the same contract"), so any method added or changed — drawing or
   registering — gets its example in `spec/support/shared_examples/a_renderer.rb`
   and its `FakeRenderer` counterpart in the same commit. Measured: no drawing
   method is needed — see
   [01-current-state.md](01-current-state.md#what-the-renderer-already-offers);
   step 4b changes what `register_ui_atlas` registers.
3. **Nothing on a per-frame path allocates.** `Menu#on_control` and every
   shipped button's `on_draw` are measured allocation-free. *Measured when
   re-planning step 3, this was not yet true:* `PanelButton#on_draw` allocates
   one `Color` per draw and `OptionButton#on_draw` four, from array colour
   constants, and `Stepping#step` one per focus step (step 1's landed note).
   Steps 3b and 5b close them.
4. **A mistake fails loudly.** Adding something that is not a button raises; a
   hotkey naming an undeclared action raises (`Actions` already does); a
   navigation shared between menus raises (already does).
5. **Driven reports do not change** for `game_menu`, `menu_navigation` and the
   `tiled_world` inventory at any step that only moves code, compared with
   `--seed 1` against the commit before.

## Decisions already taken

Not up for re-litigation inside this plan.

- **The button owns its look, its state, its label and its action.** Taken in the
  prompt that started this plan, and it replaces a proposal to put a `look:` on
  the menu. The rejected proposal is recorded in
  [03-design.md](03-design.md#considered-and-rejected) with the reason.
- **The menu owns the collection, the layout, the navigation, confirm, and its
  own backdrop.** Same prompt. For a radial menu that includes the pointer.
- **Layout and navigation stay constructor objects, as in PR #28**, not
  components — a menu with no navigation or two would otherwise be possible and
  silent.
- **This starts now, before `examples/localization` and anything else builds on
  `UI::Menu`.** Same prompt: the cheapest moment to move the line is before more
  callers depend on where it is.
- **Named icons reach the renderer through a UI atlas.** `Core::UiAtlas` grows an
  `images` key beside `nine_slices`, and `register_ui_atlas` registers both, so
  `IconButton.new(image: :home)` draws after the one registration call a game
  already makes for nine-slices. Taken in the prompt that re-planned steps 3–5,
  choosing the recommendation under open question 8, after the old wording of
  hard constraint 1 ("engine layer only") was found to rest on nothing and
  reworded. Step 4b.

## Open questions

1. ~~**Names.**~~ **Settled — rename.** `MenuItem` becomes `UI::PanelButton` and
   `OptionItem` becomes `UI::OptionButton`, so "item" and "button" stop being two
   words for one thing. Happens in step 1b, with the callers. See
   [03-design.md](03-design.md#the-buttons-that-ship).
2. ~~**Keep `add_item(label)` as sugar?**~~ **Settled — dropped**, with
   `add_option`. `menu.add(button)` is the only way in, so the menu never picks a
   look. Step 1b.
3. ~~**A navigation that focuses nothing.**~~ **Settled — `navigation: nil`**, the
   shortest and clearest way to say a menu has none. The worry that `nil` is also
   what a forgotten argument looks like does not apply: the keyword defaults to
   `Stepping.new`, so leaving it out never produces `nil`, and passing `nil` is
   always a statement. A menu with no navigation never focuses anything, so
   `ui_confirm` does nothing and only hotkeys activate — unless the game calls
   `focus` itself, which is as much a statement as passing `nil`. Step 5c. See
   [03-design.md](03-design.md#navigation-changes).
4. ~~**Does a hotkey focus the button it triggers?**~~ **Settled — no, but it
   presses it.** Focus stays where it was. What a hotkey does give is the same
   visual feedback confirming does: like a button in a browser, a button has a
   neutral look, a focused look and a pressed look, and **pressed is reached two
   ways** — being the focused button while `ui_confirm` is pressed, and being
   activated by its hotkey. See [03-design.md](03-design.md#pressed-is-reached-two-ways).
   Measured while settling it: the pressed look today is not reliably visible
   (see [01-current-state.md](01-current-state.md#pressed-is-drawn-only-while-confirm-is-held)),
   which opens question 6.
5. ~~**The icon asset.**~~ **Settled — Kenney's *Game Icons*, CC0.** 105 icons in
   white and black, 1x and 2x PNGs, a spritesheet, and SVG sources
   (<https://kenney.nl/assets/game-icons>, mirrored with the same CC0 licence at
   <https://opengameart.org/content/game-icons>). The **white** variant is the one
   to cut: `renderer.image` tints by multiplying, so white art takes any per-state
   colour and black art takes none. They are menu symbols — home, settings, save,
   star, trophy, lock, audio — which fits a radial quick menu, not a skill bar.
   Downloaded while re-planning step 3: every icon is 50×50 (1x) and 100×100
   (2x), white is RGB 255 with alpha only. Step 4c cuts eight 1x icons into one
   strip — 2 KB, against 121 KB for the eight files as shipped — and records
   provenance in `examples/assets/README.md`. Art for
   step 5's skill bar is not settled by this — see question 7.
6. ~~**When does a press activate, and how long is "pressed" visible?**~~
   **Settled — every recommendation below, confirmed as written.** Today
   pressed lasts exactly as long as `ui_confirm` is held — one frame for a tap,
   none when the activation closes the menu — and one press can activate two
   menus (see [01-current-state.md](01-current-state.md#one-confirm-activates-two-menus)).
   **Researched** in [02-prior-art.md](02-prior-art.md#when-a-press-activates--press-release-or-both):
   every toolkit with both paths activates a hotkey on press, splits on the menu
   path, and the game engines make it a per-button setting. **Decided:**
   - A per-button **`activate_on:`**, `:release` (the default) or `:press`. A
     settings menu keeps the default; a skill bar navigated by confirm, the
     Xenoblade case, builds its buttons with `:press`.
   - **A hotkey always activates on press**, ignoring `activate_on:`, as Godot's
     shortcut does. WoW's release opt-out is the precedent if anyone ever needs
     it; nothing here does.
   - **Every activation needs a press this button saw start** — the press edge
     arrived while it was focused (or, for a hotkey, while it was in a live menu).
     A button added while the key is already down never presses or activates from
     it. Moving focus away while held cancels a `:release` activation.
   - **Pressed is visible at least `PRESS_FEEDBACK` seconds**, 0.1 as Unity
     uses, after any activation on press; a `:release` activation needs no timer,
     because the hold itself was the feedback. The countdown runs in
     `update(dt)`, and step 1c has to decide what a paused menu does to it: a
     menu that hides itself in `on_activated` stops ticking, and the button would
     otherwise come back still pressed when reopened.

   Changing the default to `:release` changes when every existing menu reacts,
   one tick later on a tap — accepted with the rest. **Pausing, decided in step
   1c:** a button cannot see ticks it was not controlled for, so a press whose
   release it never saw — the key is up with no release edge — is dropped, with
   its feedback; a paused countdown otherwise freezes. See the step's landed note
   for the two cases that rule cannot see. See
   [03-design.md](03-design.md#pressed-is-reached-two-ways).
7. ~~**Skill-bar art.**~~ **Settled — Kenney's *Cursor Pack*, its tool cursors as
   farming-sim skills.** <https://kenney.nl/assets/cursor-pack>, version 1.1,
   `License.txt` reads "License: (Creative Commons Zero, CC0)". Downloaded and
   checked: the five tools are `tool_wand`, `tool_wrench`, `tool_torch` (the
   flashlight — the file is named for the British word), `tool_hammer` and
   `tool_watering_can`, each 32×32 (`Default`) and 64×64 (`Double`), in a
   `Basic` style (white-to-light-grey silhouette, values 203–255, which a tint
   colours directly) and an `Outline` style (the same with a black border, which
   stays black under a tint and so reads on any background). The pack also has
   `tool_hoe`, `tool_shovel`, `tool_axe` and `tool_pickaxe` if the farm wants
   more. Step 5e picks the style after seeing both on the example's background.
   An OpenGameArt collection of ability icons was looked at first and passed
   over: it has no licence of its own and links sixty-odd packs under mixed
   licences.
8. ~~**How does a game get named icons from one sheet onto the renderer?**~~
   **Settled — through the UI atlas**, as recommended below. See
   ["Named icons reach the renderer through a UI atlas"](#decisions-already-taken).
   `IconButton` takes an image id, and a Symbol id resolves by registration only.
   The icons ship as one strip (see question 5), so something has to cut it into
   named subimages and register them.

   **Chosen: `UiAtlas` grows an `images` key beside `nine_slices`, and
   `register_ui_atlas` registers both.** A UI atlas is already "one sheet of UI
   chrome, cut into named rectangles"; an icon is a named rectangle drawn whole
   instead of stretched. Same question, another kind of element — the "extend"
   pile, not a second loader. It comes with `AssetManager` caching and groups for
   free, and the contract runs it against both renderers.

   What it changes: `Core::UiAtlas`, and what `register_ui_atlas` does in the
   real renderer and in `FakeRenderer`, with a contract example (hard constraint
   2). No drawing method, no C, and nothing a caller already writes. Engine code
   still names the icon by id only (hard constraint 1).

   Considered:
   - *The example parses its own `.json` and calls `register_image(subimage)` in
     a loop.* No Core change. But every game with an icon sheet writes that
     loader again, next to a UI atlas that already parses the same rectangle
     shape — the parallel-vocabulary smell in CLAUDE.md — and loses the asset
     manager's cache and groups.
   - *`renderer.sprite` gains `color:` and `scale:`.* A C and contract change on
     three implementations for a drawing call, and a sprite sheet is a uniform
     grid, which an icon set picked from a pack is not in general.
   - *One PNG per icon, by path.* Needs no code at all; measured at 121 KB for
     eight, doubling `examples/assets`.

9. **Should `IconButton`'s pressed tint and `ShapeStyle`'s pressed fill stop
   being the same colour?** *Open, raised by step 4.* Both default to
   `(240, 200, 96)`, so `IconButton.new(image:, style: ShapeStyle.new(shape: :disc))`
   — the pairing `IconButton`'s own header shows — draws a gold icon on a gold
   disc while pressed, and the icon disappears. `examples/radial_menu` passes a
   dark pressed tint. That depends on every game remembering, which CLAUDE.md's
   "Design out misuse" rejects, so the defaults are the likelier fix; the
   candidates:
   - *A dark pressed tint in `IconButton::TINTS`.* Fixes every styled icon; an
     unstyled icon on a dark background then goes dark while pressed.
   - *A different pressed fill in `ShapeStyle::COLORS`.* Also changes every
     `TextButton`'s pressed look, whose light label reads on the gold.
   - *Leave both, and document the tint* (what step 4 did).

   Step 5f's skill bar builds exactly this pairing, so it waits on the answer.

## What this plan does not deliver

- Buttons sized to their content, and any layout that flows (see verdict, and
  "Text measurement for the engine layer" in `docs/plans/possible-todos.md`).
- Grids and two-dimensional navigation — an inventory grid is the obvious next
  layout, and step 5's `Stack` axis is the seam it would extend.
- Cooldown sweeps on skill buttons (needs an arc primitive, which the renderer
  does not have), and any game rule about skills.
- Scrolling, nesting, text entry, and a pointer/mouse — as `docs/api/ui.md`,
  "What this is not", already says.
