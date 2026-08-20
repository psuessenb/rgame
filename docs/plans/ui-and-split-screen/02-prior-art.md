# How other engines answer this

Background reading for the overhaul. Four engines, all of which ship local
split-screen, plus what each one's answer implies for us. Sources at the bottom.

The question they are all answering is the one
[`README.md`](README.md) left open — *does a viewport own a camera, or does a
camera own a viewport?* — and the interesting result is that **three of the four
answer "neither: the player owns both"**, and the fourth (Godot) is the one
people complain about.

---

## Unreal — the player is a first-class object

The most complete model, and the closest to what our requirement describes.

- `ULocalPlayer` — one per person on the couch. Owns a **slice of the viewport**.
- `APlayerController` — one per `ULocalPlayer`; input is routed to the
  controller that *possesses* a pawn, never broadcast globally.
- `AHUD` — **one instance per player**, drawing into that player's viewport only.
- `APlayerCameraManager` — per controller, computes that player's view.
- Split-screen is on by default the moment a second local player is created
  (`UGameplayStatics::CreatePlayer`); the engine assigns the rects.
- **Collapsing to one view is an explicit, first-class call**:
  `SetForceDisableSplitscreen(true)` forces one full-screen viewport, and the
  documented use cases are exactly ours — *menus and cutscenes*.

The consistent advice in Unreal's local-multiplayer material is: never look a
player up by hardcoded index, always go through the ownership chain
(pawn → controller → local player). That is the same failure mode as our
`@root.control(one_snapshot)`: a global reach for "the input" that silently means
player one.

**Take:** player as an owning object; per-player HUD; collapse-to-single as a
named mode rather than an ad-hoc special case.

## Unity — bindings are per player, the action *names* are global

Unity's Input System splits exactly the way our requirement asks for.

- An **Input Action Asset** declares the action vocabulary **once, game-global** —
  `Move`, `Fire`, `Submit`, `Cancel`. This is the "actions are defined
  game-global" half of the requirement.
