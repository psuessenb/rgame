# Internal building blocks

Low-level, pure-Ruby classes the engine's [components](components.md) and
[systems](systems.md) are built on. A game author rarely constructs these directly —
they sit *behind* a component (a `TileCharacterBody` resolves through `CollisionSystem`, an
`AnimatedSprite` plays through an `Animator`, a `CollisionWorld` indexes through a
`SpatialHash`) — but they are documented here because they carry the load-bearing
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
once** by `query`. That dedup is deliberately the narrowphase caller's job — guard with
`next if a.dead? || b.dead?` to keep hits idempotent — which lets the hash skip a
per-query visited set and stay allocation-free. Cell keys are packed into a single
tagged Fixnum (with an offset so off-screen / mid-wrap negative cells stay
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

## `TileCollision` — axis-separated AABB-vs-tile resolution

`RGame::Engine::TileCollision` (`rgame/engine/tile_collision`) resolves an axis-aligned box against a
grid of solid tiles. `solid` is a callable `solid.call(col, row) -> bool`, so the tile
source is decoupled (a `TileMap`, a fake in tests). It moves the box **one axis at a
time** — `resolve_x` then `resolve_y` (fed the resolved x) — which gives wall-sliding: a
diagonal push into a wall keeps the component that's still free.

```ruby
tiles = RGame::Engine::TileCollision.new(tile_width: 16, tile_height: 16,
                                  solid: ->(col, row) { map.solid_tile?(col, row) })
nx = tiles.resolve_x(x, y, w, h, dx) # snaps flush against a solid in the dx direction
ny = tiles.resolve_y(nx, y, w, h, dy)
```

It assumes per-step movement smaller than a tile (no tunneling), which holds for the
engine's speeds. It is the maths inside [`CollisionSystem`](#collisionsystem--move-an-actor-against-the-tiles-and-the-world).

## `CollisionSystem` — move an actor against the tiles and the world

`RGame::Engine::CollisionSystem` (`rgame/engine/collision_system`) wraps `TileCollision` with a
world-bounds clamp and an actor-facing `move`. It is what
[`TileWorld`](components.md#tileworld) delegates to (and what a
[`TileCharacterBody`](components.md#tilecharacterbody) moves through).

```ruby
collision = RGame::Engine::CollisionSystem.new(
  tile_collision: tiles, world_width: map.pixel_width, world_height: map.pixel_height
)
collision.move(actor, dx, dy) # actor responds to x / y / x= / y= / collision_box
```

`move` reads the actor's [`CollisionBox`](toolbox.md#collisionbox--an-actors-feet-box)
AABB, resolves it through `TileCollision` on both axes, clamps the box inside the world
as a backstop, and writes the resolved position back to the actor (accounting for the
box's offset from the sprite origin).

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
