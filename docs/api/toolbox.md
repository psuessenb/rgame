# Toolbox

This page covers engine classes **a game author uses directly** that belong to no
other chapter: pooling, the text a node draws, audio facts, the camera, collision boxes.
All are pure Ruby, so they stay testable headless. One section is a recipe, not a
class: [making a character that collides](#making-a-character-that-collides). No
single class answers that question.

[Internal building blocks](internals.md) covers the low-level classes *behind*
components, which you rarely construct by hand: collision maths, the spatial
index, animation playback.

## Grids

**The engine has no grid class of its own.** A fixed-size grid is a
[`RGame::Util::Tensor`](values.md#rgameutiltensor): three-dimensional, backed by
one flat C array. A flat 2-D grid is a `Tensor` with a depth of 1. `TileMap`
stacks its tile layers in one `Tensor(width, height, layer_count)`. It shows the
rule that the engine layer may hold `RGame::Util` values: a grid is a value, so
the engine owns one outright.

[`NavGrid`](#navgrid--routes-over-a-tile-grid) searches over a grid's solidity; it
does not store a grid. The solidity lives in a
[`Util::SolidGrid`](values.md#rgameutilsolidgrid), one byte per cell in C. The C
search must read it, and a `Tensor`'s cells are Ruby objects.

## `Text` — the string a node draws

**`RGame::Engine::Text` (`rgame/engine/text`) holds a translation key and keeps
the rendered String until an input changes.** The inputs are its variables and
`I18n.generation`. Build a `Text` once, off the per-frame path, and read it in
`on_draw`. A read with unchanged inputs returns the same frozen String and
allocates nothing. [Localization](localization.md) covers the tables it reads,
plurals, and the player's language.

```ruby
require 'rgame'

i18n = RGame::Engine::I18n
i18n.load_hash(en: { hud: { score: 'Score: %{score}', title: 'Apples' } },
               de: { hud: { score: 'Punkte: %{score}', title: 'Äpfel' } })

score = RGame::Engine::Text.new('hud.score', :score)   # built once
title = RGame::Engine::Text.new('title', scope: 'hud')

score.with(score: 7)                            # => "Score: 7"
score.with(score: 7).equal?(score.with(score: 7)) # => true — nothing changed, nothing rendered
title.to_s                                      # => "Apples"
i18n.locale = :de
score.with(score: 7)                            # => "Punkte: 7" — the switch re-renders
title.to_s                                      # => "Äpfel"
```

In a node, the draw reads the `Text` with the current value, or passes a `Text`
with no names as it is:

```ruby
def on_draw(renderer, _view)
  renderer.text(@score.with(score: @points), 12, 10)
  renderer.text(@title, 12, 30)
end
```

**A `Text` goes where a String goes.** It answers `to_str` with the same String
as `to_s`, so `Renderer#text` and `Renderer#text_width` take one directly. A
`Text` is also `==` to a String that reads the same, from either side. A spec's
spy that recorded a `Text` therefore matches `with('Apples', 12, 30)`. Two `Text`s
compare by identity, and `hash` stays the object's own, so a `Text` is not a
String-keyed Hash key.

```ruby
require 'rgame'

RGame::Engine::I18n.load_hash(en: { hud: { title: 'Apples' } })
title = RGame::Engine::Text.new('hud.title')

title == 'Apples'                               # => true
'Apples' == title                               # => true
title.to_str.equal?(title.to_s)                 # => true — the same String, no copy
```

### Variables are keywords

`Text.new(key, *names, scope: nil)` gives the `Text` a `with` whose keywords are
`names`. A missing or unknown keyword raises Ruby's own `ArgumentError`, on the
first frame that reads it. Every `Text` with the same names shares one generated
`with`, whatever order the names came in. `names` returns them sorted.

A `Text` with no names is read with `to_s`, and `with` with no keywords returns
the same. On a `Text` that has names, `to_s` reads it with the values its last
`with` was given, and renders them again after a locale switch. So one node can
set the values in `update`, and whatever draws the `Text` passes it on without
knowing them: a [button's label](ui.md#labels-are-translation-keys) works this
way. Before the first `with`, `to_s` and `to_str` raise `ArgumentError`, naming
the keywords `with` needs, and a renderer handed the `Text` lets that error
through.

The values belong to the `Text`, not to whoever set them. Two nodes sharing one
`Text` with names show whatever the last `with` gave, so give each node its own. A name must be usable as a Ruby local variable:
`Text.new('x', :Name)` and `Text.new('x', :end)` raise `ArgumentError`.

A key whose translation is a plural needs `:count` among the names, and picks its
form by `count` as [`I18n.t` does](localization.md#plurals).

### Scope

`scope: 'hud'` with key `'title'` resolves `'hud.title'`. `key` returns the key
without its scope. `scope=` changes the scope, and the next read resolves again.
A [`UI::Menu`'s `scope:`](ui.md#labels-are-translation-keys) sets the scope of
the labels its buttons build from keys.

### When it renders again

A read renders again when any keyword differs from the last read, by `==`, or
when `I18n.generation` has moved. The generation moves on every `load`, every
switch of locale or default, and `reset`. A `Text` compares that one Integer and
never subscribes to `I18n`, so nothing holds on to it.

A `Text` built before any table loads shows the [missing-key](localization.md#missing-keys)
answer. After a `load`, its next read shows the translation.

A translation whose placeholders differ from the declared names also goes to the
missing policy. Under `:key` the `Text` shows its key, and a callable receives
the key and the chain. Under `:raise` it raises `I18n::VariableMismatch` in
either direction: for a `%{name}` the `Text` does not declare, and for a
declared name the translation never prints. A plural whose `Text` lacks `:count`
raises it too.

### `Text.literal` and `Text.computed`

`Text.literal(string)` shows `string` in every locale and never consults `I18n`.
`Text.computed(*names) { |**keywords| ... }` shows what its block returns. The
block runs when a keyword or `I18n.generation` changes, and never on an unchanged
read. A block that calls `I18n.t` therefore follows the language:
`examples/pathfinding` assembles its status line this way from four keys, two of
them plurals. Both answer
`with`, `to_s` and `to_str` like any `Text`, and both ignore `scope=`.

```ruby
require 'rgame'

lives = RGame::Engine::Text.computed(:lives) { |lives:| "Lives: #{lives}" }
lives.with(lives: 3)                         # => "Lives: 3"
RGame::Engine::Text.literal('Ada').to_s      # => "Ada"
```

**Use a `Text` instead of working around the cop.** `Game/NoInterpolationInHotPath`
refuses `"Score: #{score}"` in a draw, and a `Text` built in `initialize` is the
answer. `examples/sound` shows it: a play counter on screen costs one render per
press and none in the frames between. A value that changes *every* frame, such
as an FPS counter, gains nothing from a cache. `RGame::Engine::DebugOverlay`
draws its digits one by one from cached single-character strings.

**Text chosen by state is a table of `Text`s**, such as
`{ true => Text.new('state.fullscreen'), false => Text.new('state.windowed') }.freeze`.
It selects a `Text` and builds nothing. A `Text` holds no reference to a game, so
it can live in a constant. A `Text.computed` made at the top level of a file
cannot: its block keeps that file's local variables alive, a `game` among them. A
value that **never changes and is not words**, such as an
id, belongs in an ivar built in `initialize`.

## `Pool` — reuse, don't allocate

**`RGame::Engine::Pool` (`rgame/engine/pool`) recycles short-lived objects of one
kind**, so steady-state spawning allocates nothing. Bullets, particles and
transient enemies are typical. `acquire` takes an object from a free list, and
calls the factory block only when the list is empty.

```ruby
pool = RGame::Engine::Pool.new { Bullet.new }   # factory builds a blank object
b = pool.acquire                         # recycled, or freshly built once
b.reset(x, y, angle)                     # caller re-initialises after acquire
pool.each { |bullet| bullet.update(dt) }
pool.reclaim_if(&:dead?)                 # sweep dead → free list, once per frame
```

The factory builds a *blank* object. The caller re-initialises it after
`acquire`, usually through a `reset` method on the pooled class.
`examples/pooling` shows this on a node. `reclaim_if` sweeps the active list once
and moves every object the block marks dead onto the free list. Call it *after*
iterating with `each`; never change the active list mid-iteration. `active`,
`size`, `empty?` and `each` expose the live set for update and draw.

## `Path` — a walkable polyline

**`RGame::Engine::Path` (`rgame/engine/path`) is an ordered polyline** that an
entity walks along: a road, a patrol route, a track. It is pure data. It holds the
waypoints and precomputed segment lengths, so a follower allocates nothing at
runtime. It stores waypoints flat (`x0, y0, x1, y1, …`) in one array and returns
them through scalar accessors. Neither construction nor traversal creates an
object per waypoint.

```ruby
path = RGame::Engine::Path.new([[0, 0], [100, 0], [100, 100]]) # ≥ 2 waypoints, in walk order
path.count             # number of waypoints
path.x_at(i)           # scalar coords of waypoint i (no allocation)
path.y_at(i)
path.segment_length(i) # length of the segment from waypoint i to i+1
path.length            # total length
path.distance_to(x, y) # shortest distance from a point to the polyline
```

A follower ([`Components::PathFollow`](components.md#pathfollow)) reads segments
by index and interpolates itself; `Path` never returns a coordinate pair.
`distance_to` answers "how far is this point from the road" with scalar maths and
no allocation. A level can use it to keep objects off or away from the road.

## `NavGrid` — routes over a tile grid

**`RGame::Engine::NavGrid` (`rgame/engine/nav_grid`) finds the cheapest route from
one cell to another.** The search runs in C, as a
[`Util::RouteSearch`](values.md#rgameutilroutesearch). In a tile scene you do not
build one: [`TileWorld#nav_grid`](components.md#tileworld) returns one over the
map's solid tiles.

You build a `NavGrid` in one of two ways. Passing both or neither raises
`ArgumentError`.

- **From a callable**: `NavGrid.new(width:, height:, solid:)`.
  `solid.call(col, row)` returns true for a solid cell. `NavGrid` calls it once per
  cell, copies the answers into its own grid, and never calls it again. A later
  change behind the callable stays invisible.
- **Over a shared grid**: `NavGrid.new(grid:)`, with a
  [`Util::SolidGrid`](values.md#rgameutilsolidgrid). Nothing is copied, so a cell
  changed in that grid changes for the `NavGrid` at once. `TileWorld` builds its
  grid this way. Use this form for solidity that will change. A
  [`TileBlockers`](internals.md#tileblockers--the-tile-grid-as-a-blocker-source)
  is built over the same grid, so routing and collision read one store.

```ruby
require 'rgame'

rows = [
  '........',
  '###..###',
  '........'
]
grid = RGame::Engine::NavGrid.new(width: 8, height: 3,
                                  solid: ->(col, row) { rows[row][col] == '#' })

grid.walkable?(3, 1)        # => true
grid.find(0, 0, 7, 2)       # => [[0, 0], [1, 0], [2, 0], [3, 0], [4, 1], [4, 2], [5, 2], [6, 2], [7, 2]]
grid.find(0, 0, 0, 1)       # => nil — the goal is solid
grid.reachable?(0, 0, 7, 2) # => true
grid.region(0, 0)           # => 0 — an Integer label; nil for a solid or off-grid cell
```

- **A route is a list of cells, both ends included**, as `[[col, row], ...]`. When
  start equals goal, the route has one cell. Turning a cell into a point to walk to
  depends on the node's collider, which the grid knows nothing about. So `NavGrid`
  never speaks pixels. [`Components::Navigator`](components.md#navigator) does that
  and walks the result.
- **An unreachable goal returns `nil`.** That covers a solid or off-grid end, and a
  goal in another region. `nil` is an ordinary answer, not an error.
- **Moves go 8 ways at octile cost**: 1 straight, √2 diagonal. A diagonal move
  requires both orthogonal neighbours to be open, so a route never cuts the corner
  of a solid cell. The search returns a cheapest route. It breaks ties
  deterministically, so the same query always returns the same route.
- **`NavGrid` relabels connected regions whenever the grid has changed.** A goal
  in another region is the slowest answer for a search, which must exhaust the
  start's region first. Region labels turn it into a lookup. Relabelling a 120x90
  map takes about 45 µs, on the first query after a change.
- **Regions and routes follow a shared grid.** Wall a region in two through the
  `SolidGrid`, and the next `find` across the wall returns `nil`. Open it again and
  the route goes through, with nothing rebuilt:

  ```ruby
  store = RGame::Util::SolidGrid.build(8, 3) { |col, row| rows[row][col] == '#' }
  shared = RGame::Engine::NavGrid.new(grid: store)
  store.set_solid(3, 1, true)
  store.set_solid(4, 1, true)
  shared.find(0, 0, 7, 2)       # => nil — the gap is closed
  shared.reachable?(0, 0, 7, 2) # => false
  ```

- **Coordinates are Integers.** A `Float` or `nil` names no cell and raises
  `TypeError`. An Integer outside the grid, however large, is treated like any
  other cell outside it.
- **Search on demand, never per frame.** A search allocates its result. It keeps
  its working buffers between searches, so never search one `NavGrid` from two
  threads at once. A corner-to-corner route across a 60x40 town takes under
  0.1 ms. The slowest of 200 random routes on a 120x90 map takes about 1 ms.

### What routing does not cover

- **Maps that change at runtime, in a tile scene.** A shared `SolidGrid` changes
  under a `NavGrid` and a `TileBlockers` at once, as above. `TileWorld` keeps its
  grid private, though, and a
  [`Navigator`](components.md#navigator) already walking learns nothing of a change.
- **Replanning around moving actors.** `find` knows only the grid. It cannot treat a
  cell as blocked for one query, and a `Navigator` held by another actor waits
  instead of replanning.
- **Crowds.** Many navigators can share one `TileWorld#nav_grid`. Each `go_to` costs
  a search plus smoothing, well under a millisecond on a 60x40 map. Nothing
  coordinates the walkers.
- **Avoidance.** Nothing steers a walker around another. Of the blocker sources,
  only `TileBlockers` answers `travel?`.
- **Flow fields.** A search answers one start and one goal. Nothing computes the
  distance from every cell to a shared goal.
- **Weighted terrain.** Every open cell costs the same.
- **Colliders larger than a tile.** `Navigator#go_to` raises for one.

## `Timer` — paced periodic events

**`RGame::Engine::Timer` (`rgame/engine/timer`) accumulates time; its owner decides
what each interval means.** Use it for periodic events that no input drives: a
spawner that emits an enemy every N seconds, a turret's fire rate, a wave clock.
The split lets one class serve two patterns. "Act automatically" consumes every
ready interval. "Stay loaded until allowed" checks `ready?` but calls `consume`
only when acting, so a turret without a target keeps its shot ready. `Timer` is
pure and allocates nothing, so it runs on the per-frame path.

```ruby
@spawn_timer = RGame::Engine::Timer.new(0.8)   # built once, off the hot path

def on_update(dt)
  @spawn_timer.update(dt)
  return unless @spawn_timer.ready?      # a whole interval has accumulated

  @spawn_timer.consume                   # deduct it; the remainder carries forward
  spawn_enemy
end
```

`consume` carries the overshoot forward instead of zeroing it, so a long-running
cadence does not drift. `reset` drops accumulated time, for example after you
change `interval`. When one step may span several intervals, loop:
`while timer.ready? do …; timer.consume end`.

For a node that should tick on its own, use
[`Components::Timer`](components.md#timer). It owns a `Timer`, runs in the node's
update tick so nothing can forget to drive it, and emits `on_timeout` instead of
making you poll `ready?` and `consume`.

## `Camera` — follow a point, clamp to the world

**`RGame::Engine::Camera` (`rgame/engine/camera`) holds the follow-and-clamp maths
for a scrolling view.** It splits the work into two calls:

```ruby
camera = RGame::Engine::Camera.new(world_width: map.pixel_width, world_height: map.pixel_height)
camera.center_on(player_x, player_y)   # in update: what to look at
camera.resolve(view_width, view_height) # at draw: the offset for *this* viewport
camera.x, camera.y                      # the resolved offset
```

`center_on` records the target. `resolve` computes the offset, clamped so the
view never shows past the world's edges. `world_width` and `world_height` are
optional and writable: a scene sets them when it loads a map. Left `nil`, the
camera is unbounded and follows its target exactly. With bounds, the target drifts
off centre near a corner.

**The viewport size is an argument, not state**, because one camera can be drawn
through viewports of different sizes. A half-width viewport clamps
differently from a full-width one, and the difference shows near a world edge.

**A camera belongs to a player**
([`RGame::Engine::Player#camera`](input.md#players-seats-and-joining)), not to a
scene, because a scene may have any number of viewers. You never call `resolve`
yourself. `Viewports` resolves each view's camera against that view's size before
the frame is drawn. A
[`CameraFollow`](components.md#camerafollow) component on the followed node points
the camera, and a [`WorldView`](scene_graph.md#view-transforms-and-the-camera)
applies it. See `examples/scroll_map` for one camera and `examples/split_screen`
for two.

## Making a character that collides

**A character stopped by the world *and* by other characters is four components
on a plain node.** Nothing connects them by hand:

```ruby
require 'rgame'

node = RGame::Engine::Node2D.new(x: 240, y: 320)
node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
node.add_component(RGame::Engine::Components::FeetCollider.new(width: 10, height: 8, layer: :hero))
node.add_component(RGame::Engine::Components::CharacterBody.new(speed: 60, blocked_by: %i[tiles hero npc]))
node.add_component(RGame::Engine::Components::PlayerController.new)
```

Each line does one job:

- The [sprite](components.md#animatedsprite) gives the node its dimensions, and
  reads the body's intent back as a facing.
- The [`FeetCollider`](components.md#feetcollider) derives a small box at the
  bottom of those dimensions. It is the node's **only** shape.
- The [`CharacterBody`](components.md#characterbody) names what that shape may not
  pass through.
- The [controller](components.md#playercontroller) writes an intent each step, and
  the body turns it into a move.

An NPC is the same four lines, with a
[`WanderController`](components.md#wandercontroller) and `layer: :npc`. The hero's
`blocked_by` names `:npc`, and the NPC's names `:hero`. The two stop each other
without knowing what the other is. A crowd of NPCs that all declare `:npc` works,
because a body is never stopped by its own collider.

The scene must mount what those names refer to: a
[`TileWorld`](components.md#tileworld) for `:tiles`, and a
[`CollisionWorld`](components.md#collisionworld) for the two layer names. **A name
with nothing behind it raises at attach**, naming what is missing. An actor that
silently walked through walls would look like a collision bug, with its cause in a
scene file three directories away.

Three things need no remembering:

- **Component order does not matter.** The feet box needs the size the sprite
  gives the node. So the collider builds it on first read, not at construction.
- **The node has one shape, not two.** The body resolves the collider's box. The
  rectangle a fence stops is the rectangle that reports contacts, and
  `collider.box =` retunes both.
- **Reacting needs no second mechanism.** `body.on_blocked { |by| ... }` fires once
  when something starts stopping the body: a villager, a solid tile or the world's
  edge. A blocked pair ends up *touching*, not overlapping, so `on_hit` is the wrong
  signal. See
  [Blocking and overlapping](systems.md#blocking-and-overlapping-are-two-reports-and-a-pair-gets-one-of-them).

[Collision: two indexes, one resolver](systems.md#collision-two-indexes-one-resolver)
describes the architecture behind those four lines.

## `CollisionBox` — an actor's feet box

**`RGame::Engine::CollisionBox` (`rgame/engine/collision_box`) is a character's
collision rectangle.** It stores an offset and a size **relative to the sprite's
top-left origin**, independent of the sprite's size. A 32×32 sprite can therefore
carry a small box at its feet. A [`BoxCollider`](components.md#boxcollider) holds
one. [`FeetCollider`](components.md#feetcollider) builds this shape from the node's
dimensions, so a character rarely constructs one by hand. The collision code
resolves the box, not the sprite, against whatever the body declared: solid tiles,
other actors, the world's edge.

```ruby
box = RGame::Engine::CollisionBox.bottom_anchored(
  sprite_width: 32, sprite_height: 32, width: 16, height: 16
) # centred horizontally, anchored to the sprite's feet
box.aabb(x, y) # => [x + offset_x, y + offset_y, width, height]
```

`bottom_anchored` covers the common feet box. For anything else, the constructor
takes `width:` and `height:`, plus optional `offset_x:` and `offset_y:`, both
defaulting to 0.

`CollisionBox` also holds rectangle geometry, as class methods over plain numbers.
A per-frame path can call them without building a box:

```ruby
RGame::Engine::CollisionBox.overlap?(x1, y1, w1, h1, x2, y2, w2, h2) # rect vs rect
RGame::Engine::CollisionBox.overlap_circle?(x, y, w, h, cx, cy, r)   # rect vs circle
```

**Both tests are half-open**: a shape spans `[x, x + w)`. Shapes that share only
an edge, or a circle that exactly grazes a box, do not overlap. That is also why
blocking and contact are separate reports. A blocked pair ends up exactly
touching, so it does not overlap, and `on_hit` does not fire.
`CircleCollider.overlap?` agrees, so contact means the same for every pair of
shapes. A grid needs this convention. Pieces on neighbouring squares border each
other constantly, and an inclusive test would report each as a contact. The
broadphase buckets by the same convention, so the two never disagree.

A [`BoxCollider`](components.md#boxcollider) component is a `CollisionBox` plus a
registration in the scene's [`CollisionWorld`](components.md#collisionworld). These
two methods are its narrowphase. [`FeetCollider`](components.md#feetcollider) adds
the `bottom_anchored` arithmetic, computed from the node's own dimensions.

## `AudioBus` — decoupled audio facts

**`RGame::Engine::AudioBus` (`rgame/engine/audio_bus`) is a global audio bus.**
Gameplay emits audio *facts* on it, such as "play this sound" or "play this
music", separate from playback. An `AudioDirector` subscribes and turns the facts
into sound. The bus is a module, not an instance, so any node reaches it without
wiring.

```ruby
RGame::Engine::AudioBus.play_sound(:boom)
RGame::Engine::AudioBus.play_music(:theme)
RGame::Engine::AudioBus.stop_music
```

**`RGame::Game` subscribes a director when it starts, and calls `unsubscribe`
when the loop ends.** A game does neither. The release matters. The bus is a
module, so it holds its listeners until someone removes them. A listener holds the
director, the audio device, and the asset manager the device resolves paths
through. That manager holds the `App` it loads images for, window included. A
single game never notices, because its `App` lives as long as the process. A
process that runs two games does notice.

`play_sound`, `play_music` and `stop_music` form the gameplay API. Under each sits
an [`RGame::Engine::Signal`](signals.md) (`on_play_sound`, `on_play_music`,
`on_stop_music`), which the director subscribes to. The engine only emits facts
and never names an audio device. The bus therefore stays in the engine layer, and
playback stays in `RGame::Core`.
