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