- A **control scheme** is a named set of bindings for a device class ("Keyboard &
  Mouse", "Gamepad"). Same action, different physical input per scheme.
- `PlayerInput` — one component per player, holding **that player's** device
  pairing and its own action state. "Each `PlayerInput` instance represents a
  distinct user with its own set of devices and actions."
- `PlayerInputManager` — orchestrates joining; on join it pairs the device the
  player joined *with* and picks the first compatible control scheme.
- `InputUser` underneath pairs devices to users exclusively — with an explicit
  escape hatch for two players sharing one device (left/right keyboard splits),
  which we will want for keyboard-only two-player testing.
- Cameras get a normalized `rect`; each player's camera renders to its share.
- Screen-space UI per player needs `MultiplayerEventSystem` — i.e. **focus is
  per player too**, which is directly relevant to the UI half of this folder.

**Take:** one global action vocabulary + per-player binding tables; device
pairing as an explicit, hot-pluggable assignment; per-player UI focus.

## Bevy — the camera owns the viewport, and ordering is explicit

The most minimal answer, and the one closest to our renderer's actual shape.

- `Camera { viewport: Option<Viewport>, order: isize, .. }`. Spawn two cameras,
  give each a viewport covering half the window, done — one shared `World`,
  drawn twice.
- `order` must differ between cameras, or draw order is nondeterministic.
- `RenderLayers` (a 32-bit mask on entities and cameras) filters *what* each
  camera sees. This is how "player 1's HUD appears only in player 1's viewport"
  is expressed without a second world.

**Take:** the loop-over-viewports shape is genuinely all that is needed at the
renderer level (which our C layer already proved in `test/test_canvas.c`); an
explicit ordering between passes is not optional; and something has to answer
"which viewport does this thing appear in".

## Godot — the viewport owns the camera, and it is the awkward one

- Each player gets a `SubViewportContainer` → `SubViewport` → `Camera2D`.
- The world is instanced under *one* `SubViewport`, and every other
  `SubViewport`'s `world_2d` is pointed at the first one's, so they share a scene
  tree rather than duplicating it.
- Input is global (`Input.is_action_pressed`), so the community answer for local
  multiplayer is **per-player action names** — `p1_left`, `p2_left` — or manual
  device filtering on raw events.

**Take, mostly negative:** duplicating the action vocabulary per player is
precisely what our requirement rules out ("the keys for the input mapping are
shared between players"). And "the world lives under viewport 0 and the others
borrow it" is a workaround for a containment model that got the ownership
backwards. Godot's own docs describe `Viewport` as the render target, so the
camera-inside-viewport nesting is a rendering artefact, not a game-model choice.

---

## What the four agree on

1. **The player is the owner.** Camera, input bindings, device, HUD, and UI focus
   all hang off one per-person object. Not off the world, and not off the scene.
2. **The world is shared and simulated once.** Every one of them draws the same
   world N times and updates it once. None of them duplicates the scene.
3. **Action names are global; bindings are per player.** Unity states it
   outright; Unreal gets it via per-controller input components; Godot's lack of
   it is its known wart.
4. **Rects come from a layout, not from the camera.** Unreal assigns them from
   the split-screen type, Unity from the camera `rect` a template sets, Bevy from
   whatever spawns the cameras. Nobody bakes a rect into a camera at
   construction — which is what `Camera#viewport_width` does today.
5. **Collapse-to-one-view is a named mode.** Unreal has a call for it; the others
   do it by activating a single full-viewport camera.

## What none of them gives us

- **A pure, headless-testable formulation.** All four resolve views inside a
  renderer. Ours has to stay in `RGame::Engine` with no Core reference, which
  means the layout, the view rects and the per-player input all have to be plain
  values a spec can assert on with no window. That is a constraint, but it is
  also the reason ours can be specced properly and theirs are demo-tested.
- **An answer for "one player is in a menu while the other plays".** Unreal and
  Unity both do it (per-player HUD/EventSystem), but neither treats it as a
  distinguished case, and the requirement here does. That is ours to design —
  see [`03-design.md`](03-design.md) §3.

## Sources

- [Local Multiplayer Tips — Unreal Engine Community Wiki](https://unrealcommunity.wiki/local-multiplayer-tips-993f4t24)
- [Splitscreen Multiplayer Guide — BaconGameDev](https://bacongamedev.com/unreal-post/local-coop/)
- [Set Force Disable Splitscreen — Unreal Engine Documentation](https://dev.epicgames.com/documentation/unreal-engine/BlueprintAPI/Viewport/SetForceDisableSplitscreen?lang=en-US)
- [User Interfaces & HUDs — Unreal Engine Documentation](https://docs.unrealengine.com/4.27/en-US/InteractiveExperiences/Framework/UIAndHUD)
- [PlayerInput — Unity Input System](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.11/api/UnityEngine.InputSystem.PlayerInput.html)
- [The Player Input Manager component — Unity Input System](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.5/manual/PlayerInputManager.html)
- [User Management — Unity Input System](https://docs.unity3d.com/Packages/com.unity.inputsystem@1.3/manual/UserManagement.html)
- [Bevy 0.8 release notes — camera viewports](https://bevy.org/news/bevy-0-8/)
- [Bevy split-screen example](https://bevy.org/examples/3d-rendering/split-screen/)
- [Cameras — Unofficial Bevy Cheat Book](https://bevy-cheatbook.github.io/graphics/camera.html)
- [Split Screen Coop — GDQuest](https://www.gdquest.com/library/split_screen_coop/)
- [Make a 2D Split-Screen in Godot 4 — Mina Pêcheux](https://medium.com/codex/make-a-2d-split-screen-in-godot-4-gdscript-c-47bedcaaafc4)
- [2PSplitScreenDemo — shared World2D between SubViewports](https://github.com/sarchar/2PSplitScreenDemo)
