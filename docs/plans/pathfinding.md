# Pathfinding — `examples/pathfinding` and the engine it needs

**Status:** planned at `707ea1a`. **Steps 1–4 are implemented.** Steps 1–4 are detailed; step 5 (the C search) is
rough and is to be re-planned once step 4 has put a real caller on the API; step 6
deletes this file.

The requirement, from `docs/plans/basic-examples.md` ("12. `examples/pathfinding`"):
*a click-free "go there" — pick a target tile, compute a route around the solid
tiles, walk it*, on assets **A** and **B**, with `town.tmx`'s fence as the thing
worth routing around.

## Verdict

- **The search is Ruby first, and it is fast enough for the example by a wide
  margin** — about 1.5 ms for a corner-to-corner route across `town.tmx`, on
  demand, never per frame. It is not fast enough for the engine in general: on
  `beach_large.tmx` (120x90, the largest map in the repo) the worst of 200 random
  routes took **18.7 ms**, more than a frame. A C search measured **~60x** faster
  per expanded cell. So C is justified, but *after* the example, as step 5, once a
  real caller has settled the API — the shape CLAUDE.md prescribes in the other
  direction ("only extend the Ruby wrapper once the C API is settled") applies
  here as "only port to C once the Ruby API is settled". It lands in
  `ext/rgame_util/`, because a grid search is pure logic with no SDL.
- **Three things already exist that this must extend rather than sit beside**
  (see "What it resembles"):
  1. **Solidity has one owner, `TileWorld`.** The navigation grid is a second
     *view* of the same fact the map's `TileBlockers` already answer, so
     `TileWorld` hands it out the way it hands out `blockers`. The example never
     builds one.
  2. **Facing belongs to `Mover`, not to `CharacterBody`.** `AnimatedSprite`
     `require_sibling(CharacterBody)` today, so a hero on a path slides around
     unanimated — the open question the component sweep deferred to this example.
     Every mover knows which way its step goes; `Mover#heading_x`/`#heading_y`
     say so, and `AnimatedSprite` reads any mover.
  3. **Route smoothing asks the walker's own resolver.** A smoothed segment is
     accepted only if the map's `TileBlockers` — the very source that will stop
     the walker — lets the walker's collider box travel it. A cell-based
     line-of-sight test would produce corners a 12px feet box clips, and
     `PathFollow` *does not slide*: it would stand at that corner for ever.
- **The component is `Components::Navigator < PathFollow`**, with
  `go_to(world_x, world_y)`. One component, not a search component handing a
  `Path` to a sibling `PathFollow` — that hand-off is exactly the "hook whose only
  job is handing one component's data to another" CLAUDE.md names as the smell.

## Goal

A single example a stranger reads top to bottom: move a tile cursor, confirm, and
watch the hero compute a route through the fence's one gap and walk it, animated,
with the raw grid route and the smoothed one both drawn. Everything it needs in the
engine is spec-able headless.

## Hard constraints

1. **Engine layer only** for steps 1–4: pure Ruby under `lib/rgame/engine/`, no
   `RGame::Core` — not in code, not in specs.
2. **Nothing on a per-frame path allocates.** A search runs on demand and may
   allocate; `PathFollow`'s walk, and `Mover#heading_*`, may not
   (`spec/rgame/engine/components/path_follow_allocation_spec.rb` must stay green).
3. **Existing examples must not change** under the facing change. `walk`,
   `collision_tiles`, `jump_topdown`, `split_screen`, `input_glyphs` and
   `game_menu` all mount `AnimatedSprite` on a `CharacterBody`; their driven reports
   are compared before and after step 1.
4. **Step 5's C is `ext/rgame_util/`**, layer-1 pure with Check tests, and the
   Ruby `NavGrid` specs from step 2 are its contract unchanged.
5. **No asset changes.** `town.tmx` already has the obstacle (measured below).

## Decisions already taken

Not up for re-litigation inside this plan.

- **`nil` for unreachable**, not an exception and not an empty route — an
  unreachable target is an ordinary answer. (From `basic-examples.md`.)
- **A held walker waits; it does not replan.** `PathFollow`'s blocked behaviour is
  kept as documented: `blocked_by` covers what the search could not know (another
  character), and a game that wants to get past one calls `go_to` again. (From
  `basic-examples.md`.)
- **Ruby before C**, for the reason in the verdict, and C is still planned rather
  than left as "if profiling ever says so" — the 18.7 ms on a map in this repo is
  the profiling. (Decided while writing this plan; the prompt asked for C to be
  looked into.)

## Open questions

