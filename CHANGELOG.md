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

- **`rgame new NAME`** — the gem now installs an `rgame` command that scaffolds
  a project: a game class, a root node, a passing spec suite, a RuboCop config
  that is green, a Gemfile, a Rakefile and a README. The layout it writes is the
  engine's own layering — `game.rb` is the only file that loads SDL, so `nodes/`
  and `spec/` stay graphics-free and the generated suite runs with no display.
  It also writes a `.ruby-version` holding the Ruby that ran the command, with
  the Gemfile pointing at that file rather than repeating the number.
  Also `rgame version` and `rgame help`. See [docs/api/cli.md](docs/api/cli.md).

- **BoxColliders for rectangular shaped collision bodies.** Adding a second shape of colliders, which can be used with the already existing `CollisionWorld`. Also extended both `CollisionWorld` and the underlying `SpatialHash` with some utility methods for grid-based collisions. 

- **A UI atlas can name images.** A descriptor's `images` section cuts whole
  rectangles from the sheet, `UiAtlas#images` holds them, and
  `Renderer#register_ui_atlas` registers each under its name — so a strip of
  icons reaches `UI::IconButton.new(image: :home)` in one call.

### Changed

- **`Node2D`'s internal methods start with `_`, and a subclass may not redefine
  them.** A subclass of `Node2D` or `Component` defining a method named like
  one of the base class's underscored private or protected methods now raises
  `NameError` where the class is defined; before, it silently replaced engine
  machinery for that class. `Node2D#draw_children` keeps its name and stays
  overridable. See [docs/api/scene_graph.md](docs/api/scene_graph.md).

- **Drawing happens in local space.** `Node2D#draw` pushes the node's transform
  onto the renderer before running `on_draw` and descending into children, so a
  node draws at its own origin: `renderer.rect(0, 0, width, height)`. Passing a
  position applies it a second time, so an `on_draw` that drew at
  `abs_x`/`abs_y` now drops the coordinates. Components do the same — `Sprite`
  and `AnimatedSprite` pass neither a position nor an angle — while culling
  stays in world coordinates and asks the node for one by name
  (`node.world_x`).
  See [docs/api/scene_graph.md](docs/api/scene_graph.md).
- **`abs_x`/`abs_y`/`abs_angle` are now `world_x`/`world_y`/`world_angle`, and
  are computed when read and cached** instead of being resolved by every phase.
  Moving a node — or reparenting it — marks its subtree stale, and the next read
  recomputes only what it needs. A world position is therefore never stale: a
  node whose ancestor moved, a node just reparented, and a paused node under a
  moving ancestor all answer correctly at any point in any phase, where the
  resolved value used to lag a tick behind. A frame in which nothing moves
  computes nothing at all.
  The parent-relative transform is `rel_x`/`rel_y`/`rel_angle`, which keep
  `x`/`y`/`angle` as their short names, and the ivar behind it is `@rel_x` —
  `@x` no longer exists. `abs_band` and `abs_input_owner` keep their names:
  those are inherited from an ancestor rather than expressed in a space.
