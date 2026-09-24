# Scene graph

**A game is a tree of nodes.** A node holds the state, logic and drawing of one
game object, and nested nodes build whole scenes. The tree is pure Ruby. Nodes
draw through the renderer interface and read input from a per-tick snapshot. They
never name a graphics library.

## Node2D

`RGame::Engine::Node2D` (`engine/node2d`) is the basic building block. A node
carries:

- a **transform**: `x`, `y` and `angle` relative to its parent, plus `width` and
  `height`, and a `z` that orders it among its siblings;
- **children**: other nodes nested under it (`add_node`);
- **components**: reusable pieces of behaviour attached to it (`add_component`);
- a **parent**: the node it hangs off, set when it is added.

Nodes extend the signal DSL (`RGame::Engine::Signal::DSL`), so any subclass can
declare and emit signals. See [Signals](signals.md).

### Elevation

`node.elevation` lifts a node's picture above the ground, in pixels, for a
top-down view. It defaults to 0, and positive is up the screen.

**Elevation is not part of the transform.** `y`, `world_y`, colliders, cameras and
children all ignore it. A character can therefore leave the ground while its feet
box and the camera following it stay put. Components that draw the node's
picture read it: `Components::Sprite` and `Components::AnimatedSprite` draw
lifted. `Components::Hop` writes it. A node's own `_draw` is not lifted, so the
parts that stay on the ground go there:

```ruby
require 'rgame'

class Hero < RGame::Engine::Node2D
  SHADOW = RGame::Util::Color.rgba(0, 0, 0, 90)

  def initialize(**)
    super
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: 80))
    add_component(RGame::Engine::Components::Hop.new(peak: 18, duration: 0.5))
  end

  # A shadow at the feet: drawn in _draw, so it stays down while the sprite rises.
  def _draw(renderer, _view)
    renderer.rect(2, 19, 12, 3, color: SHADOW)
  end
end
```

### The tick: control → update → draw

The engine drives a node in three phases, always in this order:

1. `control(actions)` reads intent, from the player (the `actions` snapshot) and
   from AI or scripted controllers.
2. `update(dt)` advances game logic and physics over the timestep `dt`.
3. `draw(renderer, view)` renders the current state into `view`, the viewport
   being drawn.

