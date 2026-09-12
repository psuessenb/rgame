# Systems & shared resources

Some things a node needs don't live on the node: a tilemap, the world bounds, a
shared collision world. The engine resolves this the way scene-graph engines do —
shared resources are **systems that live on an anchor node and are reached by
walking the tree**, not threaded through constructors. There is **no `GameContext`
bag**: a system is just an `RGame::Engine::Component` on a boundary node, found with the
same `get_component` every node already has.

## Two scopes = two anchor nodes

Scope is a property of the **owner** you attach a system to, not of the system
itself — the same insight behind Unreal's `UGameInstanceSubsystem` (whole session)
vs `UWorldSubsystem` (one level), and Godot's autoload singletons vs per-scene
nodes.

- **Global scope → the root node.** `root` is set once and never changes, reachable
  from every node. Program-lifetime systems (e.g. an audio bus, i18n) are components
  on the root: `node.root.get_component(AudioBus)`.
- **Scene scope → the scene node** (what `SceneStack` pushes). Scene-lifetime systems
  (the collision world, the tilemap/world-bounds holder) are components on *that*
  node — born when the scene is pushed, gone when it's popped:
  `node.scene.get_component(CollisionWorld)`.

## The anchors

Both anchors are **methods that walk the parent chain**, not cached fields. A cached
back-link set at add-time goes stale when a node is built before it's mounted (its
children would cache the wrong root); resolving on access can't.

- `root` — `@parent ? @parent.root : self`. The top-most node is its own root.
- `scene` — the nearest ancestor marked as a scene boundary. `SceneStack#push` marks
  the pushed scene with `scene.scene = scene`; descendants resolve up to it. Outside
  any scene, `scene` is `nil`.

### Looking a system up

```ruby
node.system(CollisionWorld)
```

`Node2D#system(klass)` checks the **scene scope first, then the global root**, so a
scene can override a global default and free-standing nodes still find globals. Use
the explicit anchor (`node.root.get_component` / `node.scene.get_component`) when you
specifically mean one scope.

### Ask for a contract, not a class

The lookup matches by **ancestry**, so `klass` can be a module a system includes rather
than the system's own class. That is how one question gets more than one answer.

