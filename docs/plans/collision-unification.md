# Unifying the two collision systems

**Status: steps 1–4 are implemented, and step 4 took 5a with it; steps 5b, 5c and 6
are not. Step 5 was re-planned in detail at `605432f`; step 6 stays rough until it
lands.** The two things landed steps pushed into step 4 — rule 3 of step 2's list, and
where a per-actor blocker source hangs — are settled below, and so are open questions 1,
2, 3, 4 and 5. Re-planning added six measured findings (B6–B11). One overturns a
candidate the plan had been carrying since it was written, one is a live defect
nobody had reached yet, and one closes an open question against the convenience it
proposed.

Written out of a question about the shape of the engine, not a bug. Per CLAUDE.md
this is a working document: it names the code as it stands today, records what
the conversation decided, and leaves questions open. **Delete it once step 6
lands.**

The question, in the words it arrived in:

> A game where my player character needs collision detection with both the static
> world as well as moving entities in this world is the common case and should be
> easier to set up. Also characters that collide with the world via the box at
> their feet should also collide with each other with the same box. Is a component
> `FeetCollider` feasible, that would work for both systems?
>
> - how can we make it easier to setup a game to follow both kinds of collision?
> - how can we make is easier to construct nodes that participate in both collision systems?
> - does it make sense to unify the two systems in their public API?
> - does it make sense to unify the two systems under the hood?
> - how is this solved by other engines?
> - do those changes make it easier/easy for us to add "blocking collision" — so two
>   moving actors in the world automatically block each other the way a tile would
>   block an actor, without having to hand-roll an `on_hit` every time? It should
>   still be possible to react to `on_hit`: A player character running against a
>   spiky ball should both have its movement stopped and not overlap **and** take
>   damage.

## Verdict

**Yes to `FeetCollider`, and it is the keystone rather than a convenience.** The
friction is not that there are two systems. It is that the **shape has two
owners**: `TileCharacterBody` builds a `CollisionBox` privately and
`BoxCollider` builds another, and a node that wants both must hand one to the
other by hand, after the tree is live, in a hook written for no other purpose.
Give the collider the box and let the body borrow it, and the handoff, the
placeholder and the hook all disappear together.

**Unify the public API; do not unify the index.** One shape component per node,
one body component that declares what blocks it, and `TileCharacterBody`
retired. Under the hood keep the grid arithmetic for tiles and the spatial hash
for actors, and unify one level up: a *blocker source* answers "where does this
box land moving `dx`", there are two of them, and the axis-separated slide that
gives wall-sliding its feel is written once and shared. The argument in
`examples/collision_tiles` against bucketing forty thousand tiles into a spatial
hash is correct and this plan does not disturb it.

**Blocking then costs one small step — and one that is not small at all, and is
easy to miss.** Flush blocking means the two boxes end up *touching*, and
`CollisionBox.overlap?` is half-open, so a successfully blocked pair does not
overlap and `on_hit` never fires. Measured, not reasoned: see B4. The
spiky ball therefore stops the player and deals no damage. Blocking needs its own
report, which is what Godot's slide collisions and Unity's `OnCollisionEnter2D`
are, and is why both engines keep them separate from their overlap events.

## Hard constraints

1. **`RGame::Engine` may not name `RGame::Core`.** Everything here is engine
   layer, pure Ruby, headless-specable. `Game/NoCoreInEngineLayer` enforces it.
2. **Nothing on the per-frame path may allocate.** The resolver runs per actor
   per step and the broadphase per collider per frame. `allocate_nothing` is the
   matcher that decides it.
3. **A missing system fails loudly.** `TileCharacterBody#on_attach` raises rather
   than falling back to free movement, and CLAUDE.md gives the reason: an actor
   walking through walls looks like a collision bug, and the cause would be a
   scene three files away. Any unification must keep a way to say "I expect to be
   blocked", or it trades a loud failure for a silent one.
4. **The tile map is already an index.** Re-indexing it into the broadphase is
   the one approach this plan rules out up front.

## Decisions already taken

Not up for re-litigation inside the plan.

- **`on_hit` and `on_separated` mean *overlap*.** They landed in
  `collision-improvements` as per-pair edges and stay that way. Blocking gets its
  own signal rather than overloading these.
- **Two indexes, one resolver.** See the verdict.
- **Layers stay opaque symbols.** No bitmask, no layer matrix. The engine keeps
  reporting contacts and letting the owner decide meaning.

Four more were taken when steps 4 and 5 were re-planned, and they are what those
steps are written against.

- **The resolver hangs on the body, and `TileWorld#move` retires.** A body builds
  its own `CollisionSystem` at attach out of the sources it resolved, and
  `TileWorld` goes back to being the map, its bounds and its tile solidity. See
  D5 for why, and E for the shared-system alternative that was rejected.
- **`on_blocked` is an edge, and it has an `on_unblocked` twin.** A signal pair,
  exactly like `on_hit` / `on_separated`, over the same `Engine::ContactSet`.
  This settles open question 2 against the leaning the plan recorded; the reason
  is in that question.
- **What stopped a step always answers `layer`.** The tile source reports a
  sentinel blocker rather than a bare `:tiles` symbol, so a handler reads
  `by.layer` whatever stopped it and never branches on type. See D4.
- **Blocking is box-versus-box.** A `CircleCollider` on a blocked layer does not
  stop a step and still reports `on_hit` normally. This settles open question 3
  as that question proposed.
- **The world edge is a declared blocker, not an unconditional clamp.**
  `blocked_by: [:bounds]`, and `CollisionSystem` stops clamping. This settles open
  question 5, and it settles it larger than the question asked, because asking it
  turned up B9. See D7.

## What was measured before planning

At `bbf1871`, over `lib/`, `examples/`, `test_projects/` and `spec/`.

| | |
|---|---|
| Scenes mounting `TileWorld` | 3 |
| Scenes mounting `CollisionWorld` | 3 |
| Scenes mounting **both** | **0** |
| `TileCharacterBody` references outside its own file | 13, across 9 files |
| Of those, real game call sites | 2 (`examples/collision_tiles`, `test_projects/tiled_world`) |
| `BoxCollider.new` / `CircleCollider.new` call sites | 11 |

The first row is the finding. **The case the question calls "the common case" has
never once been built in this repository** — not in an example, not in a test
project, not in a spec. That is not because nobody wanted it. It is because
writing it costs three traps, below.

## B. Current state

### B1. What each system actually is

| | Tile collision | Body collision |
|---|---|---|
| Scene system | `Components::TileWorld` | `Components::CollisionWorld` |
| Node component | `Components::TileCharacterBody` | `Components::BoxCollider` / `CircleCollider` |
| Index | none needed — divide by tile size | `Engine::SpatialHash`, rebuilt per step |
| Shape | `Engine::CollisionBox`, built privately by the body | `Engine::CollisionBox` or a radius, owned by the collider |
| Runs during | the **actor's own** `update`, at the step | the **scene's** `update`, before any child moves |
| Answers | where does this step land | who is overlapping whom |
| Effect | blocks, reports nothing | reports, blocks nothing |

The last two rows are the whole of it. One is a function of a step and the other
is a relation over a set, and they are exact complements: each does precisely
what the other does not.

### B2. Writing a node that wants both — *(measured: three traps, and one is silent)*

Built and run against the real engine classes, a hero and an NPC on a map with a
wall. It works, and this is the shortest it can be written:

```ruby
def initialize(feet_w:, feet_h:, layer:, **)
  super(**)
  @body = add_component(C::TileCharacterBody.new(feet_width: feet_w, feet_height: feet_h, speed: 60))
  # Trap 1: the real box cannot be built here. TileCharacterBody#collision_box raises
  # until the sprite has set the node's size, and it memoises whatever it first sees.
  # Trap 2: so the collider is given a placeholder box now and the real one later.
  @collider = add_component(C::BoxCollider.new(width: 1, height: 1, layer: layer))
  @collider.on_hit { |other| @hits << other.layer }
end

# Trap 3: a hook whose only job is handing one component's box to another.
def on_add
  @collider.box = @body.collision_box
end
```

Trap 3 is the bad one, because forgetting it is **silent**: the collider keeps
its 1×1 placeholder, no contact is ever reported, and nothing complains. That is
the exact failure shape CLAUDE.md's "design out misuse" section exists to
refuse — a rule that depends on someone remembering.

The run confirms the behaviour is otherwise correct, and confirms what is
missing: walking the hero into the NPC reports `on_hit` and passes straight
through, ending with the two feet boxes overlapping; walking on into the wall
stops flush at its edge.

### B3. The contact pass sees last step's positions — *(measured)*

`CollisionWorld` is a component on the scene node, and `Node2D#update` runs a
node's components before its children. So the broadphase is built and every pair
reported *before* any actor has moved this step. It is consistent and it is not
wrong, but it means contacts trail the world by one step, and it is the reason
the index is stale for anything that wants to consult it mid-step (B5).

### B4. A flush-blocked pair reports no contact — *(measured: this is the trap in the blocking question)*

Two 12×6 boxes, one snapped flush against the other exactly as
`TileCollision` snaps against a wall:

| Gap | `on_hit` |
|---|---|
| Touching exactly, right edge on left edge | **does not fire** |
| Overlapping by 0.5px | fires |

