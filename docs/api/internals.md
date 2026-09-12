# Internal building blocks

Low-level, pure-Ruby classes the engine's [components](components.md) and
[systems](systems.md) are built on. A game author rarely constructs these directly —
they sit *behind* a component (a blocked `CharacterBody` resolves through `CollisionSystem`, an
`AnimatedSprite` plays through an `Animator`, a `CollisionWorld` indexes through a
`SpatialHash` and remembers through a `ContactSet`) — but they are documented here because they carry the load-bearing
algorithms and are the seams the component tests drive. None `require "gosu"`.

For the helpers a game *does* reach for directly (pools, localization, the camera,
collision boxes, …), see [Utilities](toolbox.md).

## `SpatialHash` — uniform-grid broadphase

`RGame::Engine::SpatialHash` (`rgame/engine/spatial_hash`) is a broadphase index for collision:
bucket colliders into fixed-size grid cells, then test only candidates that share a
cell instead of every pair. It is the index inside
[`CollisionWorld`](components.md#collisionworld).

```ruby
hash = RGame::Engine::SpatialHash.new(cell_size: 64)
hash.clear                                  # reuse bucket arrays, keep capacity
rocks.each { |r| hash.insert(r, *r.aabb) }  # insert the static set
hash.query(*bullet.aabb) { |rock| ...narrowphase... }
```

Typical per-frame use is `clear`, `insert` every collider of one set, then `query`
around each moving collider. Both `insert` and `query` take an AABB (`x, y, w, h`);
an item spanning several cells is inserted into each and so **may be yielded more than
once** by `query`. That dedup is deliberately the narrowphase caller's job, which lets
the hash skip a per-query visited set and stay allocation-free. `CollisionWorld` does it
by checking the pair against the [`ContactSet`](#contactset--the-two-edges-of-a-contact)
it is filling for the step, which it needs anyway; a caller that only *selects*
(`nearest`) is written to be indifferent to repeats instead. Cell keys are packed into a
single tagged Fixnum (with an offset so off-screen / mid-wrap negative cells stay
non-negative), so keying allocates nothing either.

`query_circle(cx, cy, r, &)` is the radial counterpart to `query`: it yields the items
in the cells the circle's bounding box covers (delegating to the same cell walk), for
range and nearest lookups. It is still broadphase — it carries the same may-yield-twice
contract, and the caller refines candidates by true distance (see
[`CollisionWorld`](components.md#collisionworld)'s `query_circle`/`nearest`).

`cell_empty?(x, y)` asks whether the single cell *containing the point* `(x, y)` holds
nothing — a point, not a region, so pass any coordinate inside the cell you mean. Like
the queries it allocates nothing, and unlike them a miss does not create the bucket it
looked for (the bucket Hash builds one on a plain `[]` read).

An item is bucketed by its bounding box, and the cell walk is **half-open on the far
edge** — a box ending exactly on a cell boundary stops at the cell before it. So a piece
filling one cell is bucketed into that cell and no other, "bucketed here" means "overlaps
this cell's area" exactly, and `cell_empty?` is a true occupancy test rather than a
candidate test. That convention is shared with `CollisionBox.overlap?`, and the two have
to agree: bucketing that reached one cell further would only cost candidates, but one
that reached less far would miss a real contact.

The one thing the index cannot know is whether an occupant still counts, so
[`CollisionWorld#cell_empty?`](components.md#collisionworld) wraps this and skips
colliders whose node is queued for removal.

## `ContactSet` — the two edges of a contact

`RGame::Engine::ContactSet` (`rgame/engine/contact_set`) is what turns a per-step overlap
test into the two edges a game wants: the step a pair *starts* touching and the step it
*stops*. [`CollisionWorld`](components.md#collisionworld) owns one per registered
collider and is the only thing that drives it. Nothing in it is about *overlapping*,
though, and it has a second user: a [`CharacterBody`](components.md#characterbody) keeps
one of what stopped its step, and gets `on_blocked` / `on_unblocked` out of it on exactly
the same terms. What the class is, underneath its names, is "the set of things that were
true this step and last".

```ruby
contacts.begin_frame              # last step's list becomes the one to compare against
contacts.touching?(other)         # already recorded this step? (the broadphase repeats)
contacts.started?(other)          # not touching last step, so this is an on_hit
contacts.add(other)               # record it for this step
contacts.each_ended { |o| ... }   # touching last step, not now, so this is an on_separated
contacts.reset                    # forget both steps — a pooled collider registering again
```

It is two arrays, swapped rather than reallocated, and membership is a linear scan by
identity. Both choices are about the per-frame path: `Array#clear` keeps the capacity it
grew to, so a lasting contact costs no allocation at all after the first few steps, while
a Set or a Hash would allocate on every insert. A collider touching more than a handful
of things at once is a design problem elsewhere, not a reason to index this.

`started?` reads only the previous step's list, so it answers the same before and after
`add`, which is what lets the world ask it as a guard in the order the step happens.

## `TileBlockers` — the tile grid as a blocker source

`RGame::Engine::TileBlockers` (`rgame/engine/tile_blockers`) resolves an axis-aligned box against a
grid of solid tiles. `solid` is a callable `solid.call(col, row) -> bool`, so the tile
source is decoupled (a `TileMap`, a fake in tests). Each axis is resolved on its own —
`resolve_x` and `resolve_y` are independent — and it is
[`CollisionSystem`](#collisionsystem--move-an-actor-against-its-blockers)
that feeds one the other's result.

```ruby
tiles = RGame::Engine::TileBlockers.new(tile_width: 16, tile_height: 16,
                                        solid: ->(col, row) { map.solid_tile?(col, row) })
nx = tiles.resolve_x(x, y, w, h, dx) # snaps flush against a solid in the dx direction
ny = tiles.resolve_y(nx, y, w, h, dy)
```

It assumes per-step movement smaller than a tile (no tunneling), which holds for the
engine's speeds.

`blocker` is the sentinel `TileBlockers::TILES` — one object for the life of the process,
answering `layer` → `:tiles` and `node` → `nil`. Holding no per-step state is what makes
one `TileBlockers` safe to share between every body on the map, which is what
[`TileWorld#blockers`](components.md#tileworld) hands out.

## `ActorBlockers` — the registered colliders as a blocker source

`RGame::Engine::ActorBlockers` (`rgame/engine/actor_blockers`) is the same arithmetic with
the edge coming from another collider instead of a grid line. It asks a broadphase what is
near the swept box and snaps flush against the nearest candidate.

```ruby
actors = RGame::Engine::ActorBlockers.new(world: collision_world, owner: my_collider,
                                          layers: %i[npc hero])
```

Unlike the other two sources it is **per body**: it holds the mover's own collider, to
exclude it by identity, and the layer list that body declared. Two bodies with different
`blocked_by` cannot share one, which is why a
[`CharacterBody`](components.md#characterbody) builds its own `CollisionSystem` rather than
borrowing the scene's.

Three things it does that a grid does not need:

- **The nearest candidate wins**, kept as a running minimum — which also makes the
  broadphase offering the same collider once per shared cell harmless.
- **An overlap that already exists is not resolved.** A step is blocked only if it
  *crosses* an edge the mover was on the near side of, so a pair that starts overlapping
  stays overlapping rather than being teleported apart.
- **Boxes only.** A `CircleCollider` on a declared layer is skipped.

Its `moved` hands the mover back to
[`CollisionWorld#reindex`](components.md#collisionworld), which is what keeps a query later in
the same step exact.

## `BoundsBlockers` — the edge of the world as a blocker source

`RGame::Engine::BoundsBlockers` (`rgame/engine/bounds_blockers`) stops a box leaving the
region a [`WorldBounds`](components.md#world) describes. It reads the two numbers once at
construction, because those bounds are immutable by contract, and its `blocker` is the
sentinel `BoundsBlockers::BOUNDS`, answering `layer` → `:bounds`.

It exists because `CollisionSystem` used to clamp every step inside the world
unconditionally, and that clamp works on the collision **box** while `ScreenWrap` and
`DespawnOffscreen` read the same bounds off `node.x`/`node.y`. A hero with a feet box
therefore stood at the world's left edge, fully inside it, and despawned. Now the edge is
declared like anything else, and a body that did not ask is not held.

## `CollisionSystem` — move an actor against its blockers

`RGame::Engine::CollisionSystem` (`rgame/engine/collision_system`) holds a list of **blocker
sources** and the actor-facing `move`. A blocked
[`CharacterBody`](components.md#characterbody) builds one at attach out of the sources its
`blocked_by:` named, and hands itself to it as the actor.

```ruby
collision = RGame::Engine::CollisionSystem.new(blockers: [tiles, actors])
collision.move(actor, dx, dy) # actor responds to x / y / x= / y= / collision_box
```

`move` reads the actor's [`CollisionBox`](toolbox.md#collisionbox--an-actors-feet-box)
AABB, resolves it on both axes, writes the resolved position back to the actor (accounting
for the box's offset from the sprite origin), and finally tells every source that the step
happened. **There is no clamp of its own**: everything that can stop a step, the world's
edge included, is a source.

A blocker source answers four things, and only the first two are about arithmetic:

```ruby
source.resolve_x(x, y, w, h, dx)          # -> where the box's left edge lands moving dx
source.resolve_y(x, y, w, h, dy)          # -> where the box's top  edge lands moving dy
source.blocker                            # -> what produced that edge, or nil
source.moved(actor, from_x, from_y, w, h) # -> the step has been written back
```

There are three sources: `TileBlockers`, `ActorBlockers` and `BoundsBlockers`. The system
asks every one it holds and takes the **most restrictive** answer on each axis — the
smallest landing for a rightward or downward step, the largest for a leftward or upward one
— so no source has to know the others exist, and `blockers: []` is free movement.

`blocked_x` and `blocked_y` are what the winning source reported for each axis, or nil when
that axis was free. Each is asked of its winner during the resolve rather than afterwards,
because a source's own `blocker` is per axis and the next resolve overwrites it. Every
blocker answers `layer` and `node`, tiles and world edges included, so a caller reads
`blocked_x.layer` without asking what kind of thing stopped it.

`moved` is called on every source with the box the step **started** from. That is what lets
a source over a moving index re-bucket the mover without anything having stored a box on
its behalf — see `ActorBlockers` above.

Two things follow from the list living here rather than inside a source. The
axis-separated order — resolve x, then resolve y fed the resolved x — is what gives
wall-sliding, a diagonal push into a wall keeping the component that is still free, and it
is written once for every source. And the loop is a plain index walk rather than
`map`/`min`, because it runs per actor per axis per frame and both a block and an
intermediate array would allocate.

## `AnimationSet` — pure frame maths

`RGame::Engine::AnimationSet` (`rgame/engine/animation_set`) turns an atlas's animation table plus an
elapsed time into the sprite-sheet cell to show — no renderer, no images, fully testable.

```ruby
set = RGame::Engine::AnimationSet.new(
  stand:      { row: 0, col: 1, frames: 1, fps: 1 },
  walk_right: { row: 1, frames: 3, fps: 6 }
)
set.frame(:walk_right, elapsed) # => [row, col, flip_x]
```

Each animation is `{ row:, col: (start column, default 0), frames:, fps:, flip_x: }`.
`frame(name, elapsed)` advances `frames` columns from `col` at `fps`, wrapping — so a
held animation cycles.

## `Animator` — animation playback state

`RGame::Engine::Animator` (`rgame/engine/animator`) owns the playback state on top of an
`AnimationSet`: the current animation name and elapsed time. It is what
[`AnimatedSprite`](components.md#animatedsprite) drives.

```ruby
animator = RGame::Engine::Animator.new(set, initial: :stand)
animator.play(:walk_right) # switch (a no-op if already playing, so a walk keeps cycling)
animator.update(dt)        # advance elapsed time
animator.frame             # => [row, col, flip_x] for the current animation now
```

`play` only restarts elapsed time on an actual change, so calling it every frame with the
current intent keeps a continuing walk smooth rather than stuttering on frame 0.