- **`UI::Menu` is built from a layout and a navigation.** `Menu.new` takes
  `layout:` — `UI::Column.new(item_width:, item_height:, spacing:)` for the
  vertical list it used to be — and `navigation:`, defaulting to `UI::Stepping`,
  which is the up/down focus it always had. `UI::Ring` and `UI::Pointing` make
  the same class a radial menu that focuses whatever a stick points at, reading
  the new universal actions `ui_radial_x` / `ui_radial_y`. A subclass of
  `UI::Navigation` is a third way to move focus. `Menu#focus_by` is now
  `Stepping#step`, and `Menu#focused` can be `nil`.
  **A menu is handed its buttons**: `Menu#add(button)` replaces `add_item`,
  `add_option` and `style:`, and `items` is now `buttons`. `UI::Button` is the
  base a game subclasses for a look of its own; `MenuItem` is now
  `UI::PanelButton` and `OptionItem` `UI::OptionButton`. **Confirm activates on
  release** by default, and a button built with `activate_on: :press` activates
  on the way down and stays drawn pressed for `Button::PRESS_FEEDBACK`. A menu
  acts only on a press it saw start, so a submenu opened by a press no longer
  activates from that same press. A layout answers `bounds(buttons)` and a menu
  exposes it as `bounds_x`/`bounds_y`/`bounds_width`/`bounds_height`;
  `UI::PanelMenu` draws a nine-slice round them, so a panel grows with its menu.
  **A button draws its background from a style**: `UI::NineSliceStyle` (an atlas
  element per state) or `UI::ShapeStyle` (a rect or disc per state, no art
  needed), or any object answering `draw(renderer, state, width, height)`.
  `UI::TextButton` is a label on a style, and draws with nothing registered;
  `PanelButton` is now a `TextButton` whose `PanelButton::STYLE` is a
  `NineSliceStyle` — read its names with `STYLE.elements` and vary it with
  `STYLE.with(...)` — and its label colours are `label_color:` and
  `disabled_label_color:`. `UI::IconButton` draws an image tinted and scaled by
  state, with an optional caption. A style may answer `content_color(state)`, and
  the buttons draw their label or icon in it: `ShapeStyle`'s `content:` defaults
  to dark while pressed, so a pressed label or icon reads on the gold fill. Drawing a `PanelButton` or `OptionButton` no
  longer allocates. `UI::RadialMenu` is a `Menu` that builds its own `Ring` and
  `Pointing` and draws the wheel's backdrop, dead zone and pointer.
  **`UI::Row`** lines buttons up side by side; it and `Column` are one `UI::Stack`,
  and every layout answers `axis`. **`Stepping` steps along the layout's axis**,
  so a `Row` moves with left and right, and `Stepping.new(axis:)` overrides it;
  stepping focus no longer allocates. **`navigation: nil`** builds a menu that
  never moves focus by itself. **`Button hotkey:`** names an action that presses
  the button whether or not it is focused, activating on the press and leaving
  focus where it was; `press`, `release` and `cancel_press` take the source,
  `:confirm` or `:hotkey`, so neither can end the other's hold, and
  `activate_with_feedback` is the instant press on its own. A captioned
  `IconButton` draws its style only above the caption, which keeps its own
  colours rather than the style's content colour.
  **A menu is open or closed**: `open?`, `open` and `close`, with `on_opened` and
  `on_closed` signals; a closed menu draws nothing and takes no input.
  **`Menu trigger:`** names an action that holds a menu open — the quick wheel
  opened by a shoulder button and chosen by letting go — activating the focused
  button on its release. **`Pointing grace:`** keeps focus for a moment after the
  stick comes home, `Pointing::GRACE` (0.15 s) by default on a menu with a
  trigger. A navigation may define `update(dt)` and `on_opened`.
  See [docs/api/ui.md](docs/api/ui.md).

- **Engine internals are no longer public.** `Renderer`'s raw `draw_*`, `push_*`,
  `pop`, `next_layer_slot` and `*_record` methods are private, as are
  `Recording#draw_at` and `Song#play_looping`. Call `rect`, `translated`,
  `record`, `Recording#draw` and `Song#play` instead, which apply the z offset
  and the colour and always pop what they push. `Node2D#sibling_order` and
  `#children_unsorted!` are gone from the public API, and so are
  `AnimationSet::Anim` and `UI::Menu::ClosedSignal`. The Tiled parse helpers
  `TileMap.layer_flag?`, `Tileset.parse_animation` and `Tileset.collision_shape?`
  are private class methods now.

### Fixed

- The README's hello-world gave `on_draw` one parameter; it takes two
  (`renderer, view`).
- A newly built `UI::Menu` reported its first item as focused without telling
  the item, so it drew with no highlight until the first press.

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