"How big is the world" is the worked example. A flat game mounts
[`Components::World`](components.md#world); a tile game mounts
[`Components::TileWorld`](components.md#tileworld), which derives the same two numbers
from its map. Both include `Components::WorldBounds`, so a component that needs bounds
asks for the *contract*:

```ruby
def on_attach
  world = node.system(RGame::Engine::Components::WorldBounds)
  @width = world.world_width
  @height = world.world_height
end
```

`ScreenWrap` and `DespawnOffscreen` are written this way, which is why they work
unchanged in either kind of scene and never learn which one they are in. Naming the
contract is what keeps the two implementations from drifting apart — the same reasoning
behind the renderer and audio [shared example groups](../../spec/support/shared_examples/).

## Registering with a system — use the lifecycle, not `initialize`

A system and its clients only connect once everything is **in the live tree**, so
wiring happens in the tree-lifecycle hooks, never in `initialize` (where a node has
no anchors). See [Lifecycle](scene_graph.md#lifecycle-constructing-vs-entering-the-tree).

The entered-tree cascade guarantees ordering that makes this safe: a scene's own
components `on_attach` (so a `CollisionWorld` on the scene node exists), then the
scene's `on_add`, then its children enter — so by the time a child collider attaches,
the scene-scoped system it looks up is already there.

```ruby
# CircleCollider (engine/components/circle_collider.rb) registers itself when it
# enters the tree and releases the registration when it leaves — the engine fires
# both hooks, so a spawned/despawned entity can't leak a registration.
class CircleCollider < RGame::Engine::Component
  def on_attach = node.system(CollisionWorld)&.register(self)
  def on_detach = node.system(CollisionWorld)&.unregister(self)
end
```

**A collider tolerates a missing world, and most clients should not.** Both hooks
above are `&.`, so a collider on a scene with no `CollisionWorld` is simply a shape
that reports nothing: that is what a tile-only game wants, since its character carries
a feet box to be *stopped* by (see
[`CharacterBody`](components.md#characterbody)) and there are no pairs to find. The
price is that an `on_hit` handler in such a scene never fires and nothing says so, so
weigh it deliberately — a client that is useless without its system raises instead,
the way `CharacterBody(blocked_by:)` does.

## The two the platform mounts for you

`RGame::Game` puts two systems on the root before the tree comes alive, so any
node can reach them without a game wiring anything:

| | |
|---|---|
| `node.system(RGame::Engine::Players)` | who is playing — devices, bindings, cameras, and who a newly used controller belongs to |
| `node.system(RGame::Engine::Viewports)` | how the screen is divided — one `View` per active player, and collapsing the split |

They are ordinary root-scoped systems, mounted the same way a game would mount
its own. A scene that needs a camera to follow asks the first
(`players.primary.camera`); a cutscene that needs to collapse the split asks the
second (`viewports.solo!(camera)`), from wherever in the tree it happens to be
and with nothing threaded into it. That reachability is the whole reason they
are systems rather than something `Game` hands down.

See [Input](input.md#players-seats-and-joining) and
[Scene graph](scene_graph.md#viewports-and-views).

## Collision: two indexes, one resolver

Collision is the largest thing built out of systems here, and it is spread across
three chapters — the [components](components.md#boxcollider) a node carries, the
[systems](#systems-that-index-their-clients-the-tag-registry-pattern) a scene mounts,
and the [building blocks](internals.md#collisionsystem--move-an-actor-against-its-blockers)
underneath both. This is the shape they add up to.

**A node has exactly one collision shape, and exactly one component owns it.** The
[collider](components.md#boxcollider) *is* the shape; a
[`CharacterBody`](components.md#characterbody) that wants to be stopped reads its
sibling's box rather than building a second one. So the rectangle that stops a step and
the rectangle that reports a contact are the same rectangle, and retuning one retunes
both.

**There are two indexes, on purpose.** A tile map is already an index: the wall a step
would hit is arithmetic on the step, so a `TileWorld` divides by the tile size and asks
the grid. Actors have no such structure, so a `CollisionWorld` buckets them into a
[`SpatialHash`](internals.md#spatialhash--uniform-grid-broadphase) each step. Merging
the two — baking tile shapes into the broadphase, which is what Godot and Unity both do
— would rebuild an index the grid already is, and pay for it every frame on a map of
tens of thousands of tiles. Unity ships `CompositeCollider2D` specifically to make that
affordable; this engine declines the problem instead.

**What is unified is one level up.** A **blocker source** answers one question over
plain numbers — where does this box land moving `dx` — and there are three of them:
`TileBlockers` over the grid, `ActorBlockers` over the broadphase, and `BoundsBlockers`
over the world's edges. A blocked body builds a
[`CollisionSystem`](internals.md#collisionsystem--move-an-actor-against-its-blockers)
at attach out of the ones its `blocked_by:` named, and that system asks each of them and
takes the most restrictive answer on each axis. The axis-separated order that produces
wall-sliding is therefore written **once**, which is why an actor slides off a villager
exactly the way it slides off a fence.

| | Mounted on the scene | Owned by the node |
|---|---|---|
| Tiles | [`TileWorld`](components.md#tileworld), which hands out one shared `TileBlockers` | — |
| Actors | [`CollisionWorld`](components.md#collisionworld), the broadphase | an `ActorBlockers` per body, holding its own collider and layer list |
| The world's edge | any [`WorldBounds`](components.md#world) | a `BoundsBlockers` |
| The step | — | one `CollisionSystem`, built at attach from the names above |

Neither system needs the other, and most scenes mount one of them. `examples/scroll_map`
has a map and no broadphase; `examples/collision`, `test_projects/asteroids` and
`test_projects/snake` have a broadphase and no map. `examples/collision_tiles` mounts both,
and the only place in it that shows is the list of names in `blocked_by`.

What a body is stopped by and what a collider is touching stay two different questions,
though, and the difference is visible to a game rather than being an implementation
detail: see [Blocking and overlapping](#blocking-and-overlapping-are-two-reports-and-a-pair-gets-one-of-them)
below, once the broadphase itself has been introduced.

## Systems that index their clients (the tag-registry pattern)

A many-to-many system (broadphase collision) lives on the scene node and keeps its
own index of registered clients, so it processes only nearby candidates instead of
walking the tree for every pair. `CollisionWorld`
(engine/components/collision_world.rb) holds a `SpatialHash` for exactly this — a
spatial index of registered colliders, rebuilt each `update` — and it is shape-agnostic,
so `CircleCollider` and `BoxCollider` share one and collide with each other. This
indexing is the same idea as Godot's **groups**: a registry of node references. It is *not* an ECS —
it indexes references, carries no component data, and gains none of ECS's
data-locality; it's a lightweight index.

`CollisionWorld` is layer-agnostic: it reports every overlapping pair to both of its
colliders, and the owning node decides what a contact *means* by reading the other's
`layer` tag:

```ruby
collider.on_hit { |other| queue_free if other.layer == :bullet } # in a Rock node
```

A contact is reported as two **edges**, not as a state: `on_hit` on the step a pair
starts overlapping, `on_separated` on the step it stops, each once per pair and nothing
in between. That is what lets a handler count, play a sound or spend a life without
guarding itself, and it is why the system keeps an `Engine::ContactSet` per collider
rather than simply forwarding what the broadphase found each step.

Because it's a normal component on the scene node, it rides the `update` traversal
(its broadphase runs in `update`) and is torn down with the scene. See
`test_projects/asteroids` for the whole loop: ship, bullets, and rocks spawning,
colliding, and despawning through this system.

### Blocking and overlapping are two reports, and a pair gets one of them

The same broadphase answers a second question: a
[`CharacterBody`](components.md#characterbody) that names a collider layer in
`blocked_by:` is *stopped* by every box wearing it, flush against its edge, exactly
the way a solid tile stops it. So one `BoxCollider` can be a wall to one actor and a
trigger for another, and which it is depends on who declared the layer rather than on
anything the collider itself says.

**The two reports do not overlap, and cannot.** Blocking leaves the boxes exactly
touching, and `CollisionBox.overlap?` spans the half-open `[x, x + w)` on purpose —
on a grid, pieces on neighbouring squares border each other constantly and an
inclusive test would report every one of those as a contact. Measured on two 12×6
boxes: touching exactly, `on_hit` does not fire; overlapping by half a pixel, it
does. That convention is right and it is what makes the two reports mutually
exclusive by construction.

So a blocked pair reports **no** contact, and that is why a body that must both stop
and react reacts to `on_blocked` rather than to `on_hit` — see
[`CharacterBody`](components.md#characterbody). The rule of thumb:

| The question | The report | Where it lives |
|---|---|---|
| what may I not walk through | `on_blocked` / `on_unblocked` | the body that was stopped |
| what am I touching | `on_hit` / `on_separated` | both colliders of the pair |

`examples/collision_tiles` is the worked example of the first, `examples/collision`
of the second.
