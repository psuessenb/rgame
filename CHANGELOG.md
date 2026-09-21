# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html) —
which before 1.0 means the public API can still change in a minor release.

Entries describe what changed for someone *using* the engine. The reasoning
behind a change belongs in the documentation it lands with; this file is the
index, not the argument.

## [Unreleased]

### Added

- **Text can be measured without a window.** `RGame::Util::Typeface` loads with
  `require 'rgame'`, needs no graphics library, and gives the same width as
  `RGame::Core::Font` for the same file and size. `Typeface#text_lines` breaks
  a string into lines that fit a width, and at each newline. See
  [docs/api/text.md](docs/api/text.md#measuring-without-a-window).
- **A translated text breaks into lines that fit a width.**
  `RGame::Engine::Paragraph` takes a key or an `Engine::Text` and a width. It
  breaks the text again when a variable, the language or the width changes, and
  an unchanged read allocates nothing. `lines_per_page:` groups the lines into
  pages for a dialogue box. See
  [docs/api/text.md](docs/api/text.md#a-paragraph-that-follows-the-language).
- **A node draws with the typeface it measured with.** `Renderer#text` takes a
  `RGame::Util::Typeface` as `font:` and draws it through a font the renderer
  builds once and keeps. `Renderer#typeface` returns the typeface `text` uses by
  default. `RGame::Core::Font.new(app, typeface)` builds a font on a typeface,
  and `Font#typeface` returns it; `Font.new(app, 18)` and `path:` still work.
  See [docs/api/text.md](docs/api/text.md#drawing-with-a-typeface).
- **A label draws a translated paragraph a page at a time.**
  `RGame::Engine::UI::Label` breaks its text at its width, aligns each line
  left, centred or right, and draws `lines_per_page:` lines at once. It follows
  a variable or a language switch with no call of its own, and its owner turns
  the page with `page=`. See
  [docs/api/ui.md](docs/api/ui.md#rgameengineuilabel).
- **An intro example.** `examples/intro` tells a story a page at a time through a
  `UI::Label`, turned by Enter and by a timer. Its tables hold the story as one
  line, and German takes a page more than English. See
  [docs/api/examples.md](docs/api/examples.md#intro).

### Changed

- **`Game/NoLiteralText` also checks `text_lines`.** A String literal as the
  first argument of `text_lines` is an offense, as it is for `text` and
  `text_width`.

### Fixed

- **A one-shot timer can re-arm itself.** `Components::Timer#reset` called from
  the timer's own `on_timeout` handler was undone as the handler returned, so a
  `repeating: false` timer never fired again. It now fires one interval later.

## [0.4.0] - 2026-09-16

### Added

- **`gem install rgame` needs no compiler and no SDL2 on a common desktop.**
  Apple Silicon Macs, x86-64 Linux and 64-bit Windows get a gem whose two
  extensions are already built, with SDL2 linked into them. Every other machine,
  and every Ruby but 4.0, installs the source gem and compiles it as before.
- **A virtual gamepad for tests.** `RGame::Core::VirtualGamepad.new` plugs a
  synthetic controller into a running `App`, which seats it and reads it like a
  real pad; `set_button`, `set_axis` and `detach` drive it. See
  [docs/api/input.md](docs/api/input.md#rgamecorevirtualgamepad).

## [0.3.1] - 2026-09-15

### Fixed

- `require "rgame"` failed under Bundler with `cannot load such file --
  rexml/document`. The gem now declares `rexml` as a dependency, which Ruby 4.0
  no longer loads without one.

## [0.3.0] - 2026-09-15

### Added

- **`rgame new NAME`.** The gem installs an `rgame` command, and `rgame new`
  generates a project: a game class, a root node, an English translation table,
  and a spec suite and RuboCop config that pass. Only `game.rb` loads SDL, so the
  generated specs run without a display. See [docs/api/cli.md](docs/api/cli.md).
- **RuboCop cops for games.** The gem ships rgame's `Game/` cops as a RuboCop
  plugin, and `rgame new` enables them. They catch per-frame allocations, a node
  drawn at its own position twice, literal text and Core named from headless
  code. See [docs/api/cli.md](docs/api/cli.md#the-generated-rubocop-configuration).
- **Translation by default.** `RGame::Game` loads every `locales/**/*.yml` and
  picks the player's language from `RGame::Core.preferred_locales`. A node draws
  an `Engine::Text` built from a key, and a UI button's `label:` is a key. See
  [docs/api/localization.md](docs/api/localization.md).
- **Fullscreen and scaling.** `Game.new` takes `fullscreen:` and `scale_mode:`,
  and both can change while the game runs. `scale_mode:` maps the logical size
  onto the window, and defaults to `:letterbox`. See
  [docs/api/game.md](docs/api/game.md).
- **Saving.** `Util::SaveFile` reads and writes a game's state in the player's
  save directory. `Components::Identity` gives a node a stable id to save it
  under. See [docs/api/values.md](docs/api/values.md).
- **Box colliders.** `Components::BoxCollider` is a rectangle in the same
  `CollisionWorld` as `CircleCollider`. `FeetCollider` derives its box from the
  node's size, so a top-down character collides at its feet. See
  [docs/api/components.md](docs/api/components.md).
- **Movers that something can stop.** `CharacterBody`, `Velocity` and
  `PathFollow` share the base `Components::Mover`. Its `blocked_by:` lists what
  stops a step: solid tiles, the world's edge or collider layers. `on_blocked` and
  `on_unblocked` report the blocker and the axis. See
  [docs/api/components.md](docs/api/components.md).
- **Pathfinding.** `Engine::NavGrid` finds routes over a tile grid, and
  `TileWorld#nav_grid` hands one out. `Components::Navigator#go_to` walks a node
  there. The search runs in C, in `Util::SolidGrid`, `Util::RouteSearch` and
  `Util::TileSweep`. See [docs/api/toolbox.md](docs/api/toolbox.md).
- **`Components::World`** gives a scene its bounds without a tile map.
  `ScreenWrap` and `DespawnOffscreen` read the bounds from it or from
  `TileWorld`. See [docs/api/components.md](docs/api/components.md).
- **`Components::Hop`** lifts a character's picture off the ground through the
  new `Node2D#elevation`. Colliders and cameras ignore the lift. See
  [docs/api/components.md](docs/api/components.md).
- **New buttons and styles.** `UI::Button` is the base for a button with its
  own look. `TextButton`, `PanelButton`, `OptionButton` and `IconButton` draw
  their background from a `NineSliceStyle` or a `ShapeStyle`. A `hotkey:` presses
  a button without focusing it. See [docs/api/ui.md](docs/api/ui.md).
- **Menu layouts and navigations.** `UI::Menu` takes a `layout:` (`Column`,
  `Row` or `Ring`) and a `navigation:` (`Stepping`, `Pointing` or `nil`).
  `UI::RadialMenu` focuses whatever the stick points at. `UI::PanelMenu` draws a
  panel that grows with its buttons. See [docs/api/ui.md](docs/api/ui.md).
- **Menus open and close.** A menu answers `open?`, `open` and `close`, and
  emits `on_opened` and `on_closed`. A closed menu draws nothing and takes no
  input. `trigger:` names an action that holds a menu open while it is down. See
  [docs/api/ui.md](docs/api/ui.md).
- **A UI atlas can name images.** A descriptor's `images` section cuts
  rectangles from the sheet, and `Renderer#register_ui_atlas` registers each by
  name. `UI::IconButton.new(image: :home)` then draws one.
- **Input prompts.** `InputMap#button_for(action, device)` returns the bound
  button that device can press. `Controls.gamepad?` and `Controls.pad_button?`
  tell the two kinds of id apart. See [docs/api/input.md](docs/api/input.md).
- **Sounds by path.** `audio.play_sound` and `play_music` accept a path and
  load it through the asset manager on first use. `RGame::Game` subscribes an
  `AudioDirector`, so `AudioBus` sounds play without setup. See
  [docs/api/audio.md](docs/api/audio.md).
- **24 examples, one concept each.** Each is a single `main.rb` that runs on its
  own, from `walk` and `sprite` to `pathfinding` and `localization`. See
  [docs/api/examples.md](docs/api/examples.md).
- `AssetManager#glob` lists the files under the media root that match a pattern.
- `Util::Color` gains named colours, from `RED` to `DARK_GRAY`.

### Changed

- **A subclass may not redefine `Node2D`'s or `Component`'s internal methods.**
  Their private and protected machinery now starts with `_`. A subclass that
  defines one of those names raises `NameError` where the class is defined.
  Before, it silently switched that machinery off. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md).
- **Nodes draw in local space.** `Node2D#draw` pushes the node's transform
  before it calls `on_draw`, so a node draws at its own origin:
  `renderer.rect(0, 0, width, height)`. Drop `abs_x`/`abs_y` from draw calls, or
  the position applies twice. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md).
- **`abs_x`, `abs_y` and `abs_angle` are now `world_x`, `world_y` and
  `world_angle`.** A node computes them when read, so they are never a tick
  stale. `world_x=` and `world_y=` place a node in world space. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md).
- **`UI::Menu` is handed its buttons.** `Menu#add(button)` replaces `add_item`,
  `items` is now `buttons`, and `MenuItem` is now `UI::PanelButton`. The item
  size moves to `layout: UI::Column.new(...)`. Confirm activates a button when
  released. See [docs/api/ui.md](docs/api/ui.md).
- **`CharacterBody` takes its shape from a sibling collider.**
  `CharacterBody.new(speed:, blocked_by:)` replaces `feet_width:` and
  `feet_height:`. A body with no `blocked_by:` moves freely, and `TileWorld#move`
  is gone. See [docs/api/components.md](docs/api/components.md).
- **Contacts are edges.** `on_hit` fires once when two colliders start to
  overlap, and the new `on_separated` fires once when they part. Before,
  `on_hit` fired on every step of an overlap.
- **`I18n` reads YAML tables keyed by locale.** A key falls back from `de-AT`
  to `de` to the default. Plurals follow CLDR rules, and `I18n.missing` decides
  what a missing key shows. `load_file` is gone. See
  [docs/api/localization.md](docs/api/localization.md).
- **`ScreenWrap` and `DespawnOffscreen` work in world space**, so a node under an
  offset parent wraps at the world's edge. Their `width:` and `height:` are now
  optional. A node with two responses to the edge raises when the second
  attaches.
- **A component raises when its sibling is missing.** `PlayerController`,
  `WanderController` and `AnimatedSprite` name what they need when they attach.
  A node with two movers raises too.
- **`AnimatedSprite` follows any mover**, and faces along the larger axis of
  its heading.
- **Engine internals are private.** `Renderer`'s raw `draw_*`, `push_*`, `pop`
  and `*_record` methods, `Recording#draw_at` and `Song#play_looping` are
  private. Call `rect`, `translated`, `record`, `Recording#draw` and `Song#play`
  instead. The Tiled parse helpers are private too.

### Removed

- `Engine::CachedLabel`. Use `Engine::Text`.
- `Engine::Body`, `Engine::Actor`, `Engine::Matrix`, `Engine::Resettable` and
  `Engine::PlayerController`. None had a caller in the engine.
  `Components::PlayerController` stays.
- `Engine::TileCollision`, which is now `Engine::TileBlockers`.
- The examples `14_asteroids`, `15_tiled_world` and `16_hello_world`. They are
  whole games rather than examples of one concept, and no longer ship.

### Fixed

- The README's hello-world gave `on_draw` one parameter; it takes two
  (`renderer, view`).
- A new `UI::Menu` drew its first item without a highlight until the first
  press.
- `Path#distance_to` returned wrong distances for Integer coordinates.

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

[Unreleased]: https://github.com/psuessenb/rgame/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/psuessenb/rgame/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/psuessenb/rgame/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/psuessenb/rgame/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/psuessenb/rgame/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/psuessenb/rgame/releases/tag/v0.1.0
