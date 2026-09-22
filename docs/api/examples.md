# Examples

`examples/` holds one small program per concept. Each is a single `main.rb` that
runs on its own:

```
ruby examples/walk/main.rb
```

**An example answers "how do I do *X*".** The complete games under
`test_projects/` answer that poorly. An example shows one concept in one file,
and its header comment explains the concept at length. This page is the index;
the file is the long version.

Every example has an acceptance test as well. A scripted input track lives at
`tools/drive/examples/<name>.rb`. The harness feeds that track to the unmodified
program and reports what the game asked for:

```
ruby tools/drive_test_project.rb examples/walk/main.rb --ticks 240
```

The examples' assets live under `examples/assets/` and are redistributable, so
every example runs from a fresh clone. Most examples need no art at all.

## Movement and drawing

### walk

A player-controlled sprite: the smallest complete game. It is a plain node with
three components, and no component knows about the others.

**Uses:** `Node2D`, `Components::AnimatedSprite`, `Components::CharacterBody`,
`Components::PlayerController`, `InputMap.default`.

### sprite

One frame drawn at a node, with no animation. Most things in a game look like
this. The draw passes no position and no angle, because the node's transform
already applies.

**Uses:** `Components::Sprite`, `Image#subimage`, `renderer.register_image`.

### velocity

The second way a node moves. A character has an *intent*. A rock has a velocity,
and a component integrates it, spin included.

**Uses:** `Components::Velocity`, `Components::ScreenWrap`, `Components::World`,
`Components::WorldBounds`.

## The world

### scroll_map

A Tiled map larger than the window, scrolled by a player. No call pans the
camera. A component on a node points the camera, so scrolling is walking.

**Uses:** the `:tilemap` asset loader, `Components::TileWorld`, `TileMapLayer`,
`WorldView`, `Camera`, `Components::CameraFollow`.

### collision

Object-to-object collision. A scene-scoped system pairs up shapes each step and
tells both sides they overlapped. It never learns what either object is.

**Uses:** `Components::CollisionWorld`, `Components::CircleCollider`,
`Components::BoxCollider`, `Components::Velocity`, `Engine::Text`.

### collision_tiles

A character against a grid of solid tiles, sliding along a wall while walking
diagonally. East of the start, a spiky ball stops the hero and costs a life. One
feet box is thus stopped by two indexes: the map's grid and the broadphase.
`blocked_by: %i[tiles spike]` is the only place the difference shows. The life is
spent in `on_blocked`, because a blocked pair ends up touching, not overlapping.
`on_hit` never fires for it.

**Uses:** `Components::TileWorld`, `Components::CollisionWorld`,
`Components::FeetCollider`, `Components::CharacterBody` with
`blocked_by: %i[tiles spike]` and `on_blocked`, `Components::CameraFollow`,
`Engine::Text`.

### jump_topdown

A hop in a top-down view. "Up" on screen is north, so a jump cannot move the
character. The sprite rises along `Hop`'s parabola. The feet box, the shadow and
the camera stay on the ground. A hop at the fence therefore does not clear it,
because the part that collides never leaves the ground. The game decides what a
hop may cross, through `airborne?`.

**Uses:** `Components::Hop`, `Node2D#elevation`, `Components::AnimatedSprite`,
`Components::FeetCollider`, `Components::CharacterBody`, `Components::TileWorld`,
`Components::CameraFollow`, `InputMap.default.merge`.

### pathfinding

Pick a tile, and the hero works out how to get there. Small dots show the route
the search found, one per tile. Lines show the route the hero walks. The
navigator pulls the route tight, keeping each line straight as long as the hero's
feet box fits.

**Uses:** `Components::Navigator`, `Components::TileWorld#nav_grid`,
`Components::AnimatedSprite`, `Components::ActionTrigger`,
`Components::CameraFollow`, `Engine::Text.computed` over `I18n.t` with plurals.

## Structure

### signals

Declaring your own signal. A pressure plate announces that it was pressed, and
does nothing more. The door and the lamp connect to it; the plate never names
them.

**Uses:** `Signal::DSL`, `Signal.define`, `Components::ActionTrigger`, the
connect handle.

### timer

Periodic behaviour that no input drives: a spawn cadence and a one-shot, with two
cadences on one node.

**Uses:** `Components::Timer` (repeating and `repeating: false`, and `as:`),
`Engine::Timer`.

### pooling

Spawning many things without building any of them. The allocation count on
screen makes the case.

**Uses:** `Components::Pool`, `Engine::Pool`, `Components::DespawnOffscreen`,
`Components::Timer`, `Engine::Text`.

## UI

### game_menu

A menu that opens over a running world. Pausing belongs to a node, so only the
hero stops while the villagers walk on.

**Uses:** `PlayerLayer`, `UI::PanelMenu`, `UI::PanelButton`, `UI::Menu#open` /
`#close`, `Node2D#paused`, `renderer.nine_slice`.

