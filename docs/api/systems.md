# Systems & shared resources

Some things a node needs do not live on the node: a tile map, the world bounds, a
shared collision world. **Shared resources are systems. A system lives on an
anchor node, and other nodes reach it by walking the tree**, not through
constructor arguments. A system is an ordinary `RGame::Engine::Component` on a
boundary node, found with the same `get_component` every node has.

## Two scopes, two anchor nodes

**Scope belongs to the node you attach a system to**, not to the system.

- **Global scope → the root node.** Every node can reach the root, and it never
  changes. Systems that live as long as the program are components on the root,
  such as `Players` and `Viewports`: `node.root.get_component(RGame::Engine::Players)`.
- **Scene scope → the scene node**, the node `SceneStack` pushes. Systems that
  live as long as a scene are components on *that* node, such as the collision
  world or the tile world. They appear when the scene is pushed and go when it is
  popped: `node.scene.get_component(CollisionWorld)`.

## The anchors

**Both anchors are methods that walk the parent chain**, not cached fields. A
back-link cached at add time would go stale for a node built before it is
mounted: its children would cache the wrong root. Resolving on every access
cannot go stale.

- `root` is `@parent ? @parent.root : self`. The top-most node is its own root.
- `scene` is the nearest ancestor marked as a scene boundary. `SceneStack#push`
  marks the pushed scene with `scene.scene = scene`, and descendants resolve up to
  it. Outside any scene, `scene` is `nil`.

### Looking a system up

```ruby
node.system(CollisionWorld)
```

**`Node2D#system(klass)` checks the scene first, then the root.** A scene can
therefore override a global default, and nodes outside any scene still find
globals. To mean one scope specifically, use its anchor:
`node.root.get_component` or `node.scene.get_component`.

**`Node2D#system!(klass)` is the same lookup for a caller that cannot work
without the system.** Where `system` returns nil, `system!` raises `KeyError`.
The message names the class, the node and where it looked, and says when the
node has no parent:

```ruby
system!(RGame::Engine::AudioOut).play_sound(:boom)
# KeyError: Ship found no RGame::Engine::AudioOut system on its scene or the root.
#           Mount one there with add_component
```

### Ask for a contract, not a class

**The lookup matches by ancestry**, so `klass` can be a module the system
includes instead of its own class. One question can then have several answers.

