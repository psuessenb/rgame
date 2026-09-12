# Examples

`examples/` holds one small program per concept. Each is a single `main.rb` that
runs on its own:

```
ruby examples/walk/main.rb
```

They answer "how do I do *X*", which is the one thing the complete games under
`test_projects/` are bad at. An example is one concept, in one file, with a
header comment that explains the concept at length — this page is the index, and
the file itself is the long version.

Every example is also acceptance-tested rather than only opened by hand. A
scripted input track lives at `tools/drive/examples/<name>.rb`, and the harness
feeds it to the unmodified program and reports what the game asked for:

```
ruby tools/drive_test_project.rb examples/walk/main.rb --ticks 240
```

Assets are committed under `examples/assets/` and are redistributable, so
everything here runs from a fresh clone. Most examples need no art at all.

## Movement and drawing

### walk

A player-controlled sprite, and the smallest complete game there is: a plain
node with three components on it, none of which knows about the others.

**Uses:** `Node2D`, `Components::AnimatedSprite`, `Components::CharacterBody`,
`Components::PlayerController`, `InputMap.default`.

### sprite

One frame drawn at a node, with no animation behind it — what most things in a
game are. It passes no position and no angle, because the node's transform is
already applied.

**Uses:** `Components::Sprite`, `Image#subimage`, `renderer.register_image`.

### velocity

The other way a node moves. A character has an *intent*; a rock has a velocity
and something integrates it, including its spin.

**Uses:** `Components::Velocity`, `Components::ScreenWrap`, `Components::World`,
`Components::WorldBounds`.

## The world

### scroll_map

A Tiled map larger than the window, scrolled by a player. There is no "pan the
camera" call: a camera is pointed by a component on a node, so scrolling is
walking.

**Uses:** the `:tilemap` asset loader, `Components::TileWorld`, `TileMapLayer`,
`WorldView`, `Camera`, `Components::CameraFollow`.

### collision

Object-to-object collision: a scene-scoped system pairs up shapes each step and
tells both sides they overlapped, without knowing what either of them is.

**Uses:** `Components::CollisionWorld`, `Components::CircleCollider`,
`Components::BoxCollider`, `Components::Velocity`, `Engine::CachedLabel`.

### collision_tiles

The other collision problem, which shares no code with the first: a character
against a grid of solid tiles, sliding along a wall held diagonally.

**Uses:** `Components::TileWorld`, `Components::TileCharacterBody`,
`Engine::CollisionBox`, `Components::CameraFollow`.

## Structure

### signals

Declaring a signal of your own. A pressure plate announces that it was pressed
and stops there; the door and the lamp connect to it and appear nowhere in the
plate.

**Uses:** `Signal::DSL`, `Signal.define`, `Components::ActionTrigger`, the
connect handle.

### timer

Periodic behaviour that no input drives — a spawn cadence and a one-shot, with
two cadences on one node.

**Uses:** `Components::Timer` (repeating and `repeating: false`, and `as:`),
`Engine::Timer`.

### pooling

Spawning a lot of things without building any of them, with the allocation
count on screen as the argument.

**Uses:** `Components::Pool`, `Engine::Pool`, `Components::DespawnOffscreen`,
`Components::Timer`, `Engine::CachedLabel`.

## UI

### game_menu

A menu that opens over a world which keeps running: pausing is a property of a
node, so only the hero stops while the villagers walk on.

**Uses:** `PlayerLayer`, `UI::Menu`, `UI::MenuItem`, `Node2D#paused`,
`Node2D#draw_children`, `renderer.nine_slice`.

### menu_navigation

More than one screen — title, settings, back — and settings that change
something real and survive a restart. Shows the difference between pushing a
scene and replacing one.

**Uses:** `Scene::SceneStack`, `UI::OptionItem`, `Util::SaveFile`,
`RGame::Game`'s fullscreen, scale mode and volume.

## Audio

### sound

A sound effect fired by a button, and the seam it travels through: a node may
not name the audio device, so it emits a fact and a director plays it.

**Uses:** `Core::Sample`, `Engine::AudioBus`, `Engine::AudioDirector`,
`Engine::CachedLabel`.

### music

The other kind of sound: one streamed voice that can be stopped and asked
whether it is playing, and a start that does not restart it.

**Uses:** `Core::Song`, `AudioBus#play_music` / `#stop_music`,
`Engine::AudioDirector`.

## Players and input

### split_screen

Two players in one world, drawn once per viewport through that viewport's
camera. The world does not know how many times it is drawn.

**Uses:** `Game.new(players: 2)`, `Engine::Players`, `Engine::WorldView`,
`Engine::PlayerLayer`, `Engine::Camera`, `Components::CameraFollow`,
`input_owner`.

### input_glyphs

Prompts that match the device in the player's hands, switching between keyboard
and controller mid-session. Nothing listens for a pad being plugged in — using
one is what takes the seat.

**Uses:** `Controls.gamepad?`, `InputMap#button_for`, `Engine::Players` with
`on_unassigned_input` defaulting to `:takeover`, `renderer.sprite`.

## The window

### fullscreen

Opening fullscreen and switching while the game runs, plus all four scale modes
and the layout following each.

**Uses:** `RGame::Game.new(fullscreen:)`, `App#fullscreen?` / `#fullscreen=`,
`RGame::Game#scale_mode=`, the `view` a node is drawn with,
`InputMap.default.merge`.

## Persistence

### save_load

Writing game state to disk and putting it back. The tree is not saved: a scene
is a recipe and a save file is state, so a singular thing is restored by the
variable holding it and a flock by array order.

**Uses:** `Util::SaveFile`, the `examples/walk` composition with a
`WanderController`.

### save_load_ids

The case the previous one deliberately does not cover: a collection whose
members can be lost, and one saved object referring to another. A reference is
what forces ids, not a changing collection.

**Uses:** `Components::Identity`, `Util::SaveFile`, a save of records rather
than positions.
