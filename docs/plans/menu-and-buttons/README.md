# Plan — the menu is a shell, the button is the look

**Status:** planned, nothing implemented. Steps 1 and 2 are detailed; steps 3–5
are rough and get re-planned when the step before them lands. Builds on PR #28
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
this is five steps rather than one:

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

One requirement conflicts with a constraint and the constraint wins: buttons
**cannot size themselves from their text**, because text width is only
measurable through a renderer, and the renderer only exists during `draw` —
after layout. Layouts keep assigning every button the same slot. See
[01-current-state.md](01-current-state.md#text-width-is-a-draw-time-fact).

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

1. **Engine layer only.** Everything here is `RGame::Engine::UI`, pure Ruby,
   specced headless in `spec/`, naming no `RGame::Core`.
2. **No renderer change unless a step proves it is needed.** The renderer
   contract has three implementations to keep in step (CLAUDE.md, "Fakes must be
   checked against the same contract"). Measured: everything the shipped
   buttons need already exists — see
   [01-current-state.md](01-current-state.md#what-the-renderer-already-offers).
3. **Nothing on a per-frame path allocates.** `Menu#on_control` and every
   shipped button's `on_draw` are measured allocation-free, as `Stepping` and
   `Pointing` are today (0 and 1 objects over 200,000 calls).
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

## Open questions

1. **Names.** `MenuItem` and `OptionItem` become button classes. Rename them
   (`PanelButton`, `OptionButton`) or keep them? *Leaning rename:* "item" and
   "button" for the same thing is two vocabularies, which CLAUDE.md calls a
   smell. Blocks step 1's final names only; the structure does not depend on it.
2. **Keep `add_item(label)` as sugar?** It builds a default button, which means
   the menu choosing a look again. *Leaning remove*, so `menu.add(button)` is the
   only way in. Blocks step 1.
3. **A navigation that focuses nothing**, for a hotkey-only bar. A `UI::Hotkeys`
   navigation class, or `navigation: nil`? *Leaning a class*, since `nil` is the
   value a forgotten argument also has. Blocks step 4 only.
4. **Does a hotkey focus the button it triggers?** Xenoblade shows the chosen art
   highlighted; WoW flashes the slot without a focus. Blocks step 4 only.
5. **The icon asset.** The radial example with round image-only entries needs a
   CC0 icon set (asset **D** in `basic-examples.md`, deferred there). Kenney's
   *Game Icons* is the first candidate. Blocks step 3's example, not its code.

## What this plan does not deliver

- Buttons sized to their content, and any layout that flows (see verdict).
- Grids and two-dimensional navigation — an inventory grid is the obvious next
  layout, and step 4's axis parameter is the seam it would extend.
- Cooldown sweeps on skill buttons (needs an arc primitive, which the renderer
  does not have), and any game rule about skills.
- Scrolling, nesting, text entry, and a pointer/mouse — as `docs/api/ui.md`,
  "What this is not", already says.
