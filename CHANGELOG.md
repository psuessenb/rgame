# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) —
which before 1.0 means the public API can still change in a minor release.

Entries describe what changed for someone *using* the engine. The reasoning
behind a change belongs in the documentation it lands with; this file is the
index, not the argument.

## [Unreleased]

## [0.2.0] - 2026-08-26

### Added

- **Split-screen.** A game has seats (`RGame::Game.new(players: 2)`), and a
  `RGame::Engine::Player` owns a device, a binding table, a camera and a region
  of the screen. The shared world is updated once and drawn once per viewport by
  a `WorldView`. Which player a node answers to is inherited down the tree like
  its transform, so `ship.input_owner = players[1]` moves a whole subtree.
  New: `Player`, `Players`, `Viewports`, `View`, `WorldView`, `Layout`.
- **`RGame::Engine::InputMap`** — one binding table per player, written in terms
  of physical ids from `RGame::Util::Controls`, so a game names keys and pad
  buttons in one place and reads named actions everywhere else.
- **Draw bands** (`RGame::Util::Z`): `:world`, `:hud`, `:overlay` and `:debug`.
  A band beats every `z` in the tree, so nothing in the world can draw over the
  HUD. Inherited down the tree, and set by the nodes that exist to mark one.
- **Culling** (`RGame::Engine::Culling`, `view.visible?`), which stops being an
  optimisation once the world is drawn once per player.
- **A bare-bones UI package**: `PlayerLayer` gives a player their own screen, and
  `UI::Menu` / `UI::MenuItem` navigate it by focus and activation — enough for
  keyboard and controller menus. Layout, nesting, scrolling and text entry are
  not in it; see [docs/api/ui.md](docs/api/ui.md).
- **Pausing** (`Node2D#paused`), which stops `control` and `update` for a node
  and its whole subtree while it keeps drawing — a frozen world under a cutscene
  overlay that goes on animating.
- `Components::CameraFollow`, and `TileMapLayer` as a node of its own.
- **`tools/drive_example.rb`** — boots an example unmodified, feeds it a
  scripted input backend and reports what the game actually asked for: draws,
  clips, sounds, scenes, ticks against frames.
- **macOS and Windows support**, and CI that runs every verification tier on
  all three platforms.
- This changelog, linked from the gem's RubyGems page through `changelog_uri`.

### Changed

- `Node2D#draw` and `on_draw` take the viewport being drawn into:
  `on_draw(renderer, view)`. Most nodes ignore it; laying out against the edges
  of a player's region, and culling, need it.
- `z` orders a node among its **siblings** only. It is never added to anything
  and never reaches the renderer, so a node's whole subtree draws before or
  after a sibling's, never interleaved with it. This replaces the additive
  `abs_z = parent.abs_z + z`, under which a node at z 2 with a child at z 5
  resolved to 7 and overtook a sibling at 4.
- `F2` quits and `F1` toggles the debug overlay. `Esc` is deliberately left to
  the game, because it is the button a player expects to back out of a menu.
- Reading an action no `InputMap` declares raises `KeyError` instead of reading
  as "never pressed" forever.

### Removed

- `RGame::Engine::CameraView`. A camera belongs to a `Player` and is applied by
  the `View` being drawn.

## [0.1.0] - 2026-08-20

First release, and the first version that runs a game end to end.

### Added

- **The C engine**, as two Ruby extensions built from one source tree: an SDL2
  window and a fixed-timestep main loop, keyboard and gamepad input with
  hot-plug, a z-sorted batching renderer with transforms, clipping and baked
  recordings, text from a shipped TrueType font, and audio (samples and
  streamed Ogg Vorbis or WAV).
- **`RGame::Core`** — the half that owns the window, the GPU and the sound
  device: `App`, `Input`, `Gamepad`, `Image`, `Renderer`, `Recording`, `Font`,
  `Audio`, plus the asset layer (`AssetManager`, `SpriteSheet`, `NineSlice`,
  `UIAtlas`, `TileMapRenderer`).
- **`RGame::Util`** — the graphics-free half, so values can be required with no
  SDL and no OpenGL in the process: `Tensor`, `Color`, `Controls`.
- **`RGame::Engine`** — the scene graph a game is written in: nodes,
  components, signals, sprites, tile maps, collision and pathfinding. Pure
  Ruby, and unable to name `RGame::Core` at all, which is what lets game logic
  and its specs run with no display.
- **`RGame::Game`** — the entry point that wires the two halves together.
- Examples: `14_asteroids`, `15_tiled_world`, `16_hello_world`.

[Unreleased]: https://github.com/psuessenb/rgame/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/psuessenb/rgame/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/psuessenb/rgame/releases/tag/v0.1.0