`CollisionBox.overlap?` spans the half-open box `[x, x + w)` deliberately, and
CLAUDE.md explains why: on a grid, pieces on neighbouring squares border each
other constantly and an inclusive test would report every one of those as a
contact. That convention is right and must stay. Its consequence is that
**perfect blocking and overlap reporting are mutually exclusive by
construction**. The spiky ball cannot both stop the player and damage them
through `on_hit` alone.

### B5. The broadphase can miss a collider that moved after the index was built — *(measured)*

Buckets are filled at `insert` time, and `query` walks only the cells the query
box covers. A collider that moves after the rebuild is still bucketed where it
was:

```
querying cell 0 before the mover moves into it: [:querier]
querying cell 0 after  the mover moves into it: [:querier]
mover is now at world x 12, genuinely overlapping: true
```

Today nothing reads the index mid-step so this costs nothing. It matters the
moment an actor resolves its step against other actors, which is step 4. The
test used a 188px jump; a real step is one or two pixels against cells of 16 to
64, so the practical exposure is a near-miss at a cell boundary rather than a
systematic failure. Open question 1 is what to do about it.

### B6. The stale index misses a candidate, and only re-indexing fixes it — *(measured: this is open question 1, settled)*

Open question 1 offered three candidates and asked for a measurement rather than
an argument. All three were built and run against the real `SpatialHash` and
`CollisionWorld`: actors of 12×6 bouncing inside a square world, each one querying
the index for its own swept box and the result compared against ground truth —
every other actor whose *live* AABB genuinely overlaps that box. A miss is a
collider that genuinely overlaps and was not offered.

Live positions are never the problem. A query returns colliders, and a blocker
source reads each one's AABB fresh, so the geometry it resolves against is
current. What goes stale is **candidacy**: a collider that moved after the rebuild
is still bucketed where it was, and a query over cells it has left does not reach
it.

At 40 actors, cell 32, 300 steps — 12,000 queries:

| Strategy | 40 px/s | 80 px/s | 200 px/s |
|---|---|---|---|
| Leave it stale | 0 | 1 | 3 |
| Inflate the query by this step | 0 | 0 | 0 |
| Inflate the query by one cell | 0 | 0 | 0 |
| Re-index the mover after it moves | 0 | 0 | 0 |

At 200 actors, cell 32 — 60,000 queries:

| Strategy | 80 px/s | 200 px/s | candidates/query | ms/step |
|---|---|---|---|---|
| Leave it stale | 24 | 116 | 3.98 | 1.44 |
| Inflate the query by this step | 0 | 2 | 4.26 | 1.46 |
| Inflate the query by one cell | 0 | 0 | 15.14 | 2.11 |
| Re-index the mover after it moves | 0 | 0 | 3.98 | 1.92 |

**Inflation is not exact and cannot be made exact**, which is the finding. It pads
by the *mover's* step, and the staleness it is compensating for is the *other*
actor's — the two coincide only because every actor in this run moves at the same
speed. Padding by a whole cell hides that by brute force and costs a 3.8× wider
broadphase for it.

**Re-indexing is exact at every speed and scale tried, and it allocates nothing.**
`remove` needs no stored state: the caller knows the box the collider was bucketed
at, so `remove(collider, x, y, w, h)` walks the same cells `insert` did. Measured
over 2,000 remove+insert pairs once the buckets exist: 0 objects. Its 33% is 0.5ms
per step at two hundred actors, and the largest collider count in the repository
is eleven rocks.

A fourth candidate was measured and rejected on the numbers: **skip the index and
scan the registered colliders on the blocked layers**, reading live AABBs. Exact
by construction and the simplest thing that could work, and at ten colliders it
costs 0.08ms per step against the hash's 0.06. At two hundred it costs **15.7ms
per step** — the whole frame — against 1.13. A resolver with a cliff that steep is
not one to ship.

### B7. Rebuilding the index after the update traversal answers a different question — *(measured: candidate 3 does not do what the plan said)*

The third candidate offered for open question 1 was to move the contact pass into
a post-update traversal beside `sweep_freed`. It does nothing for the staleness
above, and the same harness says so:

```
index rebuilt pre   : 5 misses in 18000 queries
index rebuilt post  : 5 misses in 18000 queries
```

Identical, and it has to be. Nothing moves between the end of one tick's update
traversal and the start of the next, so the index a mid-traversal query reads
holds exactly the same positions either way. What moving the rebuild *does* fix is
B3 — the contact pass seeing last step's positions — which is a real defect and a
different one. It stays out of scope here.

### B8. The body resolves in local space and the collider indexes in world space — *(measured: latent today, wrong the moment actors block)*

`CharacterBody`'s actor adapter reports `node.x`, and `BoxCollider#aabb_x` reports
`node.world_x + box.offset_x`. Under an offset ancestor those are different
numbers. A hero at local (10, 20) inside a container at (100, 50):

| | |
|---|---|
| `body.x + box.offset_x`, what `CollisionSystem` resolves | 12 |
| `collider.aabb_x`, what the broadphase indexes | 112 |

It costs nothing today, because every actor that carries a body sits at world
offset zero: `TileMapLayer.mount` adds a plain `Node2D.new(z: gap)` with no
position, and `WorldView` applies the camera with `renderer.translated` at draw
time rather than by moving nodes. It is also already wrong for tiles — a map is in
world coordinates — and nobody has hit it because nobody has offset an actor
container.

`ActorBlockers` compares the mover's box against other colliders' AABBs, so it
turns a latent discrepancy into a live one. Step 4a fixes it by putting the body
in world space, which is the frame the broadphase and the tile map already use.

### B9. The world clamp misfires against `ScreenWrap` and `DespawnOffscreen` — *(measured: this is open question 5, and it is a live defect)*

`CollisionSystem#move` clamps the box inside the world after every source has
answered, unconditionally. `ScreenWrap` and `DespawnOffscreen` read the same
`WorldBounds`, but they never touch the collision system at all — they compare
`node.x` / `node.y` against the region and act on the node directly. So they do
not merely disagree with the clamp. They misread it.

The clamp works on the **box**, so a clamped node lands at `node.x == -offset_x`,
and both components test `node.x < -margin`. A `FeetCollider` on a wider node has
a positive `offset_x` by construction. Walking a hero into the left edge of a
320×240 world, 60 steps:

| Node | What happens on touching the left wall |
|---|---|
| 16px wide, 12px feet box (`offset_x` 2), `DespawnOffscreen` | **despawns itself** |
| 16px wide, 12px feet box (`offset_x` 2), `ScreenWrap` | **teleports to the right edge** |
| 16px wide, 16px feet box (`offset_x` 0), `DespawnOffscreen` | stops, correctly |

It is unreachable today only because no node in the repository carries both a
blocked body and a bounds-reading component, and `CollisionSystem` exists nowhere
but on `TileWorld`. It stops being unreachable in step 4, which gives every body
its own resolver.

### B10. The clamp has never once fired in a tile game — *(measured: every map's border is solid)*

Parsed with the engine's own `TileMap`, counting border cells that are not solid:

| Map | Size | Open border cells |
|---|---|---|
| `examples/assets/town.tmx` | 60×40 tiles, 960×640 px | **0** of 200 |
| `media/map/beach_large.tmx` | 120×90 tiles, 1920×1440 px | **0** of 420 |
| `media/map/island.tmx` | 58×47 tiles, 928×752 px | **0** of 210 |

A walled map stops an actor a whole tile before the clamp could, so the clamp is
dead code in every game that can currently reach it. That is what makes B9's fix
cheap: turning the clamp into a declared blocker source is a no-op for every
existing game, and a byte-identical drive report is what proves it.

### B11. `cell_size` tracks collider size, not tile size — *(measured: this is open question 4, settled against)*

Cost of a full `CollisionWorld#update` — clear, insert, pair — over 400 steps, in
milliseconds per step. The maps above are all 16px-tiled, so 16 is what a
tile-derived default would pick:

A 12×6 feet box, which is what a tile-map character carries:

| cell | 10 actors | 60 actors | 200 actors |
|---|---|---|---|
| 16 | 0.0380 | 0.2442 | 0.8066 |
| 32 | 0.0337 | 0.2084 | 0.7167 |
| 64 | 0.0319 | 0.1980 | 0.7425 |

A 64×64 collider in the same scene — a crate, a boss, a tree trunk:

| cell | 60 actors | 200 actors |
|---|---|---|
| 16 | 1.0359 | 4.4969 |
| 32 | 0.5224 | 2.5137 |
| 64 | 0.3644 | 2.0647 |

For a feet box a tile-sized cell costs 10–20% over the optimum, which is benign.
For one large collider in the same scene it costs **2.8×**, because a 64px box in a
16px grid is bucketed into twenty-five cells and queried out of all of them.

The finding is not the percentage, it is that **the two numbers are unrelated**. A
tile size is a fact about the map's artwork; a cell size is a fact about how big
the things that collide are. A default would tie one to the other and be wrong
whenever a scene holds anything bigger than a tile — invisibly, since the symptom
is frame budget and not behaviour.

## C. Prior art

### What the engines agree on

