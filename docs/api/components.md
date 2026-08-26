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

- `control(actions)` — read intent from the per-frame action snapshot. It is the
  actions of whoever [owns the node](scene_graph.md#who-a-node-answers-to), so a
  component never learns there is more than one player.
- `update(dt)` — advance state over the timestep.
- `draw(renderer, view)` — render against the renderer interface, into the
  [viewport being drawn](scene_graph.md#viewports-and-views). Most components ignore the
  view; it is there for laying out against the region's edges and for culling.

Tree-lifecycle hooks (fired by the engine when the node enters/leaves the live tree —
this is where anchors and sibling systems are reachable, so do cross-node wiring here,
not in `initialize`):

- `on_attach` — the node entered the tree; pull and register with shared systems.
- `on_detach` — the node is leaving; release those registrations.

`sweep_freed` exists for container components that hold nodes off the normal child
list; the default is a no-op (see [deferred free](scene_graph.md#deferred-free)).

`require_sibling(klass)` is the lookup a component's `on_attach` opens with when it
drives a sibling — `@body = require_sibling(CharacterBody)`. It returns the component
or raises naming both, instead of returning the `nil` that stays silent until the first
frame calls a method on it. When it does raise, the cause is nearly always add order —
see [Where to add a component](#where-to-add-a-component) below.

A node holds **at most one component per slot**. The slot defaults to the component's
class, so by default that's one per class (`add_component` raises on a taken slot) — but
pass `as: :name` to keep several of one type (a spawn timer and a wave timer). Look a
component up with `get_component(key)`, where `key` is a class (matched by ancestry; it
raises if several share the type) or a Symbol name.

## Where to add a component

**Assemble a node before it enters the tree.** There are two shapes for that, and which
one you use is decided by whether the node is a class of its own:

- **A `Node2D` subclass — in `initialize`.** This is the default and covers most
  entities.

  ```ruby
  class Bullet < RGame::Engine::Node2D
    def initialize(x:, y:, vx:, vy:)
      super(x: x, y: y)
      add_component(RGame::Engine::Components::Velocity.new(vx: vx, vy: vy))
      add_component(RGame::Engine::Components::DespawnOffscreen.new)
    end
  end
  ```

- **A plain `Node2D` composed from components — in a builder method** that returns the
  assembled node. Reach for this when the node is nothing but its components and a
  subclass would add no behaviour; the walkers in `examples/15_tiled_world` are built
  this way.

  ```ruby
  def build_player
    node = RGame::Engine::Node2D.new(x: spawn_x, y: spawn_y)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: PLAYER_SHEET))
    node.add_component(RGame::Engine::Components::TileCharacterBody.new(
                         feet_width: 10, feet_height: 8, speed: PLAYER_SPEED
                       ))
    node.add_component(RGame::Engine::Components::PlayerController.new)
    node
  end
  ```

**Both work for the same reason, and it is worth knowing.** The node is not in the tree
yet, so `add_component` only appends — no `on_attach` fires until the whole set is
present and the node enters. So **add order is free**: `build_player` above adds an
`AnimatedSprite` *before* the `TileCharacterBody` it pulls, and that is fine.

### Adding from `on_add`, and when you have to

A node running `on_add` is **already in the tree**, so each `add_component` attaches
immediately and can only see the components added before it. The same two lines in the
other order raise (see [`require_sibling`](#the-component-base) above). Prefer
`initialize` or a builder; use `on_add` when the component genuinely cannot be built any
earlier, which means its constructor needs something only the tree can answer:

```ruby
def on_add
  # Both arguments are cross-tree lookups: the asset manager hangs off the root's
  # context, and the player registry is a system. Neither exists at construction.
  add_component(RGame::Engine::Components::TileWorld.new(
                  map: root.context.assets.tilemap(MAP_KEY).map,
                  tilemap_id: MAP_KEY,
                  cameras: root.system(RGame::Engine::Players).map(&:camera)
                ))
end
```

That is the test to apply: **does the constructor need the tree?** A `World` built from
numbers the scene already has, or a `CollisionWorld` built from a constant, does not —
so `examples/14_asteroids` mounts both in `initialize`, where they are guaranteed to
precede every entity the scene later spawns rather than merely happening to. A
`TileWorld` parsed out of the asset manager does, so it waits.

The exception on the other side is a component added **deliberately** after entry,
because it depends on state that only exists once the node is live — a `CameraFollow`
whose offset comes from the sibling body's resolved `collision_box`. That is not
assembly, it is a later decision, and `on_add` is the right place for it.

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

### `World`

The scene-scoped **world system**: how big the world is, and nothing else yet. Mount one
on a scene whose world is a plain rectangle, and the components that need bounds find it
instead of having the numbers threaded through every constructor between the scene and
the entity.

- **Construct:** `World.new(width:, height:)`.
- **Queries:** `world_width` / `world_height`. Immutable — a world that genuinely changes
  size is a new scene.
- **Contract:** it includes `WorldBounds`, and so does [`TileWorld`](#tileworld), which
  answers the same two questions from its map's pixel size. Ask for the contract —
  `node.system(RGame::Engine::Components::WorldBounds)` — and either kind of world
  answers, because `get_component` matches an included module the same way it matches a
  class.

It is deliberately **not** the window size. The two coincide in a single-screen game,
which is what makes the mistake easy to make and hard to see: bind wrapping to the
viewport and the world silently changes shape when the window is resized, or when the
screen is split and each half is its own viewport. Ask
[`Viewports`](scene_graph.md#viewports-and-views) — or the `View` a `draw` is handed —
how big the *window* is; ask this how big the *world* is.

### `ScreenWrap`

Wraps the node's position toroidally within the world bounds, so an entity leaving one
edge reappears on the opposite one.

- **Construct:** `ScreenWrap.new(margin: 0.0)` — `margin` lets a sprite pass fully off one
  edge before reappearing on the other. Bounds come from the scene's world system.
  `ScreenWrap.new(width:, height:, margin:)` overrides them for a node whose wrap region
  is not the whole world.
- **Lifecycle:** `on_attach` resolves the bounds — which is why they can be left out:
  a pooled entity is built long before it is in a tree and has nothing to ask yet. It
  re-resolves on every entry, so a recycled node follows the scene it lands in. Attaching
  with no bounds and no world system in scope **raises**.
- **Phase:** `update(dt)` clamps-and-wraps `node.x`/`node.y` against the bounds.

### `DespawnOffscreen`

Removes the node once it has fully left the world bounds (plus margin) — for short-lived
entities like projectiles.

- **Construct:** `DespawnOffscreen.new(margin: 0.0)`, with the same optional
  `width:`/`height:` override.
- **Lifecycle:** `on_attach` resolves the bounds, exactly as `ScreenWrap` does.
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
  orders this component against the node's *other* drawing (a shadow under a sprite),
  inside the node's own slot. It is not the node's `z`, which orders the node against
  its siblings. See [Drawing](drawing.md#draw-order).
- **State:** `scale` is a read/write accessor (a pooled entity can retune it).
- **Phase:** `draw(renderer, view)` draws the image with **no angle** — `Node2D#draw`
  already wraps a node's own draws in `renderer.rotated(abs_angle, …)`, so the node's
  rotation orients the sprite; passing an angle here would rotate it twice. It skips the
  draw entirely when the view cannot show it, measuring the node's box scaled — a node
  that never set a size is never culled.

### `CameraFollow`

Points a camera at the node it is attached to.

- **Construct:** `CameraFollow.new(camera:, offset_x: 0.0, offset_y: 0.0)` — the offsets
  shift the point being centred on, for a node whose origin is not what should be in the
  middle of the screen (a bottom-anchored sprite usually wants its feet).
- **Phase:** `update(dt)` calls `camera.center_on` with the node's resolved absolute
  origin. The camera trails the node's own movement by one step, uniformly.

The camera belongs to a [player](input.md#players-seats-and-joining), not to this
component or to the scene — a scene may have any number of viewers. Ownership and
behaviour are different questions: the player owns the camera, and this moves it. So
"player two's camera follows player two" is this component with their camera in it.

### `ThrustController`

Inertial "ship" flight on top of a `Velocity` sibling: a turn axis rotates the node and
a thrust axis accelerates it along its heading.

- **Construct:** `ThrustController.new(turn_speed:, accel:, max_speed:, drag: 0.0,
  turn_action: :turn, thrust_action: :thrust)`.
- **Lifecycle:** `on_attach` pulls the node's `Velocity` component (`require_sibling`, so a
  missing one raises rather than surfacing as a nil later).
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
sibling's movement intent: `walk_left`/`walk_right`/`walk_up`/`walk_down` while moving (horizontal wins
on a diagonal), `stand` when still. Owns an `RGame::Engine::Animator` over the pure `AnimationSet` built
from the sheet's animation table.

- **Construct:** `AnimatedSprite.new(sheet:, z: 0)` — `sheet` is the asset's relative path; `z`
  orders this component against the node's other drawing, inside the node's own slot (as
  for [`Sprite`](#sprite)).
- **Lifecycle:** `on_attach` resolves the sheet from the game's asset manager
  (`node.root.context.assets.sheet(sheet)`), builds its animation set, **sizes the node** to the
  sheet's frame (`node.width`/`height`, so a `CharacterBody` sibling can read them), and pulls that
  sibling (the facing source). The renderer resolves the same path when drawing, so nothing is
  registered or passed in by hand.
- **Phase:** `update(dt)` selects + advances the animation; `draw(renderer, view)` renders the
  current frame via `renderer.sprite` at the node's **world** origin (`abs_x`/`abs_y`) with no
  angle — a [`WorldView`](scene_graph.md#view-transforms-and-the-camera) ancestor applies the
  camera offset, so the component never touches the camera. It skips the draw when the view
  cannot show it, measuring the node's box. (`Sprite` above is the single-image counterpart.)

### `CharacterBody`

Direct, per-step walking for an actor. A controller writes a movement intent (each axis −1..1);
the body turns it into a real move each `update`, at a fixed speed with no inertia — unlike
`Velocity`, which integrates a velocity the controller sets, and `ThrustController`, which
accelerates one.

This one moves the node freely, so it needs **no sprite, no dimensions and no system on the
scene**: an actor in a world with nothing to bump into is just `CharacterBody` + a controller.
[`TileCharacterBody`](#tilecharacterbody) below is the collision-checked subclass.

- **Construct:** `CharacterBody.new(speed:)` — walk speed in px/s.
- **State:** `set_intent(x, y)` writes the step's intent; `move_x`/`move_y` read it back (the facing
  for `AnimatedSprite`).
- **Phase:** `update(dt)` applies `intent * speed * dt` (nothing when the intent is zero).
- **Seam:** `apply_move(dx, dy)` is where a step lands — the one method a collision-aware body
  overrides, so it inherits the intent, the speed and the standing-still check rather than
  restating them.

### `TileCharacterBody`

A `CharacterBody` bound to a tile map: each step is resolved against the scene's
[`TileWorld`](#tileworld), so the actor slides along walls and stays inside the map. Everything
about the intent is inherited; what is added is the box a step lands with and the resolution.

- **Construct:** `TileCharacterBody.new(feet_width:, feet_height:, speed:)` — the feet box size (in
  px) and walk speed (px/s). No sprite size is passed: `collision_box` is built lazily from the
  node's `width`/`height` (which `AnimatedSprite` sets), centred horizontally and bottom-anchored.
  A body with no sprite must set the node's dimensions itself.
- **Lifecycle:** `on_attach` caches the scene's `TileWorld`, and **raises** when there is none
  rather than falling back to free movement — an actor walking through walls looks like a collision
  bug, and the cause would be a scene that never mounted the system.
- **Phase:** inherited; the move goes through the tile world instead of straight onto the node.

Siblings that pull `node.get_component(CharacterBody)` — `PlayerController`, `WanderController`,
`AnimatedSprite` — find one of these just as readily: `get_component` matches a class key by
ancestry.

### `PlayerController`

Drives a `CharacterBody` sibling (or a `TileCharacterBody`) from two input axes — direct 8-way
walking, no inertia (unlike `ThrustController`).

- **Construct:** `PlayerController.new(x_axis: :move_x, y_axis: :move_y)`.
- **Lifecycle:** `on_attach` pulls the node's `CharacterBody` (`require_sibling`).
- **Phase:** `control(actions)` copies the two axes into the body's intent.

### `WanderController`

A simple AI driver for a `CharacterBody`: every so often it rolls a new direction (one of eight, or
idle) and holds it, re-rolling early when a wall blocks it. The RNG is injected, so behaviour is
deterministic in tests.

- **Construct:** `WanderController.new(rng: Random.new, change_interval: 1.0..3.0, idle_chance: 0.25)`.
- **Lifecycle:** `on_attach` pulls the node's `CharacterBody` (`require_sibling`).
- **Phase:** `update(dt)` counts down the timer and re-rolls on timeout or when blocked.
  "Blocked" is *the node did not move while intending to* — measured, not asked of a
  collision world — so it works over a plain `CharacterBody` too, and simply never fires
  for one whose steps always land.

### `TileWorld`

The scene-scoped tile **system** (see [Systems](systems.md)): it holds the parsed `RGame::Engine::TileMap`
and answers everything an actor needs from it — collision against the solid tiles (reusing
`RGame::Engine::CollisionSystem`) and the world bounds. Found with `node.system(TileWorld)`.
It includes `WorldBounds` (see [`World`](#world)), so `ScreenWrap` and `DespawnOffscreen`
work in a tile scene with nothing passed to them.

**It does not draw.** `RGame::Engine::TileMapLayer` does — one node per Tiled layer, mounted
inside a `WorldView`, so the map is drawn once per viewport like the rest of world space.
This stays the thing actors ask questions of.

- **Construct:** `TileWorld.new(map:, tilemap_id:, cameras: [])` — it clamps each camera it is given to
  the map's edges, and `bound(camera)` does the same for one that arrives later (a player joining).
- **Queries:** `move(actor, dx, dy)` slides an actor (anything responding to `x`/`y`/`collision_box`)
  along solids and clamps it to the world; `solid?(col, row)`; `world_width`/`world_height`;
  `tilemap_id` and `elapsed`, which the layers read; `layer_count` and `first_above_layer`,
  which `TileMapLayer.mount` reads to decide where the actors go.
- **Phase:** `update(dt)` advances the map's animation clock.

```ruby
world  = scene.add_node(RGame::Engine::WorldView.new)
actors = RGame::Engine::TileMapLayer.mount(world)   # a node per Tiled layer
actors.add_node(player)                             # in the gap between them
```

`mount` returns the node the actors go in. It sits below the first layer Tiled flags
`above` — trunks under the walker, canopies over — and `mount(world, under: index)`
overrides that for a map with a different arrangement. Nothing here picks a `z`.

```ruby
# Collision meaning is decided by the owner, not the collider: the component reports a
# contact and this node says what a contact with a rock means. See
# [Where to add a component](#where-to-add-a-component) for why this is `initialize`.
class Bullet < RGame::Engine::Node2D
  def initialize(x:, y:, vx:, vy:)
    super(x: x, y: y)
    add_component(RGame::Engine::Components::Velocity.new(vx: vx, vy: vy))
    # No bounds: DespawnOffscreen asks the scene's World system once it is in the tree.
    add_component(RGame::Engine::Components::DespawnOffscreen.new)
    collider = add_component(RGame::Engine::Components::CircleCollider.new(radius: 3, layer: :bullet))
    collider.on_hit { |other| queue_free if other.layer == :rock }
  end
end
```
