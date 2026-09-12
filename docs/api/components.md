# Components

A **component** is a reusable piece of behaviour attached to a `Node2D`, instead of
baked into a node subclass. A node composes several of them; each knows its owning
`node` and is driven by the node's tick. Components live in `engine/components/` under
`RGame::Engine::Components` and subclass `RGame::Engine::Component`. See [Scene graph](scene_graph.md)
for how nodes drive components, and [Systems & shared resources](systems.md) for
components that act as shared, scene- or program-scoped services.

`examples/walk` is the smallest working composition of the three that make a
character — `AnimatedSprite` + `CharacterBody` + `PlayerController` — in one file.

## When what you want is not a component

A component is **behaviour on the node's tick**: it overrides `control`, `update`
or `draw`, and the node drives it. A good deal of what a game reaches for is not
that, and scanning this list for it is how a worse answer gets invented —
`examples/sound` once drew a row of rectangles to show a count, because nothing
here formats a number.

Those helpers are in [Utilities](toolbox.md) and a game constructs them directly,
attached to nothing. That is an ordinary thing to do, not a shortcut:
`examples/sound` emits on `AudioBus` and reads a `CachedLabel` within ten lines
of each other.

| Looking for | Reach for | |
|---|---|---|
| a label from a value that changes, with no `String` per frame | `CachedLabel` | [→](toolbox.md#cachedlabel--a-display-string-rebuilt-only-on-change) |
| to say *what happened* without naming a sound device | `AudioBus` | [→](toolbox.md#audiobus--decoupled-audio-facts) |
| a point to follow, clamped to the world | `Camera` | [→](toolbox.md#camera--follow-a-point-clamp-to-the-world) |
| text in the player's language | `I18n` | [→](toolbox.md#rgameenginei18n--localization) |
| an ordered route to walk | `Path` | [→](toolbox.md#path--a-walkable-polyline) |

**What earns a component is per-frame work.** Two of those utilities have
component wrappers, and both exist for that one reason: a timer has to be
advanced every tick, and a pool has to reclaim freed nodes every tick, so
`Components::Timer` and `Components::Pool` fold that drive into the traversal
where nothing can forget it. Where there is no per-frame work there is no
wrapper — a `CachedLabel` is read when something draws it, and a component that
overrode none of the hooks would be a component in name only, with the
one-per-slot rule making a second label on the same node harder rather than
easier.

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
  subclass would add no behaviour; the walkers in `examples/save_load` are built
  this way.

  ```ruby
  def build_player
    node = RGame::Engine::Node2D.new(x: spawn_x, y: spawn_y)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: PLAYER_SHEET))
    node.add_component(RGame::Engine::Components::FeetCollider.new(width: 10, height: 8))
    node.add_component(RGame::Engine::Components::CharacterBody.new(
                         speed: PLAYER_SPEED, blocked_by: [:tiles]
                       ))
    node.add_component(RGame::Engine::Components::PlayerController.new)
    node
  end
  ```

**Both work for the same reason, and it is worth knowing.** The node is not in the tree
yet, so `add_component` only appends — no `on_attach` fires until the whole set is
present and the node enters. So **add order is free**: `build_player` above adds an
`AnimatedSprite` *before* the `CharacterBody` that pulls it, and that is fine.

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
so `examples/collision` mounts both in `initialize`, where they are guaranteed to
precede every entity the scene later spawns rather than merely happening to. A
`TileWorld` parsed out of the asset manager does, so it waits.

The exception on the other side is a component added **deliberately** after entry,
because it depends on state that only exists once the node is live — a `CameraFollow`
whose offset comes from the sibling body's resolved `collision_box`. That is not
assembly, it is a later decision, and `on_add` is the right place for it.

## Available components

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
  current frame via `renderer.sprite` at **`0, 0`** with no angle — the traversal has already
  put the renderer on the node, and a [`WorldView`](scene_graph.md#view-transforms-and-the-camera)
  ancestor has already applied the camera, so the component passes neither a position nor an
  angle. It skips the draw when the view cannot show it, measuring the node's box against
  `node.world_x`/`world_y` — culling is the one thing here still stated in world coordinates,
  because it compares against the camera. (`Sprite` above is the single-image counterpart.)

### `BoxCollider`

A rectangular collision shape that participates in a scene's
[`CollisionWorld`](#collisionworld) — the sibling of [`CircleCollider`](#circlecollider),
for entities that are honestly box-shaped (a crate, a platform, a wall segment). It
registers itself when the node enters the tree and unregisters when it leaves, so a
spawned or despawned entity never leaks a registration.

- **Construct:** `BoxCollider.new(width:, height:, offset_x: 0, offset_y: 0, layer: :default)`.
  The offsets are relative to the node's origin, so a 32×32 sprite can carry a small box at
  its feet. `layer` is an opaque tag the *owner* reads to decide what a contact means; the
  collision system itself is layer-agnostic.
- **Lifecycle:** `on_attach` registers with `node.system(CollisionWorld)`; `on_detach`
  unregisters. A scene with **no** world mounted leaves it a bare shape rather than
  raising — a collider is a shape, and a world is what turns shapes into contacts, which
  is what lets a tile-only game carry a feet box for
  [`CharacterBody(blocked_by:)`](#characterbody) alone, or any other [`Mover`](#mover). The price: an `on_hit` handler in
  such a scene never fires and nothing says so.
- **Geometry:** the rectangle is an [`RGame::Engine::CollisionBox`](toolbox.md#collisionbox--an-actors-feet-box),
  reachable as the read/write `box` accessor — assign a new one (including
  `CollisionBox.bottom_anchored(...)`) to retune a pooled entity's shape on reset, no
  re-registration needed. `aabb_x`/`aabb_y`/`aabb_w`/`aabb_h` are the world-space box;
  `cx`/`cy` are the **box's** centre (not the node origin, which is where a circle's
  centre is), which is what the world's range queries measure from.
- **Rotation:** the box stays axis-aligned in world space — it does not turn with the
  node. A spinning entity wants a `CircleCollider`, which is rotation-invariant, rather
  than a per-frame box recompute.
- **Contacts:** `overlap?(other)` works against a box *or* a circle: the two colliders
  settle the test between themselves, so both shapes mix freely in one world.
- **Blocking:** a box on a layer some [`Mover`](#mover) named in
  `blocked_by:` also *stops* that mover's steps, flush against this box's edge. Nothing has
  to be done to opt in; the layer is the whole declaration, and it is the other body's.
- **Signals:** `on_hit` fires with the other collider on the step a contact **starts**,
  `on_separated` on the step it **ends** — `collider.on_hit { |other| ... }`. The system
  triggers them via `emit_hit(other)` / `emit_separated(other)`. Each fires once per
  pair, so a handler may count, play a sound or spend a life — see
  [`CollisionWorld`](#collisionworld).

```ruby
collider = add_component(RGame::Engine::Components::BoxCollider.new(
  width: 32, height: 32, layer: :pickup
))
collider.on_hit { |other| collect if other.layer == :player }
```

### `CameraFollow`

Points a camera at the node it is attached to.

- **Construct:** `CameraFollow.new(camera:, offset_x: 0.0, offset_y: 0.0)` — the offsets
  shift the point being centred on, for a node whose origin is not what should be in the
  middle of the screen (a bottom-anchored sprite usually wants its feet).
- **Phase:** `update(dt)` calls `camera.center_on` with the node's world
  origin. The camera trails the node's own movement by one step, uniformly.
- **Example:** `examples/scroll_map` — the node it follows is an invisible rig
  with a `CharacterBody` and a `PlayerController`, which is all "scroll the map
  with the arrow keys" turns out to be.

The camera belongs to a [player](input.md#players-seats-and-joining), not to this
component or to the scene — a scene may have any number of viewers. Ownership and
behaviour are different questions: the player owns the camera, and this moves it. So
"player two's camera follows player two" is this component with their camera in it.

### `CharacterBody`

Direct, per-step walking for an actor. A controller writes a movement intent (each axis −1..1);
the body turns it into a real move each `update`, at a fixed speed with no inertia — unlike
`Velocity`, which integrates a velocity the controller sets, and `ThrustController`, which
accelerates one.

A character is `CharacterBody` + a controller, and a character the map stops is the same
with a feet box and a declaration. **What may stop a step is [`Mover`](#mover)'s**, shared
with `Velocity` and `PathFollow`. `blocked_by:`, `on_blocked`/`on_unblocked` and the
`apply_move` seam are documented there, and work the same way here.

```ruby
add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
add_component(RGame::Engine::Components::CharacterBody.new(speed: 80, blocked_by: [:tiles]))
add_component(RGame::Engine::Components::PlayerController.new)
```

- **Construct:** `CharacterBody.new(speed:, blocked_by: [])` — walk speed in px/s, and what
  may stop a step (see [`Mover`](#mover)).
- **State:** `set_intent(x, y)` writes the step's intent; `move_x`/`move_y` read it back (the facing
  for `AnimatedSprite`).
- **Phase:** `update(dt)` applies `intent * speed * dt` through `apply_move`, and moves nothing
  when the intent is zero. That is still a step, so a body that stops pushing into a wall
  reports `on_unblocked`.
- **Seam:** a body that resolves a step some other way (a platformer's, with gravity and a jump)
  overrides [`apply_move`](#mover) and inherits the intent, the speed and the standing-still
  check rather than restating them.
- **Examples:** `examples/walk` — this, a `PlayerController` and an `AnimatedSprite`, and
  nothing else. `examples/collision_tiles` — the same with a feet box and `blocked_by:
  [:tiles]`, drawn over the sprite so what collides is visible.
  A crowd is the same thing with more names: walkers that each declare
  `%i[tiles hero npc]` are stopped by the map and by one another.

### `CircleCollider`

A circular collision shape that participates in a scene's
[`CollisionWorld`](#collisionworld). It registers itself when the node enters the tree
and unregisters when it leaves, so a spawned or despawned entity never leaks a
registration.

- **Construct:** `CircleCollider.new(radius:, layer: :default)`. `layer` is an opaque
  tag the *owner* reads to decide what a contact means; the collision system itself is
  layer-agnostic.
- **Lifecycle:** `on_attach` registers with `node.system(CollisionWorld)`; `on_detach`
  unregisters. As with [`BoxCollider`](#boxcollider), a scene with no world mounted
  leaves it a bare shape rather than raising.
- **Geometry:** `cx`/`cy` are the node's world origin (`node.world_x`/`world_y`); `radius` is a
  read/write accessor (so a pooled entity can retune its shape on reset — see
  `ScreenWrap`/pooling), `layer` is a reader; `aabb_x`/`aabb_y`/`aabb_w`/`aabb_h` are the
  bounding box the world buckets on.
- **Contacts:** `overlap?(other)` works against a circle *or* a
  [`BoxCollider`](#boxcollider): the two colliders settle the test between themselves, so
  both shapes mix freely in one world.
- **It never blocks.** Blocking is box versus box, so a circle on a layer a
  [`Mover`](#mover) named in `blocked_by:` reports its contacts exactly as
  it does now and stops nobody. Nor can a circle *be* stopped: a mover that declares
  anything needs a `BoxCollider` of its own, and raises at attach without one. That is a limit, not a check: layer membership is a runtime
  fact, so a raise at attach would catch only the circles that already existed.
- **Signals:** `on_hit` fires with the other collider on the step a contact **starts**,
  `on_separated` on the step it **ends** — `collider.on_hit { |other| ... }`. The system
  triggers them via `emit_hit(other)` / `emit_separated(other)`. Each fires once per
  pair — see [`CollisionWorld`](#collisionworld).

### `CollisionWorld`

A scene-scoped broadphase collision **system**: a component that lives on the scene
node, holds the registered colliders in a `SpatialHash`, and each step reports where
overlapping pairs begin and end. Because it is a normal component it rides the `update`
traversal and is torn down with the scene. See
[Systems & shared resources](systems.md).

It is **shape-agnostic**: it buckets each collider by the bounding box it reports
(`aabb_x`/`aabb_y`/`aabb_w`/`aabb_h`) and leaves the exact test to the pair's own
`overlap?`. So [`CircleCollider`](#circlecollider) and [`BoxCollider`](#boxcollider)
share one world and collide with each other, and a game can add a shape of its own by
answering the same handful of methods.

- **Construct:** `CollisionWorld.new(cell_size:)` — the spatial-hash cell size, which
  tracks **how big the colliders are** and nothing else. A tile map in the same scene is
  no guide, however tempting: a 64px collider in a 16px grid is bucketed into twenty-five
  cells and queried out of all of them, measured at 2.8× the cost of a cell sized to the
  collider, where a 12×6 feet box in the same 16px cells costs only 10–20% over its own
  optimum. The symptom of a wrong value is frame budget and never behaviour, which is
  what makes it worth picking deliberately.
- **Registration:** `register(collider)` / `unregister(collider)`; colliders call these
  through their own lifecycle, so nodes never wire this by hand.
- **Queries:** `query_box(x, y, w, h)` yields every registered collider bucketed in a cell
  the region covers, skipping nodes queued for removal — the rectangular counterpart to
  `query_circle`, and what a blocked [`Mover`](#mover) asks each step.
  `nearest(x, y, r, layer:)` and `cell_empty?(x, y)` are the other two. All of them read
  the index the most recent `update` built and allocate nothing.
- **Staying fresh mid-step:** `reindex(collider, from_x, from_y, from_w, from_h)`
  re-buckets a collider that has moved since the index was built, given the box it *was*
  bucketed at. Buckets are filled once per step, so a query over cells a mover has left
  would otherwise miss it — measured at 116 misses in 60,000 queries with two hundred
  actors, and none once each mover re-buckets itself. A [`Mover`](#mover) that declares a
  collider layer does this through its resolver; anything else that moves a collider
  mid-step (a mover that declared nothing, or an ancestor) may call it directly.
- **Phase:** `update(dt)` rebuilds the spatial index, fires both colliders' `on_hit`
  for each pair that has *started* overlapping, and then both colliders' `on_separated`
  for each pair that has *stopped*. It is **layer-agnostic** — it reports contacts and
  lets each collider's owner decide meaning by reading the other's `layer`. Colliders
  whose node is queued for removal are skipped.
- **Contacts are a step behind.** This is a component on the scene node, and a node runs
  its own components before its children, so the index is built and every pair reported
  *before* any actor has moved this step. Contacts therefore describe where things were
  at the end of the previous step — consistently, so nothing jitters, but a pair that
  starts overlapping during step N is reported at the top of step N+1. A blocked
  [`Mover`](#mover) does not read the index this way and is not affected;
  it queries mid-step and re-buckets itself, which is what `reindex` above is for.
- **A contact is two edges, not a state.** Each signal fires **once per pair**: nothing
  at all on the steps between the two, however long the overlap lasts, and one report
  however many broadphase cells the pair happens to span. So a handler may do what must
  happen exactly once — `score += 100`, play a sound, spend a life — with nothing to
  remember and nothing to guard. `examples/collision`'s crate counts arrivals in one
  line because of it.

  The world keeps an [`Engine::ContactSet`](internals.md#contactset--the-two-edges-of-a-contact)
  per collider to do this, which is also what absorbs the
  [`SpatialHash`](internals.md#spatialhash--uniform-grid-broadphase) may-yield-twice
  contract: a pair spanning three cells is offered three times and recorded once.
- **`on_separated` also fires when the other side goes.** A contact ends when the
  partner is destroyed (`queue_free`) or leaves the tree, not only when the two move
  apart, and the survivor is told on its next step. Without that a ship could stay "in
  contact" with a rock that no longer exists. The collider on its way out is told
  nothing; it is leaving.

  That last part is the one thing to remember when pooling. The world clears a
  collider's own contacts when it registers, so a recycled entity never reports a
  separation from its previous life — but state a *node* derived from those contacts
  (a "how many things am I touching" count) never unwinds, because the edge that would
  have unwound it was never delivered. Zero it in the node's `reset`, with the rest.
- **Example:** `examples/collision` — this system on the scene, circles and boxes on
  the nodes, two layers and the one line that ignores same-layer pairs. A circle stays
  lit while it is inside a crate (`on_hit` up, `on_separated` down) and the crate blinks
  once and counts it. The broadphase grid is drawn on the backdrop, so `cell_size` is a
  thing you can look at.
- **Range queries (targeting):** the same index answers point-radius lookups against the
  most recent `update`, so a turret can find enemies without a contact:
  - `query_circle(x, y, r) { |collider| }` yields every registered collider whose centre
    is within `r` of `(x, y)` (centre distance — the collider's own size isn't added,
    so it reads like a range ring); freed-node colliders are skipped, and a collider may
    be yielded more than once (broadphase dedup contract — fine for selecting). Filter by
    `collider.layer` in the block.
  - `nearest(x, y, r, layer: nil)` returns the closest such collider (optionally limited
    to one `layer`), or `nil`. Both are allocation-free, so a targeting component can call
    them every frame.
- **Cell occupancy (grid games):** `cell_empty?(x, y)` answers whether the cell containing
  the **world** point `(x, y)` is free — "may a pickup spawn on this square?". A point,
  not a region: pass any coordinate inside the square you mean, and set `cell_size` to the
  game's own square so the two grids line up. The cells are the hash's own lattice,
  anchored at the world origin, so a board also wants its own origin on a multiple of
  `cell_size` — off that lattice each square straddles two cells and both read occupied.
  Like the queries above it reads the index the last `update` built and allocates nothing,
  including on a miss — the case a board scan asks about most.

  A collider whose node is queued for removal doesn't count as occupying a cell, so a
  corpse can't reserve a square. Everything else is
  [`SpatialHash#cell_empty?`](internals.md#spatialhash--uniform-grid-broadphase)
  underneath: its cell walk is half-open on the far edge, so a piece filling one square
  leaves the squares it borders free.

  It takes *world* coordinates, because that is what a collider reports. A node whose own
  grid starts elsewhere adds its origin first:

  ```ruby
  # in a Grid node whose cells are cell_size across
  def free?(col, row)
    collisions = system(RGame::Engine::Components::CollisionWorld)
    collisions.cell_empty?(world_x + (col * cell_size), world_y + (row * cell_size))
  end
  ```

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
- **It contradicts `blocked_by: [:bounds]`**, for the same reason `ScreenWrap` does: this
  reads `node.x`/`node.y` and blocking works on the collision box, so a hero with a feet
  box held at the world's left edge sits at a slightly negative `node.x` and deletes
  itself. Do not declare both on one node.

### `FeetCollider`

A [`BoxCollider`](#boxcollider) whose rectangle is the node's **feet**: horizontally
centred in the node's dimensions and anchored to their bottom. That is the shape a
top-down character should collide with — a 16×22 hero occupies the 12×6 patch under
them, not the whole sprite, which is what stops their head bumping into a wall a tile
away. It is a `BoxCollider` in every other respect: same registration, same signals,
same mixing with circles, and `get_component(BoxCollider)` finds it.

- **Construct:** `FeetCollider.new(width:, height:, layer: :default)` — the feet box
  size in px. No sprite size and no offsets: those come from `node.width`/`node.height`,
  which [`AnimatedSprite`](#animatedsprite) sets from the sprite frame, so the box and
  the sprite can never disagree. A node with no sprite must set its own dimensions.
- **Geometry:** `box` is built on **first read** and memoised, not built at
  construction — a node has no size until its sprite attaches, so the order components
  were added in never matters. Reading it from a 0×0 node **raises**, naming the size,
  rather than baking a box anchored to nothing and leaving an actor that walks through
  walls a long way from the call that caused it. Assigning `box =` still wins, which is
  how a pooled entity retunes its shape on reset.
- **Everything else:** as [`BoxCollider`](#boxcollider) — `aabb_*`, `cx`/`cy`,
  `overlap?`, `on_hit` / `on_separated`, and registration with the scene's
  [`CollisionWorld`](#collisionworld) when there is one.

It is also the shape a blocked [`CharacterBody`](#characterbody) resolves its steps
against, so one component carries the feet box for both purposes: `examples/collision_tiles`
mounts no `CollisionWorld` at all and uses this purely as the rectangle a step may not
push past.

```ruby
add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
feet = add_component(RGame::Engine::Components::FeetCollider.new(
  width: 12, height: 6, layer: :hero
))
feet.on_hit { |other| take_damage if other.layer == :spike }
```

### `Identity`

A stable name for one node, so something outside the tree can refer to it.

```ruby
sheep.add_component(RGame::Engine::Components::Identity.new(id: 7))
RGame::Engine::Components::Identity.of(sheep)   # => 7
```

- **Construct:** `Identity.new(id:)` — any object; `nil` raises.
- **Read:** `#id`, or `Identity.of(node)`, which answers `nil` for a node with no
  identity and for no node at all.
- **Phase:** none. It holds a value and does nothing per frame.

**Most saving needs no identity.** A scene is a recipe and a save file is state,
so a *singular* thing is named by the variable holding it, and *interchangeable*
things are named by their order in an array. `examples/save_load` restores a dog
and a flock using exactly those two and nothing else; `examples/save_load_ids`
is the one that needs this.

This is for what those do not cover: **a collection whose members can die**,
where an array index stops naming anything once the middle is removed, and **a
reference from one saved thing to another** — a dog chasing a particular sheep.
The second is what genuinely forces ids, because a collection can be respawned
from its own records but a reference into it cannot be written without a name for
what it points at. `Targeting#target` is the worked example of the problem: it
holds a *node*, and `Identity.of` is how that becomes something a file can hold.

Two things are the game's to get right, not this component's:

- **Ids must be unique** among the things that can refer to each other. Nothing
  is checked here; a duplicate restores the wrong object, silently.
- **The allocator belongs in the save.** A counter that restarts at 1 on load
  reissues ids the restored objects already hold. Save the next id alongside
  them.

### `Mover`

The base class of every component that moves its node: [`CharacterBody`](#characterbody),
[`Velocity`](#velocity) and [`PathFollow`](#pathfollow). They are three classes because
walking an intent, integrating a velocity and following a path are three different jobs.
What they share is what happens *after* a step is computed, and that part is `Mover`. It is
not added to a node on its own.

**What stops a step is declared, not subclassed.** `blocked_by:` lists what a step may not
pass through. The default is nothing, which writes the node's position directly and needs
**no sprite, no dimensions, no collider and no system on the scene**.

```ruby
add_component(RGame::Engine::Components::BoxCollider.new(width: 12, height: 12, layer: :crate))
add_component(RGame::Engine::Components::Velocity.new(vx: 90, vy: 40, blocked_by: [:wall]))
```

Two names are reserved and every other name is a collider layer:

| Name | Resolved against | Stops the step at |
|---|---|---|
| `:tiles` | the scene's [`TileWorld`](#tileworld) | the edge of a solid tile |
| `:bounds` | the scene's [`WorldBounds`](#world) | the edge of the world |
| anything else | the scene's [`CollisionWorld`](#collisionworld) | the edge of any `BoxCollider` wearing that layer |

Each step is resolved one axis at a time and takes the most restrictive answer, so a
diagonal held against a wall keeps its free half and the mover slides — and it slides the
same way off a villager as off a fence. That is what a character wants and not what a bullet
wants, and a bullet does not need a different resolver for it. `on_blocked` fires on the step
it hits, and a bullet that queue-frees itself there is gone before it has slid anywhere. A
mover that keeps pushing also keeps its intent: a blocked `Velocity` does not zero its `vx`.

```ruby
add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6, layer: :hero))
add_component(RGame::Engine::Components::CharacterBody.new(speed: 80, blocked_by: %i[tiles npc]))
```

Three things worth knowing about a layer name:

- **A layer that is empty is not an error.** The declaration says what *may* stop this
  mover, not what does.
- **A mover is never stopped by its own collider**, so a crowd of villagers can all
  declare `blocked_by: [:npc]` while each of them wears `:npc`.
- **Blocking is box versus box.** A [`CircleCollider`](#circlecollider) on a declared
  layer reports its contacts as usual and stops nothing.

`blocked_by` and [`on_hit`](#boxcollider) answer different questions — what may I walk
through, and what am I touching — and they are not alternatives. A successfully blocked
pair ends up *touching*, and `CollisionBox.overlap?` is half-open, so blocking a step
reports no contact. An entity that must both stop and react needs both, which is the Godot
idiom of a body with a child area.

**What stopped a step is reported.** `on_blocked` fires on the step something starts
stopping this mover, `on_unblocked` on the step it stops, each once per blocker. It is the
same pair of edges [`BoxCollider`](#boxcollider) reports for a contact, pointed at what a
step could not pass through — and it is what makes a spiky ball that both stops the player
and hurts them two ordinary components rather than a hand-rolled `on_hit`.

```ruby
mover.on_blocked { |by| take_damage if by.layer == :spike }
```

The listener is handed the blocker and reads `by.layer` and `by.node`, the same way
whichever kind stopped the step: a collider answers its own layer and its owning node, the
map's solid tiles answer `:tiles` and `nil`, and the world's edge answers `:bounds` and
`nil`. Three things worth knowing:

- **Standing still is an unblocking.** The set of blockers advances once per `update`, so a
  mover that stops pushing records nothing that step and `on_unblocked` fires. It has
  not moved; it has stopped *being stopped*.
- **Once per blocker, not once per axis.** A step stopped on both axes by the same thing
  fires once. A step stopped on X by the map and on Y by a villager fires twice, once for
  each — starting edges before ending ones, the order `CollisionWorld` reports contacts in.
- **A blocked pair is not a contact**, per the paragraph above. `on_blocked` is what the
  spiky ball listens to; `on_hit` is what a trigger area listens to.

**`:bounds` is declared, not automatic.** A mover that does not name it leaves the
world. That is deliberate: [`ScreenWrap`](#screenwrap) and
[`DespawnOffscreen`](#despawnoffscreen) read the same bounds but act on `node.x`/`node.y`
rather than on the collision box, so a mover held inside the world without having asked
made those two misfire — a hero with a feet box despawned itself on touching the left
wall. Declaring `:bounds` *and* one of those components is a contradiction a game now has
to ask for twice.

**The shape has one owner, and it is not the mover.** A blocked step is resolved against the
sibling [`BoxCollider`](#boxcollider)'s rectangle — [`FeetCollider`](#feetcollider) is the one
a walking character wants. So the box is given once, to the component that *is* a shape,
and the same rectangle both stops the step and reports contacts: reassigning `collider.box`
retunes both, and there is nothing to hand from one component to the other.

- **Construct:** every mover takes `blocked_by: []`. A bare symbol works too
  (`blocked_by: :tiles`).
- **Lifecycle:** `on_attach` resolves what was declared, builds the mover's own
  [`CollisionSystem`](internals.md#collisionsystem--move-an-actor-against-its-blockers) out
  of the sources it found, and **raises** for anything it cannot find — the node's collider
  first, then the scene's `TileWorld` for `:tiles`, its `WorldBounds` for `:bounds`, its
  `CollisionWorld` for any layer name. Falling back to free movement would look like a
  collision bug, with the cause in a scene three files away that never mounted the system.
- **Signals:** `on_blocked` fires with what stopped the step, `on_unblocked` when it stops
  stopping it — `mover.on_blocked { |by| ... }`. A mover that wants the raw per-axis answer
  instead reads
  [`CollisionSystem#blocked_x` / `#blocked_y`](internals.md#collisionsystem--move-an-actor-against-its-blockers).
- **Phase:** `update(dt)` opens the step, calls the subclass's private `take_step(dt)`, and
  reports the edges. It is not for overriding: that is what keeps a mover from forgetting
  either edge.
- **Seam:** `apply_move(dx, dy)` is where a step lands. It writes straight onto the node when
  nothing was declared, and goes through the resolver when something was. A mover may call it
  several times in one step, and the edges are still reported once.
- **Actor adapter:** when blocked, the mover hands *itself* to
  [`CollisionSystem#move`](internals.md#collisionsystem--move-an-actor-against-its-blockers),
  answering `collision_box` from the collider and `x`/`y`/`x=`/`y=` from the node **in world
  space** — the frame the tile grid and the broadphase are already in. Writing back is a
  translation of the node's local position, which is exact under an unrotated ancestor chain
  and approximate under a rotated one; a thing that spins wants a circle anyway.

### `PathFollow`

Walks the owning node along an [`RGame::Engine::Path`](toolbox.md#path--a-walkable-polyline)
at a constant speed and emits `on_finished` when it reaches the last waypoint — the seam for
whatever should happen when a walker arrives.

- **Construct:** `PathFollow.new(path:, speed:)`.
- **Lifecycle:** `on_attach` (re)starts the walk — back to the first waypoint with progress
  cleared — so a pooled follower reacquired and re-added begins a fresh walk.
- **Signal:** `on_finished` fires once (no payload) at the end of the path —
  `follow.on_finished { node.queue_free }`.
- **Phase:** `update(dt)` advances `speed * dt`, crossing as many segments as one step
  spans and interpolating the node's position; allocation-free.

### `PlayerController`

Drives a `CharacterBody` sibling from two input axes — direct 8-way walking, no inertia
(unlike `ThrustController`). It neither knows nor cares whether that body is blocked by
anything.

- **Construct:** `PlayerController.new(x_axis: :move_x, y_axis: :move_y)`.
- **Lifecycle:** `on_attach` pulls the node's `CharacterBody` (`require_sibling`).
- **Example:** `examples/walk`.
- **Phase:** `control(actions)` copies the two axes into the body's intent.

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
- **It contradicts `blocked_by: [:bounds]`.** This acts on `node.x`/`node.y`; a mover
  blocked by the world edge acts on the collision **box**, so a node with an offset box is
  left just outside the bounds this then reads and wraps. Give a wrapping entity a mover
  that does not declare `:bounds` — which is why the edge is declared rather than applied
  to everybody. See [`Mover`](#mover).

### `Sprite`

Draws a single registered image centred on the node's own origin — at `0, 0`,
which the traversal has already placed and rotated.

- **Construct:** `Sprite.new(id:, scale: 1.0, z: 0)` — `id` is a renderer image id; `z`
  orders this component against the node's *other* drawing (a shadow under a sprite),
  inside the node's own slot. It is not the node's `z`, which orders the node against
  its siblings. See [Drawing](drawing.md#draw-order).
- **State:** `scale` is a read/write accessor (a pooled entity can retune it).
- **Phase:** `draw(renderer, view)` draws the image at **`0, 0`** with **no angle** —
  `Node2D#draw` has already pushed the node's transform, so its own origin is where the
  renderer already is and its rotation already applies; passing either would apply it
  twice. It skips the draw entirely when the view cannot show it, measuring the node's box
  scaled against `node.world_x`/`world_y` — a node that never set a size is never culled.

### `Targeting`

Picks a node for the owning node to aim at: each `update` it queries the scene's
[`CollisionWorld`](#collisionworld) around the node's world origin and exposes the chosen
target. It only *selects* — it never moves or fires; the owner reads `target` and acts.
Because every candidate already registers with the broadphase through its collider,
targeting keeps no entity list of its own.

- **Construct:** `Targeting.new(range:, policy: :nearest, layer: nil)`. `range` is the
  reach in pixels; `layer` restricts candidates (passing `:enemy` ignores allies and
  projectiles); an unknown `policy` raises at construction.
- **Policies** (how to choose among the in-range candidates):
  - `:nearest` — the closest candidate (the default; one broadphase nearest-lookup).
- **State:** `target` is the chosen **node** (or `nil` when nothing is in range),
  refreshed every `update` — so a freed/out-of-range target clears on its own. It's a node
  (not a collider) so the owner can read its position and components.
- **Lifecycle:** `on_attach` pulls the scene's `CollisionWorld`.
- **Phase:** `update(dt)` re-selects the target; allocation-free, so it runs every frame.

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

### `TileWorld`

The scene-scoped tile **system** (see [Systems](systems.md)): it holds the parsed `RGame::Engine::TileMap`
and answers everything an actor needs from it — where the solid tiles are, and how big the
world is. Found with `node.system(TileWorld)`.
It includes `WorldBounds` (see [`World`](#world)), so `ScreenWrap` and `DespawnOffscreen`
work in a tile scene with nothing passed to them.

**It does not draw.** `RGame::Engine::TileMapLayer` does — one node per Tiled layer, mounted
inside a `WorldView`, so the map is drawn once per viewport like the rest of world space.
This stays the thing actors ask questions of.

- **Construct:** `TileWorld.new(map:, tilemap_id:, cameras: [])` — it clamps each camera it is given to
  the map's edges, and `bound(camera)` does the same for one that arrives later (a player joining).
- **Queries:** `blockers` is the map's solid tiles as an
  [`Engine::TileBlockers`](internals.md#tileblockers--the-tile-grid-as-a-blocker-source),
  the same object every time, which a [`Mover`](#mover) declaring `:tiles`
  borrows and resolves its own steps against. Also `solid?(col, row)`;
  `world_width`/`world_height`; `tilemap_id` and `elapsed`, which the layers read;
  `layer_count` and `first_above_layer`, which `TileMapLayer.mount` reads to decide where
  the actors go.
- **It does not resolve a step.** A mover may be stopped by tiles, by other actors, by the
  world's edge or by any combination, and only the mover knows which — so the resolver is
  the mover's and the grid is this system's.
- **Phase:** `update(dt)` advances the map's animation clock.
- **Example:** `examples/scroll_map` — a `.tmx` through the asset manager, this
  system, `TileMapLayer.mount`, and a camera clamped to the map's edges.
  `examples/collision_tiles` is the same scene with an actor that collides, and is where
  the solid half of this system is shown.

```ruby
world  = scene.add_node(RGame::Engine::WorldView.new)
actors = RGame::Engine::TileMapLayer.mount(world)   # a node per Tiled layer
actors.add_node(player)                             # in the gap between them
```

`mount` returns the node the actors go in. It sits below the first layer Tiled flags
`above` — trunks under the walker, canopies over — and `mount(world, under: index)`
overrides that for a map with a different arrangement. Nothing here picks a `z`.

### `Timer`

A node-driven interval timer: it rides the node's update tick (so nothing can forget to
advance it) and emits `on_timeout` each time a whole interval elapses — a spawn cadence, a
turret's fire rate, a wave clock. Wraps the pure [`RGame::Engine::Timer`](toolbox.md#timer--paced-periodic-events),
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

### `Velocity`

Integrates linear and angular velocity into the node's transform each step.

- **Construct:** `Velocity.new(vx: 0.0, vy: 0.0, spin: 0.0, blocked_by: [])` — what may
  stop it is [`Mover`](#mover)'s, and works as it does for a `CharacterBody`.
- **State:** `vx`, `vy`, `spin` are read/write accessors — a controller (or the node's
  own `control` hook) writes them as movement intent.
- **Phase:** `update(dt)` moves the node by `vx*dt`/`vy*dt` through `apply_move`, and adds
  `spin*dt` to `node.angle` directly: a collision box does not turn with its node, so a
  rotation has nothing to be blocked by.
- **Blocked:** a stopped step leaves `vx`/`vy` as they were. They are the intent, and what
  a stop should do to them — nothing, zero them, bounce — is the game's call, made in an
  `on_blocked` handler. A `ThrustController` ship is blocked by declaring `blocked_by:` here,
  on the `Velocity` it drives.

A free-moving entity can use `Velocity` alone; pair it with a controller for input.

```ruby
add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, layer: :bullet))
velocity = add_component(RGame::Engine::Components::Velocity.new(vx: 400, blocked_by: %i[tiles]))
velocity.on_blocked { queue_free }
```

### `WanderController`

A simple AI driver for a `CharacterBody`: every so often it rolls a new direction (one of eight, or
idle) and holds it, re-rolling early when a wall blocks it. The RNG is injected, so behaviour is
deterministic in tests.

- **Construct:** `WanderController.new(rng: Random.new, change_interval: 1.0..3.0, idle_chance: 0.25)`.
- **Lifecycle:** `on_attach` pulls the node's `CharacterBody` (`require_sibling`).
- **Example:** `examples/walk`.
- **Phase:** `update(dt)` counts down the timer and re-rolls on timeout or when blocked.
  "Blocked" is *the node did not move while intending to* — measured, not asked of a
  collision world — so it works over a plain `CharacterBody` too, and simply never fires
  for one whose steps always land.

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