**The first two run once per simulation tick; `draw` runs once per rendered
frame.** The counts differ. The loop uses a fixed timestep, so a slow frame runs
several ticks before it draws. A frame in which nothing advanced skips the draw.
A `draw` must therefore depend on state alone and never read a clock. See
[The frame loop](app.md#the-frame-loop).

**Each phase settles the node first, then descends into its children.** Settling
means the node's components run, then its own hook. You override the hook, not
the phase:

- `_control(actions)`
- `_update(dt)`
- `_draw(renderer, view)`

A hook is named after the phase that calls it, with a leading `_`. The `_` marks
a method the engine calls and your code overrides. A name starting with `on_` is
a [signal](signals.md), which you connect a block to instead.

**A subclass may define a `_` method only if it is a hook.** A misspelled hook,
such as `_updte`, would never be called, so `RGame::Engine::Hooks` raises
`NameError` when the class loads and lists the hooks the class has.
`Node2D.hooks` returns the same list. Name a helper without the leading `_`. A
class that adds a hook for its own subclasses declares it with `hook` before
defining it:

```ruby
require 'rgame'

class Enemy < RGame::Engine::Node2D
  hook :_die

  # Called once the enemy's health reaches 0. Draws no explosion unless a subclass does.
  def _die; end
end

Class.new(Enemy).hooks.include?(:_die) # => true
```

`Component` follows the same rule, with its own hooks.

`view` is the viewport the node is drawn into: its rectangle and the camera, if
any. Most nodes ignore it. Two tasks need it. One is laying out against the edges
of *this* region, not the whole window (`view.x`, `view.width`). The other is
culling (`view.visible?(x, y, w, h)`), which matters once the world is drawn once
per player. See [Viewports](#viewports-and-views).

The hooks run self before subtree, but no position depends on that order. A world
position is computed when read, from wherever everything is at that moment. See
[The two spaces](#the-two-spaces).

The traversal recurses into children for you. **Never iterate children
yourself**: add them with `add_node` and let the tree drive them.

**A subclass cannot replace a `Node2D` method whose name starts with `rgame_`.**
Those methods are the machinery the phases call, such as `rgame_draw_content`
and `rgame_resolve_inherited`. A subclass method with the same name would take
its place without warning. So `RGame::Engine::SealedPrivates` raises `NameError`
when the class loads, naming both methods. `Component` follows the same rule. A
non-public method *without* the prefix is a seam, meant to be overridden with
`super`. `Node2D` has one: `draw_children`; see
[View transforms and the camera](#view-transforms-and-the-camera). Only these
two classes guard prefixed methods; engine subclasses do not.

### The two spaces

**`x`, `y` and `angle` are relative to the parent.** They are the only position a
node sets, and the space it lives in. `rel_x`, `rel_y` and `rel_angle` are long
names for the same three.

`world_x`, `world_y` and `world_angle` accumulate that transform over the whole
ancestry. `world_x` is `parent.world_x + x`, with the parent's rotation applied.
A node with no parent sits at the origin.

`world_x=` and `world_y=` place a node at a world coordinate. They compute the
local position that puts it there and leave the other coordinate alone. They
*write `x` and `y`*; they are not a second position. The node still lives in its
parent's space. The write stays exact under a rotated ancestor, where moving along
one world axis changes both local coordinates. On a node without a parent they
change nothing, because that node sits at the origin.

```ruby
require 'rgame'

root = RGame::Engine::Node2D.new
container = root.add_node(RGame::Engine::Node2D.new(x: 100, y: 40))
child = container.add_node(RGame::Engine::Node2D.new(x: 10, y: 5))
child.world_x = 250
child.x       # => 150
child.world_x # => 250
```

**World coordinates are computed when read, and cached.** Moving a node marks it
and its whole subtree stale. The next read walks up to the nearest current node
and recomputes back down. Two properties follow, and the engine relies on both:

- **A world position is never stale.** No phase takes a snapshot, so nothing goes
  out of date. Every case answers correctly, at any point in any phase: a node
  that moved, a node whose *ancestor* moved, a node reparented this tick, and a paused
  node under a moving ancestor.
- **The engine computes nothing for a node nobody asks about.** A frame in which
  nothing moves costs nothing.

Two things invalidate a world position. One is writing `x`, `y` or `angle`. The
other is a new parent through `add_node` or `remove_node`: the same offset from
somewhere else is still a move.

**A move reaches every node that names the mover as its `parent`**, whether or not
it is in the mover's `children`. `SceneStack` holds its scenes off the child list
and sets each one's `parent`, and a scene follows its host when the host moves. A
container of your own that holds nodes the same way needs nothing more than
setting `parent`, and setting it to `nil` lets the node go.

**Which one to use.** Drawing needs neither; see "Drawing happens in local space"
below. Game logic that reasons about the world reads `world_x`: a distance, a
collision, a camera target. To move a node, write `x`. Write `world_x=` when the
destination was decided in world space.
[`ScreenWrap`](components.md#screenwrap) uses it to put a node on the far edge of
the world, and a [`Mover`](components.md#mover) to write back a resolved step.

**No phase resolves the transform.** Keep that in mind when a spec drives one
phase and asserts on another's answer. The phases do resolve the *inherited*
attributes, which are not coordinates:

| Phase | Resolves | Because it reads |
|---|---|---|
| `control` | `abs_input_owner` | whose actions to hand each node |
| `update` | nothing | it reads neither |
| `draw` | `abs_band` | to open the node's own layer |

**`z` is not among them, and there is no `abs_z`.** A node's depth comes from
where the traversal reaches it, not from a sum of its ancestors' values. See
"Draw order" below.

### Drawing happens in local space

**A node's `_draw` never mentions where the node is.** `Node2D#draw` pushes the
node's transform onto the renderer before the node and its children draw. Inside
`_draw`, the origin *is* the node, turned the way the node is turned:

```ruby
def _draw(renderer, _view)
  renderer.rect(0, 0, width, height)   # this node's own box, wherever it is
end
```

Passing a position there applies it twice. Both spellings go wrong. `world_x`
doubles the whole ancestry, camera included. `x` doubles the node's own offset.
Neither raises. The mistake shows only when the node sits under a parent away from
the origin. The `Game/DrawInLocalSpace` cop flags both.

A **component** drawing for its node runs on the same path and also draws at
`0, 0`. It may still ask the node for `node.world_x`, for example to cull against
the camera. That reads another object's coordinate, not its own.

The renderer's transform stack makes this work. The same mechanism gives a
`WorldView` its camera: one `renderer.translated` around a subtree, composed with
every other.

### Draw order

**A node's `z` orders it among its siblings, and nowhere else.** The traversal
draws the tree depth-first, with siblings in `z` order:

```ruby
sky.add_node(Clouds.new(z: 2))
sky.add_node(Birds.new(z: 1))
sky.add_node(People.new(z: 0))
```

This draws people, then birds, then clouds. Each may consist of any number of
child nodes. **A subtree is atomic**, so no part of `clouds` can end up behind
`birds`, and no part of `birds` in front of `clouds`.

Only the comparison matters. The engine never adds `z` to anything and never
passes it to the renderer, so its magnitude means nothing. `1` and `1_000_000`
behave the same if they are the only two children, and negatives are ordinary.
Nodes with equal `z` keep the order they were added in.

**A band overrules all of it.** `band:` is `:world` (the default), `:hud`,
`:overlay` or `:debug`. Children inherit it, like `input_owner`:

```ruby
scene.add_node(RGame::Engine::PlayerLayer.new(player: player))  # :hud
scene.add_node(Cutscene.new(band: :overlay))
```

Everything in `:world` draws under everything in `:hud`, whatever either asked
for. No `z:` a node passes can cross the gap. `WorldView` declares `:world` and
`PlayerLayer` declares `:hud`, so most games never name a band. A node that must
leave its inherited band says so with `band:`, the one explicit way out.

`Node2D#draw` turns all of this into the single number the renderer sorts on. It
opens a layer per node, taking the next slot in the node's band. See
[Drawing](drawing.md#draw-order) and `RGame::Util::Z`.

### Opacity

**`opacity` fades a node and everything under it.** It runs from 0, which draws
none of the subtree, to 1, the default, which changes nothing:

```ruby
ghost.opacity = 0.5   # the ghost, its components and its children, at half their alpha
```

`Node2D#draw` applies it the way it applies the transform: around the node's
components, its `_draw` and its children. A child cannot draw outside it, and a
`_draw` cannot forget it. A child's own `opacity` multiplies with its parent's,
so 0.5 under 0.5 draws at a quarter. Each node's `opacity` reads back only what
was set on that node.

To fade a node in or out, change `opacity` in `_update`, from a
[`Tween`](toolbox.md#tween--a-value-that-moves-over-time) for instance. The
colours it draws with stay the same, so the fade builds no new `Color` in any
frame. [`ScreenFade`](toolbox.md#screenfade--cover-the-view-and-flash-it)
is a node built this way.

**Only drawing changes.** A node at 0 is not drawn at all, but it still takes
part in `control` and `update`, and its colliders still collide. Hide something
that should also stop with `paused` as well, or remove it.

Setting `opacity` checks the value at once. A number outside 0..1 raises
`ArgumentError`, and anything that is not a number raises `TypeError`, as
[`renderer.faded`](drawing.md#blending-and-fading) does.

### Who a node answers to

**`control` receives an input source, not one player's snapshot.** The source is
a [`RGame::Engine::Players`](input.md) registry, or a bare `Actions` when only one
answer exists. Each node asks the source for the actions of the player who owns
it. It then hands that plain `Actions` to its components and its own
`_control`.

`input_owner` sets ownership. **Children inherit it, the way the transform
accumulates.** `control`, the one phase that reads ownership, resolves it onto
`abs_input_owner`:

```ruby
ship.input_owner = game.players[1]   # the ship and everything under it
```

A node that names nobody inherits its parent's owner. A tree that names nobody
anywhere reads the primary player. Single-player games therefore never mention
ownership.

A node every player drives at once, such as a pause menu during `solo!`, takes
[`players.everyone`](input.md#everyone-at-once) as its owner.

The *source* descends through the tree, not the resolved snapshot. Two subtrees
in one traversal can thus read two different controllers, while each component
still receives a plain `control(actions)`.

> The attribute is `input_owner`, not `player`, because a game's scene usually
> calls its hero node `@player`. It is not `controller` either, because a
> controller is the component that produces movement intent.

### View transforms and the camera

**A node that owns a view transform overrides `draw` and calls `super` inside
it.** A node's own transform is its place in its **parent**, and `draw` pushes it
as the traversal descends. A *view* transform differs. It maps the world onto the
screen, as a camera does. It belongs to no node in the tree. It must wrap a whole
subtree's draw, including the subtree root's own drawing.

`draw_children` is a separate seam. Override it to wrap or skip the *children's*
draw while the node still draws itself. `examples/game_menu`'s menu closes by not
calling `super` from it.

`examples/scroll_map` is the smallest program with a camera: a `WorldView`, a map
under it, and one node the camera follows.

A `WorldView` also draws the debug layer's solid cells: while the `:shapes`
channel is on, it puts a box over every solid cell of its scene's
`Components::TileWorld` that the viewport can see. It is the node that does it
because it is the one already drawing once per viewport in world space, so the
cells follow each camera with nothing mounted. A scene with no `TileWorld` draws
none. See [Systems](systems.md#debug--a-switch-per-channel).

### Two words that are easy to confuse

**Space** is structural, and the tree enforces it. A node is either inside a
`WorldView` or not. That decides what its coordinates mean and how often it is
drawn.

**Band** is an ordering partition: `:world`, `:hud`, `:overlay`, `:debug`. It is
structural too. Children inherit it, and `WorldView` and `PlayerLayer` declare
it. But it decides *what covers what*, not what coordinates mean. See
[Drawing](drawing.md#draw-order).

The two partitions differ. All screen-space content forms one *space* and draws
once. Bands subdivide that space by what should cover what.

**`RGame::Engine::WorldView` is where world space begins.** Its children draw in
their own local space and never know about a camera. The `WorldView` draws its
subtree **once per active viewport**. Each time, it clips to that viewport's
rectangle and translates by its camera. A child drawing at its own origin lands
wherever that viewport looks:

```ruby
view = scene.add_node(RGame::Engine::WorldView.new)
view.add_node(player)     # world coordinates
```

Everything *outside* a `WorldView` is screen space and draws once. That one line
separates a HUD from the world. The game decides where to draw it; the engine
imposes nothing above the game's root.

**A `WorldView` takes no camera.** Cameras belong to players
(`RGame::Engine::Player#camera`). The `WorldView` asks
`node.system(RGame::Engine::Viewports)` which viewports exist. So the same subtree
serves one player or four, with nothing below it changing. A camera owned by a
node *inside* the world could not do that. The world would have to know how many
times it is drawn.

**Only `draw` multiplies.** `control` and `update` run once per node per tick,
however many players watch. Simulation cost therefore stays independent of player
count. It also makes the rule that `draw` only renders state essential: a `draw`
with a side effect runs once per player.

`examples/split_screen` is the smallest program with two viewports: one `Ground`,
two walkers, a badge each, and a second player who joins mid-session.

## Viewports and views

`RGame::Engine::Viewports` is a root-scoped system that divides the screen.
`RGame::Engine::Layout` holds the pure arithmetic behind it. A
`RGame::Engine::View` is one viewport being drawn.

```ruby
viewports = node.system(RGame::Engine::Viewports)
viewports.views              # one View per active player — what a WorldView draws through
viewports.screen             # the whole window, no camera — screen space
viewports.screen_for(player) # that player's own region, no camera — their HUD and menus
```

**`screen_for` returns the rectangle that player's world view uses.** A HUD laid
out at (10, 10) lands ten pixels inside the region of the world beneath it. It
returns **nil** when the player has nowhere to draw. An empty seat has no
viewport. While the split is collapsed, nobody owns a part of the screen: a
cutscene is everyone looking at one thing. Content that must stay on screen
through a cutscene belongs in the global `:overlay` band.

A **`View`** carries `x`, `y`, `width`, `height`, its `camera` (nil in screen
space) and its `player`. Nodes mostly use two more members:

| | |
|---|---|
| `view.visible?(x, y, w, h)` | is this worth drawing at all |
| `view.offset_x` / `offset_y` | the translate that maps its contents onto the screen |

**`Viewports` reuses its views instead of rebuilding them.** It updates one `View`
per viewport each frame, the way `ActionMapper` reuses its `Actions`. Building
fresh views would allocate every frame. Hold the player or the viewports, never a
`View`.

**`Layout` answers one question**: given a count and a window, where does each
viewport go? It keeps no state and no anchors. One viewport gets the window, two
get a row each, and three or four share a 2x2 grid. It computes edges as
`(i * total) / count`, so the rectangles tile exactly and an odd-sized window has
no seam.

```ruby
require 'rgame'

RGame::Engine::Layout.rects(3, 640, 480) # => [[0, 0, 320, 240], [320, 0, 320, 240], [0, 240, 320, 240]]
```

`Layout.each_rect(count, width, height)` yields `index, x, y, width, height` for
each viewport and allocates nothing. `rects` returns the same rectangles as an
Array. The shapes it picks from are public too: `each_row(count, width, height)`,
`each_column(count, width, height)` and `each_cell(count, cols, rows, width,
height)`, which fills a grid left to right, top to bottom.

### A player's own screen

**`RGame::Engine::PlayerLayer` draws its subtree once, inside one player's
region.** It clips to that player's viewport and translates to its corner, in
screen space.

```ruby
layer = scene.add_node(RGame::Engine::PlayerLayer.new(player: game.players[1]))
layer.add_node(inventory)
```

A frame holds three kinds of content. `WorldView` draws the world once per
viewport, under a camera. Any other node draws a global overlay once across the
window. `PlayerLayer` draws once per player, inside that player's region.

`PlayerLayer` declares the `:hud` band. Everything under it draws over the world
without saying so.

**Children position themselves relative to the layer.** A node at (10, 10) sits
ten pixels inside *that player's* region, wherever the layout put it. The same HUD
class serves any player unchanged. To lay out against the far edge, use the view's
**size**: `view.width - margin`. `view.x` and `view.y` place the region on the
window; they belong to the clip, not the layout. Adding them would offset twice.

**`PlayerLayer` sets `input_owner`**, and children inherit ownership. A menu
anywhere under it reads that player's controller and nobody else's. Two players
can each have a menu open, and neither menu knows about the other. See
[Who a node answers to](#who-a-node-answers-to).

It draws nothing when `screen_for` has no region for its player: an empty seat,
or any player while the split is collapsed.

### Collapsing the split

```ruby
node.system(RGame::Engine::Viewports).solo!(cutscene_camera)
node.system(RGame::Engine::Viewports).split!
```

**`solo!` collapses the screen to one view through the camera you pass.** Use it
for a cutscene, or anywhere the world should be seen through one camera. **The
camera is required.** Promoting one player's camera would silently give everyone
that player's view, and choosing what is on screen is a cutscene's whole job.
Point an ordinary `Camera` however you like, for example with a `CameraFollow` on
a cutscene actor, and pass it in.

**Both calls are deferred**, like `queue_free`. They record a request that takes
effect on the next tick. `solo?` answers for the mode in effect, so it changes on
that tick too. Any code can reach this system, including a `draw`. A
`draw` runs once per view, so an immediate change would tear the frame that
requested it.

A full-screen UI, such as a results screen or a pause panel, usually needs no
collapse. Draw it in screen space, outside any `WorldView`, with `band: :overlay`.
It then covers the whole window over the players' views, HUDs included.

## Components

**A `RGame::Engine::Component` (`rgame/engine/component`) is behaviour you attach
to a node** instead of building it into a subclass. A component knows its owning
`node`, and extends the signal DSL like a node.

- `add_component(component, as: nil)` attaches a component in a **named slot**
  and links it to the node. The slot defaults to the component's class, so a node
  holds **at most one component per class** by default. A taken slot raises. Pass
  a name when a node needs several of one type:
  `add_component(Timer.new, as: :spawn)`.
- `get_component(key)` looks a component up by slot. The key is a class, matched
  by ancestry so a base class finds a subclass instance, or a Symbol name. A class
  lookup **raises if it is ambiguous**, when several components share the type.
  Name them and look them up by name.
- `remove_component(key)` detaches the component in that slot (class or name) and
  returns it, or `nil` if the slot is empty.

A component has a hook for each of the node's three phases: `_control(actions)`,
`_update(dt)` and `_draw(renderer, view)`. In each phase the node drives its components before its
own hook and before its children. Components also have two tree-lifecycle hooks,
`_attach` and `_detach`, described below.

## Lifecycle: constructing vs. entering the tree

**A node has two distinct moments.** Mixing them up causes bugs that are hard to
trace.

1. **Construction** (`initialize`): the node and its components exist, but the
   node is **not yet in the live tree**. Its anchors are unresolved: `root` and
   `scene` (below) point nowhere useful, and shared systems are out of reach.
   Build children and attach components here. Do **not** look anything up across
   the tree.
2. **Entering the tree**: when the node goes live, the engine runs a depth-first
   cascade. It fires each component's `_attach`, then the node's `_enter_tree`, then
   the same for every child. **Anchors and systems are available here**, so a
   component registers with a shared system at this point. Leaving the tree runs
   the mirror cascade: children first, then `_exit_tree`, then each component's
   `_detach` to release its registrations.

The engine drives this; you never call it. It uses `enter_tree`, `exit_tree` and
`in_tree?`, fired at these points:

- `add_node` enters the child at once **only if** the parent is already live.
  Otherwise the child enters when its ancestor does. A tree assembled in
  `initialize` therefore comes alive all at once when it is mounted. `remove_node`
  exits the subtree the same way.
- `add_component` and `remove_component` fire `_attach` and `_detach` at once
  when the host node is live. Otherwise attachment happens when the node enters.
- A `SceneStack` switch enters its new scene as it lands, when the stack's host
  is in the tree, and exits the scene it takes off. `RGame::Game#start` enters
  the root once, at boot.
- The cascade reaches every node that names the entering or leaving node as its
  `parent`, on the child list or off it. So the scenes on a `SceneStack` are in
  the tree exactly while its host is, all of them, not only the current one. A
  node whose parent is outside the tree stays out when told to enter, and enters
  with the parent.

**Put cross-tree lookups in `_enter_tree` or `_attach`, never in `initialize`.** That
covers anchors, systems and sibling components. The engine wires the anchors
before those hooks run, so you cannot read them too early.

The mirror rule is that *attaching* components belongs in `initialize` or a
builder. Use `_enter_tree` only when the component's constructor needs the tree. See
[Where to add a component](components.md#where-to-add-a-component).

## Anchors and shared systems

Two back-links let any node reach shared state without constructor arguments.
**The engine resolves both by walking up the parents**, never caching them, so
they cannot go stale:

- `root` is the top-most node; a node without a parent is its own root. Global
  systems that live as long as the program belong there.
- `scene` is the nearest enclosing scene node, marked as a boundary by
  `SceneStack`. Systems that live as long as a scene belong there.

A *system* is a `Component` on one of those anchor nodes. A node finds one with
`node.system(SomeSystem)`, which checks the nearest scene, then each scene
around it, and then the root. See
[Systems & shared resources](systems.md) for the scoping model and worked
examples.

## Pausing a subtree

```ruby
world_view.paused = true    # the world stops; an overlay above it does not
walker.paused = true        # or one node, while its owner is in a menu
```

**A paused node skips `control` and `update`, and so does its whole subtree**,
because the traversal reaches a subtree only through its parent. **It still
draws.** Pausing concerns time, not visibility. A frozen world can therefore sit
under a cutscene that keeps animating.

Pausing belongs to a *node*, not to the world. "Pause the world" is
`world_view.paused = true`, with no new concept. The same flag stops one player's
character while they browse a menu, without touching everyone else's simulation.

No `abs_paused` exists to match `abs_input_owner`. A node needs its resolved owner
even when its parent names nobody. A paused node, by contrast, never descends.

**A press begun while a node was paused has no edges for it.** It reads the
button as held once it runs again, but `pressed?` and `released?` stay false
until the next press. See
[A node reads only the presses it saw start](input.md#a-node-reads-only-the-presses-it-saw-start).

A paused node under a moving ancestor draws where it is now, not where it
stopped. The engine also culls it against its current position. Neither depends
on the node running a phase. The traversal pushes the transform as it descends,
and `world_x` computes itself when read. See [The two spaces](#the-two-spaces).

## Deferred free

**Removal is deferred.** A node that detached itself or a sibling mid-tick would
change a parent's `children` while the traversal iterates that list.

- `queue_free` marks a node for removal, and `freed?` reports the mark. The node
  stays in the tree and keeps ticking until the sweep.
- `sweep_freed` detaches every marked node, depth-first, and runs the normal
  leave-tree cascade (`_exit_tree` / `_detach`) on each. The game loop calls it
  once per step, after `update`, outside the traversal.

Any component or hook can therefore call `node.queue_free` from inside `update`
without corrupting the traversal. A component that holds nodes outside the normal
child list, such as `SceneStack`, overrides `Component#_sweep_freed` to pass the
sweep into the subtree it owns. A `SceneStack` also lands its switches there.

`enter_tree` clears the freed flag, so a node detached and added again comes back
alive. Pools rely on this. A despawned node returns to its pool, and acquiring it
and calling `add_node` revives it cleanly.

## Scenes: `SceneStack`

**A game's scenes sit on a stack**, a component on a host node, usually the
root. `RGame::Engine::Scene::SceneStack` controls and updates only the top
scene, and draws every scene from the bottom up. A menu pushed over the world
therefore keeps the world on screen, frozen.

```ruby
require 'rgame'

class TitleScene < RGame::Engine::Node2D; end

class GameOverScene < RGame::Engine::Node2D
  attr_reader :score

  def initialize(score:)
    super()
    @score = score
  end
end

root = RGame::Engine::Node2D.new
stack = root.add_component(RGame::Engine::Scene::SceneStack.new)
stack.define(:title) { TitleScene.new }
stack.define(:game_over) { |score:| GameOverScene.new(score:) }
root.enter_tree

stack.push(:title)
stack.current                          # => nil — asked for, and not landed
stack.pending?                         # => true
root.sweep_freed                       # RGame::Game sweeps after every tick
stack.current                          # => TitleScene

stack.replace(:game_over, score: 12)   # keywords reach the builder
root.sweep_freed
stack.current.score                    # => 12
```

- `push(scene)` puts a scene on top, and the one below stays. `replace(scene)`
  takes the top scene off first. `pop` takes it off, and a pop on an empty
  stack changes nothing.
- A scene is a node, or a name given to `define`. The block builds a new scene
  each time a switch to that name lands, and takes the keywords the switch
  passes.
- `current` is the top scene, or nil on an empty stack.
- `pending?` answers whether a switch was asked for and has not landed.
- `on_changed { |scene| ... }` fires once for each switch that lands, after the
  new top scene entered the tree. It carries that scene, or nil once the stack
  is empty.
- `on_requested { |scene, transition| ... }` fires as a switch is asked for,
  before it lands. It carries the name or node asked for, or nil for a pop, and
  the `Fade` the switch runs, or nil. A switch that raises fires nothing.

### A switch lands in the sweep

**`push`, `replace` and `pop` only record what was asked.** The switch lands in
the sweep after the tick, where a `queue_free` lands, whichever node asked and
in whichever phase. A menu item activates during `control`, in the middle of a
walk over the scene the switch would take apart. Waiting for the sweep means
nothing is walking it.

So `current` changes when the switch lands, not when it is asked for. The scene
leaving still finishes the tick it asked in, and the scene arriving is first
controlled and updated on the next tick. A scene pushed from a root's
`_enter_tree` lands in the first sweep, so the first frame shows no scene.

**Two switches asked for before one sweep keep only the last.** A Back item and
Escape pressed on the same tick are one pop, not two.

### Names and keywords

A name is a Symbol, defined once per stack. The stack checks each switch to a
name when it is asked for, not when it lands, so a mistake raises where it was
made:

- a name the stack was not given raises `KeyError`;
- a keyword the builder requires and the switch leaves out raises
  `ArgumentError`, and so does a keyword the builder does not take;
- keywords beside a node, rather than a name, raise `ArgumentError`.

A builder takes keywords only. `define` raises for one that takes positional
parameters, or that declares `carry` or `transition`, which are the stack's own.

### Carrying a node into the next scene

```ruby
stack.define(:village) { |hero:, entrance:| VillageScene.new(hero:, entrance:) }
stack.replace(:village, entrance: :south_gate, carry: { hero: hero })
```

**`carry:` takes a node from one scene into the next.** As the switch lands,
the stack takes each node in `carry:` from its parent, before the old scene
leaves the tree. It hands each to the builder under its key, and the builder
puts it in the new scene.

The node's components leave the old scene's systems as the stack takes it, and
join the new scene's as it enters with that scene. A collider leaves one
`CollisionWorld`'s index and joins the next, and a `CharacterBody` is stopped by
the new scene's map. The node keeps its `x` and `y`, so the builder places it.

A key in `carry:` is checked against the builder as a keyword is, and a key
given as a keyword too raises `ArgumentError`. `carry:` beside a node rather
than a name raises `ArgumentError`, and anything but a Hash of names to nodes
raises `TypeError`.

### Transitions

```ruby
stack.transition = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)
stack.replace(:play)                     # covers, switches, reveals
stack.push(:settings, transition: nil)   # this switch without one
stack.transitioning?                     # covering or revealing
```

**A transition covers the view, switches while it is covered, and reveals the
new scene.** `RGame::Engine::Scene::Fade` describes one: a `color`, black unless
given, and `cover` and `reveal` durations in seconds, which must be positive. It
is a frozen value.

The stack builds one `ScreenFade` the first time a transition runs, and holds it
off the host's child list as it holds its scenes. It draws the fade after every
scene, over the host's view, in the `:overlay` band.

- **The switch lands in the sweep after the cover ends.** `on_changed` fires
  then, under a full cover, and the reveal starts.
- **Music that should cross over the cover starts at the request.** Start it
  from `on_requested`, which fires as the cover begins, rather than from
  `on_changed`.
- **No scene is controlled until the reveal ends.** The scene leaving is not
  updated under the cover, and the scene arriving is updated from the tick after
  it lands. A scene's first press after a transition therefore began after it:
  the press gate refuses one begun under the cover, as it refuses any press a
  node did not see start. See
  [A node reads only the presses it saw start](input.md#a-node-reads-only-the-presses-it-saw-start).
- **A push onto an empty stack starts covered**, since there is nothing to
  cover, lands in the first sweep, and reveals.
- **A switch asked for during a cover replaces the one waiting**, and the cover
  goes on. **One asked for during a reveal covers again** from where the reveal
  got to. Either joins the transition under way when it has none of its own.

`transition` is `nil` until set, and a switch without one lands in the next
sweep. `transition:` on `push`, `replace` or `pop` runs another `Fade` for that
switch, and `nil` runs none. Anything but a `Fade` or `nil` raises `TypeError`.

A paused host holds its transition where it is, since time reaches the fade
through the stack's `update`. A menu pushed over a world usually wants
`transition: nil`: a fade would hide the world that pushing keeps on screen.
