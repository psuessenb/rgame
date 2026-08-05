# Systems & shared resources

Some things a node needs don't live on the node: a tilemap, the world bounds, a
shared collision world. The engine resolves this the way scene-graph engines do —
shared resources are **systems that live on an anchor node and are reached by
walking the tree**, not threaded through constructors. There is **no `GameContext`
bag**: a system is just an `Engine::Component` on a boundary node, found with the
same `get_component` every node already has.

> Status: the anchor + lookup mechanism (`root`, `scene`, `system`), the
> tree-lifecycle hooks, and deferred removal (`queue_free`) are in place.
> `examples/14_asteroids` exercises the whole path end to end and shows **both
> scopes**: a scene-scoped `CollisionWorld` system and a root-scoped `HighScores`
> system. `examples/15_tiled_world` adds a second scene-scoped system, `TileWorld`
> (the tile map: collision, world bounds, drawing). More systems arrive with the
> rest of the component port (see `docs/wip/components.md`).

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
class CircleCollider < Engine::Component
  def on_attach = node.system(CollisionWorld).register(self)
  def on_detach = node.system(CollisionWorld)&.unregister(self)
end
```

## Systems that index their clients (the tag-registry pattern)

A many-to-many system (broadphase collision) lives on the scene node and keeps its
own index of registered clients, so it processes only nearby candidates instead of
walking the tree for every pair. `CollisionWorld`
(engine/components/collision_world.rb) holds a `SpatialHash` for exactly this — a
spatial index of registered colliders, rebuilt each `update`. This indexing is the
same idea as Godot's **groups**: a registry of node references. It is *not* an ECS —
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
