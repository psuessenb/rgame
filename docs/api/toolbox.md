# Toolbox

This page covers engine classes **a game author uses directly** that belong to no
other chapter: pooling, localization, audio facts, the camera, collision boxes.
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

## `CachedLabel` — a display string rebuilt only on change

**`RGame::Engine::CachedLabel` (`rgame/engine/cached_label`) rebuilds a label only
when its source value changes.** A per-frame draw shows the cached copy and
allocates no `String`. Build the label and its format block off the per-frame
path, for example in `initialize` or `on_add`. Read it by value in `on_draw`:

```ruby
@score_label = RGame::Engine::CachedLabel.new { |score| "Score: #{score}" }  # built once

def on_draw(renderer, _view)
  renderer.text(@score_label[@score], 12, 10)   # cached; rebuilds only when @score changes
end
```

`@score_label[value]` returns the same `String` object while `value` stays the
same. The interpolation lives in a block built off the per-frame path, so the
engine's allocation cops (`rubocop/cop/game/`) do not flag it. A value that
changes *every* frame, such as an FPS counter, gains nothing from a cache. Draw
its digits one by one from cached single-character strings, as
`RGame::Engine::DebugOverlay` does.

**Use `CachedLabel` instead of working around the cop.** Labels built from
changing values are common, and each hand-made workaround puzzles the next
reader. `examples/sound` shows it: a play counter on screen costs one allocation
per press and none in the frames between.

`CachedLabel` does not fit two cases. A **constant string chosen by state**, such
as `{ true => 'fullscreen', false => 'windowed' }.freeze`, selects a string and
builds nothing. A value that **never changes** belongs in an ivar built in
`initialize`. Both allocate nothing already, and a cache would add indirection
for no gain.

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
`size` and `each` expose the live set for update and draw.

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
grid.region(0, 0)           # => 0, an Integer label; nil for a solid or off-grid cell
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
view never shows past the world's edges; near a corner, the target drifts off
centre. **The viewport size is an argument, not state**, because one camera can be
drawn through viewports of different sizes. A half-width viewport clamps
differently from a full-width one, and the difference shows near a world edge.

**A camera belongs to a player**
([`RGame::Engine::Player#camera`](input.md#players-seats-and-joining)), not to a
scene, because a scene may have any number of viewers. You never call `resolve`
yourself. `Game` resolves each camera against the viewport it is about to draw. A
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

## `RGame::Engine::I18n` — localization

**`RGame::Engine::I18n` (`engine/i18n`) provides minimal localization.** It keeps
per-locale translation tables, loaded from YAML or an inline Hash. `t(key)` looks
a key up with `%{var}` interpolation, a fallback locale and pluralization. `I18n`
is a **global module**, so `t` works anywhere without wiring. Its only dependency
is the standard library's YAML.

```ruby
RGame::Engine::I18n.load_file(:en, "locales/en.yml")
RGame::Engine::I18n.load(:de, menu: { title: "Hauptmenü" })   # nested Hashes allowed
RGame::Engine::I18n.default = :en        # fallback when the current locale lacks a key
RGame::Engine::I18n.locale = :de

RGame::Engine::I18n.t("menu.title")               # dotted key, resolved in :de then :en
RGame::Engine::I18n.t(:greeting, name: "Ada")     # => "Hello, Ada" from %{name}
RGame::Engine::I18n.t(:apples, count: 3)          # pluralized: { one:, other:, zero? }
```

`I18n` symbolizes keys on load, so YAML's string keys and inline Symbol keys look
the same to `t`. `t` resolves a dotted key in the current locale, then in the
fallback. As a last resort, it returns the key itself. Pass `count:` to
pluralize. The key's value is then a `{ one:, other:, optionally zero: }` table,
and `count` is also available to interpolation as `%{count}`. Pluralization uses
the one/other rule of English and German.

**The `generation` counter tells cached UI text when to re-resolve.** It advances
whenever the locale changes. Cached text re-runs `t` only when `generation` moves,
not every frame, so it allocates nothing per frame.

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