### menu_navigation

Several screens (title, settings, back) and settings that change something real
and survive a restart. It contrasts pushing a scene with replacing one.

**Uses:** `Scene::SceneStack`, `UI::OptionButton`, `Util::SaveFile`,
`RGame::Game`'s fullscreen, scale mode and volume.

### radial_menu

Choosing by pointing. Eight icons sit on a wheel, focused by the direction of the
stick or the arrow keys. A released stick selects nothing, so pressing A at rest
never picks what the stick passed on its way back.

**Uses:** `UI::RadialMenu`, `UI::IconButton` on a disc `UI::ShapeStyle`,
`ui_radial_x` / `ui_radial_y`, and a UI atlas's `images` (`icons.json`).

### quick_wheel

The same eight icons, on a wheel held open by Tab or the left shoulder button.
Releasing the button chooses. A stick released a moment before the button still
chooses; a stick at rest chooses nothing. The world drifts at a quarter speed
while the wheel is open.

**Uses:** `UI::RadialMenu` with `trigger:`, `UI::Pointing`'s grace window,
`UI::Menu#on_opened` / `#on_closed`, `InputMap.default.merge`.

### skill_bar

A tool bar with five tools in a row. Left and right step through them and Enter
uses one. The number keys use a tool directly, without moving the focus. Holding
a number uses its tool once. Pressing a tool's number and Enter together also
uses it once.

**Uses:** `UI::Row`, `UI::Stepping` taking its axis from the layout,
`UI::Button`'s `hotkey:` and `activate_on: :press`, captioned `UI::IconButton`s
on a disc `UI::ShapeStyle`, `InputMap.default.merge`, and a UI atlas's `images`
(`skills.json`).

## Audio

### sound

A sound effect fired by a button, and the path it travels. A node may not name
the audio device, so it emits a fact and a director plays it.

**Uses:** `Core::Sample`, `Engine::AudioBus`, `Engine::AudioDirector`,
`Engine::Text`.

### music

The other kind of sound: one streamed voice. You can stop it and ask whether it
plays, and starting it again does not restart it.

**Uses:** `Core::Song`, `AudioBus.play_music` / `.stop_music`,
`Engine::AudioDirector`.

## Players and input

### split_screen

Two players in one world. `WorldView` draws the world once per viewport, through
that viewport's camera. The world never knows how often it is drawn.

**Uses:** `Game.new(players: 2)`, `Engine::Players`, `Engine::WorldView`,
`Engine::PlayerLayer`, `Engine::Camera`, `Components::CameraFollow`,
`input_owner`.

### input_glyphs

Prompts that match the device in the player's hands. They switch between
keyboard and controller mid-session. Nothing listens for a plugged-in pad; using
the pad takes the seat.

**Uses:** `Controls.gamepad?`, `InputMap#button_for`, `Engine::Players` with
`on_unassigned_input` defaulting to `:takeover`, `renderer.sprite`.

## The window

### fullscreen

Opening fullscreen, switching while the game runs, and all four scale modes with
the layout following each.

**Uses:** `RGame::Game.new(fullscreen:)`, `App#fullscreen?` / `#fullscreen=`,
`RGame::Game#scale_mode=`, the `view` a node is drawn with,
`InputMap.default.merge`.

## Language

### localization

The same screen in English and German. A `Text` with a `count` picks its plural
form, and one with a variable shows the current locale. German lacks one key, so
that line falls back to English. The player's language choice overrides the
operating system's and is saved.

**Uses:** `Engine::I18n`, `Engine::Text` and `Text.literal`, `UI::Menu`'s
`scope:`, `RGame::Game.new(locales:)`, `RGame::Core.preferred_locales`,
`Util::SaveFile`.

### intro

A story on a black screen, three centred lines at a time. The translation table
holds it as one line, and the label breaks it to fit 440 pixels. In German it
takes ten lines and a fourth page, where English takes eight and three. Each
page types itself out at 40 characters a second. Enter shows the rest of a page
still typing and turns a page already shown. A one-shot timer turns it six
seconds after it is fully shown.

**Uses:** `UI::Label` (`reveal:`, `revealed?`, `reveal_all`),
`Engine::Paragraph`, `Util::Typeface`, `Components::Timer` (`repeating: false`,
reset every tick while a page types).

## Persistence

### save_load

Writing game state to disk and restoring it. The tree is not saved: a scene is a
recipe, and a save file is state. The variable holding a singular thing restores
it, and array order restores a flock.

**Uses:** `Util::SaveFile`, the `examples/walk` composition with a
`WanderController`.

### save_load_ids

The case `save_load` leaves out: a collection whose members can be lost, and one
saved object that refers to another. A reference forces ids; a changing
collection alone does not.

**Uses:** `Components::Identity`, `Util::SaveFile`, a save of records rather
than positions.