| Engine | One world? | Tiles are… | Detect vs block | Blocking reported by |
|---|---|---|---|---|
| Godot 4 | yes | real collision shapes on a `TileMapLayer` physics layer | `Area2D` overlaps, bodies block | `get_slide_collision(i)` after `move_and_slide()` |
| Unity 2D | yes | `TilemapCollider2D`, usually merged by `CompositeCollider2D` | `isTrigger` flag per collider | `OnCollisionEnter2D` with contact points |
| Unreal | yes | — | per-channel response: Block / Overlap / Ignore | `OnComponentHit` |
| bump.lua | yes | ordinary items in the world | the move's `filter` returns `slide` / `cross` / `touch` / `bounce` per pair | the collision list `world:move` returns |

Three things are unanimous and worth taking:

1. **There is one API, whatever the implementation.** A character does not ask
   two different objects whether it may move.
2. **Detect-versus-block is a property of the *pair*, not of the system.** It is
   a flag, a channel response, or a filter callback — never a second engine.
3. **A blocking move returns what it hit.** Every one of them has a separate
   channel for this, because as B4 shows, blocking and overlapping cannot be the
   same report. bump.lua is the sharpest: `world:move` returns the list.

### What none of them gives us

They all afford one world by making tile shapes into real colliders, and they pay
for it. Unity needs `CompositeCollider2D` to merge the tiles or the collider count
is ruinous; Godot bakes per-tile shapes into the physics server at load. Both are
a real cost in memory and bake time that a 2D engine at this scale does not have
to accept, and both re-index something a tile map already indexes perfectly.

**So copy the API shape and refuse the implementation.** bump.lua is the closest
reference for that: small, pure, and its per-pair filter is exactly the "one call,
several kinds of answer" model, even though it does keep one index.

## D. Design

### D1. `FeetCollider` — the shape gets one owner

```ruby
class FeetCollider < BoxCollider
  def initialize(width:, height:, layer: :default)
    super(width: width, height: height, layer: layer)
    @feet_width = width
    @feet_height = height
    @box = nil # built lazily: the node has no size until its sprite attaches
  end

  def box
    @box ||= Engine::CollisionBox.bottom_anchored(
      sprite_width: node.width, sprite_height: node.height,
      width: @feet_width, height: @feet_height
    )
  end
end
```

It carries over `TileCharacterBody#build_collision_box` wholesale, including the
raise naming the 0×0 node, which is the same guard for the same reason. Because
it subclasses `BoxCollider`, `get_component(BoxCollider)` finds it and the
broadphase needs no change at all.

`feet_width:` and `feet_height:` leave the body entirely. The body stops owning a
shape and reads the collider's, which is the right way round: the collider is the
component that *is* a shape.

### D2. One body, declaring what blocks it

`TileCharacterBody` disappears. `CharacterBody` gains a list:

```ruby
CharacterBody.new(speed: 80, blocked_by: %i[tiles npc hero])
```

`:tiles` is reserved and means the scene's `TileWorld`; every other name is a
collider `layer`. The default is `[]`, which is today's free-moving
`CharacterBody` unchanged.

This keeps constraint 3 and moves it somewhere better. Declaring `:tiles` with no
`TileWorld` mounted raises at `on_attach` exactly as today, and now declaring
`:npc` with no `CollisionWorld` mounted raises too — a failure that has no way of
being reported at all under the current design, because the body does not know
actors exist.

The node becomes four ordinary lines with nothing to remember:

```ruby
add_component(AnimatedSprite.new(sheet: 'hero.json'))
add_component(FeetCollider.new(width: 12, height: 6, layer: :hero))
add_component(CharacterBody.new(speed: 80, blocked_by: %i[tiles npc]))
add_component(PlayerController.new)
```

`PlayerController`, `WanderController` and `AnimatedSprite` all find it through
`require_sibling(CharacterBody)` and are untouched — they already name the base
class precisely so the subclass choice never reached them.

### D3. One resolver, two blocker sources

A blocker source answers one question, on one axis, over plain numbers:

```ruby
# Both are pure. resolve_x returns where the box's left edge lands moving dx.
Engine::TileBlockers.new(tile_collision)          # the grid lookup, as today
Engine::ActorBlockers.new(world:, owner:, layers:) # a broadphase query
```

`CollisionSystem#move` keeps its axis-separated shape — resolve X, then resolve Y
with the X result, which is what produces wall-sliding — and takes the most
restrictive answer on each axis:

```ruby
def resolve_x(x, y, w, h, dx)
  nx = x + dx
  return nx if dx.zero?

  i = 0
  while i < @blockers.size
    landed = @blockers[i].resolve_x(x, y, w, h, dx)
    nx = landed if dx.positive? ? landed < nx : landed > nx
    i += 1
  end
  nx
end
```

A `while` loop over an array held on the system, so nothing allocates
(constraint 2). `TileBlockers` is `TileCollision` with its existing body and no
behaviour change. `ActorBlockers` snaps flush against another collider's box the
same way `TileCollision` snaps against a tile edge — the arithmetic is identical,
only the source of the edge differs.

That is the whole of "unify under the hood". The index stays two things; the
*feel* becomes one thing, decided in one place.

### D4. Blocking reports itself, as a pair of edges

Because of B4, the body announces what stopped it — and it announces the start and
the end of being stopped, the way a contact does:

```ruby
body.on_blocked   { |by| damage(1) if by.layer == :spike }
body.on_unblocked { |by| stop_grunting if by.layer == :spike }
```

Which is `get_slide_collision` and `OnCollisionEnter2D` in this engine's idiom.
The spiky ball is then exactly what was asked for, and it is two lines with no
hand-rolled anything:

```ruby
add_component(FeetCollider.new(width: 12, height: 6, layer: :player))
body = add_component(CharacterBody.new(speed: 80, blocked_by: %i[tiles spike]))
body.on_blocked { |by| damage(1) if by.layer == :spike }
```

**What arrives in the block always answers `layer` and `node`**, whether a tile
stopped the step or a collider did. The tile source reports a sentinel — one
object for the life of the process, answering `:tiles` and `nil` — rather than the
bare `:tiles` symbol the first sketch of this section passed. The difference is
one a reader feels immediately: with a symbol every handler opens by telling two
types apart (`by != :tiles && by.layer == :spike`) before it can read anything,
and a third blocker source later would make that worse rather than better.

`on_hit` and `on_separated` keep meaning overlap, and remain the right signals for
everything that should *not* block: pickups, triggers, hitboxes, the whole of
`examples/collision`. A game wanting both behaviours from one entity gives it two
colliders, which is the Godot idiom of a body with a child area and needs nothing
new here.

### D5. The resolver hangs on the body

Step 3 left this open, and the argument that decides it is that **a resolver has
to exist where there is none today.** `CollisionSystem` lives on `TileWorld` and
nowhere else, and four scenes mount a `CollisionWorld` with no `TileWorld` —
`examples/collision`, `examples/pooling`, `test_projects/asteroids`,
`test_projects/snake`. A body blocked only by actors has nothing to ask. So
"share the scene's system" has to name an owner for the tile-less case before it
can share anything, and the only candidates are the broadphase (a different
concern) or a new component that exists to hold one.

So the body builds its own, out of the sources it resolved:

```ruby
def on_attach
  return if @blocked_by.empty?

  @collider = require_sibling(BoxCollider)
  @collision = Engine::CollisionSystem.new(
    blockers: @blocked_by.map { resolve_blocker(it) },
    world_width: ..., world_height: ...   # from node.system(WorldBounds), or nil
  )
end
```

Three things make that cheaper than step 3's note feared. `WorldBounds` is
documented immutable and resolved once at attach, so a body holds two Floats
rather than a duplicated system. The sources themselves are shared — `:tiles`
resolves to the `TileBlockers` the `TileWorld` already owns, borrowed rather than
rebuilt. And nothing here runs on a frame: the list is built once and a step only
indexes it.

It also keeps `resolve_x(x, y, w, h, dx)` at five arguments. Step 3 made those
public precisely so `CollisionSystem` satisfies the blocker-source protocol
itself; threading a caller's extra source through `move` would mean threading it
through `resolve_x` and `resolve_y` too, and the protocol would grow a parameter
that only one implementation of it has.

`TileWorld#move` has exactly one caller in the repository — `CharacterBody#apply_move`
— so once the body owns a resolver, `TileWorld`'s own `CollisionSystem` is dead
weight. It goes, and `TileWorld` becomes the map, its bounds, its tile solidity
and its animation clock, exposing the one thing an actor needs from it:

```ruby
class TileWorld < Engine::Component
  include WorldBounds
  attr_reader :blockers   # an Engine::TileBlockers
  def solid?(col, row) = @map.solid_tile?(col, row)
  # no #move, no CollisionSystem
end
```

### D6. Who stopped the step, and who re-indexes

Two small additions to the blocker-source protocol carry steps 4 and 5, and both
stay inside `CollisionSystem#move`, so no caller has anything to remember.

**`#blocker`** — who produced the edge the last `resolve_x` / `resolve_y` returned.
`CollisionSystem` already picks the winner on each axis, so it asks that source
and nothing else does; it exposes `blocked_x` and `blocked_y`, each nil when the
axis was free. `TileBlockers#blocker` is the sentinel constant and holds no state
at all, which is what makes one `TileBlockers` safe to share between every body on
the map.

**`#moved(actor, from_x, from_y, w, h)`** — called on every source after the
resolved position is written back, with the box the step started from.
`TileBlockers` ignores it; `ActorBlockers` hands it to
`CollisionWorld#reindex(collider, x, y, w, h)`, which is B6's exactness. The
from-box is a local `move` already has, so nothing new is stored on a collider, on
the world, or on the source.

