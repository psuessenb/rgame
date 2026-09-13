# Prior art

How engines that ship a UI toolkit split the container from the thing in it.
Sources are the engines' reference documentation; the links were not re-fetched
while writing this, so check them before quoting a detail as current.

## Godot — `Container` + `BaseButton`

- **`BaseButton`** holds the state — `disabled`, `button_pressed`, `toggle_mode`,
  focus — and emits `pressed`. It draws nothing itself. **`Button`** (text and
  an optional icon, drawn from a theme stylebox per state) and
  **`TextureButton`** (a texture per state: normal, pressed, hover, disabled,
  focused — the image-only button) are subclasses.
  <https://docs.godotengine.org/en/stable/classes/class_basebutton.html>,
  <https://docs.godotengine.org/en/stable/classes/class_texturebutton.html>
- **`BaseButton.shortcut`** binds an input event to the button, activating it
  without focus. That is the hotkey in the requirement, and it lives on the
  button. <https://docs.godotengine.org/en/stable/classes/class_basebutton.html#class-basebutton-property-shortcut>
- **Containers** (`VBoxContainer`, `HBoxContainer`, `GridContainer`) only
  arrange children. They know nothing about focus.
- **Focus** is on `Control`: `focus_neighbor_*` can be set explicitly, and
  otherwise Godot picks the nearest focusable control in the pressed direction —
  a geometric choice, close to what `Pointing` does.
  <https://docs.godotengine.org/en/stable/classes/class_control.html#class-control-property-focus-neighbor-bottom>

This is almost exactly the requirement: state in a base button, looks as
subclasses, a hotkey on the button, arrangement in a container.

## Unity uGUI — `Selectable` + `LayoutGroup`

- **`Selectable`** is the base of `Button`, `Toggle`, `Slider`. It has the five
  states (Normal, Highlighted, Pressed, Selected, Disabled) and a **transition**
  per selectable: colour tint, sprite swap, or animation. The look is configured
  on the selectable, not on its parent.
  <https://docs.unity3d.com/Packages/com.unity.ugui@2.0/manual/script-Selectable.html>
- **Navigation** is also per selectable — Automatic, Horizontal, Vertical, or
  Explicit neighbours.
- **`HorizontalLayoutGroup`, `VerticalLayoutGroup`, `GridLayoutGroup`** arrange
  children and do nothing else.
  <https://docs.unity3d.com/Packages/com.unity.ugui@2.0/manual/script-HorizontalLayoutGroup.html>

## Unreal — UMG + CommonUI

- **`UCommonButtonBase`** holds selection/hover/disabled state and takes a
  **style** asset for its look; games subclass it in Blueprint for bespoke
  buttons. **`UCommonActionWidget`** shows the input glyph for the action bound
  to it — the `input_glyphs` question.
  <https://dev.epicgames.com/documentation/en-us/unreal-engine/common-ui-plugin-for-advanced-user-interfaces-in-unreal-engine>
- Panels (`UHorizontalBox`, `UVerticalBox`, `UUniformGridPanel`) arrange.

## When a press activates — press, release, or both

Researched for open question 6. The short answer is that **nobody picks one**:
every toolkit that has both a menu and a hotkey path activates them at different
moments, and the ones built for games make the menu moment configurable.

| System | Menu / focused button | Direct trigger (hotkey, ability key) | Feedback when activation is instant |
|---|---|---|---|
| **Web** (native `<button>`) | Enter: on **keydown**. Space: on **keyup**. Mouse: on release over the same element | — | — |
| **WCAG 2.1, SC 2.5.2** | Pointer input must not act on the down-event unless it can be aborted, undone, or is essential. Explicitly pointer-only: keyboard is out of scope | — | — |
| **Godot** `BaseButton` | `action_mode`, **default `ACTION_MODE_BUTTON_RELEASE`**; `ui_accept` from a keyboard or pad goes through the same setting as the mouse | `shortcut` fires `press()` on the **key press**, whatever `action_mode` says | `shortcut_feedback` (default on) draws the button pressed for `gui/timers/button_shortcut_feedback_highlight_time`, **0.2 s**, "not affected by `Engine.time_scale`" |
| **Unity** uGUI `Button` | Pointer: `onClick` on release after a press on the same object. Submit (Enter, pad A): on **button down** | — | `OnSubmit` shows `Pressed` and holds it for `ColorBlock.fadeDuration`, **0.1 s** by default, counted with `Time.unscaledDeltaTime` |
| **Unreal** `UButton` | `PressMethod`: `DownAndUp` (**"normally appropriate"**: press, then release *while the button has focus*), `ButtonPress` (immediate), `ButtonRelease` (release on the focused button *even if it was not pressed there*) | — | — |
| **World of Warcraft** | — | CVar `ActionButtonUseKeyDown`, **default 1: abilities fire on key press**; 0 fires on release. Since 11.1.5 a button can override it (`useOnKeyDown`) | the slot flashes on use |

