# Scene graph

The engine builds a game out of a tree of nodes — a classic scene graph. A node
holds state, logic and drawing for one game object; nesting nodes builds up whole
scenes. Everything is pure Ruby: nodes draw through the renderer interface and
read input from a per-frame snapshot, never naming a graphics library at all.

## Node2D

`RGame::Engine::Node2D` (`engine/node2d`) is the basic building block. (The `2D` in the
name leaves room for a future 3D node; today everything is 2D.) A node carries:

- a **transform** — relative `x`, `y`, `z` plus `width`/`height`;
- **children** — other nodes nested under it (`add_node`);
- **components** — reusable pieces of behaviour attached to it (`add_component`);
- a **parent** — the node it hangs off (set automatically when it is added).

Nodes extend the signal DSL (`RGame::Engine::Signal::DSL`), so any subclass can declare
and emit signals without opting in. See [Signals](signals.md).

### The tick: control → update → draw

A node is driven in three phases, run in this order every frame:

1. `control(actions)` — read intent, both from the player (the `actions`
   snapshot) and from AI/scripted controllers.
2. `update(dt)` — advance game logic and physics over the timestep `dt`.
3. `draw(renderer, view)` — render the current visual state into `view`, the
   viewport being drawn.

Each phase **settles the node itself first — its components, then its own hook —
and only then descends into the children**. So you override the hook, not the
phase itself:

- `on_control(actions)`
- `on_update(dt)`
- `on_draw(renderer, view)`

