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

- **Checkpoints.** `Components::Checkpoint` moves the respawn point of a node
  on its `by` layer to itself when that node's collider touches it, and emits
  `on_reached`. It raises over a gap, and for a toucher with no `Respawn`. See
  [docs/api/components.md](docs/api/components.md#checkpoint).
- **Moving platforms.** `Components::Platform` makes its node's box floor over
  the map's gaps, and `TileWorld#platform_under` names the one a point stands
  on. A node with a `Footing` boards the platform under it, and the mover that
  moves the platform carries every rider by its own step, through each rider's
  own `blocked_by:`. See
  [docs/api/components.md](docs/api/components.md#platform).
- **Routes that loop.** `Components::PathFollow` takes `loop: true`, and goes
  round a closed path or back and forth along an open one for good. `Path`
  takes `closed: true`, and `Path.from_object` reads a route from a map's
  polyline or polygon object. See
  [docs/api/toolbox.md](docs/api/toolbox.md#path--a-walkable-polyline).
- **`Mover#stopped?`** says whether a mover's step this update was cut short.
  See [docs/api/components.md](docs/api/components.md#mover).
- **A moving platforms example.** `examples/moving_platforms` shuttles a raft
  across a chasm, boarded with a timed hop. See
  [docs/api/examples.md](docs/api/examples.md#moving_platforms).
- **Falling into a gap, with coyote time.** `Components::Footing` drops a node
  whose box's centre stands off the floor, once it has been off it for more than
  `coyote` seconds, and at once when it lands there from a `Hop`. A node in the
  air never falls. The fall suspends the node and shrinks it into the gap, and
  `on_fell` fires as it starts. `Components::Respawn` then puts the node back
  on its respawn point, flashing, and a node without one is freed. A respawn
  point stands on ground: `Respawn` raises for one over a gap. See
  [docs/api/components.md](docs/api/components.md#footing).
- **A pits example.** `examples/pits` drops a hero who walks into a chasm and
  brings them back flashing, hops trenches, and shows coyote time running out
  in a bar. See [docs/api/examples.md](docs/api/examples.md#pits).
- **`Node2D#scale`**, a size a node and everything under it draws at, about its
  origin, applied by `draw` as `opacity` is. Only drawing changes. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#scale).
- **Gaps in a tile map, and a floor to stay on.** A tile whose Tiled class is
  `gap` makes its cell a gap, and `TileMap#gap_tile?` answers for a cell.
  `TileWorld#floor_at?` answers whether a point stands on the floor, and
  `TileWorld#ground_at?` whether its cell is not a gap. A mover declaring
  `blocked_by: [:gaps]` keeps the centre of its box on the floor, stopped by
  `Engine::GapBlockers`, and needs a `Components::Footing`. See
  [docs/api/tile_maps.md](docs/api/tile_maps.md#gaps) and
  [docs/api/components.md](docs/api/components.md#mover).
- **Y-sorted drawing.** A `Node2D` built with `y_sort: true`, or given
  `node.y_sort = true`, draws its children by `z`, then lower on the screen
  later, then in the order added. A child stands at the bottom edge of its
  `BoxCollider` box, or at its `y` if it has none. `control` and `update` keep
  the order they had. `TileMapLayer.mount` y-sorts the actors' place, and
  `mount(..., y_sort: false)` does not. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#y-sort).
- **Sprites take an anchor.** `Components::Sprite` and
  `Components::AnimatedSprite` take `anchor:`, one of `:center`, `:bottom` and
  `:top_left`, and put the picture's centre, bottom centre or top-left corner
  on the node's origin. The two cover the same pixels for the same anchor and
  size. See [docs/api/components.md](docs/api/components.md#sprite).
- **Rooms that players stand apart in.** `RGame::Engine::Scene::Rooms` runs
  every room a player stands in, each a `Scene::Room` built anew as it starts
  running. `define(name) { Room.new }` names a room, and `move(hero, to:,
  entrance:)` moves one node or an Array of them, landing in the sweep under a
  cover over each moving player's region alone. A room's `_arrive` places what
  arrives, and a move to a node's own room is a warp. `hold` keeps a room
  running with nobody in it, and `running` lists the rooms that run. A room's
  `WorldView` draws only into its players' views, and each player's camera
  takes their room's limits. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#rooms-scenerooms).
- **Cutscenes.** `RGame::Engine::Cutscene::Script.build` lists steps that run,
  wait, hold on a walk or a fade, talk, and wait for a press.
  `Components::Cutscene` runs one on a node and takes what it stops: the nodes
  in `pause:` and, with `camera:`, the window, the joins and the other rooms. It
  gives them back when it ends, is skipped with a held action, or leaves the
  tree. See [docs/api/components.md](docs/api/components.md#cutscene).
- **A solo view can show one room.** `Viewports#solo!` takes `room:`, the
  `Scene::Room` whose `WorldView` draws into the solo view, and `solo_camera`
  and `solo_room` answer what it shows. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#collapsing-the-split).
- **A node can be suspended by more than one owner.** `Node2D#suspend` stops a
  node as `paused` does until a `resume` for each call, and leaves `paused` to
  the game. `Scene::Rooms` suspends a moving node rather than pausing it. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#pausing-a-subtree).
- **A player's input can be suspended.** `Player#suspend_input` makes every
  node of that player read nothing held until `#resume_input`, and a press begun
  meanwhile is refused. `Scene::Rooms` suspends a moving player's input until
  their reveal ends. See
  [docs/api/input.md](docs/api/input.md#a-players-input-can-be-suspended).
- **Scenes that fade in and out.** `Scene::SceneStack#transition=` takes a
  `Scene::Fade`, a colour and two durations, and each switch then covers the
  view, lands while covered and reveals the new scene. No scene reads input
  until the reveal ends. `push`, `replace` and `pop` take `transition:` for one
  switch, `nil` for none, and `transitioning?` answers whether one runs.
  `ScreenFade#color=` changes the colour a fade covers in. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#transitions).
- **Scenes by name.** `Scene::SceneStack#define(name) { |**keywords| ... }`
  names a scene, and `push` and `replace` take the name with the keywords its
  builder takes. A name the stack was not given raises `KeyError` where it is
  asked for. `on_requested` fires as a switch is asked for, `on_changed` as it
  lands, and `pending?` answers whether one waits. `carry: { hero: hero }` takes a node from one scene into
  the next, its components leaving the old scene's systems and joining the new
  one's. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#scenes-scenestack).
- **Music that fades.** `AudioOut#play_music` and `#stop_music` take `fade:`,
  in seconds, and `AudioOut#crossfade(id, over:)` lowers one song while it
  raises the next. `#pause_music` and `#resume_music` hold a song and its fade.
  `examples/music` fades, pauses and sets category volumes on its track. See
  [docs/api/audio.md](docs/api/audio.md#fades).
- **A cutscene example.** `examples/cutscene` plays a town crier's news that
  both players watch, and ends in the same town whether it is watched or
  skipped. See [docs/api/examples.md](docs/api/examples.md#cutscene).
- **A doors example.** `examples/doors` walks a hero through a gate between the
  town and a garden, and across a pair of warp pads, each placed in Tiled. See
  [docs/api/examples.md](docs/api/examples.md#doors).
- **Music that a room or an event claims.** `AudioOut#claim_music(key, id,
  priority:, fade:)` asks for a song, and the claim with the highest priority
  plays, crossfading when the winner changes. `#release_music` ends a claim, and
  `#claimed_music` names the song the claims chose. `Scene::Rooms#define` takes
  `music:` and `priority:`, and a room claims its song while a player stands in
  it or is on their way to it. While a claim holds, `play_music`, `crossfade`
  and `stop_music` raise. See [docs/api/audio.md](docs/api/audio.md#claims).
- **Volume categories, and a song that pauses.** `Audio#register_sound` and
  `#register_music` take a `category:` a game names, and
  `Audio#set_category_volume` turns every sound under it up or down. The device
  also answers `pause_music`, `resume_music`, `set_music_volume(id, volume)` and
  `stop_music(id)`, and `Song#resume` carries on where `stop` left it. See
  [docs/api/audio.md](docs/api/audio.md#categories).
- **A walker can be put at the end of its route.**
  `Components::PathFollow#finish` places its node on the last waypoint and
  emits `on_finished`, and so does a `Navigator`'s. See
  [docs/api/components.md](docs/api/components.md#pathfollow).
- **A fade over the screen.** `RGame::Engine::ScreenFade` covers the view it is
  drawn into in one colour, reveals it again, and flashes it, emitting
  `on_finished` at the end of each. `finish` jumps to the end at once. See
  [docs/api/toolbox.md](docs/api/toolbox.md#screenfade--cover-the-view-and-flash-it).
- **Particles.** `RGame::Engine::Components::Particles` bursts and streams
  small squares that fall, change colour with age and vanish, allocating
  nothing once built. They draw from the game's `Components::RandomSource`
  unless handed an `rng:`. `RGame::Util::ColorRamp` answers a colour by how far
  along it is, and `Engine::Pool#reserve` builds a pool's objects ahead of
  time. See [docs/api/components.md](docs/api/components.md#particles).
- **`examples/effects`**: a fade, a flash, sparkles, embers and a lightning bolt.
- **Light that adds, and drawing that fades.** `Renderer#blended(:add)` adds
  what is drawn inside it to what is behind, and `Renderer#faded(opacity)`
  multiplies its alpha, nested fades multiplying again. Neither changes draw
  order. `Node2D#opacity` fades a node and its whole subtree. `RGame::Util::Blend`
  lists the modes and checks an opacity. See
  [docs/api/drawing.md](docs/api/drawing.md#blending-and-fading) and
  [docs/api/scene_graph.md](docs/api/scene_graph.md#opacity).
- **A menu lays its buttons out in a grid.** `RGame::Engine::UI::Grid` places
  them in rows of `columns:` slots, and `UI::Stepping` moves across it: left and
  right along a row, up and down along a column, each line wrapping inside
  itself. See [docs/api/ui.md](docs/api/ui.md#layouts-column-row-grid-and-ring).
- **Several menus make one screen.** A menu joins the nearest
  `RGame::Engine::UI::FocusGroup` above it, and only the group's `current` menu
  reads input. `Stepping` crosses to the menu beside it at the end of a line, and
  on a direction the focused button is not `adjustable?` in. `UI::Menu` answers
  `current?` and `group`, and `UI::Navigation` gains `entered`. See
  [docs/api/ui.md](docs/api/ui.md#rgameengineuifocusgroup).
- **A menu that nothing confirms, and stepping on two actions of its own.**
  `confirm:` on `RGame::Engine::UI::Menu` names the action that confirms, and
  `confirm: nil` leaves only hotkeys to press its buttons.
  `UI::Stepping.new(actions:)` steps on two named actions, reads nothing else
  and never crosses to another menu. `ui_tab_prev` and `ui_tab_next` join the
  universal UI set on Q and E and the shoulder buttons. See
  [docs/api/ui.md](docs/api/ui.md#two-actions-of-its-own).
- **A screen with pages.** `RGame::Engine::UI::Tabs` shows one page at a time
  under a bar of tabs, switched with `ui_tab_prev` and `ui_tab_next` or a tab's
  hotkey, and emits `on_changed`. A page is any node; the tabs control and draw
  the page shown and update every page. `open` and `close` show and hide the
  whole screen. See [docs/api/ui.md](docs/api/ui.md#rgameengineuitabs).
- **A list longer than its panel scrolls.** `visible_rows:` on
  `RGame::Engine::UI::Column` and `UI::Grid` shows that many rows, and a menu
  over one scrolls the focused button into view. `UI::Menu` answers
  `first_row`, `rows_above`, `rows_below` and `in_view?`. See
  [docs/api/ui.md](docs/api/ui.md#a-window-of-rows).
- **An inventory example.** `examples/inventory` is a bag in a grid that
  scrolls, a column of verbs beside it that acts on the item chosen there, and
  a second page of key items behind a tab. See
  [docs/api/examples.md](docs/api/examples.md#inventory).
- **An equipment example.** `examples/equipment` dresses a character from a
  column of slots and a grid of clothes, and a second page shows the bag and
  says what is worn. See
  [docs/api/examples.md](docs/api/examples.md#equipment).
- **A component for what the player is standing next to, and one for what picks
  itself up.** `RGame::Engine::Components::Interactor` is a `Targeting` that
  also reads a button: `target` is the nearest node in range on its layer, and
  `on_interacted(target)` fires on the press. `Components::Collectable` acts on
  the step a collider on the layer it names touches it — emit `collected`, play
  a sound, and free the node unless `free: false`. `:interact` joins
  `InputMap::DEFAULT_ACTIONS` on E and the pad's X. See
  [docs/api/components.md](docs/api/components.md#interactor) and the
  `collectables` example.
- **A mover pushes what it walks into.** `pushes:` on every mover names collider
  layers a step moves instead of stopping at, and each must be in `blocked_by:`
  too. `RGame::Engine::Components::Pushable` is the thing pushed: a mover with no
  step of its own, stopped by its own `blocked_by:`, and able to push the crates
  behind it up to `Mover::PUSH_DEPTH` in a row. A mover that declares no
  `pushes:` moves exactly as before. See
  [docs/api/components.md](docs/api/components.md#pushable).
- **A held button drags a crate.** `Components::Grab` holds the nearest
  `Pushable` in range while its action is held, and the node's mover pulls it
  as well as pushing it. `:grab` joins `InputMap::DEFAULT_ACTIONS` on Left Shift
  and the pad's Y. See [docs/api/components.md](docs/api/components.md#grab).
- **Two examples of moving things by walking into them.** `examples/push_pull`
  pushes and pulls crates, and `examples/block_puzzle` shoves blocks a cell at a
  time onto their squares with the components that already existed. See
  [docs/api/examples.md](docs/api/examples.md#push_pull).
- **`Components::Collider`, the module both colliders include**, so a component
  can ask for the collider on its node without naming a shape:
  `require_sibling(Collider)`. A node carrying both raises, as it did for
  either alone. See
  [docs/api/components.md](docs/api/components.md#collider).
- **A signal generates a public disconnect beside its connect.** `signal :hit`
  now makes `disconnect_hit(handle)` as well as `on_hit`, so a component that
  connects to a sibling in `_attach` can end that connection in `_detach` — the
  signal itself stays private, because emitting belongs to the class. See
  [docs/api/signals.md](docs/api/signals.md#the-dsl-declaring-a-signal-on-a-class).
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
  the page with `page=`. With `reveal:` it types each page out a character at a
  time, and `reveal_all` shows the rest. See
  [docs/api/ui.md](docs/api/ui.md#rgameengineuilabel).
- **An intro example.** `examples/intro` tells a story a page at a time through a
  `UI::Label`, typed out and turned by Enter and by a tween. Its tables hold the
  story as one line, and German takes a page more than English. See
  [docs/api/examples.md](docs/api/examples.md#intro).
- **A Tiled map can use what Tiled writes.** A map may have several tilesets,
  embedded or in `.tsx` files, any layer encoding but zstd, group, image and
  object layers, an infinite size, objects of every shape Tiled 1.12 draws, and
  objects placed from templates. A tile object sits where its tileset's object
  alignment puts it, and has its tile's class and properties under its own. A
  tileset set to draw its tiles at the grid's size, or to keep a tile object's
  tile in proportion, raises, since rgame would draw it differently from Tiled.
  A map rgame cannot read raises `RGame::Engine::Tiled::FormatError` naming the
  file.
  See [docs/api/tile_maps.md](docs/api/tile_maps.md#what-rgame-reads-from-tiled).
- **A tile map says what its tiles, layers and objects are.** `TileMap` answers
  `orientation`, `tile_class`, `tile_properties`, `layer`, `layer_index`,
  `image_layers` and `objects`, which are `RGame::Engine::MapObject`s in the
  game's coordinates. `object_named` finds the one object a designer named. An
  object layer is a `TileMap::ObjectLayer`, which answers `y_sort?` and
  `actors?`, and `TileMap#actors_layer` names the one a designer marked for the
  actors. Custom properties are `RGame::Engine::Properties`, and a class
  property's value answers `class_name`. See
  [docs/api/tile_maps.md](docs/api/tile_maps.md).
- **A tile map draws what Tiled shows.** Turned and flipped tiles draw turned,
  hidden layers draw nothing, and a layer fades by its opacity. Tilesets with a
  margin or spacing, collections of images, and tiles larger than a cell all
  draw, a tileset's drawing offset moves its tiles, and an image layer draws its
  image, repeated if Tiled says so. `TileMap#tile_offset`
  answers it. See [docs/api/tile_maps.md](docs/api/tile_maps.md#how-the-map-is-drawn).
- **One tile of a map draws anywhere.** `Components::MapTile` draws a tile of
  the scene's map with its bottom centre on its node's origin, stretched to the
  node's size and turned as a tile object is in Tiled, under everything else
  the node draws. `renderer.map_tile` is the draw it calls. See
  [docs/api/components.md](docs/api/components.md#maptile).
- **A node keeps its own facts.** `Components::Facts` keeps a record of named
  fields, each with a default, in the facts database under the key the node
  passes, or under one made from the map object the node was built from. So a
  chest opened once stays open when its room is built again. A field reads and
  writes without allocating. `Node2D#map_object_id` is that object's id. See
  [docs/api/components.md](docs/api/components.md#facts).
- **A tile map converts between cells and pixels.** `TileMap` and
  `Components::TileWorld` answer `cell_x`, `cell_y`, `col_at` and `row_at`, and
  `TileWorld` answers `cell_centre_x` and `cell_centre_y`. See
  [docs/api/tile_maps.md](docs/api/tile_maps.md#cells-and-pixels).
- **A thing on a tile map can block its cell.** `Components::OccupiesCell` makes
  one cell of the scene's `TileWorld` solid while its node is in the tree, for
  collision and route planning alike. See
  [docs/api/components.md](docs/api/components.md#occupiescell).
- **A map builds its own nodes.** `TileMapLayer.mount` builds each object layer
  as a node in its place, and each object whose Tiled class starts with a
  capital letter as the `Node2D` class of that name, looked up from the
  scene's module. The `@param` tags above the class's `initialize` say which
  properties a map may set, and a property they do not allow raises. Every tile
  object draws its tile, and a hidden object builds and draws nothing. See
  [docs/api/tile_maps.md](docs/api/tile_maps.md#building-nodes-from-objects).
- **A map's objects become nodes by block.** `RGame::Engine::MapObjects` takes a
  block per Tiled class and builds a node from each object of that class.
  `spawn_into` adds them under a parent. See
  [docs/api/tile_maps.md](docs/api/tile_maps.md#building-from-data-classes-with-mapobjects).
- **`Image#tiles` cuts a sheet with gaps.** It takes `margin:`, `spacing:`,
  `columns:` and `count:`. See [docs/api/images.md](docs/api/images.md).
- **A quest can be a state machine.** `RGame::Engine::StateGraph.build`
  declares states and transitions with conditions and effects, and
  `RGame::Engine::StateMachine` runs one: it takes transitions, counts visits,
  saves with `to_h` and resumes with `from:`. See
  [docs/api/dialogue.md](docs/api/dialogue.md#state-machines).
- **A game saves its flags and quests as one entry.**
  `RGame::Engine::Components::FactsDatabase` holds flags that belong to no
  object, and `RGame::Game` mounts one as `game.facts`. `on_changed` reports
  changes in play, and `watch` keeps something in step, loads included. A
  `StateMachine` built with `name:` registers with it, so `facts.to_h` saves
  every named quest too and `facts.restore` puts all of them back. A value may
  be a record, a Hash of fields that follow the same rules, and
  `facts[key, field]` reads or writes one field without allocating. See
  [docs/api/dialogue.md](docs/api/dialogue.md#facts).
- **A game has one seeded source of random numbers.**
  `RGame::Engine::Components::RandomSource` answers `rand` as `Random#rand`
  does, and `RGame::Game` mounts one as `game.random_source`, seeded from
  `seed:` or, when it is set, `RGAME_SEED`. With neither, the game picks a seed,
  and `random_source.seed` reads it back. See
  [docs/api/components.md](docs/api/components.md#randomsource).
- **A game can hold a branching conversation.**
  `RGame::Engine::Dialogue::Script.build` declares beats, each a speaker saying
  a translated line, and responses that conditions can make unavailable.
  `RGame::Engine::Dialogue` runs one and saves by `name:` like a quest, and
  `finish` ends it where it stands. It draws nothing itself. See
  [docs/api/dialogue.md](docs/api/dialogue.md#dialogue).
- **A conversation keeps a transcript and hands it over when it ends.**
  `RGame::Engine::Dialogue::Transcript` records each line with the values it
  was shown with, and each response picked. `on_ended` passes it to the game,
  frozen, and the engine saves nothing; `to_h` and `Transcript.from` save and
  restore one. See [docs/api/dialogue.md](docs/api/dialogue.md#the-transcript).
- **A dialogue box shows a conversation.** `RGame::Engine::UI::DialogueBox`
  draws the speaker's name, types the line out a page at a time, and lists the
  responses. Confirm shows the rest of a page, turns it, or moves on.
  `unavailable:` hides or disables a response the player cannot pick. The box
  answers to its player, so two players can talk in two halves of the screen,
  and it frees itself when the conversation ends, however it ends. A subclass
  draws a portrait beside the line in `_draw_portrait`. See
  [docs/api/ui.md](docs/api/ui.md#rgameengineuidialoguebox).
- **A dialogue box can show its log.** `log:` on `UI::DialogueBox` names an
  action that opens the transcript as a paged label in place of the line, and
  `log_entry:` formats each line. The conversation waits while the log is open.
  See [docs/api/ui.md](docs/api/ui.md#the-log).
- **Every player can drive one node together.** `Players#everyone` is an input
  owner whose buttons are the OR of every active player's, for a dialogue box, a
  title screen or a pause menu during `solo!`. A `PlayerLayer` refuses it. See
  [docs/api/input.md](docs/api/input.md#everyone-at-once).
- **Two dialogue examples.** `examples/dialogue` holds one branching
  conversation in a dialogue box, and nothing else. `examples/quests_and_dialogue`
  is a village where a conversation moves a quest on, with a portrait, the log
  and a save. See [docs/api/examples.md](docs/api/examples.md#conversation).
- **A menu can drop its buttons, and a label can change its text.**
  `UI::Menu#clear` removes every button. `UI::Label#text=` and
  `Engine::Paragraph#text=` take a new key or `Engine::Text`, and a label starts
  again on its first page. See [docs/api/ui.md](docs/api/ui.md#rgameengineuimenu).
- **A spec can check that no conversation strands a player.**
  `RGame::Engine::Exploration.run` walks every path a dialogue or a state
  machine can take. It reports each dead end, with the moves that reach it. See
  [docs/api/dialogue.md](docs/api/dialogue.md#checking-every-path).
- **A node that needs a system can ask for it by raising.** `Node2D#system!`
  finds a system as `system` does, and raises `KeyError` naming the class and
  where it looked, rather than returning nil. See
  [docs/api/systems.md](docs/api/systems.md#looking-a-system-up).
- **`RGame::Game` takes the sound device as `audio:`**, as it takes the input
  backend as `input:`, so a harness can record what a game plays. See
  [docs/api/game.md](docs/api/game.md).
- **A subclass cannot replace what `signal` generated.** Defining a signal's
  connect method or emit reader in a subclass, such as a `def on_activated`
  meant as a hook, raises `NameError` when the class is defined, naming the
  signal. See [docs/api/signals.md](docs/api/signals.md#the-dsl-declaring-a-signal-on-a-class).
- **A misspelled hook raises.** A `Node2D` or `Component` subclass defining a
  `_` method that no ancestor has, such as `_updte`, raises `NameError` when
  the class is defined, listing the hooks it has. `Node2D.hooks` returns that
  list, and `hook :_name` declares a new hook for a class's subclasses. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#the-tick-control--update--draw).
- **A value can move over time.** `RGame::Engine::Tween` eases a number from
  `from` to `to` over a duration, with one of five eases or any callable, and
  `loop: true` starts it again at the end. `RGame::Engine::Components::Tween`
  runs one on a node's tick and emits `on_finished` once; `stop` holds it until
  `start`. See [docs/api/toolbox.md](docs/api/toolbox.md#tween--a-value-that-moves-over-time).
- **An action can be a hold, a tap or a chord.** In an `RGame::Engine::InputMap`
  entry, `hold: 0.6` presses once the buttons have been down that long, `tap:
  0.3` presses on a release that came sooner, and `all:` is a chord that presses
  when its last id arrives. One button can back a tap and a hold, and a held
  chord silences the plain actions on its buttons. See
  [docs/api/input.md](docs/api/input.md#a-hold-a-tap-and-a-chord).
- **An action says how long it has been held, and since when.**
  `Actions#held_for(name)` is the seconds its buttons have been down, `0.0` at
  rest, and it survives the tick of the release. `Actions#down_since(name)` is
  the `poll_count` they went down on, nil at rest. `Players#everyone` folds the
  first as the longest of the active players' and the second as the earliest.
  See [docs/api/input.md](docs/api/input.md#rgameengineactionmapper).
- **An input example.** `examples/input_holds` opens a chest on a tap of one
  button, searches it on a hold of the same one, and swaps stance on a chord.
  See [docs/api/examples.md](docs/api/examples.md#input_holds).
- **`Renderer#debug_circle`.** A translucent disc in the colour `debug_box`
  draws with, for a round collision shape. See
  [docs/api/drawing.md](docs/api/drawing.md#shapes).
- **The colliders and the tile map draw their own debug shapes.** With the
  `:shapes` channel on, `Components::BoxCollider` draws its box,
  `Components::CircleCollider` its circle, and `RGame::Engine::WorldView` a box
  over each solid cell of its scene's `Components::TileWorld` that the viewport
  can see. Each draws in the `:debug` band, in its own space, once per viewport.
  See [docs/api/systems.md](docs/api/systems.md#debug--a-switch-per-channel).
- **A debug layer of named channels.** `RGame::Engine::Debug` is a system
  `RGame::Game` mounts on the root, holding a switch per channel and drawing in
  the `:debug` band. `:stats` is the overlay, `:shapes` is drawn by the things
  that have shapes, and `define(:routes) { |renderer, view| ... }` adds a
  channel of the game's own. `F3` toggles `:shapes` and `game.debug_keys =
  false` turns the development keys off. See
  [docs/api/systems.md](docs/api/systems.md#debug--a-switch-per-channel).

- **`Renderer#text` can draw the start of a string.** `bytes:` draws the
  string's first `bytes` bytes, cut back to the last whole character, so a line
  revealed a character at a time needs no String per character. `UI::Label`
  reveals its pages this way. See
  [docs/api/text.md](docs/api/text.md#where-text-goes).
- **`Game/NoBlockExitInHotPath`, a cop against leaving a block on a per-frame
  path.** A `return` or `break` out of a block allocates an object each time it
  happens, and the cop names `find`, `any?`, `index` and `while`, which leave
  for free. It runs where the other allocation cops run, and its
  `EveryMethodIn:` names files where every method counts.
- **`Game/NoEngineIvar`, a cop against the engine's ivars in a game.** It
  flags an ivar starting with `@rgame_`, read or written, and a literal name
  starting with it given to `instance_variable_get` and its siblings. See
  [docs/api/cli.md](docs/api/cli.md#the-generated-rubocop-configuration).

### Changed

- **`rgame new` writes the game's classes into a module of its own.**
  `rgame new tic_tac_toe` defines `module TicTacToe` in `tic_tac_toe.rb`, where
  `Engine`, `Util`, `UI` and `Components` stand for `RGame::Engine`,
  `RGame::Util`, `RGame::Engine::UI` and `RGame::Engine::Components`. The game class
  is `TicTacToe::Game` rather than `TicTacToeGame`, and the root node is
  `TicTacToe::Root`. A name whose module Ruby already defines, such as `signal`,
  is refused, and so are `game` and `main`. See
  [docs/api/cli.md](docs/api/cli.md).
- **rgame's classes and modules are closed to the `class` and `module`
  keywords.** A constant, method or singleton method written in a class or
  module body outside rgame, onto a class or module under `RGame::Engine` or
  `RGame::Util`, raises `NameError` naming the file and the line. A game's own
  `module UI` inside its module, which would reopen rgame's, fails where it is
  written. Subclassing, stubbing in a spec, `define_method` and `class_eval` are
  unaffected. See [A game's own module](docs/api/README.md#a-games-own-module).
- **The examples keep their classes in a module each**, such as `WalkExample`,
  and write `Engine::Node2D`, `Util::Color`, `UI::Menu` and `Components::Sprite`
  inside it. That is the shape
  [A game's own module](docs/api/README.md#a-games-own-module) recommends for
  every game.
- **`WanderController` rolls from the game's `RandomSource` by default.** Its
  `rng:` defaults to `nil`, and it finds the root's source when it attaches,
  raising `KeyError` when the root has none. An `rng:` passed in still wins.
  See [docs/api/components.md](docs/api/components.md#wandercontroller).
- **`WanderController` re-rolls when its body's step was cut short**, as
  `Mover#stopped?` says, rather than when the node did not move. A body
  sliding along a wall now re-rolls, and a body with nothing in `blocked_by:`
  never re-rolls early. See
  [docs/api/components.md](docs/api/components.md#wandercontroller).
- **`Sprite` and `AnimatedSprite` stand on the node's origin by default.** Both
  take `anchor: :bottom` unless told otherwise, so the picture's bottom centre
  is on the origin. A `Sprite` that rotates passes `anchor: :center` to keep
  spinning in place. For an `AnimatedSprite` that was top-left anchored, move
  the node down by the frame's height and right by half its width, or pass
  `anchor: :top_left`. See [docs/api/components.md](docs/api/components.md#sprite).
- **`FeetCollider` puts its box under the node's origin**, centred across it
  with its bottom edge on it. It no longer reads the node's size, so it no
  longer raises on a node without one. See
  [docs/api/components.md](docs/api/components.md#feetcollider).
- **`Node2D#system` looks through every enclosing scene**, nearest first, and
  then the root. A node in a scene held inside another finds the outer scene's
  systems. See [docs/api/systems.md](docs/api/systems.md).
- **A `CharacterBody` stands still as its node enters the tree.** A node carried
  into another scene, or taken from a pool again, no longer walks on with the
  intent it had. Set an intent after placing it.
- **`Node2D#add_node` takes a node from the parent it had.** A node that is
  already its child stays where it is, in the tree. A node added to a second
  parent used to sit in both child lists.
- **A `SceneStack` switch lands in the sweep after the tick**, not when it is
  asked for. `current` changes then, and two switches asked for before one sweep
  keep only the last. A scene pushed from a root's `_enter_tree` first shows on
  the second frame. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#a-switch-lands-in-the-sweep).
- **`Audio#play_music` makes the song it is asked for current**, even one
  already playing, so `stop_music` stops the song last asked for rather than
  the one last started. See
  [docs/api/audio.md](docs/api/audio.md#playing-by-id).
- **A node reads only the presses it saw start.** In a node's components and
  `_control`, `pressed?` and `released?` are false for a press that began before
  the node was last paused, hidden, below another scene, added, or given another
  `input_owner`. `held?`, `axis` and `held_for` answer as before, and a snapshot
  built with `Actions.new` is handed on as it is. See
  [docs/api/input.md](docs/api/input.md#a-node-reads-only-the-presses-it-saw-start).
- **Polling input takes the timestep.** `Players#poll`, `Player#poll` and
  `ActionMapper#poll` take `(backend, dt)`, in seconds, which is what a hold and
  a tap are measured against. `RGame::Game` passes its fixed step; a game driving
  a mapper itself passes the step it updates with. See
  [docs/api/input.md](docs/api/input.md#rgameengineactionmapper).

- **A node plays sound through the `AudioOut` system.** `RGame::Game` mounts
  `RGame::Engine::AudioOut` on the root, holding the sound device. Write
  `system!(RGame::Engine::AudioOut).play_sound(:boom)` for
  `RGame::Engine::AudioBus.play_sound(:boom)`, and the same for `play_music`
  and `stop_music`. A headless spec mounts an `AudioOut` on a recording device.
  See [docs/api/audio.md](docs/api/audio.md#audioout--the-system-a-node-plays-sound-through).

- **A signal is declared by its event, and the DSL adds `on_`.** Write
  `signal :hit, :other` for `signal :on_hit, Signal.define(:other)`, and emit
  with `hit_signal.emit(other)` for `on_hit_signal.emit(other)`. Listeners still
  connect with `on_hit { ... }`. A name starting with `on_`, or a signal class
  in place of the fields, raises `ArgumentError` when the class is defined. See
  [docs/api/signals.md](docs/api/signals.md#the-dsl-declaring-a-signal-on-a-class).

- **A timer's signal is renamed after what happened.**
  `Components::Timer#on_timeout` is `on_elapsed`, since a repeating timer's
  interval elapses on every fire.

- **A node's hooks start with `_`, and `on_` means a signal.** Override
  `_control`, `_update` and `_draw` for `on_control`, `on_update` and
  `on_draw`, and `_enter_tree` and `_exit_tree` for `on_add` and `on_remove`.
  Each hook is named after the step that calls it. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#the-tick-control--update--draw).
- **A component's hooks start with `_` too.** Override `_control`, `_update`
  and `_draw` for `control`, `update` and `draw`, `_attach` and `_detach` for
  `on_attach` and `on_detach`, and `_sweep_freed` for `sweep_freed`. A node and
  a component now name the same hook the same way. See
  [docs/api/components.md](docs/api/components.md).
- **The UI's hooks follow the same rule.** `UI::Button` calls `_gain_focus` and
  `_lose_focus` for `on_focus_changed(focused)`. A `UI::Navigation` answers
  `control`, `opened` and `buttons_changed` for `on_control`, `on_opened` and
  `on_buttons_changed`, which also ends the clash with `UI::Menu#on_opened`. See
  [docs/api/ui.md](docs/api/ui.md).
- **`Node2D`'s sealed machinery starts with `rgame_`, not `_`.** A subclass
  that defines `rgame_draw_content` or another of `Node2D`'s private `rgame_`
  methods raises `NameError` where the class is defined. A method starting
  with `_` is a hook, as the entries above say. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md).
- **Every engine node and component keeps its ivars under `@rgame_`.** A
  subclass's `@paused`, `@player`, `@width` or `@opacity` is its own, and no
  longer changes the node. Code that read one of the engine's ivars calls its
  public method instead: `label`, not `@label`. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#the-tick-control--update--draw).
- **`Game/NoInterpolationInHotPath` names `RGame::Engine::Text`.** Its message
  asked for a string built once and cached. It now says to build a `Text` and
  read it with `with`. See
  [docs/api/toolbox.md](docs/api/toolbox.md#text--the-string-a-node-draws).

- **Every drawing call defaults to z 0, so call order decides.** A shape used to
  default above text and images within one node. A backdrop drawn first then
  covered the text drawn after it, and ten examples showed no help text at all.
  Now a later call lies over an earlier one unless a `z:` says otherwise.
  `Renderer::SHAPE_Z`, `IMAGE_Z` and `TEXT_Z` are gone; `Renderer::DEFAULT_Z` is
  0. A node that drew a shape before an image and relied on it landing on top
  passes a `z:`, or draws the shape last. See
  [docs/api/drawing.md](docs/api/drawing.md#coordinates-colours-and-z).

- **A tile map is built from a parsed file.** `TileMap.load` and
  `TileMap.parse` are gone. Write
  `TileMap.from_tiled(RGame::Engine::Tiled::Map.load(path))`, or
  `Tiled::Map.parse(string)` for a map held in a String.
- **A cell holds a tile id, not a gid.** Ids start at 1 across every tileset.
  `map.gid(layer, col, row)` becomes `map.tile(layer, col, row)`, and
  `map.above_layer?(index)` becomes `map.layer(index).above?`. An `above`
  property that is not a bool now raises.
- **`TileMapRenderer.new(map, tiles, layer_images: [])` takes images indexed by
  tile id**, with nothing at 0, rather than one tileset sliced by local id, and
  the image of each image layer.
- **`TileMapLayer.mount` returns places, and takes no `under:`.** Write
  `mount(world)[:actors]` for the node it used to return. The actors go in the
  object layer a designer marks `actors` in Tiled, or below the first `above`
  layer on a map with no mark. `places['name']` is an object layer's node, for
  what a scene adds itself, so a layer placed in Tiled replaces `under:`. See
  [docs/api/components.md](docs/api/components.md#tileworld).

- **`Game/NoLiteralText` also checks `text_lines`.** A String literal as the
  first argument of `text_lines` is an offense, as it is for `text` and
  `text_width`.
- **The debug overlay counts allocations per second, and shows the worst
  tick's collection.** The `:stats` channel's rows are FPS, OBJ, OBJ/s and GC
  ms. OBJ/s replaces Δ/f and counts the last whole second rather than the last
  frame. GC ms is the longest the collector ran in one tick of that second. See
  [docs/api/systems.md](docs/api/systems.md#the-two-channels-the-engine-draws).
- **`WorldBounds` resolves one axis at a time.**
  `RGame::Engine::Components::WorldBounds.resolve_width(node, width)` and
  `resolve_height(node, height)` replace `resolve(node, width, height)`, which
  returned a pair.

- **`Game/NoNeedlessAllocation` flags the iterators that allocate.** In a
  per-frame method, `each_with_index`, `each_with_object`, `inject` or `reduce`
  with a block, `min_by`, `max_by`, `minmax`, `minmax_by`, `each_slice` and
  `each_cons` are flagged, each with the form that allocates nothing.

### Removed

- **`CollisionBox.bottom_anchored`.** Build the box with `CollisionBox.new` and
  its `offset_x:` and `offset_y:`, or use a `FeetCollider`.
- **`RGame::Engine::AudioBus` and `RGame::Engine::AudioDirector`.** Play sound
  through `AudioOut`, which replaces both; see Changed.
- **`RGame::Engine::Tileset` and `TileMap#tileset`.** A map answers per tile:
  `solid?(tile)`, `animated_tiles` and `frame_tile(tile, elapsed)`, which takes
  seconds. `solid_ids` has no replacement; a tile is solid when it has a
  collision shape in Tiled.
- **The `[r, g, b]` form of a colour.** A colour is a `RGame::Util::Color` or
  `nil` for white, everywhere one is taken: `Color.coerce` raises `TypeError` on
  an Array, and so do every drawing method, `NineSlice#draw`, a recording's
  replay and the UI classes that take colours. `Color` was in `Core` when the
  array form was added, out of reach of engine code; it is a `Util` value now,
  so every layer can build one. Build a `Color` once and share it — a renderer
  coerces each colour it is handed, so an array was a `Color` allocated per draw
  call. See [docs/api/values.md](docs/api/values.md#colorcoerce).
- **`Components::Timer`'s `repeating:` keyword.** A timer always repeats. For
  something that happens once, use `Components::Tween` and `on_finished`, whose
  handler may call `start` to run it again. See
  [docs/api/components.md](docs/api/components.md#tween).

### Fixed

- **A scene enters and leaves the tree with its host.** The scenes on a
  `RGame::Engine::Scene::SceneStack` stayed in the tree, and their components
  registered with their systems, after the node holding the stack left it. A
  scene pushed while the host was outside the tree entered at once. Entering
  and leaving now reach every node that names the node as its `parent`, and a
  node whose parent is outside the tree stays out. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#lifecycle-constructing-vs-entering-the-tree).
- **A scene follows its host when the host moves.** A scene on a
  `RGame::Engine::Scene::SceneStack` kept the `world_x`, `world_y` and
  `world_angle` it last read once the node holding the stack moved. A move now
  reaches every node that names the mover as its `parent`, on the child list or
  off it. See
  [docs/api/scene_graph.md](docs/api/scene_graph.md#the-two-spaces).
- **The debug overlay no longer counts its own drawing.** Its colour was the
  three numbers a colour is built from rather than a `RGame::Util::Color`, and a
  renderer coerces what it is handed — so the overlay allocated one Color per
  glyph it drew and reported its own cost as the game's. Every game read about a
  dozen objects a frame with nothing of its own to blame.
- **The frame rate on the debug overlay draws its own digits, not three hundred
  leading zeros.** `App#fps` is a Float, and the digit loop divided by ten until
  nothing was left — which a Float never reaches. Each row is rounded to an
  Integer before its digits are taken.
- **A button added during a held confirm ignores that press.** A menu read the
  confirm a parent had just acted on, so a button added on that press was
  activated by it. `add` and `clear` now make the menu wait for confirm to come
  up. A menu whose buttons change from `on_activated` reads no more input that
  tick. See [docs/api/ui.md](docs/api/ui.md#when-a-press-activates).
- **A tile from a map's second tileset draws from that tileset.** Every gid was
  resolved through the first tileset.
- **Five examples show their instructions again.** `pathfinding`,
  `collision_tiles`, `jump_topdown`, `scroll_map` and `split_screen` drew their
  text from the scene in the `:world` band, where the map drawn after it covered
  it. Each scene now draws in the `:overlay` band.
- **A pooled node spawns without allocating.** A node carrying `ScreenWrap` or
  `DespawnOffscreen` allocated an Array each time it entered the tree, and adding
  any child made its parent sort its children again. A child whose `z` puts it
  last now leaves them sorted.
- **`ScreenWrap` and `DespawnOffscreen` allocate nothing per frame.** With
  `margin:` left at its default, each allocated two Floats per node per frame.
- **`Players` answers a query without allocating.** `players.any? { ... }`,
  `find` and `count` went through `Enumerable` and cost three objects a call.
  They now run on the Array of players. `each_active` no longer builds an Array.
- **A collision world's index keeps only the cells in use.** `SpatialHash` kept
  an Array for every cell anything had been put in or looked up in, so a
  `CollisionWorld` grew for as long as its actors explored, and allocated on
  every new cell. `clear` and a `remove` that empties a cell now keep the Array
  for the next insert.
- **`TileMap#solid_tile?` allocates nothing on a solid cell.** It allocated an
  object each time it answered `true`, and a mover asks it for every cell its
  box touches.

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
