# Components

A **component** is a reusable piece of behaviour attached to a `Node2D`, instead of
baked into a node subclass. A node composes several of them; each knows its owning
`node` and is driven by the node's tick. Components live in `engine/components/` under
`RGame::Engine::Components` and subclass `RGame::Engine::Component`. See [Scene graph](scene_graph.md)
for how nodes drive components, and [Systems & shared resources](systems.md) for
components that act as shared, scene- or program-scoped services.

## The `Component` base

`RGame::Engine::Component` (`rgame/engine/component`) gives every component a `node` back-link and
a set of hooks the node calls — override the ones you need; the rest are no-ops. Like
nodes, it extends the signal DSL, so a component can declare and emit signals.

Per-tick hooks (a node runs its components in each phase, before its own hook and
before its children):

- `control(actions)` — read intent from the per-frame action snapshot.
- `update(dt)` — advance state over the timestep.
- `draw(renderer)` — render against the renderer interface.

Tree-lifecycle hooks (fired by the engine when the node enters/leaves the live tree —
this is where anchors and sibling systems are reachable, so do cross-node wiring here,
not in `initialize`):

- `on_attach` — the node entered the tree; pull and register with shared systems.
- `on_detach` — the node is leaving; release those registrations.

`sweep_freed` exists for container components that hold nodes off the normal child
list; the default is a no-op (see [deferred free](scene_graph.md#deferred-free)).

A node holds **at most one component per slot**. The slot defaults to the component's
class, so by default that's one per class (`add_component` raises on a taken slot) — but
pass `as: :name` to keep several of one type (a spawn timer and a wave timer). Look a
component up with `get_component(key)`, where `key` is a class (matched by ancestry; it
raises if several share the type) or a Symbol name.

## Available components

### `Velocity`

Integrates linear and angular velocity into the node's transform each step.

- **Construct:** `Velocity.new(vx: 0.0, vy: 0.0, spin: 0.0)`.
- **State:** `vx`, `vy`, `spin` are read/write accessors — a controller (or the node's
  own `control` hook) writes them as movement intent.
- **Phase:** `update(dt)` adds `vx*dt`/`vy*dt` to `node.x`/`node.y` and `spin*dt` to
  `node.angle`.

A free-moving entity can use `Velocity` alone; pair it with a controller for input.

### `PathFollow`

Walks the owning node along an [`RGame::Engine::Path`](toolbox.md#path--a-walkable-polyline)
at a constant speed and emits `on_finished` when it reaches the last waypoint — the seam a
tower-defense game uses to leak a life when an enemy reaches the base.

- **Construct:** `PathFollow.new(path:, speed:)`.
- **Lifecycle:** `on_attach` (re)starts the walk — back to the first waypoint with progress
  cleared — so a pooled follower reacquired and re-added begins a fresh walk.
- **Signal:** `on_finished` fires once (no payload) at the end of the path —
  `follow.on_finished { node.queue_free }`.
- **Phase:** `update(dt)` advances `speed * dt`, crossing as many segments as one step
  spans and interpolating the node's position; allocation-free.

### `Timer`

A node-driven interval timer: it rides the node's update tick (so nothing can forget to
advance it) and emits `on_timeout` each time a whole interval elapses — a spawn cadence, a
tower's fire rate, a wave clock. Wraps the pure [`RGame::Engine::Timer`](toolbox.md#timer--paced-periodic-events),
reusing its drift-free carry-forward.

- **Construct:** `Timer.new(interval, repeating: true)` (seconds). Add it named when a node
  needs several: `node.add_component(Timer.new(0.8), as: :spawn)`. `repeating: false` makes
  it a **one-shot** — it fires `on_timeout` exactly once, then goes inert. The one-shot
  replaces a dedicated "lifetime" component: a projectile that should vanish after N seconds
  on a fixed board is `Timer.new(2.0, repeating: false)` + `on_timeout { node.queue_free }`
  (use `DespawnOffscreen` instead when the board scrolls and the entity leaves the screen).
- **Signal:** `on_timeout` fires once per whole interval — `timer.on_timeout { spawn_enemy }`.
- **Lifecycle:** `on_attach` restarts the countdown (and re-arms a spent one-shot), so a
  pooled node reacquired and re-added starts fresh rather than inheriting its previous
  life's elapsed time.
- **Phase:** `update(dt)` advances and emits; a repeating timer emits once per interval
  crossed in a single long step (catch-up, not drift), a one-shot at most once. Allocation-free.
- **Reset:** `reset` drops accumulated time and re-arms a one-shot — a fresh timer.

### `Pool`

Wraps an [`RGame::Engine::Pool`](toolbox.md#pool--reuse-dont-allocate) of nodes and folds the
tree bookkeeping into the frame tick, so a scene that recycles entities (enemies, projectiles)
writes no acquire/add/reclaim bridge of its own — just `spawn` and the ordinary `queue_free`.
Pooled nodes are **normal children** of the owner, so the scene's usual traversal updates and
draws them; this component only manages their pool membership.

- **Construct:** `Pool.new { Enemy.new(...) }` — the factory builds a blank node. Add it named
  (`as:`) when a node needs more than one pool.
- **Spawn:** `pool.spawn` takes a node (recycled or freshly built) and adds it as a child;
  `pool.spawn { |n| n.reset(...) }` runs the block to re-initialise it *before* it enters the
  tree (so `on_attach` sees the reset state — the order projectiles need).
- **Reclaim:** `update(dt)` returns every freed pooled node to the free list, detaching any
  still attached. So despawning is just `node.queue_free` anywhere; the pool recycles it with
  no game-side wiring. Allocation-free in steady state.

### `Clickable`

Makes the owning node a world-space click target: on the click-down edge it hit-tests the
pointer against a circle of `radius` about the node's absolute origin and emits `on_clicked`
(no payload — the node identifies the click, like a button). It reads the pointer from the
Actions snapshot, so it assumes screen == world (a fixed, unscrolled board; a scrolling
camera would need the pointer unprojected first).

- **Construct:** `Clickable.new(radius:, action: :ui_click)`. The action must be bound to the
  pointer button — `action_map: { ui_click: { button: %i[pointer] } }`.
- **Signal:** `on_clicked` fires once per press inside the radius —
  `spot.on_clicked { build_tower }`.
- **Phase:** `control(actions)` hit-tests and emits; allocation-free. Add it named (`as:`)
  when a node needs more than one click region.

### `ScreenWrap`

Wraps the node's position toroidally within a rectangle, so an entity leaving one edge
reappears on the opposite one.

- **Construct:** `ScreenWrap.new(width:, height:, margin: 0.0)` — `margin` lets a
  sprite pass fully off one edge before reappearing on the other.
- **Phase:** `update(dt)` clamps-and-wraps `node.x`/`node.y` against the bounds.

### `DespawnOffscreen`

Removes the node once it has fully left the bounds (plus margin) — for short-lived
entities like projectiles.

- **Construct:** `DespawnOffscreen.new(width:, height:, margin: 0.0)`.
- **Phase:** `update(dt)` calls `node.queue_free` when the node is past every edge.
  Removal is *deferred* (see [deferred free](scene_graph.md#deferred-free)), so it is
  safe to trigger from inside the update traversal. For a *fixed* board (an entity that
  never leaves the screen, e.g. a projectile that should vanish after N seconds), use a
  one-shot [`Timer`](#timer) (`repeating: false`) with `on_timeout { node.queue_free }`
  instead.

### `CircleCollider`

A circular collision shape that participates in a scene's
[`CollisionWorld`](#collisionworld). It registers itself when the node enters the tree
and unregisters when it leaves, so a spawned or despawned entity never leaks a
registration.

- **Construct:** `CircleCollider.new(radius:, layer: :default)`. `layer` is an opaque
  tag the *owner* reads to decide what a contact means; the collision system itself is
  layer-agnostic.
- **Lifecycle:** `on_attach` registers with `node.system(CollisionWorld)`; `on_detach`
  unregisters.
- **Geometry:** `cx`/`cy` are the node's resolved absolute origin; `radius` is a
  read/write accessor (so a pooled entity can retune its shape on reset — see
  `ScreenWrap`/pooling), `layer` is a reader; `overlap?(other)` is the circle-vs-circle
  test.
- **Signal:** `on_hit` fires with the other collider on each contact —
  `collider.on_hit { |other| ... }`. The system triggers it via `emit_hit(other)`.

### `CollisionWorld`

A scene-scoped broadphase collision **system**: a component that lives on the scene
node, holds the registered colliders in a `SpatialHash`, and each step reports every
overlapping pair. Because it is a normal component it rides the `update` traversal and
is torn down with the scene. See [Systems & shared resources](systems.md).

- **Construct:** `CollisionWorld.new(cell_size:)` — the spatial-hash cell size (tune to
  the typical collider size).
- **Registration:** `register(collider)` / `unregister(collider)`; colliders call these
  through their own lifecycle, so nodes never wire this by hand.
- **Phase:** `update(dt)` rebuilds the spatial index and, for each overlapping pair,
  fires both colliders' `on_hit`. It is **layer-agnostic** — it reports contacts and
  lets each collider's owner decide meaning by reading the other's `layer`. Colliders
  whose node is queued for removal are skipped.
- **Range queries (targeting):** the same index answers point-radius lookups against the
  most recent `update`, so a tower can find enemies without a contact:
  - `query_circle(x, y, r) { |collider| }` yields every registered collider whose centre
    is within `r` of `(x, y)` (centre distance — the collider's own radius isn't added,
    so it reads like a range ring); freed-node colliders are skipped, and a collider may
    be yielded more than once (broadphase dedup contract — fine for selecting). Filter by
    `collider.layer` in the block.
  - `nearest(x, y, r, layer: nil)` returns the closest such collider (optionally limited
    to one `layer`), or `nil`. Both are allocation-free, so a targeting component can call
    them every frame.

### `Targeting`

Picks an enemy for the owning node (a tower) to aim at: each `update` it queries the
scene's [`CollisionWorld`](#collisionworld) around the node's world origin and exposes the
chosen target. It only *selects* — it never moves or fires; the owner reads `target` and
acts. Because enemies already register with the broadphase through their
[`CircleCollider`](#circlecollider), targeting keeps no entity list of its own.

- **Construct:** `Targeting.new(range:, policy: :nearest, layer: nil)`. `range` is the
  reach in pixels; `layer` restricts candidates (a tower passes `:enemy`, so it ignores
  other towers/projectiles); an unknown `policy` raises at construction.
- **Policies** (how to choose among the in-range candidates):
  - `:nearest` — the closest enemy (the default; one broadphase nearest-lookup).
- **State:** `target` is the chosen enemy **node** (or `nil` when nothing is in range),
  refreshed every `update` — so a freed/out-of-range target clears on its own. It's a node
  (not a collider) so the owner can read its position and components.
- **Lifecycle:** `on_attach` pulls the scene's `CollisionWorld`.
- **Phase:** `update(dt)` re-selects the target; allocation-free, so it runs every frame.

### `Sprite`

Draws a single registered image centered on the node's absolute origin.

- **Construct:** `Sprite.new(id:, scale: 1.0, z: 0)` — `id` is a renderer image id; `z`
  is the render layer (distinct from the node's transform `z`/`abs_z`).
- **State:** `scale` is a read/write accessor (a pooled entity can retune it).
- **Phase:** `draw(renderer)` draws the image with **no angle** — `Node2D#draw` already
  wraps a node's own draws in `renderer.rotated(abs_angle, …)`, so the node's rotation
  orients the sprite; passing an angle here would rotate it twice.

### `ThrustController`

Inertial "ship" flight on top of a `Velocity` sibling: a turn axis rotates the node and
a thrust axis accelerates it along its heading.

- **Construct:** `ThrustController.new(turn_speed:, accel:, max_speed:, drag: 0.0,
  turn_action: :turn, thrust_action: :thrust)`.
- **Lifecycle:** `on_attach` pulls the node's `Velocity` component.
- **Phase:** `control(actions)` reads intent (turn → `velocity.spin`, thrust stored);
  `update(dt)` accelerates along the heading (angle 0 = up, so forward is
  `(sin θ, −cos θ)`), applies drag, and clamps to `max_speed`. Firing is intentionally
  not here.

### `ActionTrigger`

Maps held input actions to an `on_triggered(action)` signal, rate-limited by a per-action
cooldown. One instance covers several actions (the engine allows one component per class
per node), so it emits the action name and lets listeners filter — reusable for "fire"
here, or "jump"/"fire" in a platformer.

- **Construct:** `ActionTrigger.new(cooldowns)` where `cooldowns` is `{ action => seconds }`,
  e.g. `ActionTrigger.new(fire: 0.22)`.
- **Signal:** `on_triggered` fires with the action name — `trigger.on_triggered { |a| … }`.
- **Phase:** `update(dt)` ticks the per-action cooldowns; `control(actions)` emits when an
  action is held and its cooldown has elapsed (held + cooldown = auto-repeat).

### `AnimatedSprite`

Draws a sprite-sheet animation and picks the animation from a [`CharacterBody`](#characterbody)
sibling's movement: `walk_left`/`walk_right`/`walk_up`/`walk_down` while moving (horizontal wins
on a diagonal), `stand` when still. Owns an `RGame::Engine::Animator` over the pure `AnimationSet` built
from the sheet's animation table.

- **Construct:** `AnimatedSprite.new(sheet:, z: 0)` — `sheet` is the asset's relative path; `z` the
  render layer.
- **Lifecycle:** `on_attach` resolves the sheet from the game's asset manager
  (`node.root.context.assets.sheet(sheet)`), builds its animation set, **sizes the node** to the
  sheet's frame (`node.width`/`height`, so a `CharacterBody` sibling can read them), and pulls that
  sibling (the facing source). The renderer resolves the same path when drawing, so nothing is
  registered or passed in by hand.
- **Phase:** `update(dt)` selects + advances the animation; `draw` renders the current frame via
  `renderer.sprite` at the node's **world** origin (`abs_x`/`abs_y`) with no angle — a
  [`CameraView`](scene_graph.md) ancestor applies the camera offset, so the component never touches
  the camera. (`Sprite` above is the single-image counterpart.)

### `CharacterBody`

Collision-checked walking for a tile-bound actor. A controller writes a per-step movement intent
(each axis −1..1); the body turns it into a real move each `update`, resolved against the scene's
[`TileWorld`](#tileworld) so the actor slides along walls and stays in the map. Unlike `Velocity`
(which integrates blindly), every step here is collision-checked.

- **Construct:** `CharacterBody.new(feet_width:, feet_height:, speed:)` — the feet box size (in px)
  and walk speed (px/s). No sprite size is passed: `collision_box` is built lazily from the node's
  `width`/`height` (which `AnimatedSprite` sets), centred horizontally and bottom-anchored. A body
  with no sprite must set the node's dimensions itself.
- **State:** `set_intent(x, y)` writes the step's intent; `move_x`/`move_y` read it back (the facing
  for `AnimatedSprite`).
- **Lifecycle:** `on_attach` caches the scene's `TileWorld`.
- **Phase:** `update(dt)` moves `intent * speed * dt` through the tile world (nothing when the
  intent is zero).

### `PlayerController`

Drives a `CharacterBody` sibling from two input axes — direct 8-way walking, no inertia (unlike
`ThrustController`).

- **Construct:** `PlayerController.new(x_axis: :move_x, y_axis: :move_y)`.
- **Phase:** `control(actions)` copies the two axes into the body's intent.

### `WanderController`

A simple AI driver for a `CharacterBody`: every so often it rolls a new direction (one of eight, or
idle) and holds it, re-rolling early when a wall blocks it. The RNG is injected, so behaviour is
deterministic in tests.

- **Construct:** `WanderController.new(rng: Random.new, change_interval: 1.0..3.0, idle_chance: 0.25)`.
- **Phase:** `update(dt)` counts down the timer and re-rolls on timeout or when blocked.

### `TileWorld`

The scene-scoped tile **system** (see [Systems](systems.md)): it holds the parsed `RGame::Engine::TileMap`
and answers everything an actor needs from it — collision against the solid tiles (reusing
`RGame::Engine::CollisionSystem`), the world bounds, and drawing the map through the scene's camera. Found
with `node.system(TileWorld)`.

- **Construct:** `TileWorld.new(map:, tilemap_id:, camera:)`.
- **Queries:** `move(actor, dx, dy)` slides an actor (anything responding to `x`/`y`/`collision_box`)
  along solids and clamps it to the world; `solid?(col, row)`; `world_width`/`world_height`.
- **Phase:** `draw(renderer)` draws the below band at `GROUND_Z` and the above band at `OVERLAY_Z`
  (canopies/roofs). Actors draw at a z in between, so the renderer's z-sort composites ground < actors <
  canopy regardless of draw-call order.

```ruby
# A node composing components, with collision meaning decided by the owner:
class Bullet < RGame::Engine::Node2D
  def initialize(x:, y:, vx:, vy:, bounds:)
    super(x: x, y: y)
    add_component(RGame::Engine::Components::Velocity.new(vx: vx, vy: vy))
    add_component(RGame::Engine::Components::DespawnOffscreen.new(**bounds))
    collider = add_component(RGame::Engine::Components::CircleCollider.new(radius: 3, layer: :bullet))
    collider.on_hit { |other| queue_free if other.layer == :rock }
  end
end
```