`view` is the viewport this node is being drawn into — its rectangle, and the camera (if
any) it is seen through. Most nodes ignore it and just draw. Two things need it: laying
out against the edges of *this* region rather than the whole window
(`view.x`, `view.width`), and culling (`view.visible?(x, y, w, h)`), which stops being an
optimisation once the world is drawn once per player. See
[Viewports](#viewports-and-views).

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

### Who a node answers to

`control` is handed an input **source**, not one player's snapshot — a
[`RGame::Engine::Players`](input.md) registry, or a bare `Actions` when there is
only ever one answer. Each node asks the source for the actions of whichever
player owns it, and hands its components and its own `on_control` that plain
`Actions`.

Ownership is `input_owner`, and it is **inherited down the tree exactly like the
transform**, resolved onto `abs_input_owner` alongside `abs_x`/`abs_y`:

```ruby
ship.input_owner = game.players[1]   # the ship and everything under it
```

A node that names nobody inherits its parent's; a tree that names nobody
anywhere reads the primary player. That is what keeps single-player free of
ceremony — no game that has one player ever mentions this.

Because the *source* descends rather than the resolved snapshot, two subtrees in
one traversal can read two different controllers, while a component still sees
the `control(actions)` it always did.

> It is `input_owner` rather than `player` because `@player` is what a game's own
> scene usually calls its hero node, and rather than `controller` because
> `Actor#controller` already means the thing producing movement intent.

### View transforms and the camera

A node's transform is its place in the **world**. A *view* transform is different: it
maps that world onto the screen (a camera), and it must wrap a whole subtree's draw
without being baked into any node's position. So `draw` calls a `draw_children` step a
subclass can override to wrap the subtree in a renderer transform.

### Two words that are easy to confuse

**Space** is structural and the tree enforces it: a node is either inside a
`WorldView` or it is not, and that decides what its coordinates mean and how
many times it is drawn.

**Z band** is an ordering convention and nothing enforces it: `Z::WORLD`,
`Z::HUD`, `Z::OVERLAY`, `Z::DEBUG` are Integers a caller passes as `z:`. See
[Drawing](drawing.md#bands-where-each-kind-of-content-sits).

They are not the same partition. All screen-space content is one *space* and is
drawn once; the z bands subdivide it by what should cover what.

`RGame::Engine::WorldView` is that subclass, and it is where **world space begins**.
Its children draw at their own world origin and never know about a camera; the node
draws them **once per active viewport**, clipping to that viewport's rectangle and
translating by its camera:

```ruby
view = scene.add_node(RGame::Engine::WorldView.new)
view.add_node(player)     # world coordinates
```

Everything *outside* a `WorldView` is screen space and draws once. That one distinction
is what separates a HUD from the world, and where it goes is the game's choice — nothing
is imposed above the game's own root.

A `WorldView` takes no camera. Cameras belong to players
(`RGame::Engine::Player#camera`), and the node asks
`node.system(RGame::Engine::Viewports)` which viewports exist, so the same subtree serves
one player or four with nothing below it changing. A camera owned by a node *inside* the
world could not do that — it would force the world to know how many times it is drawn.

**Only `draw` multiplies.** `control` and `update` still run once per node per tick
however many players are watching, which is what keeps simulation cost independent of
player count — and what makes the standing "draw renders state" rule load-bearing rather
than stylistic: a `draw` with a side effect now runs once per player.

See `examples/15_tiled_world`.

## Viewports and views

`RGame::Engine::Viewports` is a root-scoped system holding how the screen is divided;
`RGame::Engine::Layout` is the pure arithmetic behind it, and a `RGame::Engine::View` is
one viewport being drawn.

```ruby
viewports = node.system(RGame::Engine::Viewports)
viewports.views              # one View per active player — what a WorldView draws through
viewports.screen             # the whole window, no camera — screen space
viewports.screen_for(player) # that player's own region, no camera — their HUD and menus
```

`screen_for` is the same rectangle that player's world view is drawn into, so a
HUD laid out at (10, 10) lands ten pixels inside the region the world beneath it
occupies. It is **nil** when they have nowhere to draw: an empty seat has no
viewport, and while the split is collapsed nobody owns a half of the screen —
a cutscene is everyone looking at one thing, so something that must stay on
screen through it belongs in the global overlay band instead.

A **`View`** carries `x`, `y`, `width`, `height`, its `camera` (nil in screen
space) and its `player`, plus two things nodes actually use:

| | |
|---|---|
| `view.visible?(x, y, w, h)` | is this worth drawing at all |
| `view.offset_x` / `offset_y` | the translate that maps its contents onto the screen |

**Views are reused, not rebuilt.** `Viewports` mutates one per viewport each frame, the
way `ActionMapper` reuses its `Actions` — building fresh ones would allocate every frame.
Hold the player or the viewports, never a `View`.

**`Layout`** answers only "given a count and a window, where does each one go", with no
state and no anchors: one viewport gets the window, two get a row each, three or four
share a 2x2 grid. Edges are computed as `(i * total) / count`, so the rects tile exactly
and no seam is left down the middle of an odd-sized window.

### A player's own screen

`RGame::Engine::PlayerLayer` is the node for it: its subtree is drawn **once**,
clipped to that player's viewport and translated to its corner, in screen space.

```ruby
layer = scene.add_node(RGame::Engine::PlayerLayer.new(player: game.players[1]))
layer.add_node(inventory)
```

That is the third kind of content a frame holds. The world is drawn once per
viewport under a camera (`WorldView`), a global overlay once across the whole
window (anything else in the tree), and this once per player inside their own
region.

**Children are positioned relative to the layer**, so a node at (10, 10) is ten
pixels inside *that player's* region wherever the layout put it, and the same
HUD class serves either player unchanged. Lay out against the far edge with the
view's **size** — `view.width - margin`. `view.x` and `view.y` are where the
region sits on the window and are the clip's business, not a layout origin;
adding them would offset a second time.

**It sets `input_owner`**, and ownership is inherited, so a menu anywhere under
it reads that player's controller and nobody else's. Two players with a menu
open at once are independent without either knowing the other exists — see
[Who a node answers to](#who-a-node-answers-to).

It draws nothing when `screen_for` has no region for that player: an empty seat,
or anybody while the split is collapsed.

### Collapsing the split

```ruby
node.system(RGame::Engine::Viewports).solo!(cutscene_camera)
node.system(RGame::Engine::Viewports).split!
```

`solo!` collapses to one screen-wide view — for a cutscene, or anywhere the world should
be seen through a single camera. **The camera is required**: promoting one player's would
silently give everyone else their view, and choosing what is on screen is what a cutscene
is for. Point an ordinary `Camera` however you like (a `CameraFollow` on a cutscene actor
works) and hand it over.

Both are **deferred**, like `queue_free`: they record a request and it takes effect on the
next tick. This system is reachable from anywhere including a `draw`, and a `draw` runs
once per view, so applying immediately would tear the frame it was requested in.

A full-screen UI — a results screen, a pause panel — usually wants no collapse at all:
draw it in screen space, outside any `WorldView`, and it covers the whole window over
whatever the players are seeing.

## Components

`RGame::Engine::Component` (`rgame/engine/component`) is a piece of behaviour you attach to a
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

## Pausing a subtree

```ruby
world_view.paused = true    # the world stops; an overlay above it does not
walker.paused = true        # or just one node, while its owner is in a menu
```

A paused node skips `control` and `update` — and so does everything under it,
because a subtree is only ever reached through its parent. **It still draws.**
Pausing is about time, not visibility, which is what lets a frozen world sit
under a cutscene that keeps animating.

It is a property of a *node* rather than of the world on purpose. "Pause the
world" is `world_view.paused = true` with no new concept, and the same flag
stops one player's character while they browse a menu without touching the
simulation everyone else is in.

There is no `abs_paused` to go with `abs_input_owner`: ownership has to be
resolved because a node needs to know whose input it reads even when its parent
claims nobody, while a paused node simply never descends.

`draw` still resolves the transform, so a paused node under an ancestor that is
still moving is drawn where it now is rather than where it was when it stopped.

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