1. **A node with two movers.** `get_component(Mover)` raises `ArgumentError` when
   two match, so once `AnimatedSprite` reads *any* mover, a node carrying both a
   `CharacterBody` and a `Navigator` (a player who can also click-to-walk) fails at
   attach. Is two movers on one node ever coherent — both write the position —
   or is the raise the right answer and only its message needs to say so?
   *Blocks nothing in the example* (its hero has one mover); decide in step 1,
   leaning "raise, with a message that names both".
   **Resolved in step 1: raise, naming both** (decided in the prompt, "raise is fine
   for now"). The raise lives in `Component#require_sibling`, so it covers every
   component pulling a sibling by a class several components answer to, not just
   `AnimatedSprite`.
2. **Where the camera looks.** The cursor is in world space and the camera follows
   the hero; a cursor walked off-screen is lost. Options: clamp the cursor to the
   view, have the camera follow the cursor, or follow the hero and let the cursor
   push the camera. *Blocks step 4's feel, not its engine work*; decide by trying
   it, leaning "the camera follows the cursor, the hero may walk out of view".
   **Resolved in step 4: the camera follows the cursor**, as leaned. Decided from what
   picking a tile needs and from frames captured off the driven run, not by playing
   it by hand.
3. **Cursor repeat.** Does a held arrow key repeat, and if so is there a repeat the
   engine already owns (`UI::Menu`'s navigation) that can be reused rather than
   re-implemented? *Blocks nothing*; step 4 checks, and press-only is acceptable.
   **Resolved in step 4: it repeats, through `Components::ActionTrigger`.** `UI::Stepping`
   is press-only, so the menu has no repeat to reuse; `ActionTrigger` fires a held action
   on the press and every cooldown after, which is a key repeat with no initial delay.

## What was measured before planning

At `707ea1a`, Ruby 4.0.5 without YJIT. The prototypes were throwaway scripts, not
committed; the method is stated so a number can be re-taken.

| | |
|---|---|
| `rake spec` (headless) | 1783 examples, 0 failures, ~3.9 s |
| `town.tmx` | 60x40, 342 solid cells, **one** connected open region of 2058 cells |
| town fence | full width at row 20, gap at columns 12–14 only |
| Search: 8-connected, octile heuristic, no corner cutting, binary heap | |
| — Ruby, closures, fresh arrays per search: town corner to corner | 3.1 ms, 730 cells expanded |
| — the same, target walled off (floods the map) | 9.3 ms, 2054 expanded |
| — Ruby, tuned (flat arrays reused with a generation stamp, `while` loops, no closures) | **~2.2 µs per expanded cell**: 27 ms / 12 320 cells on a 128² comb maze, 442 ms / 196 736 on 512² |
| — C, `-O2`, same algorithm | **~0.035 µs per expanded cell**: 0.48 ms on 128², 6.9 ms on 512², 39 ms on 1024² |
| — tuned Ruby, `beach_large.tmx` (120x90), 200 random pairs | mean 1.22 ms, **worst 18.7 ms**, max 5359 expanded |
| — tuned Ruby, `island.tmx` (58x47), 200 random pairs | mean 0.25 ms, worst 1.4 ms, 46 of 200 unreachable |
| Building a flat solid array from `TileMap#solid_tile?` for town | 0.9 ms, once |
| Callers of `AnimatedSprite.new` | 6 examples, `test_projects/tiled_world` (2), `culling_spec` — all beside a `CharacterBody` |
| `require_sibling(CharacterBody)` | `AnimatedSprite`, `PlayerController`, `WanderController` |
| Any existing grid search, heap or route smoothing in the project | none (`grep -ri 'heap\|astar\|pathfind'` over `lib`, `ext/rgame_util`, `test_projects`) |

Two things the numbers settle beyond the verdict:

- **Unreachable is the expensive answer**, because A* has to exhaust the region to
  give it. `island.tmx` answers it 46 times in 200. Labelling the connected regions
  once, when the grid is built, turns every cross-region query into an O(1) `nil`
  — cheaper than any C port for that case, and C does not remove the need for it.
- **The one-region town cannot show a cross-region `nil`**; the only unreachable
  target it offers is a solid tile. The example shows that, and the spec suite
  covers regions on fixture grids.

## What it resembles

The three piles CLAUDE.md asks for.

### Reuse it

| Existing | Does the job of |
|---|---|
| `Engine::Path` | the route as walked: flat waypoints, precomputed lengths, no per-frame allocation |
| `Components::PathFollow` | walking it at a speed, `on_finished`, waiting when blocked |
| `Components::FeetCollider` | the box a route has to clear |
| `TileWorld`, `TileMapLayer.mount`, `WorldView`, `CameraFollow` | the scene, exactly as `examples/collision_tiles` mounts it |
| `Engine::CachedLabel` | "route: N cells, M waypoints" without a per-frame string |
| `spec/support/shared_examples/a_mover.rb` | the blocked-walk contract, already parameterised by `heading:` |

### Extend or generalize it

| Existing | Answers | Generalization |
|---|---|---|
| `TileWorld#blockers` (a `TileBlockers` over `map.solid_tile?`) | *what is in the way of a step* | `TileWorld#nav_grid` — *what is in the way of a route* — over the same `solid?`. Same fact, same owner, a second view. |
| `CharacterBody#move_x`/`#move_y`, read by `AnimatedSprite` as a facing | *which way is this node going* — for one mover only | `Mover#heading_x`/`#heading_y`, answered by all three movers; `AnimatedSprite` reads a `Mover` |
| `PathFollow.new(path:)`, a path fixed for the component's life | *walk this route* — once | `PathFollow#follow(path)` and `path: nil` (idle), so the walk can be handed a new route |
| `TileBlockers#resolve_x`/`#resolve_y` | *where does this box land moving dx* | used unchanged as the smoothing test — the generalization is in who asks |

The parallel-vocabulary check, written side by side:

| Step collision | Route planning |
|---|---|
| `TileBlockers` (over `solid?`) | `NavGrid` (over `solid?`) |
| `CollisionSystem#move` | `NavGrid#find` |
| `blocked_x` / `on_blocked` | `nil` from `find` |
| `CharacterBody` | `Navigator` |

The rows pair up, which is the signal that they should share an owner (`TileWorld`)
and an input (`solid?`), and should *not* share an implementation: one answers a
sub-tile sweep of a box, the other a graph search over cells. Smoothing is where
they meet, and it meets by calling the first from the second.

### Genuinely new

- **`Engine::NavGrid`** — the search and the region labels. Nothing in the engine
  searches a graph.
- **`Components::Navigator`** — turning a world target into a cell route, a
  smoothed `Path`, and a walk. It is new code but not a new *kind* of thing: a
  `PathFollow` that makes its own paths.

## Prior art

Plans may name other engines; the documentation this folds into will not.

- **Godot's `AStarGrid2D`**
  (<https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html>) is the
  closest match to `NavGrid`: a rectangular grid with per-cell solidity, a
  selectable heuristic (Manhattan, Euclidean, octile, Chebyshev), a `diagonal_mode`
  whose `ONLY_IF_NO_OBSTACLES` is our "no corner cutting", and `get_id_path` /
  `get_point_path` separating cell results from world results — the same split
  this plan makes between `NavGrid#find` and `Navigator`. It returns an empty
  array for unreachable; we return `nil`, by decision.
- **Godot's `NavigationAgent2D`**
  (<https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html>)
  is the `Navigator` shape: set a target position, the agent owns the path and
  its post-processing, the game moves along it and hears when it arrives. It works
  on navigation meshes and does avoidance as a separate concern.
- **Unity** answers with a baked `NavMesh` plus `NavMeshAgent`; grid search is left
  to packages.

**What none of them gives us:** a smoothing step that is checked against the same
resolver the walker collides with, so the route and the collision cannot disagree
about what a 12x6 box fits through — and the whole search running headless under
RSpec, deterministically.

## Considered and rejected

- **`AStar.find(grid, from, to) #=> Path`**, the sketch in `basic-examples.md`.
  Attractive because it made the new code "one function". It fails because a
  `Path` is in *node-origin pixels*, and turning a cell into the point a node's
  origin must reach needs the node's collider box — which a grid search has no
  business knowing. Cells out of the search, pixels out of the component.
- **A search component beside a `PathFollow`**, handing it each new `Path`.
  Reuses `PathFollow` untouched, and is the hand-off hook CLAUDE.md warns about:
  forgetting to wire it is silent, and the two components' add order starts to
  matter. A subclass is order-free.
- **Smoothing by cell line-of-sight** (Bresenham, or a supercover line). Cheap and
  standard. It ignores the walker's box, so it accepts a diagonal past a tree
  corner that the feet box clips; `PathFollow` then rewinds every step against that
  corner and the hero stands there — a bug that looks like collision.
- **Any-angle search (Theta\*)** instead of search-then-smooth. Better routes on
  open ground, but its line-of-sight test inside the search loop has the same
  box-blindness unless it calls the resolver, which multiplies the search's cost by
  a sweep per relaxation. String-pulling a finished route calls it O(route) times.
- **Jump point search.** Large speedups on uniform-cost grids, and considerably
  more code to get right; the C port buys ~60x without changing the algorithm, and
  JPS stays available inside the C later.
- **Flow fields / Dijkstra maps.** The right answer for many agents converging on
  one target, and a natural second consumer of `NavGrid`. Not what one hero
  walking to a chosen tile needs.
- **C from the start.** The CLAUDE.md default for engine features, and the numbers
  support it eventually. Rejected *for now* because the API would be designed
  without a caller; porting a settled `find` is mechanical, re-binding a moved one
  is not.
- **The example builds its own grid from the `TileMap`.** One line in the example
  and a second owner of solidity; `TileWorld` already is the owner.

## Roadmap

```
1 Mover heading + PathFollow#follow ─┐
                                     ├─→ 3 Navigator ─→ 4 examples/pathfinding ─→ 5 C search (rough) ─→ 6 fold back
2 NavGrid (pure) ────────────────────┘
```

Steps 1 and 2 are independent and each worth landing alone:

| Step | Closes |
|---|---|
| 1 | a walker on a path is unanimated — the deferred facing question; a `PathFollow` cannot be given a second route |
| 2 | the engine has no search at all |

> **Invariant from step 3 on: a route a `Navigator` walks is one its own
> `blocked_by: [:tiles]` resolver lets it walk end to end.** Walking any route it
> produced over the fixture grids reports no `on_blocked` by `:tiles`.

### Step 1 — `Mover#heading_x`/`#heading_y`, `AnimatedSprite` over any mover, `PathFollow#follow`

**Why here.** It is the open question `basic-examples.md` said blocks the example's
animation, and it touches existing components that five examples use, so it wants
its own branch and a before/after comparison of their reports rather than being
buried under new code.

**Shape.**

```ruby
class Mover < Engine::Component
  # Which way this mover's step is going, each axis in -1..1; 0, 0 when it is not
  # trying to move. A facing, not a velocity: a mover pressed into a wall still
  # heads into it.
  def heading_x = 0.0
  def heading_y = 0.0
end

class CharacterBody < Mover
  def heading_x = @move_x          # move_x/move_y stay, as the intent
  def heading_y = @move_y
end

class Velocity < Mover             # vx, vy scaled into -1..1 by the larger magnitude, no sqrt
end

class PathFollow < Mover
  def initialize(path: nil, speed:, blocked_by: [])
  def follow(path)                 # restart: segment 0, placed at waypoint 0, not finished
  def heading_x                    # current segment's direction; 0 when idle or finished
end

class AnimatedSprite < Engine::Component
  def on_attach
    # ...
    @mover = require_sibling(Mover)
  end
end
```

`PathFollow` caches the current segment's unit direction when the segment index
changes rather than dividing on every read — the walk already knows when it crosses
a segment.

**Rules the tests pin.**

1. Every mover's heading points the way its step goes; `a mover` states it once for
   all three, using the `heading:` the host already passes.
2. `CharacterBody#heading_*` equal its intent, including while blocked.
3. `PathFollow` heads along the segment it is on, `0, 0` before a path, after
   `on_finished`, and with `path: nil`.
4. `follow(path)` on a finished follower walks again and emits `on_finished` again;
   on a walking one it abandons the old route at once.
5. `AnimatedSprite` animates a `PathFollow` walker (`walk_right` along a rightward
   segment, `stand` when finished).
6. Reading a heading allocates nothing.
7. Open question 1, whichever way it is decided.

**Tests.** `spec/support/shared_examples/a_mover.rb` (heading group);
`path_follow_spec.rb` (idle, `follow`, heading per segment); `animated_sprite_spec.rb`
(a `PathFollow` sibling); `path_follow_allocation_spec.rb` gains a heading read.

**Docs.** `docs/api/components.md`: `Mover` (heading), `PathFollow` (`follow`,
`path: nil`), `AnimatedSprite` ("reads any mover's heading").

**Verify.** `rake spec` green; driven reports of `examples/walk`,
`collision_tiles`, `jump_topdown`, `split_screen`, `input_glyphs` and `game_menu`
at `--seed 1 --ticks 240` are **byte-identical** before and after.

**Landed.** `Mover#heading_x`/`#heading_y` (0, 0), answered by `CharacterBody` (its
intent), `Velocity` (scaled so the larger axis is ±1) and `PathFollow` (the unit
direction of its segment, cached when the walk crosses into one; 0, 0 idle, finished,
or on a zero-length segment). `PathFollow.new(speed:, path: nil, blocked_by: [])`,
`#follow(path)` — the same restart `on_attach` does, callable from `on_finished`, and
`follow(nil)` stops — and a `path` reader. `AnimatedSprite` pulls `require_sibling(Mover)`.
One commit, as a step with no sub-steps.

- `rake spec`: 1822 examples, 0 failures (1783 at planning; the 39 new ones are this
  step's, 18 of them the heading group run against three movers).
- The `a mover` contract gained a heading group (direction for `[1,0]`, `[0,1]`,
  `[1,1]`; within -1..1; still heading into the wall it is pressed against; zero
  allocation to read), so all three movers are held to rule 1 by the same examples.
- Driven reports of `walk`, `collision_tiles`, `jump_topdown`, `split_screen`,
  `input_glyphs` and `game_menu` at `--seed 1 --ticks 240` are **byte-identical**
  before and after — and so is `test_projects/tiled_world`, the seventh caller the
  measurement table names, which the Verify block left out. The reports do exercise
  facing: `walk`'s sprite rows span 0..2, `tiled_world`'s 0..3.

What the sketch got wrong or left out:

- **The two-mover raise is not `AnimatedSprite`'s.** `get_component` already raised,
  with a message naming neither component. `require_sibling` now looks for every match
  and raises `ArgumentError` naming each one ("AnimatedSprite reads one …Mover on the
  same node, and this node has 2: …CharacterBody, …PathFollow"), for any caller.
- **`Float#fdiv` allocates** when the numerator is `0.0` (one object per call on Ruby
  4.0.5; `/` does not). The first `Velocity#heading_*` used it and the shared allocation
  example caught it — a heading of `[1, 0]` has a zero axis on every read. It divides by
  `larger.to_f` instead.
- **For step 3: `AnimatedSprite` faces sideways on any non-zero x.** "Horizontal wins
  on a diagonal" was right for keyboard intents, which are -1/0/1, but a smoothed
  route's segments run at any angle, so a hero walking a segment 10° off vertical plays
  `walk_right`. Step 3's rule 10 should decide it; the likely answer is "the larger
  axis wins, ties go horizontal", which is identical for every keyboard intent (so the
  seven reports above would not move) and changes only an analog stick held mostly
  vertical — arguably for the better.
- `follow(nil)` and the `path` reader were not in the sketch; step 3's `Navigator`
  wanted `path` readable anyway.

Documented in `docs/api/components.md`: `Mover` (Heading), `PathFollow` (idle, a new
route with a standalone patrol example, heading), `AnimatedSprite` (any mover, the
two-mover raise), `CharacterBody` (heading), and `require_sibling`'s second raise.

### Step 2 — `Engine::NavGrid` (pure), and `TileWorld#nav_grid`

**Why here.** The search is the largest single piece and has no dependency on step 1;
landing it alone keeps its spec suite readable as the contract step 5 inherits.

**Shape.**

```ruby
module RGame::Engine
  # A walkability grid and the searches over it. Built once from a solidity callable
  # — the same `solid.call(col, row)` a TileBlockers takes — and never re-read.
  class NavGrid
    def initialize(width:, height:, solid:)

    attr_reader :width, :height
    def walkable?(col, row)
    def region(col, row)               # Integer label, nil for solid / out of bounds
    def reachable?(from_col, from_row, to_col, to_row)

    # The cells from start to goal inclusive, as [[col, row], ...], or nil when either
    # end is solid, out of bounds, or in another region. 8-connected, diagonal only
    # when both orthogonal neighbours are open, octile cost and heuristic.
    def find(from_col, from_row, to_col, to_row)
  end
end

class Components::TileWorld
  def nav_grid = @nav_grid ||= Engine::NavGrid.new(width: @map.width, height: @map.height,
                                                   solid: ->(col, row) { @map.solid_tile?(col, row) })
end
```

Internally: solidity copied into a flat Array once; regions labelled by flood fill
at construction; search buffers (`g`, parent, closed stamp, heap) allocated once and
reused with a generation counter, which is what the "tuned" measurement above was.

**Rules the tests pin.**

1. A straight corridor returns every cell in order, start and goal included.
2. Start equal to goal returns `[[col, row]]`.
3. Solid start, solid goal, out-of-bounds either end: `nil`.
4. A goal in another region is `nil` **without searching** — assert with a `solid`
   callable spy that `find` reads nothing after construction.
5. Never cuts a corner: a diagonal between two solids sharing a corner is refused.
6. The route's cost is optimal — compare its octile length to a brute-force
   Dijkstra over a few fixture grids, including the town fence shape.
7. Deterministic: the same query twice returns equal routes, and a query after an
   unrelated one returns the same route as before it (the reused buffers leak nothing
   between searches).
8. `TileWorld#nav_grid` is built once and agrees with `TileWorld#solid?` cell for cell.

**Tests.** `spec/rgame/engine/nav_grid_spec.rb`, with fixture grids drawn as string
arrays (`'#..#'`) turned into the `solid` callable; a `TileWorld` example in its
existing `tile_world_spec.rb`, against `spec/support/stub_tile_map.rb`.

**Docs.** `docs/api/toolbox.md`, a `NavGrid` section beside `Path`; `components.md`,
`TileWorld#nav_grid`.

**Verify.** `rake spec` green. Record in the landed note the town corner-to-corner
time measured by a plain script (not a spec — timing specs are flaky), for step 5 to
compare against.

**Landed.** `Engine::NavGrid.new(width:, height:, solid:)` with `walkable?`, `region`,
`reachable?` and `find`, exactly the sketched surface; `TileWorld#nav_grid`, built on first
ask and memoised. Solidity is copied into a flat Array at construction, regions are labelled
by an orthogonal flood fill, and `find` is A* over reused `cost`/`parent`/`seen`/`closed`
buffers stamped with a generation counter, with a binary heap on parallel arrays. One commit.

- `rake spec`: 1856 examples, 0 failures (1822 after step 1; 29 in `nav_grid_spec.rb`, 5 in
  `tile_world_spec.rb`). RuboCop clean over the five files touched.
- Rule 6 runs a brute-force Dijkstra (linear-scan, sharing no code with the search) against
  five fixed queries over three fixtures, and from one corner to *every* open cell of the
  scattered fixture. Its route-cost helper also raises on a non-step or a corner cut, so an
  optimal cost cannot be reached by a route that is not a walk.
- Mutations run by hand, each caught: the generation counter not advancing (3 failures), a
  diagonal allowed past one open orthogonal (3), relaxation ignoring the better cost (3),
  the heap's tie-break ignored (5). One survivor, equivalent: gating a straight move on
  bounds alone, since `relax` checks solidity itself.
- **Timings, for step 5** — `ruby -Ilib` on a plain script, Ruby 4.0.5 without YJIT, grids
  built from `TileMap.load` + `solid_tile?`, one warm-up pass, best of 5 per query:

  | | |
  |---|---|
  | town (60x40), build | 1.6 ms |
  | town, `[1, 1]` → `[58, 38]` (65 cells, 635 expanded) | **2.6 ms** |
  | `beach_large.tmx` (120x90), build | 7.5 ms |
  | `beach_large`, 200 random pairs seeded `Random.new(1)` | mean 1.5 ms, **worst 24.5 ms** (`[116, 72]` → `[39, 6]`, 5319 expanded, ~4.5 µs each) |
  | `island.tmx` (58x47), 200 random pairs | mean 0.12 ms, worst 1.4 ms; 46 unreachable, the slowest of them 2–9 µs |

What the sketch got wrong or left out:

- **The implementation is ~30% slower per cell than the prototype** measured before
  planning: the same worst `beach_large` query expands 5319 cells against the prototype's
  5359, at ~4.5 µs rather than ~3.5 µs, so 24.5 ms rather than 18.7 ms. Folding the per-
  neighbour helpers together and dropping an insertion-order tie-break each changed nothing
  measurable, so it is not call overhead in the obvious places; it was left there, since
  step 5 is the planned answer to speed. The "~2.2 µs per expanded cell" in the measurement
  table came from a comb maze, where most neighbours are solid — it is not comparable with
  an open map's cost, and step 5 should compare against the table above instead.
- **Rule 4 as sketched proves less than it reads.** Because solidity is copied at
  construction, "`find` reads nothing from `solid` after construction" holds for *every*
  query, cross-region or not, so the spy cannot show that no search ran. The example asserts
  what it can (the answer is `nil` and the reads stayed at one per cell); the O(1) claim is
  carried by the island timing above. An assertion on a private method was written and
  removed — step 5 has to inherit the suite unedited, and a private name would not survive
  the port.
- **Ties go to the smaller remaining estimate**, not insertion order. Determinism holds
  either way — the heap is deterministic given its inputs, and the "query after an unrelated
  query" example guards the reused buffers — and preferring the cell further along is the
  usual choice for octile grids. The C port should keep the same ordering, or the
  exact-route examples (the corner and diagonal ones) may pick a different equally cheap
  route.
- **The `TileWorld` example is not against `StubTileMap`**, as the Tests line said: that
  stand-in has no `solid_tile?`, and the existing `#blockers` examples already use an
  `instance_double(TileMap)` for exactly that reason. The new ones follow them.

Documented in `docs/api/toolbox.md` (a `NavGrid` section after `Path`, and a line in
"Grids" saying why it is not a grid class) and `docs/api/components.md` (`TileWorld`'s
queries, and the "Looking for" table).

### Step 3 — `Components::Navigator`

**Why here.** It needs a heading-aware `PathFollow` that can be re-routed (step 1)
and a search (step 2). It is where the invariant above starts to hold.

**Shape.**

```ruby
class Components::Navigator < PathFollow
  def initialize(speed:, blocked_by: [])      # no path:

  # Plan from where the node stands to the cell containing (world_x, world_y) and
  # start walking it. true if a route exists, false if not — in which case whatever
  # the node was doing carries on.
  def go_to(world_x, world_y)

  attr_reader :cells   # the unsmoothed route of the last successful go_to, for drawing
  # `path` (the smoothed Engine::Path being walked) is readable too
end
```

What `go_to` does, in order:

1. Find the scene's `TileWorld` (raise at `on_attach` if absent, in `Mover`'s
   voice); take `nav_grid`, `blockers`, tile size.
2. The **anchor** is the centre of the sibling `BoxCollider`'s box when there is
   one, else the node's origin. Its world position picks the start cell; the target
   point picks the goal cell.
3. `nav_grid.find` → cells, or return `false`.
4. **Smooth by string-pulling**: from the current anchor, extend to the furthest
   later cell centre whose segment the box can travel — tested by sweeping the box
   along it in steps no larger than a quarter tile through `blockers.resolve_x` /
   `resolve_y`, X before Y exactly as `CollisionSystem` orders them; any landing
   short of the intended one rejects the segment.
5. Convert each kept anchor point to a node-origin waypoint (subtract the anchor's
   offset within the node), prepend the node's current position, and `follow` the
   resulting `Path`.

**Rules the tests pin.**

1. The invariant: over the fixture grids, many random `go_to`s, each walked to
   `on_finished` in a headless scene with `blocked_by: [:tiles]`, never emit
   `on_blocked`.
2. The first waypoint is where the node stands — `follow`'s placement moves nothing.
3. On open ground a route is two waypoints; around the town fence it passes through
   the gap and has far fewer waypoints than cells.
4. A smoothed segment that would clip a tree corner with a 12x6 box but not with a
   point is rejected (a fixture built for exactly that).
5. `go_to` a solid tile returns `false` and leaves the current walk untouched.
6. `go_to` while walking re-routes from where the node is, with no jump.
7. `go_to` the node's own cell walks to the cell centre; already at the centre it
   finishes on the next step — `on_finished` never fires inside `go_to`.
8. The node reaches the target cell with the anchor at its centre.
9. `it_behaves_like 'a mover'` — held by an actor collider on its route it waits and
   resumes, since it is a `PathFollow`.
10. Beside an `AnimatedSprite` it animates in the direction of travel.

**Tests.** `spec/rgame/engine/components/navigator_spec.rb`; the "caller using
both" example — `Navigator` with `blocked_by: %i[tiles npc]` and a `CollisionWorld`
— lives there too, since CLAUDE.md asks that combination be exercised rather than
assumed.

**Docs.** `docs/api/components.md`, a `Navigator` section after `PathFollow`, stating
that it waits rather than replans.

**Verify.** `rake spec` green, including rule 1 over at least the town fence
fixture and one scattered-obstacle fixture.

**Landed.** `Components::Navigator < PathFollow` with `Navigator.new(speed:, blocked_by: [])`,
`go_to(world_x, world_y)` → `true`/`false`, and `cells`; `path` is `PathFollow`'s. `on_attach`
raises without a `TileWorld` and looks up the `BoxCollider` whose box centre is the anchor.
`TileWorld` gained `tile_width`/`tile_height`, and `AnimatedSprite` now faces by the larger axis
of the heading (step 1's note for rule 10). One commit, as a step with no sub-steps.

- `rake spec`: 1879 examples, 0 failures (1856 after step 2; 20 in `navigator_spec.rb`, 2 in
  `animated_sprite_spec.rb`, 1 in `tile_world_spec.rb`). RuboCop clean over the seven files
  touched.
- Rule 1 runs 30 chained random `go_to`s per fixture, half of them abandoned partway for another
  so a route also starts off a cell's centre, over the fence and a scattered fixture, and asserts
  no `on_blocked` and the anchor on the target's centre at every arrival.
- **The invariant on real maps**, by a plain script (hero-sized node, 12x6 feet, `blocked_by:
  [:tiles]`, walked to `on_finished` at 1/60 s): `town.tmx` 300 routes at 80 px/s and 200 at
  230 px/s, `island.tmx` 264 routes, `beach_large.tmx` 60 routes — **0 blocked**, all finished.
- The seven driven reports step 1 compared (`walk`, `collision_tiles`, `jump_topdown`,
  `split_screen`, `input_glyphs`, `game_menu`, `test_projects/tiled_world`, `--seed 1 --ticks 240`)
  are **byte-identical** with and without the facing change.
- **Timings, for step 5** (step 2's method: best of 5 after a warm-up):

  | | `find` | `go_to` (find + smoothing) |
  |---|---|---|
  | town `[1, 1]` → `[58, 38]` (65 cells → 8 waypoints) | 2.5 ms | **10.0 ms** |
  | `beach_large` `[116, 72]` → `[39, 6]` (117 cells → 13 waypoints) | 23.7 ms | **45.0 ms** |

- Mutations run by hand: the sweep as sketched (below) fails both rule 1 examples; a box-blind
  `clear?` fails 6; sweeping a point instead of the box fails 8; no smoothing fails 5; windows
  without overlap fail 1 — and that 1 exists only because the scattered fixture was *searched
  for* as a map that catches it, since the hand-drawn one did not.

What the sketch got wrong or left out:

- **The sweep as sketched is not sound.** Quarter-tile steps resolved X-then-Y blocked 18 of 100
  random routes on `town.tmx`. A quarter-tile staircase can jump diagonally past a tile corner that
  the continuous segment clips and that the walker, stepping a pixel or so at a time, meets. What
  landed sweeps **overlapping half-tile windows at a quarter-tile stride, each resolved both
  X-then-Y and Y-then-X**: both orders cover every position between a window's ends, and the
  overlap covers a walker step straddling two windows, so long as that step is under a quarter
  tile (240 px/s at 60 Hz on 16 px tiles). Without the overlap the real maps showed 19 blocks over
  the runs above; with it, none. It is still the map's own `TileBlockers` answering.
- **"The furthest later cell" became greedy**: extend cell by cell until the next is not clear.
  Scanning back from the route's end for the furthest clear cell costs a sweep per candidate per
  corner. The next cell is taken without a test, since from a cell centre (or from the node to the
  centre of its own cell) the box stays in cells it already occupies or the search's corner-free
  step — which holds only for a **box no larger than a tile**, a limit nothing checks yet.
- **Smoothing costs more than the search**: 7.5 of town's 10 ms, 21 of `beach_large`'s 45 ms,
  because every extension re-sweeps from the corner. Step 5 leaned "smoothing stays Ruby"; that
  lean was taken before this was measured, and its re-plan should weigh it — either the sweep
  moves with the search, or smoothing gets cheaper (e.g. a search for the turn rather than a
  linear extension).
- **Rule 9 is not `it_behaves_like 'a mover'`.** The contract's heading group asserts the exact
  sign of each heading axis from a node at (170, 100), but a navigator walks its anchor to a cell
  centre, and no tile size puts both the bare origin and a 16x16 box's centre on centres on both
  axes. The rule is carried by the "held by another actor" example instead — `blocked_by: %i[tiles
  npc]` with a real `CollisionWorld`, which is also the caller-using-both example — and
  `Navigator` overrides none of `Mover`'s or `PathFollow`'s step machinery that the contract
  already holds `PathFollow` to.
- **Rule 10 decided "the larger axis wins, ties go horizontal"**, as step 1's note leaned, and it
  is pinned twice: in `animated_sprite_spec.rb` against a `CharacterBody` intent, and beside a
  `Navigator` on a mostly-downward route.
- Not in the sketch: `go_to` before the node is in the tree raises rather than failing on `nil`;
  `TileWorld#tile_width`/`#tile_height`, which the sketch's "take tile size" assumed existed.
- **For step 4:** `path` waypoints are the node's origin, not the anchor, so drawing the walked
  route at the feet adds the collider's centre offset back.

Documented in `docs/api/components.md` (a `Navigator` section, in the alphabetical order the page
keeps rather than after `PathFollow`; `AnimatedSprite`'s facing rule; `TileWorld`'s tile size; the
"Looking for" table) and `docs/api/toolbox.md` (`NavGrid`'s routes point to `Navigator`).

### Step 4 — `examples/pathfinding` and its drive script

**Why here.** Everything it names exists. This is also where open questions 2 and 3
get answered, by trying them.

**Shape.** The `examples/collision_tiles` scene with the hero's `CharacterBody` and
`PlayerController` replaced by a `Navigator` (`blocked_by: [:tiles]`), plus:

- a **`Cursor`** node in the world, stepped a tile at a time by `ui_left` /
  `ui_right` / `ui_up` / `ui_down`, confirming with `ui_confirm` — which is
  `hero.navigator.go_to(cursor centre)`. It draws a tile outline: one colour for a
  reachable tile, another for a solid one (`nav_grid.walkable?`, read once per cursor
  move, not per frame).
- the **raw route** as a small dot per cell and the **walked route** as lines
  between waypoints, both from `Navigator#cells` / `#path`, drawn in the
  `WorldView`. These two drawings side by side are the point of the example.
- a `CachedLabel`: `"route: 84 cells, 6 waypoints"`, or `"no route"`.
- the header's "what this does not solve": the hero waits behind anything the map
  does not know about and does not replan; the map never changes, so the grid is
  built once; one hero, no crowd.

**Drive script** `tools/drive/examples/pathfinding.rb`: step the cursor from the
hero's start to a tile south-west of the fence (well away from the gap), confirm,
idle long enough to arrive; then put the cursor on a tree and confirm. The header
states what the report must show, read off a real run: the camera's southern clamp
reached (only possible through the gap), the label's first and last texts, the line
count of the walked route well below the cell count, and the "no route" text after
the tree.

**Verify.** `ruby tools/drive_test_project.rb examples/pathfinding/main.rb --ticks N`
shows the above; RuboCop over the new files; `rake spec`; update
`docs/plans/basic-examples.md` — entry 12 marked done with a landed note that
records how this plan's design replaced its sketch (`AStar.find → Path`), and
Implementation order item 22 struck.

**Landed.** `examples/pathfinding/main.rb` and `tools/drive/examples/pathfinding.rb`, no
engine change. `Hero` (AnimatedSprite, FeetCollider, `Navigator` with `blocked_by: [:tiles]`),
`Cursor` (a tile outline moved by an `ActionTrigger` over the four `ui_*` directions, coloured by
`nav_grid.walkable?` on each move, emitting `on_confirmed` with the tile's centre), `Route` (a dot
per `cells` entry, a line per `path` segment), and a `Scene` wiring the confirm to `go_to` and
`on_finished` to a `CachedLabel`. One commit, as a step with no sub-steps.

- `rake spec`: 1879 examples, 0 failures (unchanged; no engine code). RuboCop clean over both new
  files.
- The driven run, `--ticks 630`, byte-identical across two runs: the cursor walks from (24, 18) to
  (4, 33) and confirms at tick 169; the hero arrives at tick 472 (`on_finished`); the cursor steps
  onto the tree at (7, 31) and the confirm is refused. The last `text` is `"no route there;
  arriv..."` (in full: `no route there; arrived: 6 waypoints, 26 cells`). The dots run from
  `(390, 294)` — the start tile — to `(70, 534)`, the target. 11986 `rect` and 4825 `line` calls
  are 26 dots and 5 lines over the 461 frames the route was up, plus the cursor's 4 lines a frame.
  The `sprite` spans rows 0..2 and ends on the frame it began. The camera reaches (0.0, 160.0),
  the southern clamp.
- Frames captured off the harness's Xvfb mid-walk show the dots down through the fence gap and
  the lines pulled tight over them. Nobody has played it by hand.

What the sketch got wrong or left out:

- **"The camera's southern clamp reached (only possible through the gap)" is not evidence here.**
  That assertion is `collision_tiles`', where the camera follows the hero. Once open question 2 put
  the camera on the cursor, the clamp only says the cursor went south. The acceptance evidence is
  the label reaching `arrived`, which `on_finished` sets, and which a walker held by a tile would
  never reach.
- **The label's sketched text, `"route: 84 cells, 6 waypoints"`, is unreadable in a report**: the
  harness truncates strings to 21 characters and shows only the first and last `text` of the run,
  so "arrived" would never show. The label leads with the newest fact instead — `walking:` /
  `arrived:`, and `no route there;` before either — and the drive script ends on the refusal so
  one line carries both. Extending the harness to list distinct texts was the alternative, and was
  not needed.
- **The cell and waypoint counts are read off call counts**, not the label: the route's `rect` and
  `line` totals divided by the frames it was up. "The line count well below the cell count" is
  5 against 26 on this route — not the 84 the sketch guessed, because the target is closer to the
  gap than a corner-to-corner trip.
- **`ui_*` directions are the arrows and d-pad only**, so the cursor is not on WASD or a stick. The
  example says so rather than adding bindings.
- **For step 5:** nothing in the example stresses the search. One `go_to` per confirm, on a 60x40
  map, is the whole load, so the re-plan's cost numbers still have to come from step 2's and 3's
  scripts rather than from this caller. What the caller *did* settle is the surface it uses:
  `go_to`, `cells`, `path`, `nav_grid.walkable?` — nothing else of `NavGrid` is touched.

Documented in `docs/api/components.md` (an "Example" line under `Navigator`), and
`docs/plans/basic-examples.md` (entry 12 done with a landed note, Implementation order item 22
struck).

### Step 5 — the search in C *(rough)*

To be re-planned once step 4 has landed and the Ruby API has a real caller. What is
known now:

- `ext/rgame_util/nav_grid.{c,h}`: pure, no `ruby.h` — grid of bytes, region labels,
  A* into caller-owned buffers — covered by `test/test_nav_grid.c` in the Check suite
  (a new suite in `test/suites.h`).
- `ext/rgame_util/nav_grid_ext.c`: `RGame::Util::NavGrid` (a value in the sense
  CLAUDE.md means — no OS handle), registered from `util_ext.c`.
- `Engine::NavGrid` keeps its interface and delegates `find`/`region` to it, so the
  step 2 spec suite is the contract with no edits. If it needs edits, the port
  changed behaviour.
- Windows: see the `windows-portability` skill before writing the binding
  (`NUM2INT` widths, no `long` for sizes).
- The number to beat: `beach_large.tmx`'s 18.7 ms worst case, into the low tens of
  microseconds — re-measure on the step 2 landed note's methodology, not on the
  prototype's.
- Open: whether the result comes back as a flat Integer array (one allocation) or as
  the pairs `find` returns today, and whether smoothing moves too. Leaning: flat
  array inside, pairs at the Ruby surface; smoothing stays Ruby, because it is
  O(route) and calls a Ruby blocker source.
  *Step 3's landed note measured smoothing at three times the search on town and about
  equal on `beach_large`, so this lean needs re-deciding in the re-plan.*

### Step 6 — fold back and delete this plan

- `docs/api/toolbox.md` (`NavGrid`, including "unreachable is `nil`, and answered
  without a search across regions", and the measured cost) and
  `docs/api/components.md` (`Mover` heading, `PathFollow#follow`, `Navigator`) hold
  everything still true — most of it written by steps 1–5 already; this step checks
  and trims.
- The rejected alternatives worth keeping — box-blind line-of-sight, the separate
  search component — become one sentence each in the `Navigator` section, as the
  reason the design is what it is, without history.
- `docs/api/internals.md` if the C `NavGrid` needs naming there.
- Delete `docs/plans/pathfinding.md`.

## What this does not deliver

- Replanning around moving actors, crowds, avoidance, or flow fields.
- Maps that change at runtime — the grid is built once; a destructible wall would
  need a `NavGrid` invalidation this plan does not design.
- Weighted terrain (a road cheaper than grass), and non-tile navigation.
- Mouse picking of a target. The example is "click-free" by requirement, and the
  engine's pointer input is not part of it.
