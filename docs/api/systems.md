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
  def on_attach = node.system(CollisionWorld).register(self)
  def on_detach = node.system(CollisionWorld)&.unregister(self)
end
```

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

`CollisionWorld` is layer-agnostic: it reports every overlapping pair by firing each
collider's `on_hit` signal with the other collider, and the owning node decides what
a contact *means* by reading the other's `layer` tag:

```ruby
collider.on_hit { |other| queue_free if other.layer == :bullet } # in a Rock node
```

Because it's a normal component on the scene node, it rides the `update` traversal
(its broadphase runs in `update`) and is torn down with the scene. See
`examples/14_asteroids` for the whole loop: ship, bullets, and rocks spawning,
colliding, and despawning through this system.
