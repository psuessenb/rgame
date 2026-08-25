# Utilities

Engine classes a **game author reaches for directly** that don't belong to the scene
graph, components, signals, or systems chapters — pooling, localization, audio facts,
flat grids, the camera, collision boxes. All are pure Ruby (none `require "gosu"`), so
they stay headless-testable.

For the low-level classes that sit *behind* components and are rarely constructed by
hand (collision maths, the spatial index, animation playback), see
[Internal building blocks](internals.md).

## `Matrix` — a flat fixed-size grid

`RGame::Engine::Matrix` is a fixed-size grid addressed as `[x, y]` but backed by a
**single flat (row-major) array**, not an array-of-arrays. One contiguous
allocation is cheaper than nested arrays, and it is the shape a C-level buffer
takes — which is not hypothetical: its 3-D sibling made exactly that move.

```ruby
grid = RGame::Engine::Matrix.new(width, height, initial: 0)
grid[col, row] = gid
grid[col, row]                      # row-major: index = y * width + x
```

It does no bounds checking on the hot path (callers stay in range).

For three dimensions, reach for [`RGame::Util::Tensor`](values.md#rgameutiltensor) — the C
one. `TileMap` stacks its tile layers in a single
`Tensor(width, height, layer_count)`, and that is the worked example of the rule
that the engine layer may hold `RGame::Util` values: a grid is a value, so the
layer above owns one outright rather than being handed it.

## `CachedLabel` — a display string rebuilt only on change

`RGame::Engine::CachedLabel` (`rgame/engine/cached_label`) holds a label string and rebuilds it only when its
source value changes, so a per-frame draw shows the cached copy without interpolating (and
allocating) a `String` every frame. Construct it — and its format block — outside the per-frame
path (e.g. in `on_add`), then read it by value in `on_draw`:

```ruby
@score_label = RGame::Engine::CachedLabel.new { |score| "Score: #{score}" }  # built once

def on_draw(renderer, _view)
  renderer.text(@score_label[@score], 12, 10)   # cached; rebuilds only when @score changes
end
```

`@score_label[value]` returns the same `String` object while `value` is unchanged. This is the
sanctioned home for build-on-change interpolation, so the per-frame allocation cops
(`rubocop/cop/game/`) exempt it. For a value that changes *every* frame (an FPS or allocation counter) a cached string can't
help — draw the digits individually from cached glyph strings instead, as `RGame::Engine::DebugOverlay` does.

## `Pool` — reuse, don't allocate

`RGame::Engine::Pool` (`rgame/engine/pool`) recycles many short-lived, homogeneous objects —
bullets, particles, transient enemies — so steady-state spawning allocates nothing.
Acquired objects come from a free list, falling back to a factory block only when the
list is empty.

```ruby
pool = RGame::Engine::Pool.new { Bullet.new }   # factory builds a blank object
b = pool.acquire                         # recycled, or freshly built once
b.reset(x, y, angle)                     # caller re-initialises after acquire
pool.each { |bullet| bullet.update(dt) }
pool.reclaim_if(&:dead?)                 # sweep dead → free list, once per frame
```

The factory builds a *blank* object; the caller re-initialises it after `acquire`
(typically via a `reset` from an [`RGame::Engine::Resettable`](#resettable--mutable-only-where-a-pool-needs-it)
value object). `reclaim_if` is the deferred-removal seam: it sweeps the active list
once, moving every object the block marks dead onto the free list. Call it *after*
iterating with `each` — never mutate the active list mid-iteration. `active`, `size`,
and `each` expose the live set for update/draw traversal.

## `Path` — a walkable polyline

`RGame::Engine::Path` (`rgame/engine/path`) is an ordered polyline of waypoints an entity walks along —
the "road" of a tower-defense level. Pure data: it holds the waypoints and the precomputed
per-segment lengths, so a follower walking it at runtime allocates nothing. Waypoints are
stored flat (`x0, y0, x1, y1, …`) in one contiguous array and read back through scalar
accessors, so neither construction nor traversal leaks a pair-object per waypoint.

```ruby
path = RGame::Engine::Path.new([[0, 0], [100, 0], [100, 100]]) # ≥ 2 waypoints, in walk order
path.count             # number of waypoints
path.x_at(i)           # scalar coords of waypoint i (no allocation)
path.y_at(i)
path.segment_length(i) # length of the segment from waypoint i to i+1
path.length            # total length
path.distance_to(x, y) # shortest distance from a point to the polyline
```

A follower ([`Components::PathFollow`](components.md#pathfollow)) reads segments by index
and interpolates itself; Path never returns a coordinate pair. `distance_to` answers "how
far is this point from the road" (allocation-free scalar maths) — e.g. to mask the
tower-placement cells that sit on or hug the road.

## `Timer` — paced periodic events

`RGame::Engine::Timer` (`rgame/engine/timer`) is a repeating interval timer for periodic events that
aren't driven by input — a spawner emitting an enemy every N seconds, a tower's fire
rate, a wave clock. It only **accumulates** time; the owner decides what each elapsed
interval means. That split is deliberate: the same primitive serves both "act
automatically" (consume every ready interval) and "stay loaded until conditions allow"
(check `ready?`, but `consume` only when actually acting) — so a tower with no target
keeps its shot ready instead of wasting it. Pure and allocation-free, so it ticks on the
per-frame path.

```ruby
@spawn_timer = RGame::Engine::Timer.new(0.8)   # built once, off the hot path

def on_update(dt)
  @spawn_timer.update(dt)
  return unless @spawn_timer.ready?      # a whole interval has accumulated

  @spawn_timer.consume                   # deduct it; the remainder carries forward
  spawn_enemy
end
```

`consume` carries the overshoot forward (rather than zeroing), so a long-running cadence
doesn't drift; `reset` drops accumulated time after retuning `interval`. When a step might
span several intervals, loop: `while timer.ready? do …; timer.consume end`.

For a node that should tick automatically, reach for
[`Components::Timer`](components.md#timer) instead — it owns one of these, rides the node's
update tick (so nothing can forget to drive it), and emits `on_timeout` rather than making
you poll `ready?`/`consume`.

## `Camera` — follow a point, clamp to the world

`RGame::Engine::Camera` (`rgame/engine/camera`) is the pure follow-and-clamp maths for a
scrolling view. It splits into two calls, and the split is the whole design:

```ruby
camera = RGame::Engine::Camera.new(world_width: map.pixel_width, world_height: map.pixel_height)
camera.center_on(player_x, player_y)   # in update: what to look at
camera.resolve(view_width, view_height) # at draw: the offset for *this* viewport
camera.x, camera.y                      # the resolved offset
```

`center_on` records the target; `resolve` works out the offset, clamped so the view never
shows past the world's edges (near a corner the target drifts off-centre instead).
**The viewport size is an argument rather than state** because the same camera is drawn
through viewports of different sizes — a half-width one clamps differently from a
full-width one, and the difference is visible near a world edge.

**A camera belongs to a player** ([`RGame::Engine::Player#camera`](input.md#players-seats-and-joining)),
not to a scene: a scene may have any number of viewers. Nothing calls `resolve` by hand —
the platform resolves each camera against the viewport it is about to draw. Pointing one
is a [`CameraFollow`](components.md#camerafollow) component on the node being followed,
and applying it is a [`WorldView`](scene_graph.md#view-transforms-and-the-camera). See
`examples/15_tiled_world`.

## `CollisionBox` — an actor's feet box

`RGame::Engine::CollisionBox` (`rgame/engine/collision_box`) is a character's collision rectangle,
expressed as an offset + size **relative to the sprite's top-left origin** — decoupled
from the sprite size, so a 32×32 sprite can carry a small box at its feet. A
[`CharacterBody`](components.md#characterbody) holds one and the collision code resolves
*it* (not the sprite) against the tiles.

```ruby
box = RGame::Engine::CollisionBox.bottom_anchored(
  sprite_width: 32, sprite_height: 32, width: 16, height: 16
) # centred horizontally, anchored to the sprite's feet
box.aabb(x, y) # => [x + offset_x, y + offset_y, width, height]
```

`bottom_anchored` is the common case (feet box); the raw constructor takes explicit
`offset_x:`/`offset_y:`/`width:`/`height:` for anything else.

## `RGame::Engine::I18n` — localization

`RGame::Engine::I18n` (`engine/i18n`) is minimal localization: per-locale translation tables
(loaded from YAML or an inline Hash), `t(key)` lookup with `%{var}` interpolation and a
fallback locale, and pluralization. It is a **global module** (like the signal
dispatcher), so `t` is reachable anywhere without wiring. YAML is its only dependency.

```ruby
RGame::Engine::I18n.load_file(:en, "locales/en.yml")
RGame::Engine::I18n.load(:de, menu: { title: "Hauptmenü" })   # nested Hashes allowed
RGame::Engine::I18n.default = :en        # fallback when the current locale lacks a key
RGame::Engine::I18n.locale = :de

RGame::Engine::I18n.t("menu.title")               # dotted key, resolved in :de then :en
RGame::Engine::I18n.t(:greeting, name: "Ada")     # => "Hello, Ada" from %{name}
RGame::Engine::I18n.t(:apples, count: 3)          # pluralized: { one:, other:, zero? }
```

Keys are symbolized on load, so YAML's string keys and inline symbol keys look the same
to `t`. `t` resolves a dotted key in the current locale, then the fallback, then returns
the key itself as a last resort. Pass `count:` to pluralize — the key's value is then a
`{ one:, other:, optionally zero: }` table, and `count` is also exposed to interpolation
as `%{count}` (English/German use the one/other rule).

The **`generation` counter** is the headless-friendly change seam: it ticks whenever the
locale changes, so cached UI text can re-resolve only when `generation` moves rather than
re-running `t` every frame — keeping with the engine's no-per-frame-allocation rule.

## `AudioBus` — decoupled audio facts

`RGame::Engine::AudioBus` (`rgame/engine/audio_bus`) is a global, always-present audio bus: gameplay
emits audio *facts* (`play this sound`, `play this music`) here, decoupled from playback,
and an `AudioDirector` subscribes and turns them into actual
sound. A module rather than an instance so any node can reach it without wiring.

```ruby
RGame::Engine::AudioBus.play_sound(:boom)
RGame::Engine::AudioBus.play_music(:theme)
RGame::Engine::AudioBus.stop_music
```

The emit shims (`play_sound`, `play_music`, `stop_music`) are the gameplay-facing API;
underneath each is an [`RGame::Engine::Signal`](signals.md) (`on_play_sound`, `on_play_music`,
`on_stop_music`) that is the actual subscription seam the director listens on. Because
the engine only emits facts and never names an audio device, the bus stays in the engine
layer and playback stays in `RGame::Core`.

## `Resettable` — mutable only where a pool needs it

`RGame::Engine::Resettable` (`rgame/engine/resettable`) builds value-object classes for pooling. Like
`Data.define`, instances expose read-only accessors and carry their fields as a unit —
but where a `Data` value is fully immutable (every change is a fresh allocation), these
add exactly one mutation: `reset`, which overwrites all fields at once and returns self.

```ruby
Point = RGame::Engine::Resettable.define(:x, :y)
p = Point.new(3, 4)
p.x            # => 3 (read-only; no x= setter)
p.reset(5, 6)  # overwrite in place, allocation-free → self

Vel = RGame::Engine::Resettable.define(:dx, :dy, keyword_init: true)
Vel.new(dx: 1, dy: 0).reset(dx: 2, dy: 0)
```

That single in-place `reset` is the only mutability a [`Pool`](#pool--reuse-dont-allocate)
needs: acquire a recycled instance and `reset` it, without exposing the per-field setters
a `Struct` would. Methods are generated fixed-arity with direct ivar assignment (as
Struct/Data do), so `reset` is allocation-free and recycling stays zero-allocation in
steady state — including the `keyword_init: true` form, which generates named parameters
(`reset(x:, y:)`) rather than a `**kwargs` splat (the one form that would build a Hash per
call). Reach for this over a mutable `Struct` whenever a value object is pool-recycled; see
the Style notes in `CLAUDE.md`.