### D7. The world edge is a blocker like any other

The clamp at the end of `CollisionSystem#move` is the one piece of blocking that
is not a source, and B9 measures what that costs. It is unconditional, so a body
is clamped whether or not it asked, and `ScreenWrap` and `DespawnOffscreen` — which
read the same bounds but act on `node.x` rather than on the box — misread the
result and teleport or despawn the node instead.

So bounds join the two reserved names:

```ruby
CharacterBody.new(speed: 80, blocked_by: %i[tiles bounds npc])
```

`:bounds` resolves to an `Engine::BoundsBlockers` over `node.system(WorldBounds)`,
and the clamp leaves `CollisionSystem` entirely. Three things follow, and each of
them is the plan's own rule applied one more time:

- **A wrapping game declares no `:bounds`** and its `ScreenWrap` works, because
  nothing is holding the node inside the world any more. The conflict stops being
  something to know about and becomes something you would have to ask for twice.
- **"I hit the edge of the world" is an ordinary `on_blocked`**, with a sentinel
  answering `layer` → `:bounds`, on the same terms as tiles and colliders. There
  is no special case for a listener to learn.
- **A game that wants the clamp says so**, which is constraint 3 pointed at the
  last thing in the system that was still implicit.

B10 is what makes this affordable to land inside step 4: every map in the
repository has a solid border, so the clamp has never fired in a game that could
reach it, and removing it is verifiable as a no-op rather than argued as one.

## E. What was considered and rejected

**Bake tile shapes into the broadphase, so there is one index.** Genuinely
attractive: it collapses the two systems into one at every level, it is what all
four references do, and `ActorBlockers` would then be the only blocker source.
Rejected on constraint 4 and on arithmetic. `test_projects/tiled_world`'s map is
tens of thousands of tiles; bucketing them rebuilds an index the grid already
is, and either costs that every frame or needs a merge pass and an invalidation
rule for animated and changing tiles. Unity shipping `CompositeCollider2D`
specifically to make this affordable is the evidence that it is not free.

**Let `TileCharacterBody` keep its private box and give `BoxCollider` a
`follow:` option pointing at the body.** Smaller, and it removes trap 3 without
touching the body at all. Rejected because it leaves the shape with two owners
and merely automates the handoff between them, and because it keeps the feet
dimensions on the body, where a later `CircleCollider` at the feet would have no
way to reach them. It fixes the symptom measured in B2 and none of the cause.

**Make `on_hit` fire for blocked pairs too.** Tempting, because the spiky ball
then needs no new signal. Rejected because it makes one signal mean two things
that a listener must then tell apart, and because it would fire for every wall a
character leans on — the half-open convention in B4 exists precisely to stop
"touching" being reported as contact.

**Resolve actor blocking as a depenetration pass after everyone has moved**,
pushing overlapping pairs apart along the minimum translation vector. Robust
against ordering, and it composes with the existing pair loop for free.
Rejected as the primary mechanism because it makes blocking approximate —
actors visibly overlap for a step before being pushed apart — and because
pushing one actor can shove it into a wall, which then needs re-clamping against
the tiles and a second pass. Worth reconsidering *only* if open question 1
resolves badly.

**One scene-level `CollisionSystem`, with `move` taking the caller's own extra
sources.** The tidier-sounding half of D5's question: bounds live in one place, a
future scene-wide blocker registers once, and a body contributes only its own
`ActorBlockers`. Rejected on two counts. Four scenes mount a `CollisionWorld` and
no `TileWorld`, so something new would have to exist purely to own the shared
system in those. And an extra source threaded through `move` has to be threaded
through `resolve_x` and `resolve_y` as well, which gives the blocker-source
protocol a sixth parameter that only `CollisionSystem` itself has — undoing what
step 3 landed two commits earlier.

**Skip the index: scan the registered colliders on the blocked layers.** Exact by
construction, needs no `remove`, no `reindex` and no freshness argument at all,
and at ten colliders it is within a whisker of the hash. Rejected on the
measurement in B6: at two hundred colliders it costs 15.7ms per step against
1.13ms, which is the entire frame. A resolver whose cost curve has a cliff that
close is one a game falls off without warning.

**Inflate the broadphase query instead of re-indexing.** The free option, and the
one the plan expected to win. Rejected because B6 shows it is not exact and cannot
be made exact by choosing a better pad: the query is padded by the *mover's* step,
and what it is compensating for is some other actor's. Padding by a whole cell
covers it by brute force at 3.8× the candidates per query, and still only because
a cell is far larger than a step.

**Fire `on_blocked` every blocked step rather than as an edge.** The plan leaned
this way and open question 2 records why it was turned round: the plan's own
example deals damage, and every step is sixty damage a second.

**Rename `Engine::ContactSet` now that a second thing uses it.** `CharacterBody`
holding something called a contact set to track blockers does read slightly
crooked. Rejected as a rename touching a class the collision world drives per
frame, for a word — and because "the things this was touching, this step and
last" is what the class does and what both callers want from it. Its header gains
a sentence naming the second caller instead.

**Give the unconditional clamp a sentinel and leave it where it is.** What open
question 5 actually asked for, and about four lines. Rejected because it reports
the defect instead of removing it: B9 measures the clamp and the two
bounds-reading components disagreeing about whose coordinate the bounds describe,
and a body would still be held inside the world without having asked. A signal on
a behaviour nobody opted into is a better-documented surprise, not a fixed one.

**Default `cell_size` from the tile map.** Open question 4, and it reads as an
obvious convenience — a scene with a `TileWorld` knows its tile size. Rejected on
B11: it ties a number about how big the colliders are to a number about how big
the artwork is, and costs 2.8× the moment a scene holds one collider larger than a
tile, with frame budget as the only symptom.

## F. Open questions

1. ~~**How does the resolver see a fresh index?**~~ **Settled — the mover
   re-indexes itself.** All three candidates were built and measured; see B6.
   Inflating the query is not exact and cannot be made exact, because it pads by
   the wrong actor's step. Re-indexing is exact at every speed and scale tried and
   allocates nothing. The third candidate turned out to answer B3 rather than this
   question at all — see B7.
2. ~~**Does `on_blocked` carry an edge like `on_hit`, or fire every blocked
   step?**~~ **Settled — an edge, with an `on_unblocked` twin.** The plan leaned
   the other way, and the thing that decided it is the plan's own spiky ball:
   `on_blocked { damage(1) }` firing every step deals sixty damage a second, so
   every game using the signal for the case it was designed for would have to
   rate-limit it. An edge is also the whole collision API saying one thing rather
   than two, and `Engine::ContactSet` already implements "this step and last" for
   `on_hit`, so the pair costs one reused object per body rather than a new
   mechanism. What the every-step form was protecting — a fact about *this* step's
   resolution — is preserved by `CollisionSystem#blocked_x` / `blocked_y`, which a
   body can read directly.
3. ~~**Does `ActorBlockers` need circles?**~~ **Settled as proposed — boxes only.**
   A circle on a blocked layer does not stop a step, and still reports `on_hit`
   exactly as it does now. It is said at the code and in
   `docs/api/components.md`, and not raised at attach: layer membership is a
   runtime fact, so a check at attach would catch only the circles that already
   exist and quietly miss the ones spawned later — a guard that sometimes works is
   worse than a documented limit.
4. ~~**Should `cell_size` default from the tile map?**~~ **Settled — no, and the
   parameter stays required.** Measured in B11. A tile size is a fact about the
   map's artwork and a cell size is a fact about how big the things that collide
   are, and tying one to the other is 10–20% off for a feet box but **2.8× off**
   the moment the scene holds one 64px collider. The cost is frame budget with no
   behavioural symptom, which is the worst kind of wrong default. `cell_size` also
   has a second meaning in `test_projects/snake`, where it is deliberately the
   game's own board square so `cell_empty?` reads as occupancy — a default would
   silently break that for any grid game that also had a map. `examples/collision`
   already explains the number as the one thing the system asks a game to pick,
   and that stays true.
5. ~~**Should the world-bounds clamp report a blocker?**~~ **Settled — bigger than
   a sentinel: the clamp becomes a declared source, `:bounds`.** Asking the
   question turned up B9, which is a live defect rather than a missing
   convenience: the clamp and the two bounds-reading components read the same
   `WorldBounds` and disagree about whose coordinate it is, so a `FeetCollider`
   walker with a `DespawnOffscreen` despawns itself on touching the left wall. A
   sentinel on an unconditional clamp would leave that in place. Making bounds an
   ordinary blocker source removes it, because clamping stops being something a
   body gets whether or not it asked. See D7; it lands as step 4e.

## G. What this does not deliver

Stated up front so it does not arrive later disguised as a bug.

- **Rotated collision shapes.** The box stays axis-aligned, as
  `docs/api/components.md` already says. A thing that spins wants a circle.
- **Mass, push, or shove.** Blocking stops the mover. It never moves the thing it
  hit, so two actors walking into each other both stop rather than one budging.
- **Continuous collision detection.** `TileCollision` assumes a step smaller than
  a tile and `ActorBlockers` inherits the assumption. A bullet at 900px/s still
  wants the contact signals, not blocking.
- **One-way platforms, slopes, or anything a platformer needs.** This is
  top-down blocking.
- **A layer matrix.** Layers stay opaque symbols and `blocked_by` stays a list on
  the body.
