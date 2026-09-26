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

### collectables

Coins taken by walking over them, and a chest opened with a press. Two ways of
reaching a thing, and neither is written in the hero: a coin carries a
`Collectable` that acts on the contact, and the chest is found by an
`Interactor`, which is a `Targeting` plus a button. Opening it spills three more
coins, which are the same coin as the ones the room started with. The prompt is
drawn over `interactor.target`, so it appears before the press rather than
after.

**Uses:** `Components::Collectable`, `Components::Interactor`,
`Components::CollisionWorld`, `Components::CircleCollider`,
`Components::BoxCollider`, `Components::CharacterBody` with
`blocked_by: [:interactable]`, `Engine::Text`.

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
because the part that collides never leaves the ground. A hop over a gap in the
floor is [pits](#pits).

**Uses:** `Components::Hop`, `Node2D#elevation`, `Components::AnimatedSprite`,
`Components::FeetCollider`, `Components::CharacterBody`, `Components::TileWorld`,
`Components::CameraFollow`, `InputMap.default.merge`.

### pits

Falling into a gap, hopping across one, and coming back. A walk into the chasm
drops the hero, who shrinks toward their feet and comes back flashing on the
spot they started from, able to walk at once. A hop crosses a trench, because a
node in the air never falls. A hop pressed just after walking off an edge still
counts, and a bar shows that coyote time running out. C turns it off.

**Uses:** `Components::Footing`, `Components::Respawn`, `Components::Hop`,
`Node2D#scale`, `TileMap#gap_tile?`, `Components::TileWorld`,
`Components::CharacterBody`, `Components::FeetCollider`.

### moving_platforms

A raft shuttling across a chasm, boarded with a timed hop. The raft stops 12 px
short of each bank and a hop carries 40 px, so a hop timed for when it comes
close lands on it. On board, the raft carries the hero and the camera follows.
Walking off its edge, or a hop that misses, falls into the chasm. The raft and
its route are a polyline object on the map, and it draws its planks from a sheet
over Tiny Town's tiles.

**Uses:** `Components::Platform`, `Components::PathFollow` with `loop: true`,
`Path.from_object`, `MapObjects`, `Components::Footing`, `Components::Respawn`,
`Components::Hop`, `Components::CameraFollow`, `TileMapLayer.mount` with `slots:`.

### push_pull

Crates pushed by walking into them, and one pulled back out with a held button.
Each crate is a `Pushable` that declares what stops it, so a crate pushed into a
wall moves nothing and the hero stops flush behind it, and a crate pushed into
another crate pushes that one too. Holding Left Shift beside a crate hands it to
the hero's `Grab`, and the hero's body drags it whichever way they walk.

**Uses:** `Components::Pushable`, `Components::Grab`, `Components::CharacterBody`
with `blocked_by: %i[wall crate]` and `pushes: [:crate]`,
`Components::CollisionWorld`, `Components::BoxCollider`, `Engine::Text`.

### block_puzzle

Blocks pushed one cell at a time onto marked squares. A block is not a
`Pushable`: it is a solid cell of the map, held by `OccupiesCell`, so the hero
stops at it through `blocked_by: [:tiles]`. Pressing into it for a moment shoves
it a cell, if `TileWorld#solid?` says the cell beyond is free, and a `Tween`
slides it there. The push is the example's own rule, written against
`on_blocked` and `on_unblocked`.

**Uses:** `Components::OccupiesCell`, `Components::Tween`,
`Components::TileWorld`, `Components::CharacterBody` with `on_blocked` and
`on_unblocked`, `WorldView`, `TileMapLayer.mount`, `Engine::Text`.

### doors

A gate between the town and a garden, and a pair of warp pads. Each room is a
`Scene::Room` built over its map, and the doors come from the map's object
layer. A door is a box with a `Collectable` that asks the rooms for a move, to
the room and the entrance its properties name. The garden is built as the hero
walks in and the town freed, since nobody is left in it. A pad moves the hero
within the garden, which only places it again.

**Uses:** `Scene::Rooms`, `Scene::Room`, `Scene::Fade`, `TileMap#object_named`,
`MapObjects`, `Components::Collectable` with `free: false`,
`Components::TileWorld`, `TileMapLayer.mount`, `Engine::Text`.

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

**Uses:** `Signal::DSL`, a signal with a payload, `Components::ActionTrigger`,
the connect handle.

### timer

Periodic behaviour that no input drives: a spawn cadence and two cadences on one
node, and beside them a one-shot banner whose fuse burns down.

**Uses:** `Components::Timer` (and `as:`), `Engine::Timer`, `Components::Tween`
(`value`, `on_finished`).

### pooling

Spawning many things without building any of them. The allocation count on
screen makes the case.

**Uses:** `Components::Pool`, `Engine::Pool`, `Components::DespawnOffscreen`,
`Components::Timer`, `Engine::Text`.

### effects

A dark room with a torch streaming embers. Enter covers it in black and reveals
it again, L strikes a lightning bolt that flashes the room white, and Space
bursts sparkles. Nothing builds a colour once it runs: the fades and the bolt
change their opacity, and each particle reads its colour off a ramp.

**Uses:** `Engine::ScreenFade`, `Components::Particles`, `Util::ColorRamp`,
`Node2D#opacity`, `Renderer#blended`.

## UI

### game_menu

A menu that opens over a running world. Pausing belongs to a node, so only the
hero stops while the villagers walk on.

**Uses:** `PlayerLayer`, `UI::PanelMenu`, `UI::PanelButton`, `UI::Menu#open` /
`#close`, `Node2D#paused`, `renderer.nine_slice`.

### menu_navigation

Several screens (title, settings, back) and settings that change something real
and survive a restart. It contrasts pushing a scene with replacing one, and
asks for each scene by the name the stack was given. Play fades out and in;
Settings, pushed over the title, does not.

**Uses:** `Scene::SceneStack` and its `define`, `Scene::Fade`, `UI::OptionButton`, `Util::SaveFile`,
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

### inventory

A bag of twenty items in a grid of four columns, three rows of it in view, and a
column of two verbs, Use and Drop, beside it. Focus leaving the window scrolls the
bag a row, and marks beside it show rows out of view. Right from the end of a row
crosses into the verbs, and left crosses back. A panel under the bag names the
item last focused there, which the verbs act on. Dropping an item takes it out of
the bag. Q and E, or the shoulder buttons, switch to a second page of key items
and back, and each page keeps its focus and scroll.

**Uses:** `UI::Tabs`, `UI::Grid` with `visible_rows:`, `UI::Stepping` across a
grid, `UI::FocusGroup`, `UI::PanelMenu`, uncaptioned `UI::IconButton`s on a
`UI::ShapeStyle`, and a UI atlas's `images` (`skills.json` and `icons.json`).

### equipment

A character dressed from a column of three slots, Head, Body and Feet, and a
grid of six pieces two to a row, a row to a slot. Right from a slot crosses to
the pieces that fit it. Enter on a piece wears it in place of what its slot
held, and Enter on a slot takes its piece off. An empty slot says so and keeps
focus. The character is `hero.png` drawn five times its size, with the worn
pieces drawn over it as shapes. E switches to the bag, where a panel names the
focused piece and says whether it is worn. One object holds what each slot
wears, and every screen reads it.

**Uses:** `UI::Tabs`, `UI::FocusGroup`, `UI::Grid`, a `UI::Button` subclass that
draws its piece, a `UI::PanelButton` subclass overriding `draw_foreground`,
`UI::ShapeStyle`, `renderer.scaled` and `renderer.sprite`.

## Audio

### sound

A sound effect fired by a button, and the path it travels. A node may not name
the audio device, so it calls the `AudioOut` system, which holds it.

**Uses:** `Core::Sample`, `Engine::AudioOut`, `Node2D#system!`, `Engine::Text`,
`Engine::Tween` (the ring's flash).

### music

The other kind of sound: one streamed voice, faded in and out over a second,
paused and resumed. Asking for it while it plays does not restart it, and asking
for it while it fades out brings it back up. Up and Down set the music's
category volume and Left and Right the effects', with a blip to hear them by.
It is the example to judge by ear whether a fade stepped once a tick sounds
smooth.

**Uses:** `Core::Song`, `AudioOut#play_music` / `#stop_music` with `fade:`,
`AudioOut#pause_music` / `#resume_music`, `AudioOut#set_category_volume`,
`Engine::Tween` (`loop: true`, the playhead).

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

### input_holds

One button that opens a chest when tapped and searches it when held, and a chord
that swaps stance. The thresholds are declared in the map, so nothing in the
example counts a second for itself.

**Uses:** `InputMap` with `tap:`, `hold:` and `all:`, `Actions#held_for`,
`InputMap.default.merge`, `renderer.rect`.

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
still typing and turns a page already shown. A one-shot tween turns it once it
has been fully shown for a second, plus 20 milliseconds for each character.

**Uses:** `UI::Label` (`reveal:`, `revealed?`, `reveal_all`, `page_length`),
`Engine::Paragraph`, `Util::Typeface`, `Components::Tween` (`stop` while a page
types, `start` once it is shown).

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

## Conversation

### dialogue

One branching conversation on a black screen, and nothing else. Enter begins
it, and an innkeeper greets the player and asks what they want. Each of three
questions leads back to that question, one of them by a question of its own, and
a fourth response says goodnight. Once the conversation ends, Enter begins it
again from the start. Read this one first; `quests_and_dialogue` builds on it.

**Uses:** `Dialogue::Script`, `Engine::Dialogue`, `UI::DialogueBox`.

### quests_and_dialogue

A village where a conversation moves a quest on. The smith has lost a hammer:
asking for work starts the quest, the hammer appears by the well, and handing
it back pays 40 gold. That is what makes "I'll take a lantern." appear among the
responses. Enter talks to the smith when the hero stands within reach, and
walking into the signpost reads it. L opens the box's log. F5 saves the facts,
which hold the quest and the smith's conversation, with the hero's gold; F9
loads them. The quest and the conversation never name each other: the smith's
script asks the village, and the village fires the quest's events.

**Uses:** `StateGraph`, `StateMachine`, `Components::FactsDatabase`,
`Dialogue::Script`, `Engine::Dialogue`, `UI::DialogueBox` and its
`_draw_portrait` hook, `Components::CollisionWorld#nearest`,
`Components::BoxCollider#on_hit`, `Util::SaveFile`.

### cutscene

A town crier's news, which everybody watches. The screen becomes one view
through the cutscene's camera, the heroes stop, and the crier walks to the
square, speaks, and waits for a press. Holding Tab skips it, and the town ends
the same either way: the crier in the square, the gate open, and the screen
split again. The script is a constant, and the component gives back everything
it stopped.

**Uses:** `Cutscene::Script`, `Components::Cutscene`, `Components::PathFollow`,
`UI::DialogueBox`, `Viewports#solo!`, `InputMap` with `hold:`.
