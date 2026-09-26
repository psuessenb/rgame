# Components

**A component is a reusable piece of behaviour attached to a `Node2D`**, instead
of being built into a node subclass. A node composes several components. Each
knows its owning `node`, and the node's tick drives it. Components live in
`engine/components/`, under `RGame::Engine::Components`, and subclass
`RGame::Engine::Component`. [Scene graph](scene_graph.md) explains how nodes drive
components. [Systems & shared resources](systems.md) covers components that serve
a whole scene or program.

`examples/walk` shows the smallest character in one file: `AnimatedSprite`,
`CharacterBody` and `PlayerController`.

## When what you want is not a component

**A component is behaviour on the node's tick.** It overrides `_control`, `_update`
or `_draw`, and the node drives it. Much of what a game needs is not that. Searching
this page for it leads to worse, hand-made answers.

Those helpers live in the [Toolbox](toolbox.md). A game constructs them directly,
attached to nothing, and that is ordinary use. `examples/sound` builds a `Text` and
reads it within ten lines.

| Looking for | Reach for | |
|---|---|---|
| a label from a value that changes, with no `String` per frame | `Text` | [→](toolbox.md#text--the-string-a-node-draws) |
| to play a sound without naming the sound device | `AudioOut`, a system | [→](audio.md#audioout--the-system-a-node-plays-sound-through) |
| a point to follow, clamped to the world | `Camera` | [→](toolbox.md#camera--follow-a-point-clamp-to-the-world) |
| text in the player's language | `I18n` | [→](localization.md) |
| an ordered route to walk | `Path` | [→](toolbox.md#path--a-walkable-polyline) |
| the cheapest route between two tiles | `NavGrid`, from `TileWorld#nav_grid` | [→](toolbox.md#navgrid--routes-over-a-tile-grid) |
| a node that walks itself to a point, around the map | `Components::Navigator` | [→](#navigator) |

**Per-frame work earns a component.** Three toolbox classes have component
wrappers, for that reason only. A timer and a tween must advance every tick, and a
pool must reclaim freed nodes every tick. `Components::Timer`, `Components::Tween`
and `Components::Pool` put that work in the traversal, where nothing can forget
it. Without per-frame work there is no
wrapper. A `Text` is read when something draws it. A component that
overrode no hook would be a component in name only. The one-per-slot rule would
even make a second label on one node harder.

## The `Component` base

`RGame::Engine::Component` (`rgame/engine/component`) gives every component a
`node` back-link and hooks the node calls. Override the hooks you need; the rest
do nothing. Like nodes, components extend the signal DSL, so they can declare and
emit signals.

**Per-tick hooks.** In each phase a node runs its components before its own hook
and before its children.

- `_control(actions)` reads intent from the per-tick action snapshot. The snapshot
  belongs to whoever [owns the node](scene_graph.md#who-a-node-answers-to), so a
  component never learns there is more than one player. Its `pressed?` and
  `released?` answer only for
  [presses the node saw start](input.md#a-node-reads-only-the-presses-it-saw-start).
- `_update(dt)` advances state over the timestep.
- `_draw(renderer, view)` renders through the renderer interface into the
  [viewport being drawn](scene_graph.md#viewports-and-views). Most components
  ignore `view`. It serves layout against the region's edges, and culling.

**Tree-lifecycle hooks.** The engine fires these when the node enters or leaves
the live tree. Anchors and sibling systems are reachable here, so wire across
nodes here, not in `initialize`.

- `_attach`: the node entered the tree. Look up shared systems and register
  with them.
- `_detach`: the node is leaving. Release those registrations.

`_sweep_freed` serves container components that hold nodes outside the normal
child list. The default does nothing; see
[deferred free](scene_graph.md#deferred-free).

A component may define a `_` method only if it is one of these hooks, or one an
ancestor declared with `hook`. Anything else raises `NameError` when the class
loads; see [the tick](scene_graph.md#the-tick-control--update--draw).

**A component names its instance variables freely.** Every component in
`RGame::Engine`, `Component` itself included, keeps its own under `@rgame_`:
`node` reads `@rgame_node`. So a subclass's `@node` or `@timer` is its own.

**`require_sibling(klass)` opens the `_attach` of a component that drives a
sibling**: `@body = require_sibling(CharacterBody)`. It returns the component, or
raises naming both. A plain `nil` would stay silent until the first frame called a
method on it. When it raises, the cause is nearly always add order; see
[Where to add a component](#where-to-add-a-component) below. It also raises,
naming each one, when *several* siblings match `klass`, such as two
[`Mover`](#mover)s under one [`AnimatedSprite`](#animatedsprite). It never quietly
takes whichever came first.

**A node holds at most one component per slot.** The slot defaults to the
component's class, so by default a node holds one per class, and `add_component`
raises on a taken slot. Pass `as: :name` to keep several of one type, such as a
spawn timer and a wave timer. Look a component up with `get_component(key)`. The
key is a class, matched by ancestry and raising if several share the type, or a
Symbol name.

## Where to add a component

**Assemble a node before it enters the tree.** Two shapes do that. Which one fits
depends on whether the node has a class of its own:

- **A `Node2D` subclass adds components in `initialize`.** This default covers most
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

- **A plain `Node2D` built from components gets a builder method** that returns
  the assembled node. Use it when the node is nothing but its components, and a
  subclass would add no behaviour. `examples/save_load` builds its walkers this
  way.

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

**Both shapes work for the same reason.** The node is not in the tree yet, so
`add_component` only appends. No `_attach` fires until the whole set is present
and the node enters. **Add order is therefore free.** `build_player` above adds an
`AnimatedSprite` *before* the `CharacterBody` it faces by, and that works.

### Adding from `_enter_tree`, and when you must

**A node running `_enter_tree` is already in the tree.** Each `add_component` attaches
at once and sees only the components added before it. The same two lines in the
other order raise (see [`require_sibling`](#the-component-base) above). Prefer
`initialize` or a builder. Use `_enter_tree` only when the component cannot be built
earlier, because its constructor needs something only the tree can answer:

```ruby
def _enter_tree
  # Both arguments are cross-tree lookups: the asset manager hangs off the root's
  # context, and the player registry is a system. Neither exists at construction.
  add_component(RGame::Engine::Components::TileWorld.new(
                  map: root.context.assets.tilemap(MAP_KEY).map,
                  tilemap_id: MAP_KEY,
                  cameras: root.system(RGame::Engine::Players).map(&:camera)
                ))
end
```

**Apply one test: does the constructor need the tree?** A `World` built from
numbers the scene already has does not. Nor does a `CollisionWorld` built from a
constant. `examples/collision` mounts both in `initialize`. There they are
guaranteed to precede every entity the scene spawns later. A `TileWorld` parsed
from the asset manager needs the tree, so it waits.

The opposite exception is a component added **deliberately** after entry, because
it depends on state that exists only once the node is live. An example is a
`CameraFollow` whose offset comes from the sibling body's resolved
`collision_box`. That is a later decision, not assembly, and `_enter_tree` suits it.

## Available components

### `ActionTrigger`

**Maps held input actions to an `on_triggered(action)` signal, limited by a
per-action cooldown.** One instance covers several actions and emits the action
name, so listeners filter. The same component serves "fire" in a shooter or
"jump" and "fire" in a platformer.

- **Construct:** `ActionTrigger.new(cooldowns)`, where `cooldowns` is
  `{ action => seconds }`, e.g. `ActionTrigger.new(fire: 0.22)`.
- **Signal:** `on_triggered` fires with the action name:
  `trigger.on_triggered { |a| … }`.
- **Phase:** `_update(dt)` ticks the per-action cooldowns. `_control(actions)` emits
  when an action is held and its cooldown has elapsed. Held plus cooldown gives
  auto-repeat.

### `AnimatedSprite`

**Draws a sprite-sheet animation, chosen from its [`Mover`](#mover) sibling's
[heading](#mover).** It plays `walk_left`, `walk_right`, `walk_up` or `walk_down`
while moving, and `stand` when still. The heading's larger axis picks the
direction, and a tie goes horizontal. A keyboard diagonal therefore walks sideways,
while a stick held mostly down walks down, as does a route segment running mostly
down. Any mover works. A [`CharacterBody`](#characterbody) faces its intent. A
[`PathFollow`](#pathfollow) or [`Navigator`](#navigator) faces the segment it
walks. A [`Velocity`](#velocity) faces where it flies. The component owns an
`RGame::Engine::Animator` over the pure `AnimationSet` built from the sheet's
animation table.

- **Construct:** `AnimatedSprite.new(sheet:, z: 0, anchor: :bottom)`. `sheet`
  is the asset's relative path. `z` orders this component against the node's
  other drawing, inside the node's own slot, as for [`Sprite`](#sprite). `anchor`
  places the frame against the node's origin, with the same three values as
  [`Sprite`](#sprite). The default stands the character on the origin, which is
  where a [`FeetCollider`](#feetcollider) puts its box. An unknown anchor raises
  `ArgumentError`.
- **Lifecycle:** `_attach` resolves the sheet from the game's asset manager
  (`node.root.context.assets.sheet(sheet)`) and builds its animation set. It
  **sizes the node** to the sheet's frame (`node.width` and `height`), which the
  anchor and culling measure from. It then looks up the mover sibling
  it faces by. A node with **two** movers raises here, naming both: both write the
  position, so no facing is defined. The renderer resolves the same path when
  drawing, so nothing is registered or passed in by hand.
- **Phase:** `_update(dt)` selects and advances the animation.
  `_draw(renderer, view)` renders the current frame via `renderer.sprite`, placed
  by the anchor, with no angle. The traversal already placed the renderer on the
  node, and a [`WorldView`](scene_graph.md#view-transforms-and-the-camera)
  ancestor already applied the camera. The frame is lifted by
  [`node.elevation`](scene_graph.md#elevation). The component skips the draw when
  the view cannot show it. It measures the node's box, moved by the anchor and
  raised by the elevation, against `node.world_x` and `world_y`. Culling uses
  world coordinates because it compares against the camera.
  [`Sprite`](#sprite) is the single-image counterpart: with the same anchor and
  size, the two cover the same pixels.

### `BoxCollider`

**A rectangular collision shape in a scene's
[`CollisionWorld`](#collisionworld).** It is the sibling of
[`CircleCollider`](#circlecollider), for box-shaped entities: a crate, a platform,
a wall segment. It registers when the node enters the tree and unregisters when it
leaves, so spawning and despawning never leak a registration.

- **Construct:** `BoxCollider.new(width:, height:, offset_x: 0, offset_y: 0, layer: :default)`.
  The offsets are relative to the node's origin, so a 32×32 sprite can carry a
  small box at its feet. `layer` is an opaque tag. The *owner* reads it to decide
  what a contact means; the collision system ignores it.
- **Lifecycle:** `_attach` registers with `node.system(CollisionWorld)`, and
  `_detach` unregisters. In a scene with **no** world, it stays a bare shape and
  does not raise. A collider is a shape; a world turns shapes into contacts. A
  tile-only game can therefore carry a feet box for
  [`CharacterBody(blocked_by:)`](#characterbody), or any other [`Mover`](#mover),
  alone. The cost: an `on_hit` handler in such a scene never fires, and nothing
  reports it.
- **Geometry:** the rectangle is an
  [`RGame::Engine::CollisionBox`](toolbox.md#collisionbox--an-actors-feet-box),
  exposed as the read/write `box` accessor. Assign a new one to retune a pooled
  entity's shape on reset. No re-registration is needed. `aabb_x`, `aabb_y`, `aabb_w` and `aabb_h` give the
  world-space box. `cx` and `cy` give the **box's** centre, which the world's range
  queries measure from. A circle's centre, by contrast, is the node origin.
- **Rotation:** the box stays axis-aligned in world space and does not turn with
  the node. A spinning entity wants a `CircleCollider`, which rotation does not
  affect, instead of a box recomputed every frame.
- **Contacts:** `overlap?(other)` works against a box *or* a circle. The two
  colliders settle the test between themselves, so both shapes mix freely in one
  world.
- **Blocking:** a box on a layer that some [`Mover`](#mover) named in
  `blocked_by:` also *stops* that mover's steps, flush against this box's edge. The
  box needs no opt-in; the other body's layer declaration is the whole setup.
- **Drawing itself:** while the debug layer's `:shapes` channel is on, `_draw`
  draws the box with `renderer.debug_box` in the `:debug` band, over everything
  else in the frame. The box is already in the node's local space, so it lands on
  the node in every viewport with no camera arithmetic. The `Debug` system is
  looked up once, on attach, so a frame with the channel off costs a `nil` check
  and a scene with no debug layer above it draws nothing. See
  [Systems](systems.md#debug--a-switch-per-channel).
- **Signals:** `on_hit` fires with the other collider on the step a contact
  **starts**, and `on_separated` on the step it **ends**:
  `collider.on_hit { |other| ... }`. The system triggers them through
  `emit_hit(other)` and `emit_separated(other)`. Each fires once per pair, so a
  handler may count, play a sound or spend a life; see
  [`CollisionWorld`](#collisionworld).

```ruby
collider = add_component(RGame::Engine::Components::BoxCollider.new(
  width: 32, height: 32, layer: :pickup
))
collider.on_hit { |other| collect if other.layer == :player }
```

### `CameraFollow`

**Points a camera at the node it is attached to.**

- **Construct:** `CameraFollow.new(camera:, offset_x: 0.0, offset_y: 0.0)`. The
  offsets shift the point the camera centres on, for a node whose origin should not
  sit mid-screen. A character drawn with the default `:bottom` anchor stands on its
  origin, so the camera centres on their feet with no offset.
- **Phase:** `_update(dt)` calls `camera.center_on` with the node's world origin.
  The camera trails the node's movement by one step, uniformly.
- **Example:** `examples/scroll_map`. The followed node is an invisible rig with a
  `CharacterBody` and a `PlayerController`. That is all "scroll the map with the
  arrow keys" takes.

**The camera belongs to a [player](input.md#players-seats-and-joining)**, not to
this component or the scene, because a scene may have any number of viewers. The
player owns the camera; this component moves it. "Player two's camera follows
player two" is this component holding player two's camera.

### `CharacterBody`

**Direct, per-step walking for an actor.** A controller writes a movement intent,
each axis −1..1. The body turns it into a move each `update`, at a fixed speed with
no inertia. `Velocity`, by contrast, integrates a velocity the controller sets, and
`ThrustController` accelerates one.

A character is a `CharacterBody` plus a controller. A character the map stops adds
a feet box and a declaration. **[`Mover`](#mover) decides what may stop a step**,
for `Velocity` and `PathFollow` too. `blocked_by:`, `on_blocked`, `on_unblocked`
and the `apply_move` seam are documented there, and work the same way here.

```ruby
add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
add_component(RGame::Engine::Components::CharacterBody.new(speed: 80, blocked_by: [:tiles]))
add_component(RGame::Engine::Components::PlayerController.new)
```

- **Construct:** `CharacterBody.new(speed:, blocked_by: [], pushes: [])`: walk speed
  in px/s, what may stop a step, and what a step pushes (see [`Mover`](#mover)).
- **State:** `set_intent(x, y)` writes the step's intent. `move_x` and `move_y`
  read it back, and so do `heading_x` and `heading_y`. A body pressed into a wall
  still heads into it.
- **Attach:** the body stands still as its node enters the tree, whatever intent
  it had. A hero carried into another scene or room, or a node taken from a pool
  again, does not walk on under the reveal. Set an intent after placing the node
  for one that should walk in.
- **Phase:** `_update(dt)` applies `intent * speed * dt` through `apply_move`, and
  moves nothing when the intent is zero. That still counts as a step, so a body
  that stops pushing into a wall reports `on_unblocked`.
- **Seam:** a body that resolves a step differently, such as a platformer's with
  gravity and a jump, overrides [`apply_move`](#mover). It inherits the intent, the
  speed and the standing-still check.
- **Examples:** `examples/walk` uses this, a `PlayerController` and an
  `AnimatedSprite`, and nothing else. `examples/collision_tiles` adds a feet box and
  `blocked_by: [:tiles]`, and draws the box over the sprite so you can see what
  collides. A crowd adds more names: walkers that each declare
  `%i[tiles hero npc]` are stopped by the map and by one another.

### `Checkpoint`

**A place a node comes back to after a fall, once it has touched it.** It
listens to its own node's collider, as [`Collectable`](#collectable) does. On the
step a collider on the `by` layer starts overlapping it, it moves that node's
[`Respawn`](#respawn) point to its own node's world position.

```ruby
flag.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, offset_x: -8,
                                                              offset_y: -16, layer: :checkpoint))
flag.add_component(RGame::Engine::Components::Checkpoint.new(by: :hero))
    .on_reached { |_other| @raised = true }
```

- **Construct:** `Checkpoint.new(by:)`. `by` is the layer whose colliders reach
  it, readable as `by`; every other layer is ignored.
- **Signal:** `on_reached(other)` fires with the collider that touched it, once
  its node's `Respawn` has the new point. `on_hit` is an edge, so a node standing
  on a checkpoint reaches it once.
- **Lifecycle:** `_attach` needs a [`Collider`](#collider) on the same node and
  connects to it. `_detach` ends that connection, so a checkpoint taken out of the
  tree and added again fires once per touch.

**A touch moves only the toucher's point.** Two heroes each come back at the last
checkpoint they touched, an earlier one touched again included.

**A node on `by` with no `Respawn` raises at the touch**, naming its class and the
layer. A game that ends on a fall decides at the fall instead, and removes the
`Respawn` in [`Footing`](#footing)'s `on_fell`.

**It stands on ground.** With a [`TileWorld`](#tileworld) on the scene, `_attach`
raises `ArgumentError` where the node's cell is a gap, under a platform or not. A
checkpoint placed over a gap fails as the scene loads.

`Checkpoint` has no `_update`, so it costs nothing per frame.

### `CircleCollider`

**A circular collision shape in a scene's [`CollisionWorld`](#collisionworld).** It
registers when the node enters the tree and unregisters when it leaves, so spawning
and despawning never leak a registration.

- **Construct:** `CircleCollider.new(radius:, layer: :default)`. `layer` is an
  opaque tag. The *owner* reads it to decide what a contact means; the collision
  system ignores it.
- **Lifecycle:** `_attach` registers with `node.system(CollisionWorld)`, and
  `_detach` unregisters. As with [`BoxCollider`](#boxcollider), a scene with no
  world leaves it a bare shape, without raising.
- **Geometry:** `cx` and `cy` are the node's world origin (`node.world_x`,
  `world_y`). `radius` is read/write, so a pooled entity can retune its shape on
  reset. `layer` is a reader. `aabb_x`, `aabb_y`, `aabb_w` and `aabb_h` give the
  bounding box the world buckets on.
- **Contacts:** `overlap?(other)` works against a circle *or* a
  [`BoxCollider`](#boxcollider). The two colliders settle the test between
  themselves, so both shapes mix freely in one world.
- **Drawing itself:** while the debug layer's `:shapes` channel is on, `_draw`
  draws the circle with `renderer.debug_circle` in the `:debug` band. Its centre
  is the node's own origin, which is `(0, 0)` in the space a component draws in.
  As with [`BoxCollider`](#boxcollider), the lookup happens on attach and a scene
  with no debug layer draws nothing. See
  [Systems](systems.md#debug--a-switch-per-channel).
- **It never blocks.** Blocking is box against box. A circle on a layer that a
  [`Mover`](#mover) named in `blocked_by:` reports contacts as usual and stops
  nobody. Nor can a circle *be* stopped. A mover that declares anything needs a
  `BoxCollider` of its own, and raises at attach without one. The first rule is a
  limit, not a check: layer membership is a runtime fact, so a raise at attach
  would catch only circles that already existed.
- **Signals:** `on_hit` fires with the other collider on the step a contact
  **starts**, and `on_separated` on the step it **ends**:
  `collider.on_hit { |other| ... }`. The system triggers them through
  `emit_hit(other)` and `emit_separated(other)`. Each fires once per pair; see
  [`CollisionWorld`](#collisionworld).

### `Collectable`

**A thing that is taken by being touched.** It listens to its own node's
collider and acts on the step a collider on the `by` layer starts overlapping
it: emit `collected`, play `sound`, and free the node.

```ruby
coin.add_component(RGame::Engine::Components::Collectable.new(by: :hero, sound: :blip))
    .on_collected { |_other| purse.add(:coin) }

chest.add_component(RGame::Engine::Components::Collectable.new(by: :hero, free: false))
```

- **Construct:** `Collectable.new(by:, sound: nil, free: true)`. `by` is the
  layer whose colliders take this; every other layer is ignored. `sound` is a
  sound id, or `nil` for a silent pickup. `free: false` keeps the node.
- **Signal:** `on_collected(other)` fires with the collider that took it, before
  the node is freed, so a listener can still read its node. `on_hit` is an edge,
  so standing on a coin takes it once.
- **Lifecycle:** `_attach` needs a [`Collider`](#collider) on the same node and
  connects to it; `_detach` ends that connection, so a pooled node taken twice
  fires twice.
- **Sound:** played through the tree's [`AudioOut`](systems.md), looked up with
  `system!` — a scene with a `sound:` and no `AudioOut` raises rather than going
  quietly silent. A collectable given no sound needs no `AudioOut` at all.

**The collectable does the collecting**, rather than the hero holding a list of
what it may pick up. What a coin is worth belongs to the coin, and a game adds
one by adding a node.

**`free: false` is the chest**: it reports the touch and stays, and whatever
listens decides what opening means. Pair it with an
[`Interactor`](#interactor) for something reached by touch and opened with a
press.

### `Collider`

**What [`BoxCollider`](#boxcollider) and [`CircleCollider`](#circlecollider)
both are**, and the name to ask for when the shape does not matter:

```ruby
def _attach = @collider = require_sibling(RGame::Engine::Components::Collider)
```

It declares nothing. Both colliders already answer the same broadphase,
narrowphase and contact protocol; this is the module they include so a component
can name it. A coin is round and a chest is not, so
[`Collectable`](#collectable) asks for this rather than for either shape.

A node carrying both matches twice and `require_sibling` raises, which is the
right answer: there is no telling which was meant.

### `CollisionWorld`

**A scene-scoped broadphase collision system.** The component lives on the scene
node, holds the registered colliders in a `SpatialHash`, and reports each step
where overlapping pairs begin and end. As a normal component, it runs in the
`update` traversal and goes away with the scene. See
[Systems & shared resources](systems.md).

**It ignores shape.** It buckets each collider by its reported bounding box
(`aabb_x`, `aabb_y`, `aabb_w`, `aabb_h`) and leaves the exact test to the pair's own
`overlap?`. [`CircleCollider`](#circlecollider) and [`BoxCollider`](#boxcollider)
therefore share one world and collide with each other. A game can add its own
shape by answering the same few methods.

- **Construct:** `CollisionWorld.new(cell_size:)`, the spatial hash's cell size.
  **Size it to the colliders**, and nothing else. A tile map in the same scene is
  no guide. A 64px collider in 16px cells lands in twenty-five cells and is queried
  from all of them. That measured 2.8× the cost of a cell sized to the collider. A
  12×6 feet box in the same 16px cells costs only 10–20% over its own optimum. A
  wrong value costs frame time, never correctness, so pick it deliberately.
- **Registration:** `register(collider)` and `unregister(collider)`. Colliders call
  these through their own lifecycle, so nodes never wire them.
- **Queries:** `query_box(x, y, w, h)` yields every registered collider bucketed in
  a cell the region covers. It skips nodes queued for removal. It is the
  rectangular form of `query_circle`, and a blocked [`Mover`](#mover) asks it each
  step. `nearest(x, y, r, layer:)` and `cell_empty?(x, y)` complete the set. All of
  them read the index the most recent `update` built, and allocate nothing.
- **Staying current mid-step:** `reindex(collider, from_x, from_y, from_w, from_h)`
  re-buckets a collider that moved after the index was built, given the box it
  *was* bucketed at. Buckets fill once per step, so a query over cells a mover left
  would miss it. With two hundred actors, that measured 116 misses in 60,000
  queries, and none once each mover re-bucketed itself. A [`Mover`](#mover) that
  declares a collider layer does this through its resolver. Anything else that
  moves a collider mid-step may call it directly: a mover that declared nothing, or
  an ancestor.
- **Phase:** `_update(dt)` rebuilds the spatial index. It fires both colliders'
  `on_hit` for each pair that *started* overlapping, then both colliders'
  `on_separated` for each pair that *stopped*. It **ignores layers**: it reports
  contacts, and each owner decides their meaning by reading the other's `layer`. It
  skips colliders whose node is queued for removal.
- **Contacts arrive one step late.** This component sits on the scene node, and a
  node runs its components before its children. The world builds the index and
  reports every pair *before* any actor moves this step. Contacts therefore
  describe where things stood at the end of the previous step. The delay is
  consistent, so nothing jitters, but a pair that starts overlapping during step N
  is reported at the start of step N+1. A blocked [`Mover`](#mover) does not read
  the index this way and is unaffected. It queries mid-step and re-buckets itself,
  through `reindex` above.
- **A contact is two edges, not a state.** Each signal fires **once per pair**.
  Nothing fires on the steps between, however long the overlap lasts, and a pair
  spanning several cells reports once. A handler may therefore do what must happen
  exactly once, such as `score += 100`, playing a sound or spending a life, with
  nothing to guard. `examples/collision`'s crate counts arrivals in one line thanks
  to this.

  The world keeps an
  [`Engine::ContactSet`](internals.md#contactset--the-two-edges-of-a-contact) per
  collider for this. The set also absorbs the
  [`SpatialHash`](internals.md#spatialhash--uniform-grid-broadphase) may-yield-twice
  contract: a pair spanning three cells is offered three times and recorded once.
- **`on_separated` also fires when the partner goes.** A contact ends when the
  partner is destroyed (`queue_free`) or leaves the tree, not only when the two move
  apart. The survivor hears about it on its next step. Otherwise a ship could stay
  "in contact" with a rock that no longer exists. The departing collider hears
  nothing, because it is leaving.

  **Remember that last point when pooling.** The world clears a collider's own
  contacts when it registers, so a recycled entity never reports a separation from
  its previous life. But state a *node* derived from those contacts, such as a "how
  many things am I touching" count, never unwinds. The edge that would unwind it
  never arrived. Zero that state in the node's `reset`, with the rest.
- **Example:** `examples/collision` puts this system on the scene, circles and boxes
  on the nodes, two layers, and one line that ignores same-layer pairs. A circle
  stays lit while inside a crate (`on_hit` on, `on_separated` off), and the crate
  blinks once and counts it. The backdrop draws the broadphase grid, so you can see
  `cell_size`.
- **Range queries (targeting):** the same index answers point-radius lookups
  against the most recent `update`. A turret can find enemies without a contact:
  - `query_circle(x, y, r) { |collider| }` yields every registered collider whose
    centre lies within `r` of `(x, y)`. It measures centre distance and does not add
    the collider's size, so it reads like a range ring. It skips freed nodes'
    colliders, and may yield a collider more than once, which is fine for selecting.
    Filter by `collider.layer` in the block.
  - `nearest(x, y, r, layer: nil)` returns the closest such collider, optionally
    limited to one `layer`, or `nil`. Both allocate nothing, so a targeting
    component can call them every frame.
- **Cell occupancy (grid games):** `cell_empty?(x, y)` answers whether the cell
  containing the **world** point `(x, y)` is free, for questions like "may a pickup
  spawn on this square?". It takes a point, not a region; pass any coordinate inside
  the square you mean. Set `cell_size` to the game's own square so the two grids
  line up. The cells form the hash's own lattice, anchored at the world origin. A
  board should therefore put its origin on a multiple of `cell_size`. Off that
  lattice, each square straddles two cells and both read occupied. Like the queries
  above, it reads the index the last `update` built. It allocates nothing, even on a
  miss, which is what a board scan asks most.

  A collider whose node is queued for removal does not occupy a cell, so a corpse
  cannot reserve a square. The rest is
  [`SpatialHash#cell_empty?`](internals.md#spatialhash--uniform-grid-broadphase).
  Its cell walk is half-open on the far edge, so a piece filling one square leaves
  its neighbours free.

  It takes *world* coordinates, because colliders report those. A node whose grid
  starts elsewhere adds its origin first:

  ```ruby
  # in a Grid node whose cells are cell_size across
  def free?(col, row)
    collisions = system(RGame::Engine::Components::CollisionWorld)
    collisions.cell_empty?(world_x + (col * cell_size), world_y + (row * cell_size))
  end
  ```

### `Cutscene`

**Runs a [`Cutscene::Script`](toolbox.md#cutscenescript--a-cutscenes-steps) on
its node**, each step in order on the node's update, from the moment the
component attaches. It takes what it stops and gives it back.

```ruby
OPENING = RGame::Engine::Cutscene::Script.build do
  wait 0.5
  hold { |c| c.pan_to('square') }   # the game's method, returning a Components::Tween
  talk { |c| c.say(MAYOR) }          # puts up a UI::DialogueBox, returns its Dialogue
  press
  run { |c| c.open_gate }
end

# In a room's _enter_tree, everybody watching:
cutscene = add_component(RGame::Engine::Components::Cutscene.new(
  OPENING, context: self, camera: @camera, pause: heroes, skip: :skip
))
cutscene.on_ended { |skipped| @log << (skipped ? :skipped : :watched) }
```

[`examples/cutscene`](examples.md#cutscene) runs one that everybody watches,
and ends in the same town whether it is watched or skipped.

- **Construct:** `Cutscene.new(script, context: nil, camera: nil, pause: [], skip: nil)`.
  Each step's block is called with `context`. It raises `TypeError` for a
  `script` that is not a `Cutscene::Script` and a `skip:` that is not a Symbol.
- **What it stops:** as it starts, it
  [suspends](scene_graph.md#pausing-a-subtree) each node in `pause:`. With
  `camera:`, everybody watches: it calls
  [`solo!`](scene_graph.md#collapsing-the-split) with that camera, onto the
  `Scene::Room` its node stands in, sets `Players#accepting_joins` to false,
  and suspends every other room `Scene::Rooms#running` lists. Without `camera:`
  it does none of those three, so a scene for the one player who walked into it
  leaves the other players playing.
- **What it gives back:** when it ends, is skipped, or leaves the tree, it
  resumes each node and room and puts back the joins and the solo or split as
  they were. It suspends rather than pauses, so a hero it stopped and a door
  also moves, or a bag also pauses, runs again once every hold on it has ended.
  A door taken in its last step, which frees its room, still leaves the game
  split and running. `pause:` naming the node it rides, or a node above it,
  raises `ArgumentError`, since the cutscene would never run.
- **Its player:** it reads its node's player, the primary one unless the game
  sets `input_owner`. On a node `Players#everyone` owns, it reads every player.
  A `press` step waits for that player's press of its action. A press begun
  before the cutscene started counts for neither a `press` nor the skip.
- **Skipping:** `skip:` names an action the game declares with `hold:`, so a
  tap does not skip. Its press finishes the step under way, runs each remaining
  step's skip in order, and ends. A skip leaves the world where watching would
  have: every `run` has run, and each walk, fade and conversation stands at its
  end. Without `skip:`, only a call to `skip` skips it.

  ```ruby
  map = RGame::Engine::InputMap.default.merge(
    skip: { buttons: [RGame::Util::Controls::KEY_TAB, RGame::Util::Controls::PAD_Y], hold: 0.6 }
  )
  ```
- **Signal:** `on_ended` fires once, with true when skipped, after everything is
  given back. One that leaves the tree before its end gives everything back and
  fires nothing.
- **Reading it:** `running?`, `ended?`, and `step_index`, the index of the step
  under way in `script.steps`, nil when not running. `script`, `context` and
  `camera` return what it was built with.
- **Phase:** it reads its player in `_control` and moves on in `_update`. A step
  that ended before the cutscene's update in a tick starts the next one that
  tick. A `hold` on a node the tree updates after the cutscene's node is heard
  as it ends, and the cutscene moves on in its next update. A running cutscene
  allocates nothing a tick, and a step's block runs the game's own code as the
  step starts.

### `DespawnOffscreen`

**Removes the node once its origin passes an edge of the world bounds by more than
`margin`.** Use it for short-lived entities like projectiles. The margin stands in
for the node's size: a node drawn centred on its origin has fully left once the
margin reaches half its extent.

- **Construct:** `DespawnOffscreen.new(margin: 0.0)`, with the same optional
  `width:` and `height:` override as `ScreenWrap`.
- **Lifecycle:** `_attach` resolves the bounds, exactly as `ScreenWrap` does.
- **Phase:** `_update(dt)` calls `node.queue_free` once the node's **world**
  position passes an edge. A projectile spawned as a child of an offset emitter
  leaves at the world's edge, not at an edge shifted by the emitter's position.
  Removal is *deferred* (see [deferred free](scene_graph.md#deferred-free)), so
  triggering it inside the update traversal is safe. For an entity that never
  leaves a *fixed* board, such as a projectile that should vanish after N seconds,
  use a [`Tween`](#tween) with `on_finished { node.queue_free }` instead.
- **One response to the edge per node.** It raises at attach beside a `ScreenWrap`
  or a mover declaring `blocked_by: [:bounds]`; see
  [`WorldBounds.one_response!`](#world).

### `Fact`

**Keeps one of its node's values in the root's [`Facts`](dialogue.md#facts), so
it outlives the room the node stands in.** A chest opened once stays open when
its room is built again, and a save keeps it with every other fact.

```ruby
# A node class in a game's module, where Components is RGame::Engine::Components.
class Chest < Engine::Node2D
  def initialize(key: nil, **)
    super(**)
    @kept = add_component(Components::Fact.new(key:, default: 'closed'))
  end

  def _enter_tree = @state = @kept.value.to_sym

  def open = @kept.value = 'open'
end
```

- **Construct:** `Fact.new(default: nil, key: nil, part: nil)`. `default` is
  what `value` reads for a fact never set. It must be a value `Facts` holds, so a
  Symbol raises `TypeError`, and so does a `key:` or a `part:` that is not a
  Symbol.
- **The key** is `key:` when the node passes one, as a node built in code does.
  A node a map built passes none. Its key is then `:"<tilemap id>#<object id>"`,
  made from its [`Node2D#map_object_id`](internals.md#mapbuilder--a-node-from-a-maps-object)
  and the scene's [`TileWorld`](#tileworld), such as `:"map/town.tmx#7"`. A
  `part:` joins the key after a dot: `:"map/town.tmx#7.x"`, or `:"crate.x"`.
- **Several values take one `Fact` each**, each with its own `part:` and a slot
  of its own: `add_component(Fact.new(part: :x, default: x), as: :x)`.
- **Lifecycle:** `_attach` finds the root's `Facts` and makes the key, once, so a
  node moved into another room keeps its key. It raises `ArgumentError` for a
  node with neither a `key:` nor a `map_object_id`. It raises `KeyError` when
  there is no `Facts`, or no `TileWorld` to make a map's key from.
- **`key`, `value` and `value=`.** `value` is the fact, or `default` for a fact
  never set. `value=` writes the fact as `facts[key] = value` does, so `Facts`
  emits `on_changed` and calls its watchers. All three raise before the node
  first enters a tree: read the value in `_enter_tree` or later.
- **A designer's key comes through the node**, as any value for a component
  does. The class tags `@param fact [Symbol]` and passes it on as `key:`.
- **A read allocates nothing**, and neither does writing the value a fact holds
  already.

### `FeetCollider`

**A [`BoxCollider`](#boxcollider) whose rectangle is the node's feet**: centred
across the node's origin, with its bottom edge on it. A top-down
character should collide with this shape. A 16×22 hero occupies the 12×6 patch
under them, not the whole sprite, so their head does not bump a wall a tile away. In
every other respect it is a `BoxCollider`: same registration, same signals, same
mixing with circles. `get_component(BoxCollider)` finds it.

- **Construct:** `FeetCollider.new(width:, height:, layer: :default)`, the feet box
  size in px. It takes no sprite size and no offsets. A 12×6 box has
  `offset_x: -6.0` and `offset_y: -6`.
- **Geometry:** the box is right from construction and never reads the node's
  size. [`Sprite`](#sprite) and [`AnimatedSprite`](#animatedsprite) stand on the
  origin with their default `:bottom` anchor, so the box sits under the picture
  whatever size it is. A picture drawn with another anchor needs a plain
  [`BoxCollider`](#boxcollider) with offsets instead. Assigning `box =` lets a
  pooled entity retune its shape on reset.
- **Everything else:** as [`BoxCollider`](#boxcollider): `aabb_*`, `cx` and `cy`,
  `overlap?`, `on_hit` and `on_separated`, and registration with the scene's
  [`CollisionWorld`](#collisionworld) when one exists.

A blocked [`CharacterBody`](#characterbody) resolves its steps against this same
shape, so one component carries the feet box for both jobs.
`examples/collision_tiles` mounts no `CollisionWorld` at all, and uses the collider
only as the rectangle a step may not push past.

```ruby
add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
feet = add_component(RGame::Engine::Components::FeetCollider.new(
  width: 12, height: 6, layer: :hero
))
feet.on_hit { |other| take_damage if other.layer == :spike }
```

### `Footing`

**What the node stands on, and the fall when that is nothing.** It watches the
centre of the node's [`BoxCollider`](#boxcollider) box against the floor the
scene's [`TileWorld`](#tileworld) describes, and drops the node into a gap it walked
into. A tile of class `gap` makes a gap ([Gaps](tile_maps.md#gaps)).

```ruby
hero.add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
hero.add_component(RGame::Engine::Components::Hop.new(peak: 18, duration: 0.5))
hero.add_component(RGame::Engine::Components::Footing.new(coyote: 0.1))
```

- **Construct:** `Footing.new(coyote: 0.1, fall: 0.4)`, both in seconds. `coyote`
  must be 0 or more, and `fall` positive, or it raises `ArgumentError`.
- **Lifecycle:** `_attach` raises when the node has no `BoxCollider` or the scene
  no `TileWorld`. `_detach` leaves the node's platform and ends a fall under way.
- **State:** `standing?` says whether the centre of the box is on the floor.
  `coyote_left` is the coyote time left: `coyote` while standing, counting down off
  the floor, and 0 in the air or falling. `falling?`, and `coyote` and `fall`.
  `coyote=` changes the coyote time, and refuses a negative number. `platform` is
  the [`Platform`](#platform) the node rides, or `nil`.
- **Signal:** `on_fell` fires once as the node starts to fall, before it shrinks.
  That is where a game takes a life.

**A node in the air never falls.** A node whose [`Hop`](#hop) is `airborne?`
crosses a gap, and one that lands on a gap falls on the tick it lands. `Footing`
finds the node's `Hop` on its first update, so a `Hop` added after it still counts.

**Coyote time lets a hop start just past the edge.** A node that walks off the
floor falls once it has been off it for more than `coyote` seconds. At 0.1 s and
60 ticks a second, a hop pressed in any of the six ticks after the step off still
crosses. That holds with the `Footing` added after the node's mover. Added before
it, the `Footing` sees the step off a tick later, and the window runs seven ticks.
`coyote: 0` drops the node on its first tick off the floor.

**A node rides the [`Platform`](#platform) under it.** Where the centre of the box
stands on a platform over a gap, the node boards it, in the air or not. The platform
then carries it by every step it takes. The carry goes through the node's
[`Mover`](#mover), so its own `blocked_by:` still stops it, or straight onto the
node when it has none. The node leaves as its centre leaves the platform, as it
falls, and as it leaves the tree. `platform` is the one it rides, or `nil`.
`Footing` finds the node's `Mover` on its first update, as it finds the `Hop`.

**A fall stops the node and shrinks it into the gap.** The node is suspended, and
its [`scale`](scene_graph.md#scale) runs from 1 to 0 over `fall` seconds, toward
its origin, where it stands. A node with a [`Respawn`](#respawn) then comes back
on its respawn point, and any other node is freed. The fall runs from a helper node `Footing` adds beside the
falling one, so it pauses when the world around the node is paused. A node taken
out of the tree mid-fall, through a door or freed, stops falling at once, at
scale 1 and resumed.

**A game decides at each fall whether the node comes back.** The fall looks the
node's `Respawn` up as it ends, not as it starts. So a game that ends on a fall
removes the `Respawn` in `on_fell`, and the node is freed instead:

```ruby
footing.on_fell do
  @lives -= 1
  hero.remove_component(RGame::Engine::Components::Respawn) if @lives.zero?
end
```

### `Grab`

**Holds a [`Pushable`](#pushable) while a button is held, so the node's mover drags
it**: forwards, backwards and sideways. A [`Targeting`](#targeting) that also reads
a button, as [`Interactor`](#interactor) is.

```ruby
hero.add_component(RGame::Engine::Components::CharacterBody.new(speed: 60, blocked_by: %i[tiles crate]))
hero.add_component(RGame::Engine::Components::Grab.new(layer: :crate, range: 24))
```

While `action` is held, it takes hold of the `Pushable` on its `target`'s node, and
keeps that one until the action is let go, even when another comes nearer. It lets
go on the tick the action is released, and when the held node is freed or leaves
the tree. A target with no `Pushable` is not held, and a press with nothing in range
holds nothing.

It hands the crate to the sibling [`Mover`](#mover) as `grabbed`, and the mover
does the moving: see "A mover drags what it holds" there. `Grab` hands it over in
`_control`, and every `_control` in the tree runs before any `update`, so the crate
is in hand for the step that drags it, whatever order the two components were added
in.

- **Construct:** `Grab.new(range:, layer:, action: :grab, policy: :nearest)`. The
  range, layer and policy are `Targeting`'s, measured from the node's origin.
  `:grab` is in [`InputMap.default`](input.md#defaults-and-rebinding) on Left Shift
  and the pad's Y.
- **Lifecycle:** `_attach` raises when the node has no `Mover`. `_detach` lets go.
- **State:** `holding` is the held node, or `nil`. `action` is the action it reads,
  for a prompt.
- **Two players:** it reads the actions of whoever owns the node, so each player
  holds their own crate.

**It is a `Targeting`, as an `Interactor` is.** A node holding either of them beside
another `Targeting` cannot ask `get_component(Targeting)` for one; hold each by name.

### `Hop`

**A jump in a top-down view.** The node's picture rises along a parabola and comes
back down. The node itself stays on the ground, and so does every collider, camera
and child that reads its position.

- **Construct:** `Hop.new(peak:, duration:, action: :jump)`. `peak` is the highest
  the picture rises, in px, reached halfway through `duration` seconds. Both must be
  positive, or the constructor raises `ArgumentError`. `action` names the action
  whose **press edge** starts a hop, so holding it hops once. `action: nil` reads no
  input.
- **State:** `height` (px above the ground now), `airborne?`, `peak`, `duration`.
- **Starting one:** press `action` during `control`, or call `jump`. `jump` does
  nothing while a hop is under way. NPCs and scripts call it.
- **Phase:** `_update(dt)` advances the arc and writes the height to
  [`node.elevation`](scene_graph.md#elevation). [`AnimatedSprite`](#animatedsprite)
  and [`Sprite`](#sprite) draw lifted by it. The arc is an
  [`Engine::Tween`](toolbox.md#tween--a-value-that-moves-over-time) with the
  `:arc` ease, advanced in `update` and never read off a clock, so a paused node
  hangs in the air.
- **Lifecycle:** `_attach` lands the node, so a pooled node reused mid-hop starts
  on the ground.

**The game decides what a hop crosses.** `Hop` knows nothing about tiles or
colliders. A [`CharacterBody`](#characterbody) blocked by a wall stays blocked while
its node is in the air. A [`Footing`](#footing) reads `airborne?`, so a node with
both crosses a gap in the map mid-hop and falls into one it walks into.

```ruby
hop = add_component(RGame::Engine::Components::Hop.new(peak: 18, duration: 0.5))
hop.airborne? # => false — until the :jump action is pressed
```

`examples/jump_topdown` draws the shadow and the feet box that stay on the ground
under the picture.

### `Identity`

**A stable name for one node**, so something outside the tree can refer to it.

```ruby
sheep.add_component(RGame::Engine::Components::Identity.new(id: 7))
RGame::Engine::Components::Identity.of(sheep)   # => 7
```

- **Construct:** `Identity.new(id:)`, with any object; `nil` raises.
- **Read:** `#id`, or `Identity.of(node)`. `of` returns `nil` for a node without an
  identity, and for no node at all.
- **Phase:** none. It holds a value and does nothing per frame.

**Most saving needs no identity.** A scene is a recipe and a save file is state. A
*singular* thing is named by the variable that holds it. *Interchangeable* things
are named by their order in an array. `examples/save_load` restores a dog and a
flock with exactly those two and nothing else. `examples/save_load_ids` needs this
component.

`Identity` covers two cases the others miss:

- **A collection whose members can die.** An array index names nothing once a
  middle member is gone.
- **A reference from one saved thing to another**, such as a dog chasing one
  particular sheep. This case truly forces ids. A collection can be respawned from
  its own records, but a reference into it needs a name for its target.
  `Targeting#target` shows the problem: it holds a *node*, and `Identity.of` turns
  that into something a file can hold.

The game must get two things right; this component does not check them:

- **Ids must be unique** among things that can refer to each other. A duplicate
  restores the wrong object, silently.
- **The id allocator belongs in the save.** A counter that restarts at 1 on load
  reissues ids the restored objects already hold. Save the next id with them.

### `Interactor`

**What the owner would interact with, and the press that does it.** A
[`Targeting`](#targeting) that also reads a button: each `update` it picks the
nearest node in range on its layer, and a press on `action` emits it.

```ruby
hero.add_component(RGame::Engine::Components::Interactor.new(range: 56, layer: :interactable))
    .on_interacted { |target| target.open }
```

- **Construct:** `Interactor.new(range:, layer: :interactable, action: :interact,
  policy: :nearest)`. The range, layer and policy are `Targeting`'s. `action` is
  read from the actions of whoever owns the node, and `:interact` is in
  [`InputMap.default`](input.md#defaults-and-rebinding) on E and the pad's X.
- **State:** `target`, `Targeting`'s, and `action`. Draw a prompt over `target`
  and label it with `player.input_map.button_for(interactor.action, player.device)`.
- **Signal:** `on_interacted(target)` fires once per press, and never while
  `target` is `nil`. There is no signal for a press that reached nothing.
- **Phase:** `_update(dt)` picks the target, `_control(actions)` reads the press.
  A press acts on the target the last `update` chose.

**It is a `Targeting`, so `get_component(Targeting)` matches it too.** A node
holding both cannot be asked for either by class — hold the one you want by
name, which is what `add_component` returns.

**Two players interact independently with no per-player state here.** The
control traversal hands each node the actions of its owner, so two heroes either
side of one chest each press their own button and each reach it.

### `MapTile`

**Draws one tile of the scene's tile map with its bottom centre on the node's
origin, stretched to the node's width and height.** That is how Tiled draws a
tile object, so a tree placed in Tiled can stand in the world as a node and sort
against the actors.

```ruby
# In a scene whose TileWorld holds the map; `actors` is the :actors slot.
tree = actors.add_node(RGame::Engine::Node2D.new(x: 184, y: 312, width: 16, height: 32))
tree.add_component(RGame::Engine::Components::MapTile.new(tile: object.tile, orientation: object.orientation))
```

- **Construct:** `MapTile.new(tile:, orientation: TileMap::Orientation::IDENTITY)`.
  `tile` is the map's own id for the tile and `orientation` how it is turned, as a
  [`MapObject`](tile_maps.md#objects) gives both. `tile` and `orientation` read
  them back.
- **Lifecycle:** `_attach` finds the scene's [`TileWorld`](#tileworld), and raises
  `KeyError` naming it when there is none. The map id comes from it, and so does
  the clock an animated tile shows its frame by, so the tile stops animating when
  the world stops updating.
- **Phase:** `_draw(renderer, view)` calls
  [`renderer.map_tile`](drawing.md#drawing-by-id) with the box standing on the
  origin, and **no angle**: `Node2D#draw` already pushed the node's rotation, so
  the tile turns with its node. A turned or mirrored tile turns inside the box, as
  in Tiled. [`node.elevation`](scene_graph.md#elevation) lifts it, as it lifts a
  [`Sprite`](#sprite).
- **Under the node's other drawing.** It draws at the lowest `z` in the node's
  slot, so a `Sprite` or a `_draw` on the same node draws over the tile, whichever
  was added first.
- **Culled like a `Sprite`.** It skips the draw when the view cannot show its box,
  and a node that never set a size is never culled. The tileset's drawing offset
  can move the tile a few pixels off its box, and the cull does not count it.

### `Mover`

**The base class of every component that moves its node**:
[`CharacterBody`](#characterbody), [`Velocity`](#velocity),
[`PathFollow`](#pathfollow) and [`Pushable`](#pushable). Walking an intent,
integrating a velocity and following a path are three different jobs, so they are
three classes, and a `Pushable` moves only when pushed. They share what happens
*after* a step is computed, and `Mover` holds that part. You never add a `Mover` on
its own.

**A mover declares what stops a step; it does not subclass for it.**
`blocked_by:` lists what a step may not pass through. The default is nothing. Then
the mover writes the node's position directly, and needs **no sprite, no
dimensions, no collider and no system on the scene**.

```ruby
add_component(RGame::Engine::Components::BoxCollider.new(width: 12, height: 12, layer: :crate))
add_component(RGame::Engine::Components::Velocity.new(vx: 90, vy: 40, blocked_by: [:wall]))
```

Three names are reserved, and every other name is a collider layer:

| Name | Resolved against | Stops the step at |
|---|---|---|
| `:tiles` | the scene's [`TileWorld`](#tileworld) | the edge of a solid tile |
| `:bounds` | the scene's [`WorldBounds`](#world) | the edge of the world |
| `:gaps` | the scene's [`TileWorld`](#tileworld) | the edge of the floor, with the centre of the box on the last of it |
| anything else | the scene's [`CollisionWorld`](#collisionworld) | the edge of any `BoxCollider` wearing that layer |

**Each step resolves one axis at a time and takes the most restrictive answer.** A
diagonal held against a wall keeps its free half, so the mover slides. It slides
off a villager exactly as off a fence. A character wants that; a bullet does not,
but needs no separate resolver. `on_blocked` fires on the step the bullet hits, and
a bullet that frees itself there is gone before it slides. A mover that keeps
pushing also keeps its intent: a blocked `Velocity` does not zero its `vx`. A bullet
that bounces reads which axis stopped, and reverses that half of its velocity:

```ruby
velocity = RGame::Engine::Components::Velocity.new(vx: 120, vy: 80, blocked_by: %i[wall bounds])
velocity.on_blocked do |_by, axis|
  velocity.vx = -velocity.vx unless axis == :y
  velocity.vy = -velocity.vy unless axis == :x
end
```

```ruby
add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6, layer: :hero))
add_component(RGame::Engine::Components::CharacterBody.new(speed: 80, blocked_by: %i[tiles npc]))
```

Three rules apply to layer names:

- **An empty layer is not an error.** The declaration says what *may* stop this
  mover, not what does.
- **A mover is never stopped by its own collider.** A crowd of villagers can all
  declare `blocked_by: [:npc]` while each wears `:npc`.
- **Blocking is box against box.** A [`CircleCollider`](#circlecollider) on a
  declared layer reports contacts as usual and stops nothing.

`blocked_by` and [`on_hit`](#boxcollider) answer different questions: what may I
walk through, and what am I touching? They are not alternatives. A blocked pair
ends up *touching*, and `CollisionBox.overlap?` is half-open, so a blocked step
reports no contact. An entity that must both stop and react needs both.

**The mover reports what stopped a step.** `on_blocked` fires on the step something
starts stopping the mover, and `on_unblocked` on the step it stops doing so. Each
fires once per blocker. `BoxCollider` reports contacts with the same pair of edges,
here aimed at what a step could not pass. A spiky ball that both stops the player and
hurts them is thus two ordinary components, not a hand-written `on_hit`.

```ruby
mover.on_blocked { |by| take_damage if by.layer == :spike }
```

The listener receives the blocker and reads `by.layer` and `by.node`, whatever kind
stopped the step. A collider answers its own layer and owning node. The map's solid
tiles answer `:tiles` and `nil`. The world's edge answers `:bounds` and `nil`, and
the floor's edge `:gaps` and `nil`. The second argument is the stopped axis: `:x`, `:y` or `:both`. A listener that names
only the blocker never sees it. Three details matter:

- **Standing still counts as unblocking.** The set of blockers advances once per
  `update`. A mover that stops pushing records nothing that step, so `on_unblocked`
  fires. The mover has not moved; it has stopped *being stopped*.
- **Once per blocker, not once per axis.** A step stopped on both axes by one thing
  fires once, with `:both`. Only the map produces that, with a diagonal into an
  inside corner of solid tiles. A step resolves X first, and once X is flush, a
  single collider no longer overlaps on Y. A step stopped on X by the map and on Y
  by a villager fires twice, each with its own axis. Starting edges come before
  ending ones, the order `CollisionWorld` uses for contacts. A blocker that stops X
  on one step and Y on the next stood in the way throughout. It fires once, with the
  axis it first stopped. `on_unblocked` carries no axis for the same reason.
- **A blocked pair is not a contact**, as the paragraph above explains. The spiky
  ball listens to `on_blocked`; a trigger area listens to `on_hit`.

**`:bounds` must be declared.** A mover that does not name it leaves the world.
Stopping at the edge is one of three responses to it, beside
[`ScreenWrap`](#screenwrap) and [`DespawnOffscreen`](#despawnoffscreen), and a node
may carry only one. Declaring `:bounds` beside either raises at attach. A game whose
entities wrap or despawn at the edge gives their movers no `:bounds`.
`blocked_by?(name)` answers whether a mover declared a name.

**`:gaps` keeps a mover on the floor.** A cell holding a
[gap tile](tile_maps.md#gaps) has no floor, except where a
[`Platform`](#platform) covers it, and a step may not take the centre of the
mover's box off the floor. The box may overlap a gap, so a walker stands right at
the edge. A step that starts with the centre off the floor is free, so a node that
lands in a gap is not held there. [`Engine::GapBlockers`](internals.md#gapblockers--the-edge-of-the-floor-as-a-blocker-source)
does the resolving, over [`TileWorld#floor_at?`](#tileworld).

```ruby
add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6, layer: :npc))
add_component(RGame::Engine::Components::CharacterBody.new(speed: 30, blocked_by: %i[tiles gaps]))
add_component(RGame::Engine::Components::Footing.new)
```

**`:gaps` needs a [`Footing`](#footing).** A platform moves the floor under a
mover, and the `Footing` is what rides it. A mover declaring `:gaps` on a node with
no `Footing` raises at attach, instead of being left behind and walking free.

**A mover declares what it pushes, beside what stops it.** `pushes:` names collider
layers a step moves instead of stopping at. Every layer in it must also be in
`blocked_by:`, since a step passes through anything else and would push nothing; the
constructor raises `ArgumentError` for one that is not, and for `:tiles`,
`:bounds` or `:gaps`.

```ruby
add_component(RGame::Engine::Components::CharacterBody.new(speed: 80, blocked_by: %i[tiles crate],
                                                           pushes: [:crate]))
```

A step stopped by a collider on a pushed layer whose node holds a
[`Pushable`](#pushable) moves that node by what is left of the step, on the stopped
axis. The pushed node resolves the push against its own `blocked_by:`. The pusher
then resolves the rest of its step again, so it follows as far as the crate went:

- **A crate that goes the whole way stops nothing**, and the pusher reports nothing.
- **A crate that goes part of the way, or none**, stops the pusher flush against it,
  and `on_blocked` reports the crate's collider.
- **A crate on a pushed layer with no `Pushable`** stops the step as `blocked_by:`
  alone would.

A mover that declares `pushes:` resolves X and then Y as two moves, so a crate it
met on X has moved before Y is resolved. One that declares none takes a single move,
exactly as without the keyword. `pushes?(name)` answers whether a mover declared a
layer.

A `Pushable` may declare `pushes:` too, which is how a crate pushes a crate. One step
moves at most `Mover::PUSH_DEPTH` crates in a row, 4; the next one stops the chain as a
wall would. A pushed node never pushes the node that pushed it.

**A mover drags what it holds.** `grabbed` is a `Pushable` the mover moves with every
step, or `nil`; [`Grab`](#grab) sets it. On each axis the crate moves first, passing
through the mover, and the mover follows as far as the crate went, passing through
the crate. If the mover then went less far, the crate comes back to match. So the
two always move together:

- **Towards the crate** is a push, with or without `pushes:`.
- **Away from it** is a pull: the crate follows into the space the mover leaves.
- **A crate that cannot move holds the mover still**, and `on_blocked` reports the
  crate's collider. A mover backed into a wall holds the crate still, and reports
  the wall.

**A platform's mover carries its riders.** A mover whose node holds a
[`Platform`](#platform) measures the node's world position around each step, and
hands the difference to the platform. The platform moves every node standing on it
by that much. So a `PathFollow` that places its node carries as well as a
`Velocity`. The mover finds the `Platform` on its first update, so either may be
added first.

A rider moves through its own mover's `ride(dx, dy)`, as far as its own
`blocked_by:` allows. A wall therefore scrapes a rider off a platform. Being carried
is not a step of the rider's: it fires no `on_blocked` and leaves `stopped?` as it
was.

**The shape has one owner, and it is not the mover.** A blocked step resolves
against the sibling [`BoxCollider`](#boxcollider)'s rectangle;
[`FeetCollider`](#feetcollider) suits a walking character. You give the box once,
to the component that *is* a shape. The same rectangle stops the step and reports
contacts. Reassigning `collider.box` retunes both, and no component hands data to
another.

- **Construct:** every mover takes `blocked_by: []` and `pushes: []`. A bare Symbol
  also works (`blocked_by: :tiles`).
- **Lifecycle:** `_attach` resolves the declarations and builds the mover's own
  [`CollisionSystem`](internals.md#collisionsystem--move-an-actor-against-its-blockers)
  from the sources it finds. It **raises** for anything missing. It checks the
  node's collider first, then the scene's `TileWorld` for `:tiles` and `:gaps` and the
  node's `Footing` for `:gaps`, its `WorldBounds` for `:bounds`, and its
  `CollisionWorld` for any layer name. Falling back to free
  movement would look like a collision bug, caused by a scene three files away that
  never mounted the system.
- **Signals:** `on_blocked` fires with what stopped the step and the stopped axis.
  `on_unblocked` fires with what stopped stopping it:
  `mover.on_blocked { |by, axis| ... }`, `mover.on_unblocked { |by| ... }`.
- **Phase:** `_update(dt)` opens the step, calls the subclass's private
  `take_step(dt)`, reports the edges, and carries a platform's riders. Do not
  override it; it guarantees that no mover forgets an edge. `Pushable` replaces it,
  because it has no step of its own, so a pushed platform carries nobody.
- **State:** `stopped?` is true when something cut this update's step short, on
  either axis. It is false after an update that took no step, and always false for
  a mover with nothing declared.
- **Heading:** `heading_x` and `heading_y` give the step's direction, each axis in
  -1..1, and `0, 0` when the mover is not trying to move.
  [`AnimatedSprite`](#animatedsprite) faces by it. It is a facing, not a velocity: a
  mover pressed into a wall still heads into it. A [`CharacterBody`](#characterbody)
  answers its intent. A [`Velocity`](#velocity) answers its velocity, scaled so the
  larger axis is ±1. A [`PathFollow`](#pathfollow) answers the unit direction of its
  current segment. Reading it allocates nothing.
- **Seam:** `apply_move(dx, dy)` lands a step. With nothing declared, it writes
  straight onto the node. With declarations, it goes through the resolver. A mover
  may call it several times in one step, and still reports the edges once.
- **Actor adapter:** when blocked, the mover passes *itself* to
  [`CollisionSystem#move`](internals.md#collisionsystem--move-an-actor-against-its-blockers).
  It answers `collision_box` from the collider, and `x`, `y`, `x=` and `y=` from the
  node **in world space**, the frame the tile grid and broadphase use. Writing back
  translates the node's local position. That is exact under an unrotated ancestor
  chain and approximate under a rotated one. A spinning thing wants a circle anyway.

### `Navigator`

**A [`PathFollow`](#pathfollow) that plans its own paths.** `go_to(world_x, world_y)`
finds a route over the scene's [`TileWorld`](#tileworld) to the tile containing that
point. It smooths the route into as few straight segments as the node's collider can
travel, and walks it.

```ruby
# `actors` is the :actors slot TileMapLayer.mount returned, in a scene with a TileWorld mounted.
hero = RGame::Engine::Node2D.new(x: 40, y: 40)
hero.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
hero.add_component(RGame::Engine::Components::FeetCollider.new(width: 12, height: 6))
navigator = hero.add_component(RGame::Engine::Components::Navigator.new(speed: 80, blocked_by: [:tiles]))
actors.add_node(hero)

navigator.go_to(200.0, 360.0) # => true — the hero sets off; false when there is no route
```

- **Construct:** `Navigator.new(speed:, blocked_by: [], pushes: [])`. It takes no `path:` and
  stays idle until the first `go_to`. [`Mover`](#mover) decides what may stop it. A
  navigator that should stay off solid tiles while walking declares `:tiles`, like
  any mover.
- **Lifecycle:** `_attach` raises when the scene has no `TileWorld` to plan over.
  It also looks up the node's `BoxCollider`, if any. Calling `go_to` before the
  node is in the tree raises too.
- **`go_to(world_x, world_y)`** plans from where the node stands and starts walking
  at once, from exactly there. A navigator halfway along one route turns onto the
  next without a jump. It returns `true`, or `false` when no route exists: the
  target is solid, outside the map, or in a part the node cannot reach. On `false`
  nothing changes, and a walk under way continues. `on_finished` never fires inside
  `go_to`, even for a target in the node's own cell; it fires on the next step.
- **The anchor.** The centre of the collider's box reaches the target: the feet,
  for a [`FeetCollider`](#feetcollider). On a node without a collider, the origin
  does. The walk ends with the anchor on the centre of the target tile.
- **Readers:** `cells` returns the route as the search found it,
  `[[col, row], ...]` from start tile to target, or `nil` before the first `go_to`.
  Use it to draw the route. `path` returns the smoothed
  [`Path`](toolbox.md#path--a-walkable-polyline) the node walks, in the node's
  coordinates, starting where the node stood.
- **It can walk every route it plans.** Smoothing keeps a straight segment only if
  the map's own blocker source says the collider's box can travel it. That source is
  `TileWorld#blockers`, the one that stops a mover declaring `:tiles`, queried
  through [`TileBlockers#travel?`](internals.md#tileblockers--the-tile-grid-as-a-blocker-source).
  A test on tiles alone would keep a diagonal past a tree's corner that a point
  clears but a feet box clips. A `PathFollow` held on a corner does not slide off;
  it would stand there. `travel?` holds for a walker taking steps under a quarter
  tile: 240 px/s at 60 ticks a second on 16 px tiles.
- **One component, not a search beside a walker.** A navigator *is* a `PathFollow`,
  so no component hands a route to a sibling. There is no wiring to forget, and the
  order you add components in does not matter.
- **Colliders up to one tile only.** Pathfinding for a collider wider or taller than
  a tile is unsupported. Smoothing assumes the box fits the cells the search found.
  `go_to` raises `ArgumentError`, naming the box and the tile size, instead of
  planning a route such a walker could stall on. A collider of exactly one tile
  works.
- **It waits; it does not replan.** It plans against the map and knows only the
  map. A navigator declaring other collider layers waits behind anything standing on
  its route, as a `PathFollow` does, and resumes when the way clears. To go around
  instead, call `go_to` again. A route also keeps to the cells that were solid when
  `go_to` ran. A cell an [`OccupiesCell`](#occupiescell) makes solid later stops a
  navigator declaring `:tiles` there, until `go_to` is called again.
- **Cost.** Planning runs when `go_to` is called, never per frame, and allocates. It
  takes about 0.2 ms for a 65-tile route across a 60x40 map. A 117-tile route across
  120x90 takes 1.3 ms, 1 ms of it in the search. The walk itself is `PathFollow`'s,
  and allocates nothing.
- **Spaces:** it plans in world space and walks in the parent's. The two agree under
  an unrotated ancestor chain, the same limit a blocked [`Mover`](#mover) has.
- **Example:** in `examples/pathfinding`, a tile cursor picks the target. The scene
  draws `cells` as a dot per tile and `path` as lines. It adds the feet box's centre
  back to each waypoint so the lines sit on the dots.

### `OccupiesCell`

**Makes one cell of the scene's [`TileWorld`](#tileworld) solid while its node is in
the tree**, for a crate, a closed door or a statue.

```ruby
# `actors` is the :actors slot TileMapLayer.mount returned, and `world` the scene's TileWorld.
crate = Crate.new(x: world.cell_x(12), y: world.cell_y(7))
crate.add_component(RGame::Engine::Components::OccupiesCell.new(col: 12, row: 7))
actors.add_node(crate)
world.solid?(12, 7) # => true
```

- **Construct:** `OccupiesCell.new(col:, row:)`. `col` and `row` read it back.
- **Lifecycle:** the cell turns solid when the node enters the tree, or when the
  component is added to a node already in it. It turns back when the node leaves the
  tree or the component is removed. `_attach` raises when the scene has no
  `TileWorld`, and raises `ArgumentError` naming the cell and the map's size for a
  cell outside the map.
- **One store.** The cell is solid in the store `TileWorld#blockers`, `#nav_grid`
  and `#solid?` all read. A [`Mover`](#mover) declaring `:tiles` stops at it, and
  reports it as `:tiles` with no node. A route [`Navigator#go_to`](#navigator) plans
  after it arrives goes around it.
- **Counted.** Two occupants of one cell keep it solid until both have left. A cell
  the map made solid stays solid when its occupant leaves.
- **It does not place the node.** Where a node draws depends on where its origin
  is, which only its class knows. Place it with `TileWorld#cell_x` and
  `#cell_centre_x`, as the example above does.
- **The cell is fixed.** Something that moves from cell to cell is a body with a
  collider. A mover that names the collider's layer in `blocked_by` stops against it.

### `Particles`

**Sparks, embers and dust: small squares that fly out from a point, fall,
change colour as they age, and vanish.**

```ruby
EMBER = RGame::Util::ColorRamp.new(RGame::Util::Color.new(255, 240, 160),
                                   RGame::Util::Color.new(255, 120, 0, 0))

# In a scene's initialize.
sparkles = add_node(RGame::Engine::Node2D.new)
@sparks = sparkles.add_component(RGame::Engine::Components::Particles.new(
  limit: 48, lifetime: 0.4..0.7, speed: 30.0..80.0,
  direction: -Math::PI / 2, spread: Math::PI, gravity: 90.0,
  size: 3, ramp: EMBER, blend: :add
))

@sparks.burst(16, x, y)   # 16 at once from (x, y)
@sparks.rate = 40         # a stream from the node's origin, 40 a second
```

A particle is a plain object in an [`Engine::Pool`](toolbox.md#pool--reuse-dont-allocate),
not a node. The component builds `limit` of them when it is made, so bursting,
streaming, stepping and drawing allocate nothing after that.

- **Construct:** `Particles.new(limit:, lifetime:, speed:, ramp:, direction: -Math::PI / 2,
  spread: Math::PI, gravity: 0.0, size: 2, blend: :alpha, rng: nil)`.
  - `limit` is how many can be alive at once, a positive Integer.
  - `lifetime`, in seconds, and `speed`, in pixels a second, are each a number
    or a Range to draw one from. A lifetime must be above 0, and a speed at
    least 0.
  - `direction` and `spread` are radians. 0 is right, `-Math::PI / 2` is up,
    and each particle heads up to `spread` either side of `direction`, so
    `Math::PI` is every way.
  - `gravity` is added to each particle's downward speed, in pixels a second
    per second.
  - `size` is the side of each square, in pixels.
  - `ramp` is a [`Util::ColorRamp`](values.md#rgameutilcolorramp). A particle
    draws in `ramp.at(age / lifetime)`, so a ramp to alpha 0 fades it out.
  - `blend` is a mode [`renderer.blended`](drawing.md#blending-and-fading)
    takes. `:add` makes sparks glow over what is behind them.
  - `rng` is what the particles draw from: anything answering `rand` as
    `Random#rand` does. With none, they draw from the root's
    [`RandomSource`](#randomsource), so a seeded game places every particle the
    same each run.

  A bad value raises `ArgumentError`, and a `ramp` that is not a `ColorRamp`
  raises `TypeError`.
- **`burst(count, x = 0.0, y = 0.0)`** places `count` particles at (x, y), in
  the node's local space. Past `limit` it places what fits, drops the rest, and
  returns how many it placed. With no `rng:`, it raises until the node is in the
  tree, where the component finds the root's `RandomSource`.
- **`rate=`** streams that many a second from the node's origin. It carries the
  fraction from tick to tick, so 40 a second at 60 ticks is 2 in every 3. 0, the
  default, streams none. A negative rate raises `ArgumentError`.
- **`live`** is how many are alive. `limit`, `rate` and `blend` read back what
  was set.
- **Phase:** `_update(dt)` adds gravity to each particle's downward speed,
  moves it, and frees it once its age reaches its lifetime. Then it streams.
  `_draw` draws every particle as a square centred on it, inside
  `renderer.blended(blend)`, and draws nothing while none is alive.
- **Lifecycle:** with no `rng:`, `_attach` finds the root's `RandomSource`, and
  raises `KeyError` naming it when the root has none. `_detach` frees every
  particle, so a node that leaves the tree enters again with none.

Particles live in the node's local space and move with it. An emitter that
must outlive what it sparkles for goes on a node of its own. A coin that frees
itself when taken would take its sparkles with it, so the scene holds one
`Particles` and each coin's `on_collected` bursts it:

```ruby
coin.add_component(RGame::Engine::Components::Collectable.new(by: :hero))
    .on_collected { @sparks.burst(8, coin.world_x, coin.world_y) }
```

A component draws in its node's slot, so put that node where the sparks should
show, such as a tile map's actors slot, among the characters.
`examples/effects` streams embers from a torch and bursts sparkles on a key.

### `PathFollow`

**Walks the owning node along an
[`RGame::Engine::Path`](toolbox.md#path--a-walkable-polyline) at constant speed**,
and emits `on_finished` at the last waypoint. Hook whatever should happen on arrival
to that signal.

- **Construct:** `PathFollow.new(speed:, path: nil, loop: false, blocked_by: [], pushes: [])`.
  [`Mover`](#mover) decides what may stop it. Without a path, the follower is idle:
  it moves nothing, never finishes, and heads nowhere until it receives one.
- **Lifecycle:** `_attach` restarts the walk. It returns to the first waypoint,
  clears progress, and *places* the node there regardless of declarations. A pooled
  follower acquired and added again starts a fresh walk.
- **A new route:** `follow(path)` restarts with a different path, at any time. A
  finished follower walks it and emits `on_finished` again. A follower halfway along
  another route drops that route at once and is placed on the new first waypoint. You
  may call it from an `on_finished` handler. `follow(nil)` stops the walk where it
  stands. `path` returns the route being walked.
- **To the end at once:** `finish` places the node on the last waypoint and emits
  `on_finished`, whatever stands in the way, as skipping a
  [cutscene](#cutscene) does. It does nothing for a finished or idle follower.
  A [`Navigator`](#navigator) finishes the same way, at the end of its route.

  ```ruby
  out  = RGame::Engine::Path.new([[40.0, 100.0], [200.0, 100.0]])
  back = RGame::Engine::Path.new([[200.0, 100.0], [40.0, 100.0]])
  patrol = RGame::Engine::Components::PathFollow.new(path: out, speed: 40)
  patrol.on_finished { patrol.follow(patrol.path.equal?(out) ? back : out) }
  ```
- **A walk that never ends:** `loop: true` goes round a closed path for good, and
  back and forth along an open one. A step that overshoots an end carries on past
  it, so the pace holds. A looping follower never finishes: `on_finished` never
  fires and `finish` does nothing. `looping?` says which kind it is. A
  [`Platform`](#platform) shuttling across a chasm walks this way.

  ```ruby
  shuttle = RGame::Engine::Components::PathFollow.new(path: route, speed: 40, loop: true)
  ```
- **Heading:** the unit direction of the current segment, the way the walk goes
  along it. It is computed as the walk enters a segment or turns round. It is
  `0, 0` while idle, after finishing, and along a zero-length segment.
- **Signal:** `on_finished` fires once, without payload, at the path's end:
  `follow.on_finished { node.queue_free }`. `finished?` reports the same state.
- **Phase:** `_update(dt)` advances `speed * dt`, crosses as many segments as one step
  spans, and interpolates the node's position. It allocates nothing. With nothing
  declared, it places the node on that point.
- **When blocked, the walk waits.** With declarations, the follower moves the node
  to that point through `apply_move`. A step stopped short **does not advance the
  walk**: progress returns to where the step began. A follower held for a second
  arrives a second late instead of racing ahead once free. `on_finished` never fires
  for a walker still standing in front of its blocker.
- **A held follower does not slide.** The step's free axis still moves, but each
  step aims at the same path point again. A follower pressed diagonally against a
  wall comes to rest, unlike a [`Velocity`](#velocity), which slides. To get around
  an obstacle, replan the path.

### `Platform`

**Makes its node's box floor over the map's gaps**, for a raft, a lift or a slab of
stone over a chasm.

```ruby
raft.add_component(RGame::Engine::Components::BoxCollider.new(width: 32, height: 16, layer: :platform))
raft.add_component(RGame::Engine::Components::Platform.new)
raft.add_component(RGame::Engine::Components::PathFollow.new(speed: 40, path: route, loop: true))
```

- **Construct:** `Platform.new`.
- **Lifecycle:** `_attach` registers with the scene's [`TileWorld`](#tileworld),
  and raises when the node has no [`BoxCollider`](#boxcollider) or the scene no
  `TileWorld`. `_detach` lets every rider go and leaves the `TileWorld`, so the
  cells under the box are gaps again.
- **The floor:** wherever the box covers a gap cell, `TileWorld#floor_at?` is
  true. A [`Footing`](#footing) stands there instead of falling, and a
  [`Mover`](#mover) declaring `:gaps` walks onto the box from the ground and stops
  at its edge. `covers?(x, y)` says whether a world point is on the box: its left
  and top edges are, its right and bottom edges are not, as with a cell.
- **It moves with its node.** `TileWorld` reads the box each time it asks, so a
  platform a [`PathFollow`](#pathfollow) walks takes its floor with it.
- **It carries whoever stands on it.** Boarding is the rider's question: a node with
  a [`Footing`](#footing) boards the platform under the centre of its box. Carrying
  is the platform's: the [`Mover`](#mover) that moves its node carries every rider
  by exactly its own step, front first along the step, so no rider runs into one not
  yet moved. A rider moves by that step whichever of the two updates first. A node
  that boards on a tick the platform has already moved rides from the next one.
- **State:** `riders`, the `Footing`s standing on it now. `collider`, the box, and
  `left`, `top`, `right` and `bottom`, its edges in world pixels.
- **Example:** `examples/moving_platforms` shuttles a raft across a chasm, read
  from a polyline object on the map.

### `PlayerController`

**Drives a `CharacterBody` sibling from two input axes**: direct 8-way walking, no
inertia (unlike `ThrustController`). It neither knows nor cares whether the body is
blocked.

- **Construct:** `PlayerController.new(x_axis: :move_x, y_axis: :move_y)`.
- **Lifecycle:** `_attach` looks up the node's `CharacterBody` with
  `require_sibling`.
- **Phase:** `_control(actions)` copies the two axes into the body's intent.
- **Example:** `examples/walk`.

### `Pool`

**Wraps an [`RGame::Engine::Pool`](toolbox.md#pool--reuse-dont-allocate) of nodes
and runs its tree bookkeeping in the frame tick.** A scene that recycles entities,
such as enemies or projectiles, writes no acquire/add/reclaim code. It calls `spawn`
and the ordinary `queue_free`. Pooled nodes are **normal children** of the owner, so
the scene's traversal updates and draws them. This component manages only pool
membership.

- **Construct:** `Pool.new { Enemy.new(...) }`. The factory builds a blank node. Add
  the component with a name (`as:`) when a node needs several pools.
- **Spawn:** `pool.spawn` takes a node, recycled or newly built, and adds it as a
  child. `pool.spawn { |n| n.reset(...) }` runs the block to re-initialise the node
  *before* it enters the tree, so `_attach` sees the reset state. Projectiles need
  that order.
- **Reclaim:** `_update(dt)` returns every freed pooled node to the free list, and
  detaches any still attached. Despawning is thus `node.queue_free` from anywhere;
  the pool recycles the node with no game-side wiring. It allocates nothing in steady
  state.
- **State:** `size` counts the live pooled nodes, and `empty?` is true once all are
  reclaimed. A scene reads it to tell when a wave is cleared.

### `Pushable`

**A [`Mover`](#mover) that moves only when something pushes it**: a crate, a boulder,
a cart. A mover declaring its layer in `pushes:` moves it by what is left of a step
it stopped, and it resolves that push against its own `blocked_by:`. So a crate stops
against a solid tile, a wall collider or another crate, and its pusher stops flush
behind it.

```ruby
crate = RGame::Engine::Node2D.new(x: 120, y: 80)
crate.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: :crate))
crate.add_component(RGame::Engine::Components::Pushable.new(blocked_by: %i[tiles crate hero]))

hero.add_component(RGame::Engine::Components::CharacterBody.new(speed: 80, blocked_by: %i[tiles crate],
                                                                pushes: [:crate]))
```

**Put the pushers' layer in the crate's `blocked_by:`.** Two players pushing one crate
from opposite sides then hold it still, and both stop against it. A crate that heroes
do not stop is pushed into the hero on the far side, and neither stops the other
while they overlap. Two players pushing side by side move it as far as one would.

- **Construct:** `Pushable.new(blocked_by:, pushes: [])`. `blocked_by:` is what stops
  the crate. `pushes:` makes it push the crates behind it, as for any
  [`Mover`](#mover).
- **Lifecycle:** `_attach` raises when the node has no
  [`BoxCollider`](#boxcollider), which is what a pusher runs into, or the scene has
  no [`CollisionWorld`](#collisionworld), which is where a pusher finds it.
- **Push:** `push(dx, dy, by: nil, depth: 1)` moves the node as far as `blocked_by:`
  allows. Movers call it through `pushes:` and `grabbed`, and a game may call it
  directly, for a crate a spell shoves. `by` is the node pushing or pulling, which
  the crate neither pushes back nor is stopped by.
  It re-indexes the collider at once, so a mover resolving later in the same step
  meets the crate where it now is.
- **State:** `pushed_x` and `pushed_y` say how far the last push moved the node, in
  world pixels. [`Mover#stopped?`](#mover) is true when something cut the last push
  short, until the crate's next update. `collider` is the `BoxCollider` a pusher
  runs into.
- **Signals:** `on_blocked` and `on_unblocked`, as for any mover. A crate's pushes
  arrive during other movers' updates, so it counts blockers from one of its own
  updates to the next. A crate held against a wall reports it once, whatever order
  the crate and its pusher update in.
- **Heading:** `0, 0`. A crate faces nowhere.

### `RandomSource`

**The game's one seeded source of random numbers**, a system on the root.
`RGame::Game` mounts one, seeded from `seed:` or `RGAME_SEED`; see
[`seed:`](game.md). Every node finds it without being handed it:

```ruby
require 'rgame'

root = RGame::Engine::Node2D.new
root.add_component(RGame::Engine::Components::RandomSource.new(seed: 42))
walker = root.add_node(RGame::Engine::Node2D.new)
root.enter_tree

random = walker.system!(RGame::Engine::Components::RandomSource)
random.seed                                    # => 42
random.rand(3) == Random.new(42).rand(3)       # => true — the sequence Random.new(42) gives
```

- **Construct:** `RandomSource.new(seed:)`, with an Integer seed.
- **`rand(...)`** takes what `Random#rand` takes: nothing for a Float in
  [0, 1), an Integer for one below it, or a Range. It allocates nothing beyond
  what `Random#rand` allocates. `Array#sample(random:)` and
  `Array#shuffle(random:)` take the source as it is.
- **`seed`** reads back the seed it was built with, so a run can be repeated.

`WanderController` and `Particles` draw from it unless they are handed an
`rng:`. One source serves the whole game, so a scene entered a second time
continues the sequence rather than starting it again.

### `Respawn`

**Where a node comes back after a fall, and the flash that shows it has.** A
[`Footing`](#footing) whose node has one calls `respawn` at the end of a fall,
instead of freeing the node.

```ruby
hero.add_component(RGame::Engine::Components::Footing.new(coyote: 0.1))
hero.add_component(RGame::Engine::Components::Respawn.new(flash: 1.0))
```

- **Construct:** `Respawn.new(flash: 1.0)`, in seconds. It must be 0 or more, or it
  raises `ArgumentError`. `flash: 0` flashes nothing.
- **The point:** `point_x` and `point_y`, in world pixels. The first attach records
  where the node stands. Later attaches, such as a door moving the node to another
  room, keep the point. `set_point(x, y)` moves it and returns the `Respawn`, and a
  [`Checkpoint`](#checkpoint) calls it.
- **`respawn`** places the node on its point and starts the flash. A game may call
  it with no fall before it.
- **Signal:** `on_respawned` fires once the node stands on its point, as the flash
  starts.
- **Lifecycle:** `_attach` checks the point, as below. `_detach` stops a flash and
  gives the opacity back.

**The point stands on ground.** With a [`TileWorld`](#tileworld) on the scene,
each attach raises `ArgumentError` for a point whose cell is a gap, and so does
`set_point` once attached. A gap under a [`Platform`](#platform) counts: the platform
moves on, and a node brought back there would fall again as soon as it stood. A
refused `set_point` keeps the point it had. A node that starts on a platform takes
a point on ground before it is added, and its first attach checks that point
instead:

```ruby
hero.add_component(RGame::Engine::Components::Respawn.new.set_point(96.0, 248.0))
```

With no `TileWorld`, a `Respawn` checks nothing.

**The node comes back working.** Its controls answer from the tick it lands, and a
[`CameraFollow`](#camerafollow) cuts to it. The flash only shows where it came back:
`_update` blinks the node's [`opacity`](scene_graph.md#opacity), shown for
`Respawn::BLINK` seconds and hidden for as many, until `flash` seconds have passed.
Then it gives back the opacity it found. `flashing?` says whether one is under way.

### `ScreenWrap`

**Wraps the node's position within the world bounds**, so an entity leaving one edge
reappears at the opposite one.

- **Construct:** `ScreenWrap.new(margin: 0.0)`. `margin` lets a sprite pass fully off
  one edge before reappearing on the other. Bounds come from the scene's world
  system. `ScreenWrap.new(width:, height:, margin:)` overrides them for a node whose
  wrap region is not the whole world.
- **Lifecycle:** `_attach` resolves the bounds, which is why you can omit them. A
  pooled entity is built long before it enters a tree, and has nothing to ask yet. It
  resolves again on every entry, so a recycled node follows the scene it lands in.
  Attaching without bounds and without a world system in scope **raises**.
- **Phase:** `_update(dt)` wraps the node's **world** position against the bounds, and
  writes it back through [`Node2D#world_x=`](scene_graph.md#the-two-spaces). A node
  under an offset container wraps at the world's edge, not at an edge shifted by the
  container.
- **A wrap is a placement, not a step.** It does not consult a sibling mover's
  `blocked_by` about the far side. A node wrapped onto something that blocks it stays
  pressed against it.
- **One response to the edge per node.** It raises at attach beside a
  `DespawnOffscreen`, or beside a mover declaring `blocked_by: [:bounds]`. A wrapping
  entity's mover declares no `:bounds`; see [`WorldBounds.one_response!`](#world).

### `Sprite`

**Draws one registered image at the node's origin**, where the traversal already
placed and rotated the renderer. By default the image stands on the origin, its
bottom centre there. A node that rotates passes `anchor: :center`, so it spins in
place.

- **Construct:** `Sprite.new(id:, scale: 1.0, z: 0, anchor: :bottom)`. `id` is a
  renderer image id. `z` orders this component against the node's *other* drawing,
  such as a shadow under a sprite, inside the node's own slot. It is not the node's
  `z`, which orders the node among its siblings. See
  [Drawing](drawing.md#draw-order). `anchor` places the image against the origin,
  measured from the node's size. An unknown anchor raises `ArgumentError`.

  | `anchor:` | On the origin |
  |---|---|
  | `:center` | the image's centre, so a rotating node spins in place |
  | `:bottom` | its bottom centre, so a character's origin is where they stand. The default |
  | `:top_left` | its top-left corner |

- **State:** `scale` is read/write, so a pooled entity can retune it. The image
  scales about the anchor.
- **Phase:** `_draw(renderer, view)` draws the image with **no angle** and no
  position of its own. `Node2D#draw` already pushed the node's transform, so the
  origin and rotation already apply. Passing either would apply it twice. The
  node rotates about its origin, whatever the anchor. The image is lifted by
  [`node.elevation`](scene_graph.md#elevation), in the node's local space. The
  component skips the draw entirely when the view cannot show it. It measures the
  node's box, scaled, moved by the anchor and lifted, against `node.world_x` and
  `world_y`. A node that never set a size is never culled, and draws centred on
  its origin whatever the anchor.

### `Targeting`

**Picks a node for the owner to aim at.** Each `update`, it queries the scene's
[`CollisionWorld`](#collisionworld) around the node's world origin and exposes the
chosen target. It only *selects*; it never moves or fires. The owner reads `target`
and acts. Every candidate already registers with the broadphase through its
collider, so targeting keeps no entity list.

- **Construct:** `Targeting.new(range:, policy: :nearest, layer: nil)`. `range` is
  the reach in pixels. `layer` restricts candidates, so `:enemy` ignores allies and
  projectiles. An unknown `policy` raises at construction.
- **Policies:** `:nearest`, the default and only policy, picks the closest candidate
  in range with one broadphase lookup.
- **State:** `target` is the chosen **node**, or `nil` when nothing is in range. It
  refreshes every `update`, so a freed or out-of-range target clears itself. It is a
  node, not a collider, so the owner can read its position and components.
- **Lifecycle:** `_attach` looks up the scene's `CollisionWorld`.
- **Phase:** `_update(dt)` selects the target again. It allocates nothing, so it runs
  every frame.

### `ThrustController`

**Inertial ship flight on top of a `Velocity` sibling.** A turn axis rotates the
node, and a thrust axis accelerates it along its heading.

- **Construct:** `ThrustController.new(turn_speed:, accel:, max_speed:, drag: 0.0,
  turn_action: :turn, thrust_action: :thrust)`.
- **Lifecycle:** `_attach` looks up the node's `Velocity` with `require_sibling`,
  so a missing one raises at once instead of surfacing later as a `nil`.
- **Phase:** `_control(actions)` reads intent: turn sets `velocity.spin`, and thrust
  is stored. `_update(dt)` accelerates along the heading, applies drag, and clamps to
  `max_speed`. Angle 0 points up, so forward is `(sin θ, −cos θ)`. Firing is not part
  of this component.

### `TileWorld`

**The scene-scoped tile system** (see [Systems](systems.md)). It holds the parsed
[`RGame::Engine::TileMap`](tile_maps.md) and answers what an actor needs from it: where the solid
tiles are, and how big the world is. Find it with `node.system(TileWorld)`. It
includes `WorldBounds` (see [`World`](#world)), so `ScreenWrap` and
`DespawnOffscreen` work in a tile scene with no arguments.

**It does not draw.** `RGame::Engine::TileMapLayer` draws, one node per Tiled layer,
mounted inside a `WorldView`. The map is therefore drawn once per viewport, like the
rest of world space. `TileWorld` stays the thing actors ask.

**Each piece of the tile stack is the kind of object its job requires:**

| Piece | Kind | Because |
|---|---|---|
| `TileMap` | values | parsed data with no handle; the tile rows are a `Util::Tensor` |
| `TileWorld` | component, mounted as a system | it is a scene-scoped answer — solid tiles, world size — that actors look up |
| `TileMapLayer` | node | it draws in world space, and draw order is tree order |

None of them duplicates state the node owns. None needs a hand-written hook to pass
data to another, depends on a sibling's add order, or names a layer it may not name.

- **Construct:** `TileWorld.new(map:, tilemap_id:, cameras: [])`. It clamps each
  camera it receives to the map's edges. `bound(camera)` does the same for a camera
  that arrives later, when a player joins.
- **Queries:**
  - `blockers` returns the map's solid tiles as an
    [`Engine::TileBlockers`](internals.md#tileblockers--the-tile-grid-as-a-blocker-source),
    the same object every time. A [`Mover`](#mover) declaring `:tiles` borrows it
    and resolves its own steps against it.
  - `gap_blockers` returns the edge of the floor as an
    [`Engine::GapBlockers`](internals.md#gapblockers--the-edge-of-the-floor-as-a-blocker-source),
    the same object every time, for a mover declaring `:gaps`.
  - `nav_grid` returns the same solidity as an
    [`Engine::NavGrid`](toolbox.md#navgrid--routes-over-a-tile-grid), for planning a
    route instead of resolving a step. It is built on first request and reused.
  - `tile_width` and `tile_height`, the size of one cell in pixels.
  - `cell_x(col)`, `cell_y(row)`, `col_at(world_x)` and `row_at(world_y)` convert
    between cells and world pixels, as [`TileMap`](tile_maps.md#cells-and-pixels)
    does. `cell_centre_x(col)` and `cell_centre_y(row)` answer the middle of a
    cell, which is where a [`Navigator`](#navigator) steers to.
  - `solid?(col, row)`, `world_width` and `world_height`.
  - `gap?(col, row)`, whether any layer holds a [gap tile](tile_maps.md#gaps) at
    that cell, and `floor_at?(x, y)`, whether the world point stands on the
    floor: its cell is not a gap, or a [`Platform`](#platform) covers it. A point
    on a cell's left or top edge is in that cell, and a point off the map is on
    the floor.
  - `ground_at?(x, y)`, whether the point's cell is not a gap. A platform does
    not make a gap ground, so this is where a thing may stand and stay, such as a
    [`Respawn`](#respawn)'s point.
  - `platform_under(x, y)`, the platform a node standing at the point rides: the
    first one registered that covers the point, where the cell is a gap. It is
    `nil` wherever the cell is ground, whatever covers it.
  - `floor_reach_x(x, y, dx)` and `floor_reach_y(x, y, dy)`, how far a point can
    move along one axis and stay on the floor. The answer is the whole step, or
    as far as `TileWorld::FLOOR_EDGE` (a billionth of a pixel) short of where the
    floor ends on the way. Ground and platforms make one floor, so a point walks
    from one onto the other wherever they meet or overlap. A point already off
    the floor moves the whole way.
  - `tilemap_id` and `elapsed`, which the layers read.
  - `layer_count`, `layer(index)`, `layer_index(name_or_path)` and
    `first_above_layer`, which `TileMapLayer.mount` reads to decide where its slots
    go. The first three answer as [`TileMap`](tile_maps.md#layers) does, and so
    does `actors_layer`, the index of the object layer marked for the actors, or
    `nil`.
- **Solidity is read from the map once.** On the first request, `TileWorld` reads
  the map's `solid_tile?` once per cell into one
  [`Util::SolidGrid`](values.md#rgameutilsolidgrid). From then on, `blockers`,
  `nav_grid` and `solid?` all read that store, never the map. They cannot disagree
  about a cell. A resolve on the per-frame path becomes a byte lookup instead of a
  walk through the map's layers and tileset. Everything past the map's edges is open.
  `TileWorld` does not hand the store out. A game changes a cell's solidity at
  runtime only through [`OccupiesCell`](#occupiescell).
  The gaps are read the same way, into a second grid that `gap?` and `floor_at?`
  read. Platforms move, so `floor_at?` asks each of them every time.
- **It does not resolve a step.** Tiles, other actors, the world's edge, or any
  combination may stop a mover, and only the mover knows which. The resolver
  therefore belongs to the mover, and the grid to this system.
- **Phase:** `_update(dt)` advances the map's animation clock.
- **Examples:** `examples/scroll_map` loads a `.tmx` through the asset manager and
  uses this system, `TileMapLayer.mount`, and a camera clamped to the map's edges.
  `examples/collision_tiles` adds an actor that collides, and shows the solid half of
  this system.

```ruby
world = scene.add_node(RGame::Engine::WorldView.new)
slots = RGame::Engine::TileMapLayer.mount(world)   # a node per Tiled layer
slots[:actors].add_node(player)                    # in the slot between them
```

**`mount` returns a `TileMapLayer::Slots`: the slots it left between the layers.**
Each slot is an empty node to add to. With no `slots:` there is one, `:actors`,
below the first layer Tiled flags `above`, so trunks draw under the walker and
canopies over it. `slots[name]` raises `KeyError` naming the slots for a name that
was not mounted, and `slots.names` lists them in the order declared.

**`slots:` names the slots and the layer that covers each:**

```ruby
slots = RGame::Engine::TileMapLayer.mount(world, slots: { actors: nil, boats: 'Water/bridge' })
slots[:boats].add_node(ferry)   # under the bridge, over the water
```

A slot's value is a layer index, a layer's name or `'Group/layer'` path, `nil` for
the first layer flagged `above`, or `layer_count` for over every layer. A name the
map lacks raises `KeyError` listing its layers, when `mount` runs. Slots under the
same layer draw in the order declared. An object layer gets no node, since it has
nothing to draw. Nothing here picks a `z`.

**Every slot is [y-sorted](scene_graph.md#y-sort)**, so actors in one slot draw by
where they stand: a hero walking below a chest draws in front of it. A side-view
game passes `y_sort: false`, and its slots draw their children in `z` order and
then in the order added:

```ruby
slots = RGame::Engine::TileMapLayer.mount(world, y_sort: false)
```

### `Timer`

**A node-driven interval timer.** It runs in the node's update tick, so nothing can
forget to advance it. It emits `on_elapsed` each time a whole interval elapses: a
spawn cadence, a turret's fire rate, a wave clock. It wraps the pure
[`RGame::Engine::Timer`](toolbox.md#timer--paced-periodic-events) and reuses its
drift-free carry-forward.

- **Construct:** `Timer.new(interval)`, in seconds. Add it with a name when a node
  needs several: `node.add_component(Timer.new(0.8), as: :spawn)`. For something
  that happens once, use a [`Tween`](#tween).
- **Signal:** `on_elapsed` fires once per whole interval:
  `timer.on_elapsed { spawn_enemy }`.
- **Lifecycle:** `_attach` restarts the countdown. A pooled node acquired and
  added again starts fresh, without its previous life's elapsed time.
- **Phase:** `_update(dt)` advances and emits. In one long step it emits once per
  interval crossed, catching up without drift. It allocates nothing.
- **Reset:** `reset` drops accumulated time, giving a fresh timer.

### `Tween`

**A one-shot that says how far along it is.** It runs an
[`Engine::Tween`](toolbox.md#tween--a-value-that-moves-over-time) in the node's
update tick and emits `on_finished` once, when it reaches the end: a banner that
removes itself, a projectile's lifetime, a hold before a page turns, a fade the
next scene waits for.

```ruby
life = node.add_component(RGame::Engine::Components::Tween.new(2.0), as: :life)
life.on_finished { node.queue_free }

fade = node.add_component(RGame::Engine::Components::Tween.new(0.5, from: 0, to: 255))
fade.value   # read in the node's _draw
```

- **Construct:** `Tween.new(duration, from: 0.0, to: 1.0, ease: :linear)`, as
  `Engine::Tween` takes them. It refuses `loop:`, since a tween that loops never
  finishes. A projectile that should vanish after N seconds on a fixed board is
  `Tween.new(2.0)` plus `on_finished { node.queue_free }`. When the board scrolls
  and the entity leaves the screen, use `DespawnOffscreen` instead.
- **Reading it:** `value`, `progress`, `done?` and `duration`, as on
  `Engine::Tween`. `running?` is true while it advances. `stopped?` is true while
  `stop` holds it.
- **Signal:** `on_finished` fires once per run, even when one long step passes the
  end by several durations.
- **Lifecycle:** `_attach` starts it from the beginning. A pooled node acquired and
  added again runs a fresh one.
- **Controlling it:** `start` runs it from the beginning, and an `on_finished`
  handler may call it to run again. `stop` holds it at the beginning, emitting
  nothing, until `start`: `examples/intro` stops its page hold while a page types.
  `finish` jumps to the end and emits `on_finished`, and does nothing unless it is
  running. `duration=` changes when it ends.
- **Phase:** `_update(dt)` advances and emits. A paused node holds it. It
  allocates nothing.

### `Velocity`

**Integrates linear and angular velocity into the node's transform each step.**

- **Construct:** `Velocity.new(vx: 0.0, vy: 0.0, spin: 0.0, blocked_by: [], pushes: [])`.
  [`Mover`](#mover) decides what may stop it, as for a `CharacterBody`.
- **State:** `vx`, `vy` and `spin` are read/write. A controller, or the node's own
  `_control` hook, writes them as movement intent.
- **Phase:** `_update(dt)` moves the node by `vx*dt` and `vy*dt` through `apply_move`.
  It adds `spin*dt` to `node.angle` directly: a collision box does not turn with its
  node, so nothing can block a rotation.
- **Blocked:** a stopped step leaves `vx` and `vy` unchanged. They are the intent.
  The game decides what a stop does to them, whether nothing, zero or a bounce, in an
  `on_blocked` handler. To block a `ThrustController` ship, declare `blocked_by:` on
  the `Velocity` it drives.

A free-moving entity can use `Velocity` alone. Pair it with a controller for input.

```ruby
add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, layer: :bullet))
velocity = add_component(RGame::Engine::Components::Velocity.new(vx: 400, blocked_by: %i[tiles]))
velocity.on_blocked { queue_free }
```

### `WanderController`

**A simple AI driver for a `CharacterBody`.** At intervals it rolls a new direction,
one of eight or idle, and holds it. A wall that blocks it triggers an early re-roll.

- **Construct:** `WanderController.new(rng: nil, change_interval: 1.0..3.0, idle_chance: 0.25)`.
  With no `rng:`, it rolls from the root's [`RandomSource`](#randomsource), so a
  seeded game wanders the same way each run. A spec passes `Random.new(seed)` to
  pin one walker's rolls; anything answering `rand` as `Random#rand` does will do.
- **Lifecycle:** `_attach` looks up the node's `CharacterBody` with
  `require_sibling`. With no `rng:`, it finds the root's `RandomSource`, and
  raises `KeyError` naming it when the root has none.
- **Phase:** `_update(dt)` counts down and re-rolls on timeout or when blocked.
  "Blocked" means the body meant to move and its [`stopped?`](#mover) is true: its
  step was cut short on either axis. A body with nothing declared is never blocked.
  One riding a [`Platform`](#platform) re-rolls at the platform's edge, though the
  platform moves it every tick.
- **Example:** `examples/save_load`.

### `World`

**The scene-scoped world system for a rectangular world**: it knows how big the
world is, and nothing more. Mount one on a scene with a plain rectangular world. The
components that need bounds find it, so no constructor between scene and entity has
to pass the numbers along.

- **Construct:** `World.new(width:, height:)`.
- **Queries:** `world_width` and `world_height`. They never change; a world of a
  different size is a new scene.
- **Contract:** it includes `WorldBounds`, and so does [`TileWorld`](#tileworld),
  which answers the same two questions from its map's pixel size. Ask for the
  contract, `node.system(RGame::Engine::Components::WorldBounds)`, and either kind of
  world answers. `get_component` matches an included module the same way it matches a
  class.
- **Frame:** the bounds run from (0, 0) to (`world_width`, `world_height`) in
  **world** coordinates. Everything that compares a node against them reads
  `world_x` and `world_y`. An entity under an offset container is inside the world
  exactly when its world position is.
- **Resolving a component's bounds:** `WorldBounds.resolve_width(node, width)`
  returns `width`, or the width of the world system `node` finds when `width` is
  nil. `WorldBounds.resolve_height(node, height)` does the same for the height.
  Each raises when it has to look and finds no system. Neither allocates:
  [`ScreenWrap`](#screenwrap) and [`DespawnOffscreen`](#despawnoffscreen) call both
  from `_attach`, and a pooled node attaches on every spawn.
- **One response to the edge per node:** `WorldBounds.one_response!(node)` raises,
  naming both, if the node carries more than one of [`ScreenWrap`](#screenwrap),
  [`DespawnOffscreen`](#despawnoffscreen) and a [`Mover`](#mover) declaring
  `blocked_by: [:bounds]`. Each of the three calls it from `_attach`, so whichever
  attaches second raises, in any add order. No pair makes sense. Stopping and
  wrapping disagree about where the node ends up. Wrapping and despawning race on
  which margin is reached first. Stopping tests the collision box, while the other
  two test the node's origin. The engine therefore refuses every combination.

**The world is not the window.** The two coincide in a single-screen game, which
makes the mistake easy to make and hard to see. Bind wrapping to the viewport, and
the world changes shape without warning when the window resizes or the screen
splits into viewports. Ask [`Viewports`](scene_graph.md#viewports-and-views), or the
`View` a `draw` receives, how big the *window* is. Ask `World` how big the *world*
is.