"How big is the world" shows this. A flat game mounts
[`Components::World`](components.md#world). A tile game mounts
[`Components::TileWorld`](components.md#tileworld), which derives the same two
numbers from its map. Both include `Components::WorldBounds`, so a component
that needs bounds asks for the *contract*:

```ruby
def _attach
  world = node.system(RGame::Engine::Components::WorldBounds)
  @width = world.world_width
  @height = world.world_height
end
```

`ScreenWrap` and `DespawnOffscreen` work this way. They run unchanged in either
kind of scene and never learn which one they are in. Naming the contract keeps
the two implementations from drifting apart.

## Registering with a system: use the lifecycle, not `initialize`

**A system and its clients connect in the tree-lifecycle hooks**, never in
`initialize`. They can only connect once everything is in the live tree, and a
node under construction has no anchors. See
[Lifecycle](scene_graph.md#lifecycle-constructing-vs-entering-the-tree).

The entered-tree cascade fixes an order that makes this safe. The scene's own
components run `_attach` first, so a `CollisionWorld` on the scene node exists.
Then the scene's `_enter_tree` runs, then its children enter. By the time a child
collider attaches, the scene-scoped system it looks up is already there.

```ruby
# CircleCollider (engine/components/circle_collider.rb) registers itself when it
# enters the tree and releases the registration when it leaves — the engine fires
# both hooks, so a spawned/despawned entity can't leak a registration.
class CircleCollider < RGame::Engine::Component
  def _attach = node.system(CollisionWorld)&.register(self)
  def _detach = node.system(CollisionWorld)&.unregister(self)
end
```

**A collider tolerates a missing world; most clients should not.** Both hooks
above use `&.`. A collider in a scene without a `CollisionWorld` is a shape that
reports nothing. A tile-only game wants exactly that: its character carries a
feet box to be *stopped* by (see [`Mover`](components.md#mover)), and there are no
pairs to find. The cost is that an `on_hit` handler in such a scene never fires,
and nothing reports it. Weigh that deliberately. A client that is useless without
its system raises instead: with `system!`, or with a message of its own, as a
mover's `blocked_by:` does.

## The four systems `Game` mounts

**`RGame::Game` puts four systems on the root before the tree goes live.** Any
node can reach them without the game wiring anything:

| | |
|---|---|
| `node.system(RGame::Engine::Players)` | who is playing — devices, bindings, cameras, and who a newly used controller belongs to |
| `node.system(RGame::Engine::Viewports)` | how the screen is divided — one `View` per active player, and collapsing the split |
| `node.system(RGame::Engine::Components::Facts)` | the flags and named state machines a game saves as one entry |
| `node.system!(RGame::Engine::AudioOut)` | the sound device: `play_sound`, `play_music`, `stop_music` |

They are ordinary root-scoped systems, mounted the way a game mounts its own. A
scene that needs a camera to follow asks `Players` (`players.primary.camera`). A
cutscene that collapses the split asks `Viewports` (`viewports.solo!(camera)`).
A quest built in a scene registers with `Facts`, which the save code writes. A
node plays a sound through `AudioOut`. All four work from anywhere in the tree,
with nothing passed in. That reach is why they are systems and not objects
`Game` hands down.

See [Input](input.md#players-seats-and-joining),
[Scene graph](scene_graph.md#viewports-and-views),
[Facts](dialogue.md#facts) and
[Audio](audio.md#audioout--the-system-a-node-plays-sound-through).

## Collision: two indexes, one resolver

Collision is the largest structure built from systems. Three pages cover its
parts: the [components](components.md#boxcollider) a node carries, the
[systems](#systems-that-index-their-clients-the-tag-registry-pattern) a scene
mounts, and the
[building blocks](internals.md#collisionsystem--move-an-actor-against-its-blockers)
underneath. This section shows how they fit together.

**A node has exactly one collision shape, and exactly one component owns it.** The
[collider](components.md#boxcollider) *is* the shape. A
[mover](components.md#mover) that wants to be stopped reads its sibling's box
instead of building a second one. The rectangle that stops a step is the
rectangle that reports a contact, so retuning one retunes both.

**Collision uses two indexes, on purpose.** A tile map is already an index: the
wall a step would hit follows from arithmetic on the step. A `TileWorld` divides
by the tile size and asks the grid. Actors have no such structure, so a
`CollisionWorld` buckets them into a
[`SpatialHash`](internals.md#spatialhash--uniform-grid-broadphase) each step.
Baking tile shapes into the broadphase would rebuild an index the grid already
is. It would also cost time every frame on a map of tens of thousands of tiles.

**The unification happens one level up.** A **blocker source** answers one
question over plain numbers: where does this box land when it moves `dx`? Three
sources exist:

- `TileBlockers`, over the grid;
- `ActorBlockers`, over the broadphase;
- `BoundsBlockers`, over the world's edges.

A blocked mover builds a
[`CollisionSystem`](internals.md#collisionsystem--move-an-actor-against-its-blockers)
at attach, from the sources its `blocked_by:` names. That system asks each source
and takes the most restrictive answer on each axis. The axis-separated order that
produces wall-sliding therefore exists **once**. An actor slides off a villager
exactly as it slides off a fence.

A source may also answer `travel?`: can this box move along a segment without
being stopped? `TileBlockers` does. A [`Navigator`](components.md#navigator) uses
it to check a route against the same resolver that will stop its walk.

| | Mounted on the scene | Owned by the node |
|---|---|---|
| Tiles | [`TileWorld`](components.md#tileworld), which hands out one shared `TileBlockers` | — |
| Actors | [`CollisionWorld`](components.md#collisionworld), the broadphase | an `ActorBlockers` per mover, holding its own collider and layer list |
| The world's edge | any [`WorldBounds`](components.md#world) | a `BoundsBlockers` |
| The step | — | one `CollisionSystem`, built at attach from the names above |

Neither system needs the other, and most scenes mount one. `examples/scroll_map`
has a map and no broadphase. `examples/collision` has a broadphase and no map.
`examples/collision_tiles` mounts both, and the difference shows only in the names
listed in `blocked_by`.

"What stops a mover" and "what a collider touches" remain two questions, and a
game sees the difference. See
[Blocking and overlapping](#blocking-and-overlapping-are-two-reports-and-a-pair-gets-one-of-them)
below, after the broadphase.

## Systems that index their clients (the tag-registry pattern)

**A many-to-many system keeps its own index of registered clients**, so it checks
only nearby candidates instead of walking the tree for every pair. Broadphase
collision works this way, on the scene node. `CollisionWorld`
(engine/components/collision_world.rb) holds a `SpatialHash`: a spatial index of
registered colliders, rebuilt each `update`. The index ignores shape, so
`CircleCollider` and `BoxCollider` share one and collide with each other. The
index holds node references only. It carries no component data and gives no
data-locality benefit; it is a lightweight registry.

**`CollisionWorld` ignores layers.** It reports every overlapping pair to both
colliders. The owning node decides what a contact *means* by reading the other
collider's `layer` tag:

```ruby
collider.on_hit { |other| queue_free if other.layer == :bullet } # in a Rock node
```

**A contact arrives as two edges, not as a state.** `on_hit` fires on the step a
pair starts overlapping. `on_separated` fires on the step it stops. Each fires
once per pair, with nothing in between. A handler can therefore count, play a
sound or spend a life without guarding itself. That is why the system keeps an
`Engine::ContactSet` per collider, instead of forwarding each step's broadphase
results.

`CollisionWorld` is a normal component on the scene node. It runs in the
`update` traversal, where its broadphase runs, and goes away with the scene.
`examples/collision` shows the whole loop: circles and crates registering,
overlapping and separating through this system.

### Blocking and overlapping are two reports, and a pair gets one of them

**The same broadphase answers a second question.** A
[mover](components.md#mover) that names a collider layer in `blocked_by:` is
*stopped* by every box with that layer. It stops flush against the box's edge, as
against a solid tile. One `BoxCollider` can thus be a wall to one actor and a
trigger for another. Who declared the layer decides which; the collider itself
says nothing.

**The two reports never both fire for one pair.** Blocking leaves the boxes
exactly touching. `CollisionBox.overlap?` uses the half-open span `[x, x + w)` on
purpose. On a grid, pieces on neighbouring squares border each other constantly,
and an inclusive test would report each as a contact. Measured on two 12×6 boxes:
touching exactly, `on_hit` does not fire; overlapping by half a pixel, it does.
That convention makes the two reports mutually exclusive by construction.

A blocked pair therefore reports **no** contact. A mover that must both stop and
react listens to `on_blocked`, not `on_hit`; see [`Mover`](components.md#mover).
The rule of thumb:

| The question | The report | Where it lives |
|---|---|---|
| what may I not pass through | `on_blocked` / `on_unblocked` | the mover that was stopped |
| what am I touching | `on_hit` / `on_separated` | both colliders of the pair |

`examples/collision_tiles` shows the first, and `examples/collision` the second.
