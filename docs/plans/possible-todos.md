# Possible todos

Work that has a reason to exist but no reason to happen yet. Nothing here is
scheduled, and nothing here is a promise.

Each entry says what the thing is, why it is not being done now, and what would
make it worth doing. **An entry with no trigger is a wish, not a todo**: delete
it. A trigger names what would make this entry worth starting. "A game that
needs it" names nothing, since it would fire for every entry here.

Entries sit under the area they belong to. One that fits no area goes under
[Misc](#misc) rather than opening an area of its own.

---

## Rendering and the GPU

The render target in the first entry is the project's first call above GL
1.1. The crossfade and the smooth tileset wait on it; the blend modes and
mipmaps need no loader.

### A low-resolution render target, and the GL loader it needs

**What.** Render a frame into an offscreen buffer at the game's own resolution,
then scale that buffer onto the window — Godot's `viewport` stretch mode, as
against the `canvas_items` one.

**What exists instead.** `Game::Configuration`'s `scale_mode` and
`RGame::Engine::Presentation` scale the *coordinates*: everything still
rasterises at the window's real resolution, and the transform maps a logical
size onto it. That covers most of what a game wants, `:integer` included, and it
needed no C at all.

The difference shows up in one place. Coordinate scaling rasterises text and
shapes at full resolution, which is what you want for anything that is not pixel
art — but a *sprite* drawn at 2x is still sampled from its original texels, so
the crispness depends on `texture_filter` and the factor rather than on having been
rasterised at 320x240 in the first place. A render target gives the genuine
low-resolution look, and hands the frame over as a texture, which is also what
any post-processing effect would need.

**Why not now.** It is the project's first call above OpenGL 1.1, and that is a
threshold rather than a line of code. Every `gl*` call in `ext/rgame_core/` today
is GL 1.1 — checked, all 23 of them — which is exactly what "no GL loader" has
bought so far. Windows' `opengl32.dll` exports only GL 1.1, so `glGenFramebuffers`
and friends must be fetched through `SDL_GL_GetProcAddress`. A naive
implementation compiles, links and runs perfectly on Linux and fails on Windows,
which is the failure class the `write-c-code` skill's portability section
exists for.

**What it would take.**

- A keyhole loader: six entry points (`glGenFramebuffers`, `glBindFramebuffer`,
  `glFramebufferTexture2D`, `glCheckFramebufferStatus`, `glDeleteFramebuffers`,
  and `glGenerateMipmap` if wanted) resolved once into a struct. Roughly thirty
  lines, and not GLAD.
- An availability check with a clear failure. We never request a context
  version, so we take SDL's default; a missing FBO must say so rather than draw
  a blank screen.
- Two entries on `backend.h`'s table — bind target, unbind target — which
  `test/support/recording_backend.c` implements too, so "bound, drew, unbound,
  blitted once" stays assertable with no display.
- The Y flip. An FBO-rendered texture is upside down against our
  `glOrtho(0, w, h, 0, …)` top-left origin, so the final blit needs flipped
  texture coordinates. This one is famous for costing an afternoon.

Three things are already in place and do not need designing:
`rgame_texture_sheet_create` takes a raw GL texture name and does not care where
it came from, so an FBO's colour attachment becomes an ordinary sheet the whole
existing sprite path can draw; the policy half — which scale, which
offsets — is `Presentation`, which is pure and already specced; and every
colour is premultiplied. A frame drawn into a texture comes out premultiplied
too, so the blend takes it as it takes an image. Under straight alpha, its
translucent pixels would have been darkened by their alpha twice.

**Trigger.** A game that wants a genuine low-resolution look and finds
coordinate scaling not good enough, or the first want for a post-processing
effect.

#### SDL3's GPU API, and why it comes after the loader

**Decision.** When GL 1.1 stops being enough, the next step is the keyhole
loader above, over GL 2.1. SDL3's GPU API is the likely step after that. GL 2.1
and its framebuffer-object extension give everything this file wants from a
GPU: render targets, and fragment shaders in GLSL 1.20. macOS gives an app that requests no version a 2.1
context, so 2.1 is the floor on every platform rgame supports.

GLSL 1.20 reads `gl_Vertex`, `gl_MultiTexCoord0` and `gl_Color`, which
`gl_backend.c`'s client-side arrays already feed, so a shader needs no new
vertex path. It travels with each draw command as texture and blend do, and the
queue sorts and batches by it the same way. Shaders add about ten entry points
to the loader's six.

**Why not SDL3's GPU API now.** It fits the renderer: the queue already builds
one sorted vertex array a frame, which SDL_GPU uploads once and draws batch by
batch. The costs lie elsewhere.

- **SDL3 comes first.** SDL_GPU exists only in SDL3. That move touches 192
  distinct SDL names in 15 files and `rakelib/sdl2.rake`. SDL3 still creates GL
  contexts, so the move is worth making on its own and decides nothing about
  the renderer.
- **Shaders are compiled ahead of time.** SDL_GPU takes SPIR-V, DXIL, DXBC or
  MSL, never GLSL source for the driver to compile. The source gem compiles on
  `gem install`, where no shader compiler exists. So the engine's shaders would
  ship compiled under `lib/`, with a spec checking them against their source. A
  shader a game wrote would need a compile step in every game's build, or
  SDL_shadercross at runtime. Shadercross brings DXC and SPIRV-Cross, two large
  C++ libraries, into every game.
- **There is no fallback.** SDL_GPU has three backends: Vulkan, D3D12 on
  Windows 10 or newer, and Metal on macOS 10.14 or newer. It has no GL backend,
  so a Windows machine whose driver offers only OpenGL could no longer run
  rgame. Metal costs nothing, since the gem already targets macOS 11.
- **CI is unverified.** `rake spec:core` draws real pixels on all three runners
  through software GL: Mesa on Linux and Windows, Apple's GL on macOS. SDL_GPU
  would need Mesa's software Vulkan, lavapipe, on Linux and Windows, and
  working Metal on GitHub's macOS VMs. Nobody has checked either.
  `spec_core/support/rendered_frame.rb` also reads pixels by calling GL through
  Fiddle, so the extension would have to expose a readback.

**The shader API is the decision that cannot be undone, not the backend.** If
games write GLSL 1.20, a move to SDL_GPU breaks every game's shaders. So the
engine offers effects rather than a shader language. Palette swap, hit flash,
outline, CRT and lighting become engine-owned shaders that take parameters, as
the UI package offers menus rather than a toolkit. Games then never see the
backend, and shaders that ship compiled cost them nothing.

A GL 2.1 step throws little away when SDL_GPU follows: the loader, the render
target and shader code in `gl_backend.c`, and a few short shaders. The Ruby API,
the queue's batching, `Presentation` and the tests against
`test/support/recording_backend.c` all carry over.

**Trigger.** macOS removes or breaks OpenGL. Or a game needs what macOS's GL
cannot give: it stops at 4.1, which has no compute shaders, so particles
simulated on the GPU need another API. Or a measurement shows driver overhead
costing a game frames. Going straight to SDL_GPU at the first render target
makes sense only if three things hold: SDL3 is happening anyway, games get
effects rather than shaders, and a probe shows all three CI runners draw with
it.

#### Two smaller things in the same area

- **`:overscan`.** `Presentation` has four modes; SDL has a fifth, which fills
  the window on the *smaller* axis and lets the larger overflow. It is two lines
  — `max` where `fit_uniform` takes `min` — and was left out because no example
  asks for it. Adding an unused mode is a claim nothing checks.
- **A minimum window size.** `:integer` never scales below 1x, so a window
  smaller than the logical size crops instead of shrinking. `SDL_SetWindowMinimumSize`
  would design the case out entirely rather than documenting it. It needs C, and
  the case only arises if a player drags a window below the game's design size.

### A crossfade between two live scenes

**What.** A scene transition that dissolves one scene into the next, both
drawn at once, rather than covering the first and revealing the second.

**What exists instead.** A `SceneStack` or `Scene::Rooms` transition shows one
scene at a time: it covers the screen with a `ScreenFade`, switches while
covered, and reveals. Drawing two scenes into one frame, each at part opacity,
blends their overlapping sprites into each other rather than into the picture
behind.

**Why not now.** A dissolve draws each scene into a texture of its own and
blends the two textures. That needs the render target in
[A low-resolution render target](#a-low-resolution-render-target-and-the-gl-loader-it-needs),
and nothing else wants one yet.

**Trigger.** The render target landing, or a game whose design needs a
dissolve.

### Blend modes beyond `:add`

**What.** More modes for `renderer.blended` and `Components::Particles`'
`blend:`, starting with multiply, which darkens what it draws over: shadows,
tints, a night filter.

**What exists instead.** `:alpha`, the default, and `:add`. The canvas carries
the mode with each draw command, so the queue already sorts and batches by
mode.

**Why not now.** Nothing asks for it. Every colour is premultiplied, so
multiply is `glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA)`, and a
transparent pixel leaves what is behind it as it was. It is core GL 1.0, so it
needs no loader: one more `rgame_blend` value, and one symbol in the renderer
and its shared contract. `gl_set_blend` switches only the destination factor
today, so multiply adds a case for the source factor as well.

**Trigger.** A game that draws a shadow or a tint and fakes it with a dark rect
at part alpha.

### Loose ends from smooth art

`texture_filter` samples every image a game loads with `:nearest` or `:linear`,
and is fixed when the app is created. `docs/api/images.md` has it under
"Filtering". Five things the smooth-art plan left:

- **A filter per image.** A game cannot draw crisp pixel-art tiles and smooth
  figures in one scene. Each sheet already records its filter, and
  `rgame_texture_uv` insets by it. What is missing is a keyword on the image,
  and an upload that reads it rather than the app's. A Tiled tileset choosing
  its own filter is the same change, read from a property. **Trigger:** a game
  whose art mixes both styles.
- **Mipmaps.** Under `:linear`, art drawn at under half its size skips texels,
  and shimmers as it moves. GL 1.1 takes each smaller level through
  `glTexImage2D` and samples between them with `GL_LINEAR_MIPMAP_LINEAR`. So
  `graphics/pixels.c` could build the levels on the CPU, with no loader, and
  premultiplied texels already average correctly. The inset does not carry
  over: on a smaller level one texel covers several of the sheet's, so a sprite
  would sample its neighbours again. `texture_filter` would take a third value.
  **Trigger:** a game that draws its art at under half its size.
- **Switching the filter while the game runs.** It is fixed at startup, as
  `media_root` is, since the asset cache would otherwise hold images made under
  two. A switch would set two parameters on every live sheet. It would also
  re-bake every `Recording`, which keeps the texture coordinates inset for the
  filter it was baked under. `Core::TileMapRenderer` bakes a map's static tiles
  on its first draw. **Trigger:** a "crisp or smooth" choice in a game's
  options.
- **A region drawn at its own size, exactly.** The half-texel inset that keeps a
  tile off its neighbours also leaves it up to a texel less of the sheet than it
  covers on screen. So under `:linear` a tile or subimage is resampled even at
  its own size. A tile of alternating black and white columns reads 0, 207, 80,
  143 across a row, where `:nearest` reads 0, 255, 0, 255. A whole image draws
  exactly, and smooth art drawn at another scale is resampled anyway. Skipping
  the inset at 1× on whole pixels needs the final scale, which a `Recording`
  lacks when it bakes. Padding each region at load needs to know where the
  regions are, and `subimage` and `tile` slice after the upload. **Trigger:** a
  `:linear` game that draws a sheet's tiles or icons at their own size and finds
  them soft.
- **A smooth tileset.** Each tile samples only its own pixels, so two tiles of a
  map meet in a step under `:linear`, as under `:nearest`. Extruding the
  tileset's edges changes nothing, since the inset keeps each tile inside its
  own pixels whatever lies beyond them. Drawing the map into a
  [render target](#a-low-resolution-render-target-and-the-gl-loader-it-needs) at
  its own size, then scaling that one texture, would blend across the seams.
  `examples/smooth_art` draws no tile map or nine-slice panel for want of such
  art. **Trigger:** a smooth tileset whose seams show, which is also the art
  that example is missing.

### Move the hot paths into C

Only after profiling, and only where there is a measured reason. Carried over
from the roadmap that planned the C engine; the entries have been checked
against what the code does now.

- **`NineSlice`'s tiling loops.** Still Ruby: `draw` walks each band with nested
  `while` loops, five tiled regions per call per frame. Every menu item on screen
  is one of these.
- **`TileMapRenderer`'s per-tile draw loop.** Half of this is already gone, and
  it is the outcome the roadmap hoped for: static tiles are baked into a
  `Recording` on first draw and replayed as one call per texture. What still
  loops per tile is the *animated* ones, which are collected once at construction
  precisely because finding them again each frame would cost more than drawing
  them. A map with a handful of animated tiles is already cheap; one with
  thousands is the case that would justify moving this.
- **`Renderer`'s per-draw id lookups.** Now one hash fetch on a registry that
  caches the resolved asset, so this is a much smaller item than when it was
  written. Left here only because it is the third thing to look at if a profile
  ever points this way.

**Why not now.** Each is a straightforward move once the pure geometry is
separable, and doing any of them early trades readability for a speedup nobody
has measured.

**Trigger.** A profile. Not a suspicion.

---

## Tile maps, Tiled and rooms

### Loose ends from the Tiled format plan

What the Tiled format plan chose not to read, and two measurements it left open.
What rgame reads and draws is in `docs/api/tile_maps.md`. Object layers have
their own plan in [object-layers/](object-layers/README.md).

- **Isometric, staggered and hexagonal maps.** Each raises `Tiled::FormatError`.
  Every conversion between cells and pixels goes through `TileMap`'s seam
  (`cell_x`, `col_at` and the rest), so a later plan fills the seam rather than
  sweeping for copies. `Util::SolidGrid`, `Util::TileSweep` and
  `Util::RouteSearch` are square-grid C, and a diamond grid rewrites all three.
  **Trigger:** a game on an isometric or hexagonal map.
- **Collision shapes smaller than a tile.** A tile is solid when it has any
  collision shape, and the shape's geometry is discarded. `SolidGrid` keeps a byte
  per cell, which is what makes collision and A* fast. **Trigger:** a game with
  a slope or a half-height ledge.
- **Per-layer parallax, offset and tint.** None is read. Parallax needs the draw
  path to know the camera, and the other two were not worth opening that door
  alone. **Trigger:** a parallax background.
- **World files.** A `.world` lays several maps out side by side. `Scene::Rooms`
  runs rooms side by side, but each builds its own map. **Trigger:** a game that
  lays its rooms out in a Tiled world.
- **A collection tile's sub-rectangle.** Tiled can cut one tile out of part of a
  collection image, and rgame draws the whole image. Of the attributes the parser
  skips, it is the one that would change what rgame draws today. **Trigger:** a
  tileset that uses it.
- **The orientation plane.** `Util::Tensor` holds a Ruby value per cell, so a
  layer's orientations cost 8 bytes a cell. Building that plane was 11.6 ms of
  the 29.5 ms a 250×250×6 map spent on its transform, measured while designing
  it. A map with no turned tile builds none. **Trigger:** a map big enough for
  either number to matter.
- **Built maps cached across runs.** `AssetManager` already transforms a map
  once per process. A cache across runs needs a format, a location and a rule
  for what invalidates it, for a transform that took about 35 ms on a
  250×250×6 map. A bulk fill of `Util::Tensor` in C comes first: it halves the
  dominant cost. **Trigger:** a scene load where building the map shows.

### A map that sets a component's values

**What.** A Tiled property whose type is a component's class, such as a
`BoxCollider` holding `width: 20`, sets that component's keywords on the node
built from the object. The node class would not pass the value on itself.

**What exists instead.** The object-layers plan lets a map set only a node's own
keywords, the ones the `@param` tags above its `initialize` make settable. A node
that lets a designer tune a component takes the value as its own keyword and
passes it on, together with what it derives from it. The parse already keeps a
class property's class, in `Properties#class_name`.

**Why not now.** Nothing asks for it. Measured at `abb91ad`, none of the 7 node
classes built from maps sets a component value per object: every value a map sets
is the node's own, such as a size, a route or a destination. And in 4 of the 7,
the two rafts, `Flag` and `Crate`, the code derives several of a component's
values from one, such as a box's offsets from its width. A map overriding `width`
would leave the offsets behind, and the box would sit off-centre without a word.

**What it would take.** The object-layers plan drafted it before taking it out:

- While a map-built node's `initialize` runs, `Component.new` merges the map's
  values for exactly its own class into its keywords, the map's winning.
  `Node2D.new` opens a scope of its own, so a child node's components take
  nothing. With no build in progress, both forward with `(...)` and allocate
  nothing extra.
- Each value is taken exactly once. A component class the node never builds, or
  builds twice, raises, naming the object.
- Components get `@param` tags as nodes do. 29 of the 39 take only keywords
  Tiled can express.
- Still unsolved: a guard for derived values, so a component can say that other
  values follow from one keyword.

Rejected on the way there:

- **Writers on each component.** That is up to 29 writers, each re-deriving what
  its constructor derived.
- **Running `initialize` again with the map's values.** It rebuilds what the
  first run set up, signals included.
- **Matching property names across components.** The Tiled format plan rejected
  it: nothing checks the name, and two components with one attribute both
  receive the value.

**Trigger.** A map that wants a component value no node class passes on, from a
node class whose derived values stay right under the override.

### Map notes that survive a save in Tiled

**What.** Move the note each example map opens with into a README beside it, so
the maps can be edited in Tiled without losing anything.

**What exists instead.** The six maps in `examples/assets/` and topdownplatformer's
`course.tmx` each open with an XML comment, 6 to 19 lines long. It says what the
map is for and why it is shaped that way: `town.tmx`'s says where the fence's one
gap sits, and why there. Each comment also says to edit the map in Tiled, and so
does `examples/assets/README.md`, four times. But Tiled writes a map anew when it
saves it, and keeps no comment. `town.tmx` written again by Tiled 1.12.2's
`--export-map tmx` kept 0 of its 1. So anyone following the advice deletes the
note, and every edit so far has been made in a text editor instead.

**Why not now.** The maps are plain, and several were written by a short Ruby
script. Their edits are a few lines each, such as an empty object layer for the
actors, and a text editor makes them. Only a designer drawing in Tiled loses the
notes, and nobody draws these maps.

**Trigger.** The example maps being replaced by better-looking maps drawn by hand
in Tiled. What still holds of each note moves into the README before the first
save, and the maps open with nothing Tiled would drop.

### Tile layers sorted row by row with the actors

**What.** Tiles that sort against actors by where they stand, as Godot 4's
`TileMapLayer` does with `y_sort_enabled` and a per-tile `y_sort_origin`.

**What exists instead.** A tile layer draws in one go, and y-sort orders only
nodes. Tall scenery is split in two: a trunk below the actors' slot, and a
canopy in a layer marked `above` that covers an actor wherever they stand. Tiled
tile objects are the other answer: one picture at one position, sorting like an
actor. They do not draw yet, and
[object-layers/](object-layers/README.md) says what they wait on.

**Why not now.** `Core::TileMapRenderer` would draw a layer a row at a time,
interleaved with the nodes of the slot. That changes how a layer and a slot
relate, and no map here asks for it.

**Trigger.** A map whose tall scenery neither the canopy layer nor tile objects
can express, such as a wall a character walks both in front of and behind.

### Rooms loaded by nearness, and big maps in chunks

**What.** Rooms built before a player reaches them, because they are near, and
a map too big to load at once split into chunks loaded in the background. This
is what an open world needs.

**What exists instead.** `Scene::Rooms` runs every room a player stands in, and
builds a room as the first player moves into it, under that player's cover.
`Rooms#hold` keeps a room running with nobody in it and `release` ends that, so
a game can build a room early by hand. Each room loads its whole map as one
`TileMap`.

**Why not now.** Every map here loads under a door's cover without a visible
wait, and no game is an open world. Loading in the background needs a thread
or a slice of each tick, and the tile map loader does neither.

**Trigger.** A room whose build shows as a hitch under the cover, or a map too
big to load at once. `Rooms#hold` is the seam a nearness policy calls.

---

## Movement, collision and pathfinding

### Pathfinding beyond one hero walking a fixed map

The pathfinding plan built `Util::SolidGrid`, `Util::RouteSearch`, `Util::TileSweep`,
`Engine::NavGrid` and `Components::Navigator` for one hero on an unchanging map, and
checked the design against five additions it did not build. What each would start
from:

- **Maps that change at runtime.** `Components::OccupiesCell` makes a cell solid
  while its node is in the tree, so a crate or a closed door blocks without an
  invisible wall. Two things are still missing. One is a decision about what a
  walking `Navigator` does when a cell turns solid under its route: today it
  stands at the new wall, `on_blocked` by `:tiles`, with nothing saying why. The
  other is changing which tile *types* are solid, such as "all water is now
  walkable". `Tileset#solid_ids=` did that until the Tiled format plan removed
  it. `TileWorld` keeps no bare `set_solid`, because a solid cell with nothing
  drawn on it is an invisible wall. A switch per tile type would not be
  invisible, since the designer drew the tile. **Trigger:** a door, a
  destructible wall, or a bridge a game wants, or a game that wants a tile type
  to change.
- **Replanning around moving actors.** The search state lives in `RouteSearch`,
  separate from the grid, so a per-query overlay of blocked cells is a parameter of
  `find`, not a second grid. **Trigger:** a game whose navigator must go around
  another character rather than wait (today it waits, by decision).
- **Crowds.** ~0.19 µs per expanded cell in C on an open map (measured on
  `beach_large.tmx`), untuned. A struct-of-entries heap and cheaper seen/closed
  stamps are the first moves. **Trigger:** a profile of many navigators.
- **Avoidance, and `travel?` on the other blocker sources.** "Clear" means no
  resolve falls short of the intended landing, so a system travels exactly when
  every source does: `CollisionSystem#travel?` would be `all?` over its sources.
  `BoundsBlockers` would answer in closed form (blocked only when the segment ends
  past an edge it moves toward). `ActorBlockers` is the open design — snapshot
  semantics over moving actors, its existing-overlap rule, its own sweep versus a
  closed-form swept box — and needs avoidance as a caller to settle. The shared
  group `a blocker source answering travel?` is ready for each. **Trigger:**
  steering that must rejoin a route.
- **Flow fields.** `rgame_route_neighbours` is the one neighbour-and-corner rule A*
  uses, public in `route_search.h`; a distance field from a goal is its second
  caller. **Trigger:** many walkers converging on one target.
- **Colliders larger than a tile.** Smoothing takes the next cell untested, sound
  only up to one tile, so `go_to` raises. Needs a search over cells the box fits
  (clearance per cell) and a smoothing that tests every step. **Trigger:** a large
  creature that must path.
- **Routes around gaps.** `NavGrid` plans over solidity only, so a `Navigator`
  routes straight through a gap, and a `:gaps` blocker stops it at the edge.
  `TileWorld` already keeps the gaps in a second `SolidGrid`, so the search could
  read both. Platforms move, and a route across one is a timing question the
  search cannot answer. **Trigger:** an NPC that plans routes near gaps.

### Loose ends from top-down platforming

Five things the top-down platforming plan found and left. `Footing`, `Platform`,
`Respawn` and `Checkpoint` are in `docs/api/components.md`:

- **Platforms that wait at their ends.** A platform that pauses at a dock is
  easier to board. `PathFollow` with `loop: true` never stops. On
  `examples/moving_platforms`' raft, a hop from the bank's edge boards it on
  1.37 s of every 8.4 s round trip. **Trigger:** a game whose players find a
  platform that never stops too hard to board.
- **Momentum on leaving a platform.** A hop off a platform keeps only the node's
  own walk, not the platform's last step. Godot adds the platform's velocity by
  default. **Trigger:** a hop off a moving platform that feels wrong without it,
  to someone playing it.
- **A pushed platform.** `Pushable` replaces `Mover#_update`, so a raft a hero
  pushes carries nobody. **Trigger:** a game with a raft to push.
- **A respawn point in a room left behind.** A `Rooms` move does not touch
  `Respawn`, so a hero who walks through a door keeps the old room's point.
  `Respawn` checks its point at every attach, so a gap under that point in the
  new room raises there. **Trigger:** a game with gaps in two rooms.
- **Platforms as Tiled tile objects.** A platform draws its own tiles in code.
  Once a tile object draws as a node, a platform could draw the one a designer
  placed. [object-layers/](object-layers/README.md) collects what
  that waits on. **Trigger:** tile objects drawing as nodes.

### Loose ends from y-sort

Three things the y-sort plan left open. The sort is in
`docs/api/scene_graph.md`, and the anchors in `docs/api/components.md`:

- **A node with a feet box and a second box.** The sort finds where a node
  stands with `get_component(BoxCollider)`, which raises when two components
  match. So such a node raises at its first sorted draw. No node in the
  repository has two. The likely answer is that a `FeetCollider` wins.
  **Trigger:** a game that needs a hitbox beside a feet box.
- **A sorted node inside a sorted node.** The inner one sorts as one unit, at
  its own footing. Merging the two into one sort is the alternative.
  **Trigger:** a scene that needs it.
- **`Targeting` reaches from the origin.** `Interactor` and `Grab` measure reach
  from the node's origin, while the sort and `Navigator` ask its `BoxCollider`
  where it stands. Sprites now stand on the origin, so the two differ only for a
  node whose box does not end there. **Trigger:** a reach that looks wrong on
  such a node.

### Edge margins derived from the node's size

**What.** `ScreenWrap` and `DespawnOffscreen` derive their `margin` from how big
the node is, rather than taking it by hand.

**What exists instead.** Every caller sets `margin` to a radius or more itself.
Asteroids' rock uses its largest tier's radius for all four tiers.

**Why not now.** It needs a footprint the node itself answers, and there is
none: `node.width` and `height` do not say where the box sits. A `Sprite` or an
`AnimatedSprite` places it by its own `anchor:`, `:bottom` unless told
otherwise, and the wrapped and despawned nodes in asteroids pass `:center`.

**Trigger.** A caller whose hand-set margin is visibly wrong, or a second place
that needs a node's footprint and has to pick a convention.

---

## Signals, components and naming

### A connection that ends with its node

**What.** A signal connection, or a `Facts#watch`, that ends by itself when the
node that made it leaves the tree.

**What exists instead.** A node that connects in `_enter_tree` disconnects in
`_exit_tree`: `Facts#unwatch` for a watch, and the same by hand for every other
signal. `docs/api/dialogue.md` says so for watchers.

**Why not now.** Forgetting is loud in one case and silent in the other. A
watcher that moves a named machine finds it replaced and raises; one that only
sets its own node's state keeps running on a node nobody draws. A fix belongs
to every signal the engine has, not to facts alone, so it is a change to
`Signal` rather than to the dialogue.

**Trigger.** A bug traced to a connection that outlived its node, or a second
component that has to write the same `_exit_tree`.

**The trigger has fired, three times.** The v0.5.0 roadmap wrote the same
disconnect in three places and kept doing it by hand (its decision 26, in git
at `b765de3`):

- `Components::Collectable` disconnects from its collider's `on_hit` as it
  detaches. That needed a public `disconnect_hit`, so `signal :name` now
  generates `disconnect_<name>` for every signal. The disconnect is possible,
  not automatic.
- `test_projects/adventure`'s world connects to `Players#on_joined` in
  `_enter_tree` and disconnects in `_exit_tree`. Before rooms, three scenes
  connected there and none disconnected, so a replaced one would have spawned a
  hero for every later join.
- `Components::Cutscene` disconnects from what each `hold` or `talk` step
  handed it, as the step ends.

`Components::Checkpoint`, which came later, disconnects from its collider as
`Collectable` does. The next change to `Signal` should start here.

### A seal on the private methods of every engine node

**What.** `Engine::SealedPrivates` refuses a subclass method that would replace
a private `rgame_` method of `Node2D` or `Component`. It covers those two
classes only. A private method of `UI::Button` or `Components::Mover` is still
an ordinary name, so a game's subclass can replace one without a word.

**Why not now.** Every ivar of every engine node and component starts with
`rgame_`, so the ivar rule is wider than the method rule. Widening the seal
means deciding, in each of 77 classes, which private methods are machinery and
which are seams, as `spec/rgame/engine/sealed_privates_spec.rb` already does for
the two base classes. No collision on such a method has happened yet.

**Trigger.** A game's subclass that replaces a private method of an engine
descendant by accident. Or a game that names an attribute `rgame_` in one,
which `Game/NoEngineIvar` cannot see either.

### Two loose ends from the naming plan

The plan that named signals, hooks and the engine's machinery left two things
it chose not to change.

- **`on_hit` passes the tense rule only weakly.** It fires when two colliders
  start to touch, and its partner is `on_separated`. "Hit" suggests one thing
  striking another, and reads the same in both tenses. **Trigger:** any
  change to the collision API, which would carry a rename with it.
- **The plain `system` lookup still returns nil where a system is required.**
  `Node2D#system!` raises with the class and where it looked, but
  `PlayerLayer` calls `system(Viewports).screen_for`, and ten examples call
  `system(Engine::Players)` and use the result. Outside a
  `Game` each fails as a `NoMethodError` on nil. **Trigger:** someone hitting
  that `NoMethodError`, or the next change to one of those callers.

### Loose ends from interaction verbs

`Components::Interaction` maps the actions a node answers to its own methods,
and an `Interactor` presses the nearest node that answers each action. Both are
in `docs/api/components.md`. Two things the interaction-verbs plan left:

- **A slot the component names itself.** A component takes its class's slot
  unless `add_component` is given `as:`. One `Interaction` per verb, in slots
  of their own, lost to one per node for three reasons. The verb is written
  twice, in the constructor and in `as:`. `get_component(Interaction)` raises
  on two. And two Interactions for one verb go unnoticed. A component that
  names its own slot, here after its verb, would answer all three. Every `as:`
  in the repository is a purpose its owner chose, such as a timer's `:spawn`,
  so that hook would have one caller. **Trigger:** a second component whose
  natural slot is a value it is built with.
- **A verb a target cannot answer right now.** A searched chest still answers
  `search`, and its handler finds nothing. An `Interaction` cannot say a verb is
  unavailable, so a prompt drawn per verb would still offer the search.
  **Trigger:** a game that draws a prompt per verb.

### Loose ends from single-job components

The plan that gave each component one question left three things. The
[build-components](../../.claude/skills/build-components/SKILL.md) skill holds
what it found, and the [component review](research/component-review-findings.md)
the defects it did not fix.

- **`Mover` answers two questions.** It answers where its step lands, and what
  moves with the step through three wirings: the `Pushable` it pushes, the one
  a `Grab` has it drag, and its `Platform`'s riders. Its header and the skill
  name it as the exception. The second half must run after the step, and a
  sibling could run it only from its own `_update`, so add order would decide
  the tick. A `Blocking` sibling once fired `on_unblocked` on two different
  ticks that way. No split that avoids it is known. **Trigger:** a fourth thing
  a step moves along, such as a tow rope or a vehicle, or a bug traced to one
  of the three wirings.
- **A component for doors.** A door connects its collider's `on_hit` and
  checks the toucher's layer by hand, as seven other handlers in the examples
  and test projects do. A `Touch.new(by: :hero).on_touched { ... }` would make
  the layer a required keyword, so no handler could forget it. Its whole job
  is one `if` over what `on_hit` hands over. **Trigger:** a bug traced to an
  `on_hit` handler missing its layer check.
- **A sheet animation that plays once, or holds a frame longer.**
  `AnimationSet` loops every animation, at one rate a frame. `Engine::FrameTimes`
  already answers a map tile whose frames last different times, and it times
  sheets too. So either is one change, in one place. **Trigger:** an attack or
  a death that must stop on its last frame, or a sheet whose frames are drawn to
  be held for different times.

---

## Dialogue, state graphs and cutscenes

### State machines for per-frame behaviour

**What.** A state machine that decides every frame rather than a few times a
minute: an enemy that patrols, chases and flees, or a sprite whose animation
follows idle, run and jump. Each state would get an update hook, and a
transition would fire from a test run every tick rather than from an event.

**What exists instead.** `Engine::StateMachine` runs decision graphs: a quest's
stages and a conversation's beats. State moves when a player chooses or an event
arrives, and nothing in it runs per frame. Its conditions run on every
`available?` call, and its transitions list is built for a menu of choices, not
for a loop that must allocate nothing. The dialogue plan kept per-frame
behaviour out on purpose (its decision 6, in git at `bf5db5c`).

**Why not now.** No NPC or animation in this repository hand-rolls a state
machine, so nothing says what shape the per-frame one should take, or whether
it should share a graph with the decision one at all.

**Trigger.** The second hand-rolled state machine in NPC or animation code — a
`case @state` in an `update` written for the second time.

### A file format for dialogue and state graphs

**What.** A loader that reads a conversation or a quest from a data file, YAML
or a reading of Yarn Spinner's format, and builds the same `Dialogue::Script` or
`StateGraph` the Ruby builder does.

**What exists instead.** `Dialogue::Script.build` and `StateGraph.build` are the
graphs' construction API, and a loader would call the same one. The dialogue
plan kept that possible on purpose (its decision 2, in git at `bf5db5c`). Every
option a builder takes as a block also takes a Symbol, sent to the context, so
`if: :can_buy?` is what a file would say where Ruby says a lambda. A line is a
translation key, and `vars:` a Symbol. Nothing about a format needs deciding
before a loader exists.

**Why not now.** Everyone writing a script so far writes Ruby, and a format
chosen with no writer to serve is a guess at what they need.

**Trigger.** A writer who will not write Ruby, or a game importing conversations
written in Yarn Spinner.

### Loose ends from cutscenes

Three things the v0.5.0 roadmap found and left, each small:

- **Nothing refuses a skip action without `hold:`.** `Components::Cutscene`'s
  `skip:` names an action the game should declare with `hold:`, so a tap does
  not skip. `docs/api/components.md` says so, and no code checks the binding.
  **Trigger:** a cutscene skipped by an accidental tap, or the next change to
  `Cutscene`'s constructor.
- **A cutscene that leaves the tree fires no `ended`.** It gives back
  everything it took, and did not end, so nothing fires. A game listening for
  the end to move on hears nothing. **Trigger:** a game that frees a scene
  under a running cutscene and waits for `ended`.
- **`Viewports#solo_camera` reads the applied mode.** A `solo!` asked for in
  the tick a cutscene with a camera starts is not seen, so the cutscene gives
  back the split rather than that solo. Nothing does that today. **Trigger:**
  a game that solos and starts a cutscene in the same tick.

---

## Input

### Input sequences and double taps

**What.** An action that presses on buttons pressed in order, such as a
fighting game's down, forward, punch, or on the same button pressed twice
within a window, such as a double tap that dashes.

**What exists instead.** An `InputMap` entry declares `hold:`, `tap:` and
`all:`: a press after a hold, a press on a short release, and a chord of buttons
down together. `ActionMapper#held_for` answers how long an action has been down.
A game can count a double tap itself from `pressed?` and its own timer.

**Why not now.** No game here asks for either. A sequence needs a buffer of
recent presses per player, and a double tap has to decide whether the first tap
also presses, so both are designs rather than a keyword.

**Trigger.** A game that dashes on a double tap, or reads a sequence, and
writes its own timer for it.

### Buffered input

**What.** A press remembered for a moment, so an action refused now happens as
soon as it can. A hop pressed a few ticks before a landing is one case, and an
attack pressed during another attack is a second.

**What exists instead.** Nothing in the engine buffers input. `Components::Hop`
reads `pressed?` on the tick it could start, so a hop pressed in the air is lost.
Coyote time in `Components::Footing` covers the opposite case, a hop pressed just
too late.

**Why not now.** It belongs to input, not to `Hop`: every action refused for a
few ticks at a time wants it, and each would otherwise grow its own. So it needs
a design first, per player and per action, and no game here has asked.

**Trigger.** A game whose players press early, and whose actions are refused
for a few ticks at a time.

---

## Text and UI

### Text layout past a label

**What.** Three things `Util::Typeface`, `Engine::Paragraph` and `UI::Label`
were built without, each with its own trigger:

- **Ascent and descent on `Typeface`.** The C face has both
  (`rgame_typeface_ascent`), and Ruby sees only `height`.
- **Breaking between characters.** `rgame_typeface_fit` breaks at spaces and
  newlines only, so a script written without spaces never breaks.
- **A panel behind a label, and vertical alignment.** `UI::Label` draws text
  from its top-left corner and nothing behind it. The design had a `style:`
  like `UI::TextButton`'s, but a style draws per button state, which a label
  does not have.
- **A face per `UI::TextButton`.** A button draws its label in the renderer's
  font, so a `UI::DialogueBox` given a larger `typeface:` draws the name and
  the line in it and its responses in the default font.

**What exists instead.** A caller steps lines by `height` and aligns them
horizontally. `examples/intro` places its block of text with its own arithmetic
and draws its own backdrop.

**Why not now.** Nothing asks for any of them. The shipped font covers no
script written without spaces, and nothing aligns two faces on one line.

**Trigger.** Ascent and descent: a caller aligning two faces on one line.
Breaking between characters: a font shipped or loaded that covers such a script.
The panel and vertical alignment: a third place drawing a backdrop behind a
label by hand. `examples/intro` is one, and `UI::DialogueBox` draws its `panel:`
behind the whole box rather than the label. A face per button: a game that
passes the box a `typeface:` and finds its responses in another face.

### Partial rows in a scrolling menu

**What.** A menu over a layout with `visible_rows` that scrolls smoothly, with
the rows at its edges drawn in part and clipped to the menu's window.

**What exists instead.** Whole rows scroll, by the fewest rows that bring focus
into view, and nothing is clipped. `rows_above` and `rows_below` say what a
game draws a scroll arrow from.

**Why not now.** Every scrolling menu so far is a bag or a list of short rows,
and a jump of one row reads as a step through a list.

**Trigger.** A list of rows tall enough that a whole-row jump reads badly, or a
game that wants the list to glide.

---

## Audio

### Ducking

**What.** Music that drops while something else plays over it, a voiced line
or a loud effect, and comes back up after.

**What exists instead.** `AudioOut` fades, crossfades, pauses and resumes music,
and sets a volume per category a game names. A game can lower its `:music`
category when a line starts and raise it when the line ends, by hand and without
a fade.

**Why not now.** Nothing in the engine plays a voice, and the dialogue system
draws text. Ducking needs to know when a sound ends, which a fire-and-forget
`play_sound` does not report.

**Trigger.** A game with voiced dialogue, or an effect that has to be heard over
the music.

### A second music track in the gem

**What.** A second loop under `examples/assets/`, so a shipped example can play
a crossfade between two songs.

**What exists instead.** One track ships, `music.ogg`. `examples/music` shows
fades, pause and resume and category volumes on it, and `docs/api/audio.md`
shows a crossfade in prose and code. `test_projects/adventure` crossfades
between two rooms' songs when `media/music/garden.ogg` exists, and `media/` is
never shipped. `examples/assets/README.md` measured the candidates for seam and
tail silence.

**Why not now.** A second loop adds about 6.5% to a 1.64 MB gem, for an effect
the documentation already shows.

**Trigger.** A shipped example that cannot make its point without a crossfade,
or a CC0 loop small enough that the size stops mattering.

---

## Packaging, CI and release

### Precompiled gems beyond three platforms and one Ruby

The precompiled binary gems plan shipped `arm64-darwin`, `x86_64-linux-gnu` and
`x64-mingw-ucrt` for Ruby 4.0, and left five questions open that it did not need
to answer. Every other machine and every other Ruby installs the source gem and
compiles, which works, so none of these blocks anything.

- **Bundler lockfiles across platforms.** A game's `Gemfile.lock` written on
  Linux lists only Linux under `PLATFORMS`. Recent Bundler adds the running
  platform on `bundle install`, but whether that picks the platform gem or the
  source gem on a teammate's Mac has never been tried. **Trigger:** the first
  published version with platform gems — it can be checked the day one exists,
  and until then there is nothing to check against.
- **Ruby 4.1**, due December 2026. A platform gem is bounded to one ABI, so a
  4.1 user falls back to the source gem and compiles. Covering 4.1 means either
  one gem per ABI or one gem holding a directory per ABI with a loader that
  picks. **Trigger:** Ruby 4.1 existing, plus someone who wants binaries on it.
- **More platforms.** Intel Macs, ARM Linux, musl Linux and Windows on ARM each
  add a `build-gem` leg and a `smoke` leg. The machinery takes a new platform by
  adding it to `CheckPlatformGem::PLATFORMS` and the CI matrix; nothing else
  knows the list. **Trigger:** someone asking for one.
- **Whether the source gem should use the pinned SDL2 too.** It would make every
  install run the same SDL version, but it would need CMake and a network fetch
  during `gem install`, which is a lot to ask of the path taken when everything
  else failed. The recommendation is no. **Trigger:** a source install that
  breaks on a system SDL2 old or odd enough to be worth the cost.
- **Native Wayland decorations.** The Linux build image cannot build SDL with
  libdecor, so under `SDL_VIDEODRIVER=wayland` on GNOME — which draws no
  server-side decorations — a window has no title bar. SDL2 picks X11 through
  XWayland by default, so nothing hits this without asking for it. Building
  libdecor from source in the image is possible. **Trigger:** someone wanting
  native Wayland.

### CI runs the whole matrix twice for every step

**What.** Stop a merge to `main` re-running what the pull request just ran.

**What exists instead.** `.github/workflows/ci.yml` triggers on `pull_request`
and on a push to `main`, and every roadmap step is a branch, a pull request and
then a merge — so the same commit is verified twice. Measured on the step 5
merge: the squash of #60 produced tree `580b4e8`, byte-identical to the branch
head the pull request run had already checked, so all ten non-`release` jobs
re-verified an identical tree. That identity holds only while a branch is
current; when `main` has moved underneath one, the merge produces a tree nothing
has tested, which is the case the second run would genuinely be for.

`release` is the only job on `main` whose output is new, and it declines on
nearly every push — four published versions across twenty `main` runs.

**Why not now.** It costs nothing measurable. The repository is public and the
runners are standard, so every job reports a `billable.duration_ms` of `0`. The
six-minute critical path — `build-gem windows` at 5m, then `smoke windows` at 1m
— is waited on only for the pull request, because the `main` run happens after
the merge when nobody is watching it. Trimming `main` would save neither money
nor attention, and would amend release machinery that has only just landed.

**What it would take.** Four shapes were weighed:

- **Release on a tag.** `on: push: tags: ['v*']` runs the full matrix and
  publishes; a merge to `main` runs nothing. It fits how releasing actually
  happens here — a deliberate act, not a side effect of merging — and it would
  let the job stop manufacturing the tag it now creates just before the first
  `gem push`, since the tag would be the trigger and `tools/release_gems.rb`
  would verify HEAD against it rather than supply the evidence itself. The cost
  is that a merge which breaks `main` waits for the next pull request or the
  next release to surface it, which is safe only while branches are current and
  one step is in flight at a time — precisely what
  [implement-step](../../.claude/skills/implement-step/SKILL.md) stops
  guaranteeing when step N+1 branches off step N's branch.
- **Trim the pull request run** to Linux and keep all three platforms on `main`.
  The only shape that shortens the wait, and it gives up the one thing no local
  run provides: macOS and Windows before the merge rather than after it.
- **Gate `main` on a version bump**, skipping the matrix unless
  `lib/rgame/version.rb` changed in that push. That is `release_gems.rb`'s own
  question asked in seconds, ahead of six minutes of building rather than after.
- **Leave it**, which is what was chosen.

**Trigger.** The pull request wait growing long enough to be felt, or these runs
starting to be billed — which is what making the repository private would do,
since the free minutes are a property of it being public.

### `rgame examples`: finding the examples in an installed gem

**What.** An `rgame examples` command that lists the examples shipped in the gem
with their one-line descriptions, and perhaps copies one into the working
directory the way `rgame new` scaffolds a project.

**What exists instead.** `examples/` ships inside the installed gem, and the
README and `docs/api/examples.md` describe each one. But the gem's directory is
somewhere nobody browses, and `rgame` knows only `new`, `version` and `help`.

**Why not now.** It was deliberately deferred until the examples existed, and
nobody has yet failed to find them. It is a CLI feature, and `docs/api/cli.md`
is where its shape would be argued.

**Trigger.** Someone who installed the gem asking where the examples are, or the
first release announced to people who will not clone the repository.

### A packed asset format

**What.** Read a game's assets out of one or a few pack files instead of loose
files, for a release on a store such as Steam.

**What exists instead.** Loose files under the media root. Steam does not require
packs: SteamPipe splits every file into ~1 MB chunks and uploads only the chunks
that differ, so loose files patch well. Its advice for packs — keep changes
localized, keep asset order stable, compress per asset, no table of contents of
absolute offsets — constrains the tool that *writes* a pack. The reader only
needs every read to go through one seam
([Steamworks: Uploading to Steam](https://partner.steamgames.com/doc/sdk/uploading)).

Translation tables already do: `AssetManager#glob` lists them and the `:locale`
loader reads them. What does not:

- `image.c` and `font_atlas.c` `fopen` a path. A pack needs
  `stbi_load_from_memory` and a font read from a buffer.
- `audio.c` calls `ma_decoder_init_file` and `ma_sound_init_from_file`. A pack
  needs miniaudio's VFS (a resource manager with a custom `ma_vfs`), which
  `vorbis_decoder.c`'s `onInit` entry point already reads through.
- `AssetManager#resolve` is `File.expand_path`. That is the Ruby seam, and it is
  already the only one.

**Why not now.** Nothing ships through a store yet, and loose files are what
SteamPipe patches best.

**Trigger.** A release whose file count or install layout makes loose files a
problem, or a store that requires a pack.

---

## Misc

### An example that flies, for `ThrustController`

**What.** One example, `examples/twin_stick` or similar: a ship that turns and
thrusts with `Components::ThrustController`. A turret aiming at the nearest
enemy through `Components::Targeting` would make it most of a twin-stick
shooter.

**What exists instead.** `ThrustController` has a spec and a section in
`docs/api/components.md`, and only `test_projects/asteroids` builds one, which
does not ship. Every example moves things in screen axes, so nothing flies.
`Targeting` needs no example of its own: `components.md` aims a turret in an
example the doc specs run, and `Grab` and `Interactor` are Targetings that
`push_pull`, `collectables` and `quests_and_dialogue` build.

**Why not now.** The single-concept examples plan that found the gap is done,
and no caller asks for one. The
[component review](research/component-review-findings.md) found two defects in
`ThrustController`. Pull request #184 fixed one: it wrote its `Velocity` in the
phase that `Velocity` reads. The other stands: it answers which actions steer a
ship as well as how the ship handles. An example built now would be built on
the shape that fix changes.

**Trigger.** A fix for the finding that stands, which then has no example to
check it against, or a reader asking how to fly something.

### A snapshot of the loaded translation tables

**What.** `I18n.snapshot` and `I18n.restore`, so a spec suite puts its tables
back before each example without parsing them again.

**What exists instead.** The `spec_helper` that `rgame new` generates calls
`I18n.reset` and loads every table before every example, because `I18n` is
global and a spec that switches the locale or loads a table would otherwise leak
into the next one. Measured when it was written (Ruby 4.0.5, no YJIT): 0.03 ms
for the generated one-key table, 8.1 ms for 1,000 keys — 5.0 ms of YAML parsing
and 2.9 ms of compiling. Compiled tables are frozen, so a restore could hand the
same objects back for a constant cost.

**Why not now.** No game's suite is slow because of it. The generated project
has one key.

**Trigger.** A game whose spec run is measurably slowed by reloading its tables.

### Particles that stay where they were emitted

**What.** A particle that keeps its place in the world when its emitter moves,
so a moving node leaves a trail. Godot calls the switch `local_coords`.

**What exists instead.** `Components::Particles` places its particles in its
node's local space, and they move with the node. An emitter that must outlive
its node already goes on a node of its own. A trail can be faked by moving a
separate emitter node and bursting at the mover's position each tick.

**Why not now.** Every emitter so far sparkles from a node that stands still, a
coin, a chest or a spell. A world-space particle needs its emitter's world
position at emit time and must draw outside its node's transform, which
`Node2D#draw` has already pushed.

**Trigger.** An exhaust, a dust cloud behind a runner, or any trail behind a
moving node.