- **Circles as blockers.** Settled in open question 3. A `CircleCollider` on a
  blocked layer reports contacts and stops nothing.
- **An index that is fresh for movers other than a `CharacterBody`.** Re-indexing
  is driven from `CollisionSystem#move`, so a collider moved within the same tick
  by a `Velocity`, a `PathFollow` or an ancestor is bucketed where the last
  rebuild left it. B6 measures what that costs: a near-miss at a cell boundary,
  one to three in twelve thousand queries at walking speed. Anything else that
  moves a collider mid-tick can call `CollisionWorld#reindex` itself, which is the
  same escape hatch bump.lua's `world:update` is.
- **Per-axis blocking reports.** `on_blocked` is per blocker, so a step stopped on
  both axes by the same thing fires once. Which axis stopped is in
  `CollisionSystem#blocked_x` / `blocked_y` for a body that needs it.

## H. Roadmap

```
1 FeetCollider ──→ 2 CharacterBody(blocked_by:) ──→ 3 blocker sources ──→ 4 actor blocking ──→ 5 on_blocked/on_unblocked ──→ 6 fold back
       │                      │                            │                      │
       └── one box, no handoff┘                            └── pure refactor ─────┘
                                                       4a world space ─→ 4b index API ─→ 4c ActorBlockers ─→ 4d wiring ─→ 4e :bounds ─→ 4f docs
                                                                                              5a who stopped it ─→ 5b the edges ─→ 5c the spiky ball
```

Steps 1–3 are worth landing even if 4 and 5 never happen, and 4 is worth landing
even if 5 never does:

| Step | Defect it closes |
|---|---|
| 1 | Trap 1 and 2 of B2 — the placeholder box and the raise |
| 2 | Trap 3 of B2 — the silent handoff hook; and a missing `CollisionWorld` starts failing loudly |
| 3 | Nothing user-visible; it is what makes 4 a small step instead of a large one |
| 4 | Actors pass through each other; a body under an offset ancestor resolves in the wrong frame (B8); and a blocked body with a `ScreenWrap` or `DespawnOffscreen` teleports or despawns itself at the world edge (B9) |
| 5 | B4 — a flush-blocked pair reports no contact, so the spiky ball deals no damage |

> **The invariant every step must preserve: a node has exactly one collision
> shape, and exactly one component owns it.** Everything in B2 follows from that
> being false today.

> **And from step 4 on, a second: everything about collision is in world space.**
> The broadphase and the tile grid always were; B8 measures the body as the one
> thing that was not.

### Step 1 — `Components::FeetCollider` (pure)

A bottom-anchored `BoxCollider` that derives its box from the node's sprite size.
First because it is the keystone and because it is useful on its own: an existing
`BoxCollider` user gets a feet box without arithmetic in the caller.

Shape as in D1. Nothing else changes; `TileCharacterBody` still builds its own box
and step 2 is what takes that away.

Rules the tests must pin:

1. The box is bottom-anchored and horizontally centred in the node's dimensions.
2. It is built on first read, not at construction, so component order never
   matters.
3. Reading it from a 0×0 node raises, naming the size, as `TileCharacterBody`
   does now.
4. It is memoised, so a node that grows later keeps the box it first reported.
5. `get_component(BoxCollider)` finds it.

Tests: `spec/rgame/engine/components/feet_collider_spec.rb`, one case per rule,
plus the broadphase reporting a contact between a feet collider and a plain box.

Verify: a `FeetCollider` on a 16×22 node with a 12×6 box reports a world AABB at
the node's feet, and `rake spec` stays green.

**Landed.** `Components::FeetCollider` in `lib/rgame/engine/components/`, nine
examples in `spec/rgame/engine/components/feet_collider_spec.rb`, documented in
`docs/api/components.md` with a cross-link from `toolbox.md`. `rake spec` is
1186 examples, 0 failures. The acceptance case reports `[102, 216, 12, 6]` for a
12×6 box on a 16×22 node at (100, 200), which is the feet patch. `TileCharacterBody`
is untouched, as the sketch says.

Two things the sketch got wrong:

- **`BoxCollider` had to change after all**, which D1's "the broadphase needs no
  change at all" is right about but its code is not. `aabb_x` and friends read
  `@box` directly, so a subclass overriding `box` would have been invisible to
  the broadphase — the placeholder built by `super` would have been bucketed
  instead, silently, since it is a valid box of the right size at the wrong
  offset. They now go through the `box` reader. That is a method call per read on
  a per-frame path, so the spec pins `scene.update` allocating nothing with a
  feet collider registered.
- **`super` still builds a throwaway box.** The sketch's `@box = nil` discards
  it. Keeping the call is what keeps the layer, the contact set and the signals
  set up in one place, so the waste is one `CollisionBox` per collider at
  construction and never on a frame. Left as sketched, with a comment saying so.

`examples/collision` and `test_projects/snake` drive to byte-identical reports
before and after at `--ticks 240 --seed 7`, which is what says the `box`-reader
change moved nothing.

### Step 2 — `CharacterBody(blocked_by:)`, and `TileCharacterBody` retired

The step that closes the silent trap. The body stops owning a shape and starts
declaring what stops it.

```ruby
class CharacterBody < Engine::Component
  def initialize(speed:, blocked_by: [])

  # on_attach resolves each declared source, raising for one that is not mounted:
  #   :tiles          -> node.system(TileWorld)
  #   any other name  -> node.system(CollisionWorld), and the node's own collider
end
```

Sub-steps, one commit each: (2a) `CharacterBody` reads the sibling collider's box
and takes `blocked_by:`, with `:tiles` the only accepted name; (2b) delete
`TileCharacterBody` and migrate `examples/collision_tiles`,
`test_projects/tiled_world` and the specs; (2c) documentation.

Rules the tests must pin:

1. `blocked_by: []` moves the node freely and needs no system and no collider.
2. `blocked_by: [:tiles]` with no `TileWorld` raises at attach, naming both.
3. A layer name with no `CollisionWorld` raises at attach.
4. A layer name with no collider on the node raises at attach.
5. The box used for tile resolution is the sibling collider's, so reassigning
   `collider.box` retunes what collides.

Verify: `examples/collision_tiles` and `test_projects/tiled_world` drive to their
scripts' existing numbers, which is the acceptance criterion — the feel of
sliding along the fence must not change, and the drive scripts already pin it.

**Landed.** `CharacterBody(speed:, blocked_by: [])` in
`lib/rgame/engine/components/character_body.rb`, `TileCharacterBody` and its spec
deleted, seventeen examples in `spec/rgame/engine/components/character_body_spec.rb`.
`rake spec` is 1191 examples, 0 failures (1186 before, minus the eight that covered
the deleted class, plus thirteen new); `make test` 326 checks, 0 failures;
`rake spec:core` 367 examples, 0 failures.

The acceptance criterion holds exactly. `examples/collision_tiles` and all five
`tiled_world` scripts — `tiled_world`, `_2p`, `_cutscene`, `_inventory`, and `_pad`
with `--gamepad` — drive to **byte-identical** reports before and after at
`--ticks 240 --seed 7`. So do `examples/collision`, `examples/pooling`,
`examples/signals`, `examples/walk`, `test_projects/snake` and
`test_projects/asteroids`, which is what says the collider change below moved
nothing where a `CollisionWorld` *is* mounted. (One early run of `tiled_world_2p`
reported 239 frames rather than 240; nine further runs matched the baseline
exactly, so it is a frame the harness dropped under load, not a behaviour change.)

Three things the sketch got wrong, and the first is the one to carry into step 4:

- **Registering with a `CollisionWorld` had to become optional**, and the sketch does
  not mention it. `BoxCollider#on_attach` was `node.system(CollisionWorld).register(self)`
  — an unguarded call — so the moment `examples/collision_tiles` carried a
  `FeetCollider` it crashed on a scene that deliberately mounts no broadphase. The
  alternative was making every tile-only game mount one, which bucket-indexes nothing
  and couples the two systems the verdict keeps apart. So both colliders now use `&.`,
  and the sentence that falls out of it is a good one: **a collider is a shape; a
  `CollisionWorld` is what turns shapes into contacts.** The cost is real and is stated
  at the code — an `on_hit` handler in a world-less scene never fires and nothing says
  so — and the thing that *does* declare an expectation, and does raise, is
  `blocked_by:`.
- **Rule 3 cannot be pinned yet, and a layer name raises instead.** Sub-step 2a says
  ":tiles the only accepted name" and rules 3 and 4 assume a layer name is accepted and
  merely validated; those disagree, and accepting `blocked_by: [:npc]` today would mean
  a body that silently is not blocked by anything — the exact failure this step exists
  to close. So a name that is not `:tiles` raises at attach, naming what `on_hit` does
  instead. **Rule 3 moves to step 4**, which is where a layer name starts meaning
  something; rule 4 landed anyway, because the collider is required whatever was
  declared.
- **The raise order is collider first, then system.** Rule 2's "naming both" is two
  separate raises rather than one message: `require_sibling(BoxCollider)` runs before
  any system lookup, because a body declaring `:tiles` with no shape is the likelier of
  the two mistakes and its message already explains component add order.