Sources: Godot `scene/gui/base_button.cpp` at `2f698aa5fe` (`shortcut_input`,
`get_draw_mode`, the `GLOBAL_DEF` of the highlight time) and
<https://docs.godotengine.org/en/stable/classes/class_basebutton.html>; Unity
`com.unity.ugui/Runtime/UGUI/UI/Core/Button.cs` (`OnSubmit`, `OnFinishSubmit`),
`ColorBlock.cs` and `StandaloneInputModule.cs` (`GetButtonDown(m_SubmitButton)`)
at `a9ebf25246`; <https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/SlateCore/EButtonPressMethod__Type>;
<https://www.w3.org/WAI/WCAG21/Understanding/pointer-cancellation.html>;
<https://www.stefanjudis.com/today-i-learned/keyboard-button-clicks-with-space-and-enter-behave-differently/>;
<https://warcraft.wiki.gg/wiki/CVar_ActionButtonUseKeyDown>. The Godot and Unity
rows were read from source through the GitHub API, not only from documentation.

What that adds up to:

1. **Direct triggers fire on press, everywhere that has them.** Godot's shortcut
   ignores `action_mode`; WoW defaults to key down and treats release as the
   opt-out. This is the "a skill must react instantly" intuition, and no system
   contradicts it.
2. **Menus split between the two, and the split is by input kind.** Pointer and
   touch activate on release, for the abort reason WCAG gives. Keyboard and pad
   are mixed: Unity activates submit on press, Godot defaults to release, a
   browser does both depending on the key. So "release, like a browser" is true
   of the mouse and of Space, and not of Enter.
3. **The two game engines that activate on press both paint a timed pressed
   state**, and both count it in **unscaled** time: 0.1 s (Unity), 0.2 s
   (Godot). Instant activation without that timer is exactly the invisible
   press measured in [01-current-state.md](01-current-state.md#pressed-is-drawn-only-while-confirm-is-held).
4. **Release needs the press to have started on the same button.** Unreal's
   `ButtonRelease` exists and its own description warns it fires "even if the
   button wasn't pressed while focused"; `DownAndUp` is the default because of
   that. Moving focus away while holding cancels, which is the pad's version of
   WCAG's abort.
5. **It is configurable per button** in Godot, Unreal and (since 11.1.5) WoW,
   and globally in WoW and Godot's project settings. Nobody configures it per
   container.

## What they agree on

1. **The button owns its state and its look.** All three. None puts the look on
   the container.
2. **A container arranges and does nothing else.** Layout is never a property of
   the button.
3. **There is a stateful base with no look**, and looks are subclasses or
   configuration of it.
4. **Direct input activation lives on the button** where it exists (Godot's
   `shortcut`).

## What none of them gives us

- **A radial layout or direction-picking navigation.** Radial menus are built by
  hand in all three, usually as a custom widget that does its own angle maths.
  `Ring` + `Pointing` is beyond what any of them ships.
- **Navigation as an object on the container.** All three put navigation on each
  selectable or on a global focus system. We keep it on the menu (#28), which is
  what lets one menu be stepped *or* pointed without touching its buttons.
- **A container that draws its own backdrop from its layout's extent.** All
  three leave the panel to a separate background widget sized by the layout
  system. Ours has no general layout system, so the menu knowing its bounds is
  the substitute, and it is deliberately narrow.
