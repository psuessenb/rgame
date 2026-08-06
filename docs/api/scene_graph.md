# Scene graph

The engine builds a game out of a tree of nodes — a classic scene graph. A node
holds state, logic and drawing for one game object; nesting nodes builds up whole
scenes. Everything is pure Ruby: nodes draw through the renderer interface and
read input from a per-frame snapshot, never touching Gosu directly.

## Node2D

`Engine::Node2D` (`engine/node2d`) is the basic building block. (The `2D` in the
name leaves room for a future 3D node; today everything is 2D.) A node carries:

- a **transform** — relative `x`, `y`, `z` plus `width`/`height`;
- **children** — other nodes nested under it (`add_node`);
- **components** — reusable pieces of behaviour attached to it (`add_component`);
- a **parent** — the node it hangs off (set automatically when it is added).

Nodes extend the signal DSL (`Engine::Signal::DSL`), so any subclass can declare
and emit signals without opting in. See [Signals](signals.md).

### The tick: control → update → draw

A node is driven in three phases, run in this order every frame:

1. `control(actions)` — read intent, both from the player (the `actions`
   snapshot) and from AI/scripted controllers.
2. `update(dt)` — advance game logic and physics over the timestep `dt`.
3. `draw(renderer)` — render the current visual state.

Each phase **settles the node itself first — its components, then its own hook —
and only then descends into the children**. So you override the hook, not the
phase itself:

- `on_control(actions)`
- `on_update(dt)`
- `on_draw(renderer)`

Self-before-subtree keeps the transform flowing downward: a component or hook
that moves the node does so before its children resolve their origin from it (see
[Absolute position](#absolute-position)).

Because the traversal recurses into children for you, **never re-implement child
iteration** — add children with `add_node` and let the tree drive them.

### Absolute position

`x`/`y`/`z` are **relative to the parent**. At the start of each phase a node
resolves its absolute position by accumulating onto the parent's origin
(`abs_x = parent.abs_x + x`, and likewise for `y`/`z`); a node with no parent
sits at the origin. Moving or re-layering a node therefore moves and re-layers
its whole subtree. (Rotation, dirty-flag caching and smarter `z`/depth handling
are noted as future work in the source.)

### View transforms and the camera

A node's transform is its place in the **world**. A *view* transform is different: it
maps that world onto the screen (a camera), and it must wrap a whole subtree's draw
without being baked into any node's position. So `draw` calls a `draw_children` step a
subclass can override to wrap the subtree in a renderer transform.

`Engine::CameraView` is that subclass: built with an `Engine::Camera`, it wraps its
children's draw in `renderer.translated(-camera.x, -camera.y)`. Its children draw at
their own world origin (they never know about the camera); the translate maps them to
the screen. Because the offset is a draw-time transform rather than a node position, the
same world can later be drawn through several cameras — split-screen is repeating the
pass under different offsets/clips. The owning scene drives the camera (e.g. centring it
on the player); `CameraView` only applies it. See `examples/15_tiled_world`.

## Components

`Engine::Component` (`engine/component`) is a piece of behaviour you attach to a
node instead of baking it into a subclass. A component knows its owning `node`,
and like nodes it extends the signal DSL.

- `add_component(component, as: nil)` attaches one in a **named slot** and back-links
  it to the node. The slot defaults to the component's class, so by default a node
  still holds **at most one component per class** — a taken slot raises. Pass a name
  (`add_component(Timer.new, as: :spawn)`) when a node needs several of one type.
- `get_component(key)` looks a component up by its slot: a class (matched by ancestry,
  so a base class finds a subclass instance) or a Symbol name. A class lookup **raises
  if it is ambiguous** — several components share that type — so name them and look up
  by name.
- `remove_component(key)` detaches and unlinks the component in that slot (class or
  name), returning it (or `nil` if the slot is empty).

A component mirrors the node's three phases — `control(actions)`, `update(dt)`,
`draw(renderer)` — and the node drives its components in each phase, before its
own hook and before its children. It also has the two tree-lifecycle hooks below
(`on_attach`/`on_detach`).

## Lifecycle: constructing vs. entering the tree

A node has two distinct moments, and conflating them is a classic source of bugs
(it is why mature engines split Godot's `_init`/`_ready`, Unity's `Awake`/`OnEnable`,
Unreal's constructor/`BeginPlay`):

1. **Construction** (`initialize`) — the node and its components exist, but the node
   is **not yet in the live tree**. It has no resolved anchors: `root`/`scene` (below)
   don't point anywhere useful, and shared systems aren't reachable. Build children
   and attach components here; do **not** look anything up across the tree.
2. **Entering the tree** — when the node becomes live, the engine runs a depth-first
   cascade that fires, in order: each component's `on_attach`, then the node's
   `on_add`, then the same for every child. **This is where anchors and systems are
   available**, so it's where a component registers with a shared system. Leaving the
   tree runs the mirror cascade — children first, then `on_remove`, then component
   `on_detach` to release those registrations.

The engine drives this; you never call it. The relevant calls are `enter_tree` /
`exit_tree` (and `in_tree?`), fired automatically:

- `add_node` enters the child immediately **iff** the parent is already live;
  otherwise the child waits and is entered when its ancestor enters. So a node tree
  assembled in `initialize` (before it's mounted) comes alive all at once when it
  is. `remove_node` exits the subtree the same way.
- `add_component` / `remove_component` fire `on_attach` / `on_detach` immediately when
  the host node is already live (otherwise attach happens during the node's entry).
- `SceneStack#push` / `pop` enter/exit a scene; the platform enters the root once at
  boot (`RGame::Game#start`).

**The split is load-bearing for the `on_add`/`initialize` divide:** put cross-tree
lookups (anchors, systems, sibling components) in `on_add` / `on_attach`, never in
`initialize`. The engine guarantees the anchors are wired before those hooks run, so
you can't accidentally read them too early.

## Anchors and shared systems

Two back-links let any node reach shared state without it being threaded through
constructors, both **resolved by walking parents** (never cached, so they can't go
stale):

- `root` — the top-most node (a node with no parent is its own root). Home for
  global, program-lifetime systems.
- `scene` — the nearest enclosing scene node (marked as a boundary by `SceneStack`).
  Home for scene-lifetime systems.

A *system* is just a `Component` living on one of those anchor nodes; nodes find one
with `node.system(SomeSystem)` (scene scope first, then the global root). See
[Systems & shared resources](systems.md) for the scoping model and worked examples.

## Deferred free

A node that detaches itself or a sibling mid-tick would mutate a parent's `children`
while that list is being iterated — the classic scene-graph footgun. So removal is
**deferred** (as in Godot's `queue_free`):

- `queue_free` marks a node for removal; `freed?` reports the mark. The node stays in
  the tree and keeps ticking until the sweep.
- `sweep_freed` detaches every marked node, depth-first, running the normal leave-tree
  cascade (`on_remove` / `on_detach`) on each. It runs from a safe point **outside** the
  tick — the platform loop flushes it once per step, after `update`.

Because it's deferred, any component or hook can call `node.queue_free` from inside
`update` without corrupting the traversal. Container components that hold nodes off the
normal child list (e.g. `SceneStack`) override `Component#sweep_freed` to forward the
sweep into the subtree they own.

`enter_tree` clears the freed flag, so a node detached and later re-added comes back
alive. This is what lets a pool recycle nodes: a despawned (freed) node is returned to
its pool, and re-acquiring it and `add_node`-ing it revives it cleanly.