Documented in `docs/api/components.md` (the `CharacterBody` entry rewritten around the
declaration, the `TileCharacterBody` entry gone, both collider entries noting the
conditional registration), `docs/api/systems.md` (which way a new client should choose),
and one reference each in `internals.md`, `toolbox.md` and `examples.md`.
`examples/collision_tiles`'s header claim that it "shares no code" with
`examples/collision` was **false after this step and has been rewritten** rather than
left for step 6: it now says the two share the collider and differ in mounting a world.
Step 6's remaining work there is the other half — what they will share once step 3 lands.

### Step 3 — blocker sources and the shared resolver (pure)

A refactor with no behaviour change, which is what makes it safe to land alone.
`CollisionSystem` stops holding a `TileCollision` and starts holding a list of
sources; `TileBlockers` is the only one, and it is `TileCollision` under a new
name.

Shape as in D3. The value of doing it as its own step is that the existing
`test/`-equivalent Ruby specs for tile resolution keep passing unchanged, which
is a strong signal that the seam is in the right place.

Rules the tests must pin:

1. One source gives exactly today's results, axis by axis.
2. Two sources take the most restrictive answer, in both directions on both axes.
3. Zero sources is free movement.
4. `move` allocates nothing with two sources registered.

Tests: `spec/rgame/engine/collision_system_spec.rb` gains the multi-source cases;
a fake source returning a fixed edge is enough and needs no world.

Verify: `rake spec` green with no example changed in the tile-resolution specs.

**Landed.** `Engine::TileBlockers` in `lib/rgame/engine/tile_blockers.rb` and
`CollisionSystem` holding a list of sources, with nine new examples in
`spec/rgame/engine/collision_system_spec.rb`. `rake spec` is 1200 examples, 0 failures
(1191 before, plus nine); `make test` 326 checks, 0 failures; `rake spec:core` 367
examples, 0 failures.

The acceptance criterion is met twice over. `spec/rgame/engine/tile_blockers_spec.rb`
differs from the old `tile_collision_spec.rb` in its `describe` line and nothing else —
no example changed — and the implementation body is byte-identical apart from the class
name and its header. Eight driven runs are **byte-identical** to `main` at
`--ticks 240 --seed 7`: `examples/collision_tiles`, `examples/walk`,
`examples/scroll_map`, and all five `tiled_world` scripts including `_pad` with
`--gamepad`.

Three things the sketch got wrong, and the third is the one step 4 has to answer:

- **`TileBlockers` is the rename, not a wrapper.** D3 sketches
  `TileBlockers.new(tile_collision)`, and building that would have been a class whose
  every method forwarded — `TileCollision` already implements the blocker-source
  protocol exactly, having been the only thing the system called. So the class is
  renamed and the file with it. The name lost a good word: what it does is still
  tile *collision*, and `Blockers` says instead what it is *for*, which is the thing
  worth naming once a second source exists. Step 6's "gains the blocker sources beside
  `TileCollision`" is therefore wrong and should read "renames the `TileCollision`
  section".
- **`resolve_x` / `resolve_y` are public on the system**, which the sketch does not say
  either way. They are what the new examples drive — a fake source returning a fixed
  edge needs no world, no tiles and no actor — and making them public means
  `CollisionSystem` satisfies the blocker-source protocol itself, so nesting one inside
  another would work. Nothing does that and nothing should yet.
- **A blocker source cannot simply live on the system, and `ActorBlockers` is why.**
  D3 puts `@blockers` on `CollisionSystem`, which is a scene-scoped object shared by
  every actor, and that is right for tiles: the grid is the same for everybody. But
  D3's own `ActorBlockers.new(world:, owner:, layers:)` takes an `owner` and a layer
  list, so it is **per body** — two actors declaring different `blocked_by` cannot
  share one. Step 4 therefore has to decide where a per-actor source hangs, and the
  shapes are: a `CollisionSystem` per body (cheap, but duplicates the world bounds and
  the tile source), or `move` taking the caller's extra sources as an argument (one
  shared system, and the argument is the body's own long-lived source, so it still
  allocates nothing). Nothing speculative was built for it here. **Add this to step 4
  alongside open question 1.**

Documented in `docs/api/internals.md`: the `TileCollision` section is now
`TileBlockers` and says what a blocker source is for, the `CollisionSystem` section
carries the protocol, the most-restrictive rule and why the loop is an index walk, and
its heading changed, so the one link to it in `docs/api/components.md` moved with it.
`Components::TileWorld`'s header names its one source. Sub-steps were not given in the
sketch; it landed as two commits, the refactor and the documentation.

### Step 4 — `ActorBlockers`, and the body owns its resolver

Actors block actors. Open question 1 is settled by measurement (B6) and step 3's
deferred question by D5, so what is left is a known amount of code in six
commits. It is much the largest step in the plan, and the only one that changes a
public signature — `TileWorld#move` goes in 4d and `CollisionSystem`'s bounds
arguments in 4e.

Rule 3 of step 2's list lands here too: a layer name with no `CollisionWorld`
raises at attach. It could not be pinned while every layer name raised.

#### 4a — `CharacterBody` resolves in world space *(pure, no behaviour change)*

First, because `ActorBlockers` compares the mover's box against other colliders'
AABBs and B8 measures those as being in different frames. World space is the frame
the broadphase and the tile map already use, so the body moves to it rather than
the other way round.

```ruby
# The actor adapter CollisionSystem#move drives. World space, because that is
# where the tile grid and the broadphase both are.
def x = node.world_x
def y = node.world_y

def x=(value)
  node.x += value - node.world_x
end

def y=(value)
  node.y += value - node.world_y
end
```

The `+=` form is what keeps this a translation of the node's own local position
rather than an assignment into a frame it does not live in. It is exact for an
unrotated ancestor chain and approximate for a rotated one — but an actor under a
rotated ancestor is already outside what an axis-aligned box supports, and
`docs/api/components.md` already says a thing that spins wants a circle. So this
is **a documented limit at the code, not a raise**, for the same reason open
question 3 refuses one: the ancestor can start rotating after attach, and a guard
that only catches the rotation that was there at attach is worse than a sentence
that is always true.

Rules the tests must pin:

1. A body under an offset ancestor resolves against tiles at its world position,
   not its local one.
2. Writing the resolved position leaves the node's *local* x/y offset by exactly
   the resolved delta.
3. A body under a *rotated* ancestor resolves against the ancestor's unrotated
   axes — the documented limit, pinned so it is a decision rather than a surprise.
4. `move` still allocates nothing — `world_x` is cached and self-invalidating, so
   this must not have introduced a per-step recompute that does.

Verify: every driven run is byte-identical to `main` at `--ticks 240 --seed 7`,
which is the acceptance criterion — B8 says the discrepancy is latent, and a
byte-identical report is what proves the claim rather than restating it. Run
`examples/collision_tiles`, `examples/walk`, `examples/scroll_map` and all five
`tiled_world` scripts.

#### 4b — `SpatialHash#remove`, `CollisionWorld#reindex` and `#query_box`

The index API the resolver needs, landed on its own so its allocation behaviour is
pinned before anything depends on it.

```ruby
class SpatialHash
  # Un-bucket an item from the cells the given box covers — the exact inverse of
  # #insert, so the caller passes the box the item was inserted at.
  def remove(item, x, y, w, h)
end

class CollisionWorld
  # Re-bucket a collider that has moved since the index was built, so a query
  # later in the same step still finds it.
  def reindex(collider, from_x, from_y, from_w, from_h)

  # Yield every registered collider bucketed in a cell the region covers, skipping
  # those whose node is queued for removal. The rectangular counterpart to
  # #query_circle, and it inherits its dedup contract: a collider spanning several
  # cells may be yielded more than once.
  def query_box(x, y, w, h)
end
```

`remove` needs no stored state because the caller knows the box: that is what
makes this cheap, and it is why `CollisionSystem#move` passes the from-box to
`#moved` (D6) rather than anything remembering one.

Rules the tests must pin:

1. `remove` un-buckets from every cell a multi-cell box covered, and leaves other
   items in those cells alone.
2. `remove` of an item that was never inserted is a no-op, not a raise.
3. `remove` + `insert` allocates nothing once the buckets exist.
4. `reindex` makes a collider that moved findable at its new position and not at
   its old one, within the same step.
5. `query_box` skips a collider whose node is `freed?`.
6. `query_box` allocates nothing.

Tests: `spec/rgame/engine/spatial_hash_spec.rb` and
`spec/rgame/engine/components/collision_world_spec.rb`.

#### 4c — `Engine::ActorBlockers` *(pure)*

The source itself. It needs no scene, no node and no tree: a double standing in
for the world and answering `query_box` is enough to drive every case.

```ruby
# The registered colliders as a blocker source: the broadphase answers "what is
# near this box", and the same snapping arithmetic TileBlockers uses against a
# tile edge runs against a collider's edge. Pure.
class ActorBlockers
  # `world` answers query_box/reindex; `owner` is the mover's own collider, excluded
  # by identity so a body is never stopped by itself; `layers` is what may stop it.
  def initialize(world:, owner:, layers:)

  def resolve_x(x, y, w, h, dx)   # -> where the box's left edge lands
  def resolve_y(x, y, w, h, dy)   # -> where the box's top edge lands
  def blocker                     # -> the collider that produced the last edge, or nil
  def moved(actor, from_x, from_y, w, h)  # -> world.reindex(owner, ...)
end
```

The arithmetic is `TileBlockers`' with the edge coming from a collider instead of
a grid line, plus three things a grid does not need:

