# Internal building blocks

**The engine's [components](components.md) and [systems](systems.md) are built on
these low-level, pure-Ruby classes.** A game author rarely constructs them. They
sit *behind* components:

- a blocked `Mover` resolves through `CollisionSystem`;
- an `AnimatedSprite` plays through an `Animator`;
- a `CollisionWorld` indexes through a `SpatialHash` and remembers contacts
  through a `ContactSet`.

This page documents them because they hold the core algorithms, and component
specs drive them directly.

[Toolbox](toolbox.md) covers the helpers a game *does* use directly: pools,
the camera, collision boxes. [Localization](localization.md) covers `I18n`.

## `SpatialHash` — uniform-grid broadphase

**`RGame::Engine::SpatialHash` (`rgame/engine/spatial_hash`) is a broadphase index
for collision.** It buckets colliders into fixed-size grid cells, then tests only
candidates that share a cell, not every pair. It is the index inside
[`CollisionWorld`](components.md#collisionworld).

```ruby
hash = RGame::Engine::SpatialHash.new(cell_size: 64)
hash.clear                                  # empty every cell, keeping its Array
rocks.each { |r| hash.insert(r, *r.aabb) }  # insert the static set
hash.query(*bullet.aabb) { |rock| ...narrowphase... }
```

A typical frame calls `clear`, inserts every collider of one set, then runs
`query` around each moving collider. `insert` and `query` both take an AABB
(`x, y, w, h`).

`remove(item, x, y, w, h)` undoes one `insert`. Pass the box the item was
inserted at, not where it is now: the hash does not remember where it put
anything. Removing an item that is not there does nothing.

**The hash holds only the cells in use.** `clear`, and a `remove` that empties a
cell, keep the cell's Array for the next insert, wherever that lands. A frame
that fills as many cells as the one before allocates nothing, however far its
colliders have moved. So the hash grows with the most cells in use at once, not
with every cell a walker has crossed.

**`query` may yield an item more than once.** An item spanning several cells sits
in each of them. Removing repeats is the narrowphase caller's job, which spares the
hash a per-query visited set and keeps it allocation-free. `CollisionWorld` checks
each pair against the [`ContactSet`](#contactset--the-two-edges-of-a-contact) it
fills for the step, which it needs anyway. A caller that only *selects*, like
`nearest`, ignores repeats instead. The hash packs each cell key into one tagged
Fixnum, offset so negative cells stay non-negative. Keying therefore allocates
nothing either.

`query_circle(cx, cy, r, &)` is the radial form of `query`. It yields the items in
the cells the circle's bounding box covers, through the same cell walk. Use it for
range and nearest lookups. It remains a broadphase with the same may-yield-twice
contract. The caller refines candidates by true distance (see
[`CollisionWorld`](components.md#collisionworld)'s `query_circle` and `nearest`).

`cell_empty?(x, y)` asks whether the single cell *containing the point* `(x, y)`
is empty. It takes a point, not a region, so pass any coordinate inside the cell
you mean. It allocates nothing. Neither it nor `query` stores anything for a
cell that holds nothing.

**The cell walk is half-open on the far edge.** The hash buckets an item by its
bounding box. A box ending exactly on a cell boundary stops at the cell before it.
A piece filling one cell therefore lands in that cell only. "Bucketed here" means
exactly "overlaps this cell's area", so `cell_empty?` tests occupancy, not
candidacy. `CollisionBox.overlap?` uses the same convention, and the two must
agree. Bucketing one cell too far would only cost extra candidates. Bucketing one
cell short would miss a real contact.

The index cannot know whether an occupant still counts.
[`CollisionWorld#cell_empty?`](components.md#collisionworld) therefore wraps this
method and skips colliders whose node is queued for removal.

## `ContactSet` — the two edges of a contact

**`RGame::Engine::ContactSet` (`rgame/engine/contact_set`) turns a per-step overlap
test into two edges**: the step a pair *starts* touching and the step it *stops*.
[`CollisionWorld`](components.md#collisionworld) owns one per registered collider
and is its only driver there. Nothing in the class concerns overlap, though, and
it has a second user. Every [`Mover`](components.md#mover) keeps one of what
stopped its step, and derives `on_blocked` / `on_unblocked` from it the same way.
Underneath its names, the class is "the set of things true this step and last".

```ruby
contacts.begin_frame              # last step's list becomes the one to compare against
contacts.touching?(other)         # already recorded this step? (the broadphase repeats)
contacts.started?(other)          # not touching last step, so this is an on_hit
contacts.add(other)               # record it for this step
contacts.each_ended { |o| ... }   # touching last step, not now, so this is an on_separated
contacts.reset                    # forget both steps — a pooled collider registering again
```

**It uses two arrays, swapped each step, and checks membership by a linear scan
on identity.** Both choices serve the per-frame path. `Array#clear` keeps the
capacity the array grew to, so a lasting contact allocates nothing after the first
few steps. A Set or a Hash would allocate on every insert. A collider touching more
than a handful of things at once points to a design problem elsewhere; it is no
reason to index this.

`started?` reads only the previous step's list. It answers the same before and
after `add`, so the world can use it as a guard in step order.

## `TileBlockers` — the tile grid as a blocker source

**`RGame::Engine::TileBlockers` (`rgame/engine/tile_blockers`) resolves an
axis-aligned box against the solid tiles of a
[`Util::SolidGrid`](values.md#rgameutilsolidgrid)**, at a given tile size.
[`TileWorld`](components.md#tileworld) builds one over the grid it reads the map
into; a spec builds the grid itself. `TileBlockers` reads the grid and never copies
it, so a cell changed with `set_solid` stops the next step. It resolves each
axis on its own. [`CollisionSystem`](#collisionsystem--move-an-actor-against-its-blockers)
feeds one axis's result into the other.

```ruby
require 'rgame'

grid = RGame::Util::SolidGrid.build(20, 15) { |col, _row| col == 5 }   # a wall at x 80..96
tiles = RGame::Engine::TileBlockers.new(grid: grid, tile_width: 16, tile_height: 16)

x, y, w, h = 58.0, 32.0, 12, 6
nx = tiles.resolve_x(x, y, w, h, 14.0)   # => 68.0 — snapped flush against the wall's left edge
ny = tiles.resolve_y(nx, y, w, h, 4.0)   # => 36.0
tiles.travel?(10.0, 32.0, w, h, 50.0, 0.0)   # => true
tiles.travel?(10.0, 32.0, w, h, 90.0, 0.0)   # => false — the wall is in the way
```

[`Util::TileSweep`](values.md#rgameutiltilesweep) does the arithmetic, in C;
`TileBlockers` presents it as a blocker source. Results are Floats. It assumes each
step moves less than a tile, so nothing tunnels. The engine's speeds meet that.

**`travel?(x, y, w, h, dx, dy)` answers whether the box can move `(dx, dy)`
without any resolve stopping it short.** It is the optional extra question of the
[blocker-source protocol](#collisionsystem--move-an-actor-against-its-blockers).
It sweeps the box in overlapping windows half a tile long and a quarter tile
apart. It resolves each window x-then-y and y-then-x. A `true` holds for a walker
that resolves its own steps against this source, as long as each step is under a
quarter tile: 240 px/s at 60 ticks a second on 16 px tiles. It may refuse a segment
such a walker could manage. It never clears one the walker could not.
[`Navigator`](components.md#navigator) smooths its routes with it.

`blocker` returns the sentinel `TileBlockers::TILES`: one object for the life of
the process, answering `layer` → `:tiles` and `node` → `nil`. `TileBlockers` holds
no per-step state, so every body on the map can share one.
[`TileWorld#blockers`](components.md#tileworld) hands out that shared instance.

## `ActorBlockers` — the registered colliders as a blocker source

**`RGame::Engine::ActorBlockers` (`rgame/engine/actor_blockers`) does the same
arithmetic, with the edge coming from another collider instead of a grid line.**
It asks a broadphase what lies near the swept box, and snaps flush against the
nearest candidate.

```ruby
actors = RGame::Engine::ActorBlockers.new(world: collision_world, owner: my_collider,
                                          layers: %i[npc hero])
```

**Unlike the other two sources, it belongs to one mover.** It holds that mover's
own collider, to exclude it by identity, and the layer list the mover declared.
Two movers with different `blocked_by` cannot share one. That is why a
[`Mover`](components.md#mover) builds its own `CollisionSystem` instead of
borrowing the scene's.

It does three things a grid does not need:

- **The nearest candidate wins**, tracked as a running minimum. The broadphase can
  therefore offer one collider once per shared cell without harm.
- **It leaves an existing overlap unresolved.** A step is blocked only if it
  *crosses* an edge the mover started on the near side of. A pair that starts
  overlapping stays overlapping and is not teleported apart.
- **It handles boxes only.** It skips a `CircleCollider` on a declared layer.

`passing` names a node whose colliders stop nothing until it is set back to `nil`.
A mover dragging a [`Pushable`](components.md#pushable) passes the crate, and the
crate passes the mover, because the two move together.

Its `moved` passes the mover to
[`CollisionWorld#reindex`](components.md#collisionworld). That keeps a later query
in the same step exact.

## `BoundsBlockers` — the edge of the world as a blocker source

**`RGame::Engine::BoundsBlockers` (`rgame/engine/bounds_blockers`) stops a box from
leaving the region a [`WorldBounds`](components.md#world) describes.** It reads
the two numbers once at construction, because those bounds are immutable by
contract. Its `blocker` is the sentinel `BoundsBlockers::BOUNDS`, answering
`layer` → `:bounds`.

**A mover declares the edge as a source; the engine applies no automatic clamp.**
Stopping at the edge is one of three responses to it. `ScreenWrap` and
`DespawnOffscreen` are the others, and a node may carry only one
([`WorldBounds.one_response!`](components.md#world)). A mover that did not ask is
not held.

## `GapBlockers` — the edge of the floor as a blocker source

**`RGame::Engine::GapBlockers` (`rgame/engine/gap_blockers`) stops the centre of a
box at the edge of the floor** that
[`TileWorld#floor_at?`](components.md#tileworld) describes: every cell without a
[gap tile](tile_maps.md#gaps), and the box of every
[`Platform`](components.md#platform) over one. `TileWorld#gap_blockers` builds one over its world
and hands the same one to every mover declaring `:gaps`.

```ruby
gaps = world.gap_blockers
gaps.resolve_x(10.0, 30.0, 12, 6, 20.0)   # => 26.0 less a billionth: the centre stops short of x 32
```

It asks `TileWorld#floor_reach_x` and `#floor_reach_y` about the centre of the box,
so a box may overlap a gap while its centre stands on the floor. A box whose centre
starts off the floor moves the whole way. Its `blocker` is the sentinel
`GapBlockers::GAPS`, answering `layer` → `:gaps` and `node` → `nil`. It holds no
per-step state, and it indexes nothing, so its `moved` does nothing.

## `CollisionSystem` — move an actor against its blockers

**`RGame::Engine::CollisionSystem` (`rgame/engine/collision_system`) holds a list of
blocker sources and moves an actor against them.** A blocked
[`Mover`](components.md#mover) builds one at attach, from the sources its
`blocked_by:` names, and passes itself as the actor.

```ruby
collision = RGame::Engine::CollisionSystem.new(blockers: [tiles, actors])
collision.move(actor, dx, dy) # actor responds to x / y / x= / y= / collision_box
```

`move` reads the actor's
[`CollisionBox`](toolbox.md#collisionbox--an-actors-feet-box) AABB and resolves it
on both axes. It writes the resolved position back to the actor, accounting for the
box's offset from the sprite origin. Finally it tells every source that the step
happened. **It has no clamp of its own.** Everything that can stop a step is a
source, the world's edge included.

A blocker source answers four questions. Only the first two involve arithmetic:

```ruby
source.resolve_x(x, y, w, h, dx)          # -> where the box's left edge lands moving dx
source.resolve_y(x, y, w, h, dy)          # -> where the box's top  edge lands moving dy
source.blocker                            # -> what produced that edge, or nil
source.moved(actor, from_x, from_y, w, h) # -> the step has been written back
```

A fifth is optional. Of the four sources, only `TileBlockers` answers it:

```ruby
source.travel?(x, y, w, h, dx, dy)        # -> can the box move (dx, dy) without being stopped?
```

**"Stopped" means a resolve lands short of where the step was heading.** A landing
past it does not count: `move` ignores it, and it does not stop a travel either.
`BoundsBlockers` gives such a landing to a box that starts outside the world. Under
this reading, a box travels past several sources exactly when it travels past each
one alone. The shared example group `a blocker source answering travel?`
(`spec/support/shared_examples/`) states that meaning. It checks a source's answer
against a walker stepping through the source's own resolves.

The four sources are `TileBlockers`, `ActorBlockers`, `BoundsBlockers` and
`GapBlockers`. **The
system asks each source and takes the most restrictive answer on each axis**: the
smallest landing for a rightward or downward step, the largest for a leftward or
upward one. No source needs to know the others exist, and `blockers: []` means free
movement.

`blocked_x` and `blocked_y` hold what the winning source reported for each axis, or
nil when that axis was free. The system asks each winner during the resolve, not
afterwards, because a source's `blocker` is per axis and the next resolve overwrites
it. Every blocker answers `layer` and `node`, tiles and world edges included. A
caller reads `blocked_x.layer` without checking what kind of thing stopped it.

The system calls `moved` on every source with the box the step **started** from. A
source over a moving index can then re-bucket the mover, without anyone storing a
box for it; see `ActorBlockers` above.

Keeping the list in the system, not inside a source, has two consequences. First,
the axis-separated order exists once for every source: resolve x, then resolve y
with the resolved x. That order produces wall-sliding, where a diagonal push into a
wall keeps the component that is still free. Second, the loop walks an index
instead of using `map` or `min`. It runs per actor, per axis, per frame, and both a
block and an intermediate array would allocate.

## `AnimationSet` — pure frame maths

**`RGame::Engine::AnimationSet` (`rgame/engine/animation_set`) turns an animation
table and an elapsed time into the sprite-sheet cell to show.** It needs no
renderer and no images, so specs test it fully.

```ruby
require 'rgame'

set = RGame::Engine::AnimationSet.new(
  stand:      { row: 0, col: 1, frames: 1, fps: 1 },
  walk_right: { row: 1, frames: 3, fps: 6 }
)
set.frame(:walk_right, 0.4) # => [1, 2, false] — [row, col, flip_x]
```

Each animation is `{ row:, col: (start column, default 0), frames:, fps:, flip_x: }`.
`frame(name, elapsed)` advances through `frames` columns from `col` at `fps`, and
wraps around. A held animation therefore cycles.

## `Animator` — animation playback state

**`RGame::Engine::Animator` (`rgame/engine/animator`) owns playback state on top of
an `AnimationSet`**: the current animation name and its elapsed time.
[`AnimatedSprite`](components.md#animatedsprite) drives it.

```ruby
animator = RGame::Engine::Animator.new(set, initial: :stand)
animator.play(:walk_right) # switch (a no-op if already playing, so a walk keeps cycling)
animator.update(dt)        # advance elapsed time
animator.frame             # => [row, col, flip_x] — for the current animation now
```

`play` resets elapsed time only when the animation changes. Calling it
every frame with the current intent keeps a walk smooth instead of stuttering on
frame 0.

## `MapBuilder` — a node from a map's object

**`RGame::Engine::MapBuilder` (`rgame/engine/map_builder`) builds the node a
map's object names.** It finds the node class, sets it up from the object's
properties, and stands it on the object. No engine class calls it. A scene
builds nodes from a map's objects with `MapObjects`, as
[Building nodes from objects](tile_maps.md#building-nodes-from-objects) shows.

```ruby
module MyGame
  Engine = RGame::Engine
  Components = Engine::Components

  class Town < Engine::Node2D; end

  class Chest < Engine::Node2D
    # A chest the hero opens once.
    #
    # @param contents [String] the item inside
    # @param locked [Boolean] whether it takes a key to open
    def initialize(contents:, locked: false, **)
      super(**)
      @contents = contents
      @locked = locked
    end
  end
end

# `object` is object 7 of map/town.tmx: class Chest, property contents: 'key'.
builder = RGame::Engine::MapBuilder.new(tilemap_id: 'map/town.tmx', scope: MyGame::Town)
chest = builder.build(object)   # => a MyGame::Chest, standing at the bottom centre of the object
chest.map_object_id             # => 7
```

**A class starting with a capital letter names the node class.** Any other
class, and none, is data: `build` returns `nil`, and the object stays a record in
`map.objects`. The name resolves as Ruby would resolve it inside the class
`scope`. `Chest` is `MyGame::Town::Chest`, then
`MyGame::Chest`, then a constant `MyGame::Town` inherits, then `::Chest`. A
path such as `Town::Chest` resolves the same way. So a map names no module, and
two games can share one map, each with a `Chest` of its own. A name that
resolves to no constant raises `NameError`, and a constant that is not
`Node2D` or a subclass of it raises `TypeError`.

**The tags above `initialize` say what a map may set.** A keyword is settable
when the comment directly above the `def` documents it with a YARD `@param`
tag of a type from this table:

| Tag | Tiled property | The keyword receives |
|---|---|---|
| `[String]` | string | a String |
| `[Integer]` | int | an Integer |
| `[Float]` | float, or int | a Float |
| `[Boolean]` | bool | `true` or `false` |
| `[Symbol]` | string | a Symbol |
| a list of Symbols, such as `[:flat, :round]` | string, holding one of them | a Symbol |
| `[Util::Color]` | color | a `Util::Color` |

- **A keyword with no tag, or a tag of another type, stays out of a map's
  reach.** `@param rng [Random]` documents a keyword no map can set.
- **The tags are the unbroken run of comment lines above the `def`.** A blank
  line detaches them. A subclass without an `initialize` of its own reads its
  parent's tags, and one with its own reads only its own.
- **A tag must name a keyword `initialize` takes.** Reading one that names
  another raises `ArgumentError`, listing the keywords. So does a tag naming one
  of `Node2D`'s own keywords, `map_object_id` among them, or `route` or `name`.
  The builder sets those.
- **A class needs a source file.** A class defined by `eval`, in IRB or with
  `ruby -e` has none, and building it raises `ArgumentError`.

**Each property sets the keyword of its name.** A property no tag makes
settable raises `ArgumentError`, listing the keywords that are. A property of
the wrong type raises `TypeError`, naming the Tiled type to use, and a class
property is refused like any other value. A required keyword no property sets
raises `ArgumentError`. A tile object's properties include its tile's, so the
class tags those too.

**The node stands at the bottom centre of the object's box**, turned with it.
`angle` is the object's rotation in radians, and `width` and `height` are its
size. A point object's node stands on its point, and a polygon's or polyline's
on its own `(x, y)`.

**The builder hands the node values, and keeps the object.** Every node gets
its object's id as `map_object_id`, which is `nil` on a node built in code.
[`Components::Fact`](components.md#fact) keys a node's state by it. A
class whose `initialize` names `route:` gets the route of a polyline or a
polygon, as `Path.from_object` builds it, turned with the object. One that
names `name:` gets the object's name, or `''` when the designer gave none. A
class that requires `route:` raises `ArgumentError` when built from another
shape, and a class that names neither gets neither.

**A node passes a designer's value on to its components itself.** The map sets
only the node's own keywords, so a node that lets a designer tune a collider
takes the value and derives the collider from it:

```ruby
module MyGame
  class Crate < Engine::Node2D
    # @param size [Float] the crate's side, in pixels
    def initialize(size: 16.0, **)
      super(**)
      add_component(Components::BoxCollider.new(width: size, height: size,
                                                offset_x: -size / 2, offset_y: -size))
    end
  end
end
```

The offsets put the collider on the object's box, since the node stands at its
bottom centre. On a turned object, the node's frame turns with the box Tiled
draws, and the collider does not: a `BoxCollider` stays axis-aligned in the
world.