- **The most restrictive candidate wins**, since several colliders may be in the
  way. A running minimum, which is dup-insensitive — the broadphase may offer the
  same collider once per shared cell, and `CollisionWorld#nearest` is written the
  same way for the same reason.
- **An overlap that already exists is not resolved.** A step is blocked only if it
  *crosses* the blocker's edge: the mover's leading edge was at or before that
  edge before the step. Two actors that start overlapping stay overlapping and
  neither is teleported, which is the same "blocking never moves the thing it hit"
  rule G already states.
- **Boxes only.** A candidate that is not a `BoxCollider` is skipped (open
  question 3). `CircleCollider` is a sibling class rather than a subclass, so
  `is_a?` separates them exactly.

Rules the tests must pin:

1. A step into a collider on a blocked layer lands flush against its edge, in all
   four directions.
2. A collider on a layer that was not declared does not stop the step.
3. The owner's own collider never stops it, even when its own layer is declared —
   which is what lets a crowd of NPCs all declare `blocked_by: [:npc]`.
4. A collider whose node is `freed?` does not stop it.
5. A `CircleCollider` on a declared layer does not stop it.
6. With several blockers in the way, the step lands against the nearest.
7. A pair that already overlaps is not pushed apart, and the step is not blocked.
8. The same collider offered twice by the broadphase gives the same answer as once.
9. `blocker` names the collider that produced the edge, and is nil when the step
   was free.
10. `moved` re-indexes the owner at its new box.
11. `resolve_x` and `resolve_y` allocate nothing.

Tests: `spec/rgame/engine/actor_blockers_spec.rb`, one case per rule, against an
instance double for the world.

#### 4d — `CharacterBody` owns its resolver, and `TileWorld#move` retires

The wiring, and the only commit that changes a public signature.

```ruby
class CharacterBody < Engine::Component
  # on_attach now resolves each declared source and builds the system:
  #   :tiles          -> node.system(TileWorld).blockers, or raise
  #   any other name  -> one ActorBlockers over every such name, or raise for a
  #                      scene with no CollisionWorld  (step 2, rule 3)
  # World bounds come from node.system(WorldBounds), and nil means no clamp.
end

class TileWorld < Engine::Component
  attr_reader :blockers   # an Engine::TileBlockers
  # #move and its CollisionSystem are gone
end

class CollisionSystem
  def initialize(world_width: nil, world_height: nil, blockers: [])
  def move(actor, dx, dy)   # now also calls #moved on every source
  attr_reader :blocked_x, :blocked_y   # set by #move; step 5 reads them
end
```

`CollisionSystem`'s bounds become optional here because `test_projects/snake`
mounts a `CollisionWorld` and no `WorldBounds` at all, so a body blocked only by
actors has nowhere to get them. That is an interim: 4e takes the clamp out
altogether and the arguments with it. Nothing changes for a `:tiles` body in
between — `TileWorld` *is* a `WorldBounds`, so it clamps against the same numbers
it clamps against today.

Rules the tests must pin:

1. `blocked_by: [:npc]` with no `CollisionWorld` raises at attach, naming the
   layer — step 2's rule 3, finally pinnable.
2. `blocked_by: [:npc]` with a `CollisionWorld` and no collider on that layer
   moves freely, and does not raise. A layer can legitimately be empty.
3. `blocked_by: %i[tiles npc]` stops at whichever is nearer, both ways on both
   axes.
4. `blocked_by: [:npc]` in a scene with no `WorldBounds` is not clamped and does
   not raise.
5. `blocked_by: [:tiles]` is clamped to the map exactly as it is today.
6. Two bodies walking into each other both stop, and neither is pushed.
7. `update` allocates nothing with both kinds of blocker declared.

Verify: this is the step where `test_projects/tiled_world` must change *behaviour*
and say so. Give its NPCs and walkers `blocked_by: %i[tiles npc hero]`, add a
drive script that walks a player into an NPC, and report the difference: today the
walker passes through, afterwards it stops. Every other driven run stays
byte-identical at `--ticks 240 --seed 7` — `examples/collision`,
`examples/collision_tiles`, `examples/walk`, `examples/scroll_map`,
`examples/pooling`, `examples/signals`, `test_projects/snake`,
`test_projects/asteroids`.

#### 4e — `:bounds` as a blocker source, and the clamp retires

The last implicit piece of blocking becomes a declared one. Shape as in D7.

```ruby
# The edges of the world as a blocker source: a box may not leave the region the
# scene's WorldBounds describes. Pure — it is four numbers and the same snapping
# arithmetic every other source uses.
class BoundsBlockers
  def initialize(bounds:)   # anything answering world_width / world_height
  def resolve_x(x, y, w, h, dx)
  def resolve_y(x, y, w, h, dy)
  def blocker               # -> BOUNDS, a sentinel answering layer -> :bounds
  def moved(actor, from_x, from_y, w, h) = nil
end

class CollisionSystem
  def initialize(blockers: [])   # world_width:/world_height: are gone with the clamp
end
```

`CollisionSystem` loses its bounds arguments altogether rather than keeping them
optional, which is what 4d would otherwise have done. A body that wants the world
edge names it, and a body that does not is not silently held inside anything.

Rules the tests must pin:

1. `blocked_by: [:bounds]` stops a step flush against each of the four edges.
2. `blocked_by: [:bounds]` with no `WorldBounds` in scope raises at attach, the
   same way `:tiles` with no `TileWorld` does.
3. A body *without* `:bounds` walks past the world edge, and is not clamped.
4. `blocked_by: %i[tiles bounds]` takes whichever is nearer.
5. A node carrying both a bounds-blocked body and a `ScreenWrap` is a declared
   contradiction rather than the silent teleport B9 measures — pin which one wins,
   so the answer is a decision.
6. `blocked_by: [:bounds]` on a node under an offset ancestor bounds the *world*
   region, not one shifted by the ancestor. 4a is what makes this true.

Verify: every tile drive run stays byte-identical at `--ticks 240 --seed 7`, which
B10 predicts and which is the whole reason this can land here — `examples/collision_tiles`,
`examples/walk`, `examples/scroll_map` and all five `tiled_world` scripts. Then the
case B9 could not reach before: a `FeetCollider` walker with a `DespawnOffscreen`
survives touching the left wall.

#### 4f — documentation

`docs/api/components.md`: `CharacterBody`'s entry gains layer names in
`blocked_by` and the box-only limit; both collider entries note that a circle
reports contacts and stops nothing. `docs/api/systems.md`: `TileWorld` loses
`move` and gains `blockers`; `CollisionWorld` gains `query_box` and `reindex`,
with B6's numbers behind the re-index rather than an assertion that it is needed.
`docs/api/internals.md`: `ActorBlockers` and `BoundsBlockers` beside
`TileBlockers`, and the `CollisionSystem` section gains `#blocker` and `#moved`
and loses the clamp. `ScreenWrap` and `DespawnOffscreen` gain a line each saying
that a body blocked by `:bounds` is the thing they contradict — B9 is a defect
nobody could have read about anywhere.

**Landed.** Six commits, one per sub-step. `Engine::ActorBlockers` and
`Engine::BoundsBlockers` in `lib/rgame/engine/`, `SpatialHash#remove`,
`CollisionWorld#query_box` / `#reindex`, `CharacterBody` owning its resolver and
resolving in world space, `TileWorld#move` and the world clamp both gone.
`rake spec` is 1285 examples, 0 failures (1200 before, plus 85); `make test` 326
checks, 0 failures; `rake spec:core` 367 examples, 0 failures.

The acceptance evidence, in three parts.

**4a is invisible, as B8 predicted.** All eight tile-driven runs are byte-identical
to `main` at `--ticks 240 --seed 7`.

**4d changes `test_projects/tiled_world` and says so.** It mounts a `CollisionWorld`
and every walker declares `blocked_by: %i[tiles hero npc]`.
`tools/drive/test_projects/tiled_world_blocking.rb` walks the player into the villager
who stands still at (880, 672):

| | player stops at | last `tilemap` camera x | distinct translates |
|---|---|---|---|
| `blocked_by: [:tiles]` | x 820, at a wall, having walked through the villager | 508 | 777 |
| `blocked_by: %i[tiles hero npc]` | **x 900, against the villager** | 588 | 697 |

Every driven run outside `tiled_world` is byte-identical: `examples/collision`,
`collision_tiles`, `walk`, `scroll_map`, `pooling`, `signals`, `test_projects/snake`,
`asteroids`. The four other `tiled_world` scripts do change, because the villagers now
block each other too; `tiled_world_pad` happens not to walk far enough to notice.

**4e is a no-op for every game, as B10 predicted.** All thirteen driven runs are
byte-identical across the clamp's removal. And B9, measured the same way it was found —
a 16×22 hero with a 12×6 feet box and a `DespawnOffscreen`, walking left for 60 steps in
a 320×240 `World` scene:

| | ends at `node.x` | despawned |
|---|---|---|
| at 4d, `blocked_by: [:npc]` | −2, held at the world edge and fully inside it | **yes — the defect** |
| at 4e, `blocked_by: [:npc]` | −20, having genuinely left | yes, correctly |
| at 4e, `blocked_by: %i[npc bounds]` | −2 | yes — a *declared* contradiction |

That third row is the honest limit and it is worth stating plainly: **4e does not
reconcile the two coordinate frames, it stops anyone being put between them without
asking.** A body that declares `:bounds` is still held by its *box* while
`DespawnOffscreen` and `ScreenWrap` still read its *node*, so declaring both is still
wrong — it is now wrong on purpose, pinned by a spec and documented at both components.

Nine things the sketch got wrong, and the first is the one step 5 needs:

- **`blocked_x` / `blocked_y` and `TileBlockers::TILES` landed here, not in 5a.** 4d's
  own sketch lists the two readers, and they cannot mean anything until every source
  answers `blocker` — which 5a's sketch owned. Pulling the sentinel forward was cheaper
  than half a protocol. **Step 5a is therefore already done**, and step 5 is now only 5b
  (the two signals on the body) and 5c (the spiky ball).
- **The blocker-source protocol went from two methods to four, so every stand-in did
  too.** `collision_system_spec`'s fake source grew `blocker` and `moved`, and its
  `moved` records into four preallocated slots rather than pushing an Array — the
  allocation example drives the same fake, and a recording fake that allocates is the
  only thing such an example would then see.
- **`ActorBlockers` checks `freed?` itself**, duplicating `CollisionWorld#query_box`.
  Deliberate: what may stop a step is the source's rule, and a source that inherits its
  world's filtering policy is not the pure, world-agnostic thing D3 describes.
- **"Stops at whichever is nearer, both ways on both axes" cannot be built with a narrow
  blocker in the direction where the *wall* wins.** `TileBlockers` only tests the column
  or row the step *lands in*, so a collider beyond a solid column is reachable only by a
  step that tunnels it. Where the wall has to win, the competing collider must be a wide
  one whose far edge is just short of the wall's. Said at the spec, because the next
  person to write one of these will hit it.
- **A parentless node is pinned to the world origin.** `Node2D#resolve_transform` gives
  the root identity, so `world_x` is 0 whatever the node's own x says — which meant 4a
  turned every existing body spec red until each hung its actor under a root. No code
  changed for it; any later spec of a blocked body has to do the same.
- **`test_projects/tiled_world` needed a `CollisionWorld` mounted**, which 4d's verify
  does not mention — "give its NPCs and walkers `blocked_by: %i[tiles npc hero]`" is not
  possible without one. `cell_size: 32`, following B11: sized to the actors, not to the
  16px tiles.
- **An allocation example has to leave the body *pressing* against a blocker, not
  travelling.** A moving actor enters fresh broadphase cells and the buckets built for
  them read as a per-frame leak — measured at 32 objects over 1,000 calls before the
  example was pinned to a stopped body.
- **4e's rule 5 resolves as "ScreenWrap wins", and the reason is B9 itself.** The body
  holds the *box* at the edge, which leaves `node.x` at minus the box offset, which is
  exactly what `ScreenWrap` reads and wraps.
- **The drive harness dropped a frame in three of about forty runs** (239 of 240), each
  time reproducing byte-identically on a re-run. It is the documented fixed-timestep
  effect, not a behaviour change, and it is worth knowing that a first capture of a
  baseline can be the run that is wrong.

Documented in `docs/api/components.md` (the `blocked_by` table, the three things worth
knowing about a layer name, why `blocked_by` and `on_hit` are not alternatives, both
collider entries on what can and cannot stop a step, `TileWorld#blockers`,
`CollisionWorld#query_box` / `#reindex`, and a contradiction line each on `ScreenWrap`
and `DespawnOffscreen`), `docs/api/internals.md` (`ActorBlockers` and `BoundsBlockers`
beside `TileBlockers`; `CollisionSystem` gains the four-method protocol, `blocked_x` /
`blocked_y`, and loses the clamp), `docs/api/toolbox.md` and `docs/api/examples.md`.
`examples/collision_tiles`'s "what it does not solve" section was **false after this
step and has been rewritten** — passing through another character is now a choice of
that scene rather than a limit of the engine, and the header says which line changes it.
Step 5c still owns the worked example there.

### Step 5 — `on_blocked` and `on_unblocked`

The body reports what stopped it. This is what makes the spiky ball work and is
the reason steps 1–4 were worth doing. Small, because step 4 built the parts:
`CollisionSystem` already knows which source won each axis, and `Engine::ContactSet`
already implements "this step and last".

#### 5a — the sources report who

> **Landed inside step 4d.** All three sentinels and both `CollisionSystem` readers
> exist; see step 4's landed note for why they could not wait. What is left of step 5 is
> 5b and 5c.

```ruby
class TileBlockers
  # What a TileBlockers reports as having stopped a step. One object for the life
  # of the process, answering the same two questions a collider does, so a handler
  # reads `by.layer` whatever stopped it.
  TILES = (a frozen object answering `layer` -> :tiles and `node` -> nil)

  def blocker = TILES
end

class CollisionSystem
  # The blocker that produced each axis's edge on the last #move, or nil when the
  # axis was free. Read immediately after #move; #move sets both every call.
  attr_reader :blocked_x, :blocked_y
end
```

`BoundsBlockers#blocker` is a constant on the same terms, answering `:bounds`, so
the three sources report three sentinels of one shape and a handler reads
`by.layer` without ever asking which kind stopped it.

`TileBlockers#blocker` being a constant is what keeps one `TileBlockers` shared by
every body on the map: the source holds no per-move state, so there is nothing for
two bodies to race over. `ActorBlockers#blocker` *is* per-move state, and it is
safe for the opposite reason — the source belongs to one body, and that body reads
it inside its own `update`.

#### 5b — the body emits the two edges

```ruby
class CharacterBody < Engine::Component
  # The two edges of being stopped: on_blocked on the step this body starts being
  # stopped by something, on_unblocked on the step it stops. Each fires once per
  # blocker, so a handler may spend a life or play a sound. The listener gets the
  # blocker and reads its #layer / #node — the map's solid tiles included.
  signal :on_blocked,   Engine::Signal.define(:by)
  signal :on_unblocked, Engine::Signal.define(:by)
end
```

**The set advances once per `update`, not once per `apply_move`.** That is what
makes standing still an unblocking: a body that stops pressing into the spiky ball
records nothing this step, so the ball ends and `on_unblocked` fires. It also
keeps the bookkeeping where a subclass cannot lose it — `update` opens the step,
calls `apply_move`, and reports the edges, so a platformer body overriding
`apply_move` (which step 2 says is exactly what that split is for) inherits all of
it.

Rules the tests must pin:

1. Walking into a wall fires `on_blocked` once, with a blocker whose `layer` is
   `:tiles`, and not again while the body keeps pushing.
2. Walking away fires `on_unblocked` once, with the same blocker.
3. Standing still against a wall fires `on_unblocked` — the body is no longer
   being stopped.
4. Walking into a collider fires `on_blocked` with that collider, and `node` is
   its owner.
5. A step stopped on both axes by the same blocker fires `on_blocked` once.
6. A step stopped on X by a tile and on Y by a collider fires twice, once for
   each.
7. Being blocked by A and then by B without a gap fires `on_unblocked(A)` and
   `on_blocked(B)`.
8. A pooled body reacquired after death does not fire a spurious `on_unblocked`
   on its first step — `on_attach` resets the set, the same rule
   `CollisionWorld#register` follows for contacts.
9. A blocked step allocates nothing, edges included.
10. `blocked_x` / `blocked_y` name the axis, for a body that wants it without the
    signals.

Tests: `spec/rgame/engine/components/character_body_spec.rb` gains a `describe`
for the edges; `spec/rgame/engine/collision_system_spec.rb` gains `blocked_x` /
`blocked_y` against the fake source it already uses.

#### 5c — the spiky ball, as an example and as documentation

A worked example is what proves the signal answers the question this plan was
written from. Extend `examples/collision_tiles` rather than adding a nineteenth
example directory: it already has a map, a walker and a feet box, and what it is
missing is exactly the actor half. Add a spiky ball on its own layer, give the
walker `blocked_by: %i[tiles spike]` and an `on_blocked` that spends a life, and
drive it with a script that walks into the ball and away again. Its header
currently explains that the scene mounts no `CollisionWorld`, so that paragraph is
rewritten rather than patched — which is also the other half of the rewrite step 2
started there, and takes it off step 6's list.

Per the write-example skill: the drive script goes in
`tools/drive/examples/collision_tiles.rb`, and the report is the acceptance
criterion — lives lost, not a screenshot.

Then `docs/api/components.md` gains the two signals, and `docs/api/systems.md`
gains the blocking-versus-overlap distinction step 6 was holding, with B4 as the
reason a blocked pair reports no contact.

### Step 6 — fold the plan back and delete it

Real work, not tidy-up — but less of it than when the plan was written, because
steps 2 to 5 each documented themselves as they landed. What is left is the part
no single step owned.

`docs/api/systems.md` gains the shape of the whole thing in one place: two
indexes, one resolver, and the reason blocking and overlapping cannot be the same
report (B4). Each step wrote its own entries; none of them wrote the paragraph a
reader needs before those entries make sense.

`docs/api/toolbox.md` gains the four-line node — sprite, feet collider, body,
controller — as the answer to "how do I make a character that collides with the
world and with other characters", which is the question this plan started from and
which had no answer anywhere in the documentation.

`examples/collision_tiles`'s header is done by step 5c, and `examples.md`'s
catalogue entry for it needs to match.

Then delete this file.
