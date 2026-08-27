# Moving the transform out of the node and into the renderer

**Status: landed 2026-08-27, with one open question left (step 3).** Written out
of a discussion that began with a bug in `Game/UseAbsoluteCoords` and turned into
a question about the design the cop was guarding.

Steps 1, 2, 4 and 5 are done and the suites are green. What is still open is
whether `update` keeps resolving eagerly or moves to a cached transform — the
measurements for that decision are below, and nothing else depends on it.

Per CLAUDE.md this is a working document: what is still true has been folded into
`docs/api/scene_graph.md` (a rewritten "The two spaces" and a new "Drawing happens
in local space"), `docs/api/components.md`, `docs/api/README.md` and CLAUDE.md's
RuboCop table. **Delete this file once step 3 is decided.**

Two things in the plan below turned out to be wrong when implemented, and are
corrected in place rather than quietly edited away — see "Where the plan was
wrong".

The question: **a `Node2D` has a parent-relative `x`/`y`/`angle` and a resolved
`abs_x`/`abs_y`/`abs_angle`, and using the wrong one is silent. Can the design
stop the mistake instead of a cop reporting it?**

## Verdict

**Yes, for drawing — which is where the mistake actually happens — by giving
the node no absolute coordinate to draw with.** The renderer already owns a
transform stack; the scene graph is not using it.

Where the `abs_*` references actually live, counted across `lib/` and
`examples/`:

| Where | Refs |
|---|---|
| `on_draw` / `draw` / the `label_x`,`label_y` draw helpers | **40** |
| `resolve_origin` + `initialize` + the `attr_reader` (plumbing) | 16 |
| `update` path | **6** |
| `culled?` | 1 |

And the six on the update path are all one shape — a *component* asking another
object for its world position, spelled explicitly as `node.abs_x`:
`camera_follow.rb:39`, `targeting.rb:48`, `circle_collider.rb:32-33`. Written
once, engine-internal, reviewed. That is not the failure mode. The failure mode
is a subclass author writing `on_draw` and reaching for the nearest coordinate,
which is 100% of what the cop caught when it was fixed (three sites in
`examples/17_snake`).

So: **remove the choice from the draw path, and the remainder is small enough
to name honestly.**

## What was considered and rejected

A mode-switching accessor: one flag `in_traversal` on the node, and `x` returns
`@rel_x` normally, `@abs_x` while the node's own lifecycle methods are running.
Attractive because the wrong value becomes unreachable rather than merely
discouraged.

Rejected because the *setter* has to follow the reader into the mode, and it
turns out to need four rules at once:

1. The destination never flips — `@rel_x` is the only storage of truth, and a
   write that lands only in `@abs_x` is erased by the next `resolve_origin`.
   What flips is the interpretation: during traversal the caller is handing over
   a world coordinate, so it must be converted back through the parent's
   transform.
2. It must also write `@abs_x`, or read-after-write inside one hook returns the
   stale value.
3. Under a rotated parent the inverse transform **couples the axes**, so a
   setter cannot update its own component alone: `self.x = a` followed by
   `self.y = b` leaves `@rel_x` derived from a `y` that no longer holds. Each
   write has to re-derive the whole relative pair.
4. Rule 3 is invisible in testing. `resolve_origin` has a `pa.zero?` fast path,
   so with an unrotated parent the coupling terms vanish and separate writes
   look correct. It only appears under a rotated ancestor — exactly the case the
   design exists to make safe.

That is a permanent tax on every coordinate access in the API to prevent one
class of authoring mistake, and no engine surveyed does it (see Prior art). The
draw-path fix below removes ~90% of the same exposure and costs nothing.

## Prior art

Every scene-graph engine has this split. None mode-switches a name.

| | Local | World | Drawing |
|---|---|---|---|
| **Godot** | `position` | `global_position` (settable; the setter converts back) | `_draw()` runs in local space |
| **Unity** | `localPosition` | `position` — the *short* name is world | renderers consume `localToWorldMatrix` |
| **Bevy** | `Transform` | `GlobalTransform`, a separate component, derived and effectively read-only | render pipeline reads the global one |

Three rules fall out, and all three follow all three: the render path is never
given a choice; logic gets two clearly distinct names; and the default name is
the one you usually want.

## The plan

### 1. `draw` draws in local space

`Node2D#draw` pushes the node's **relative** transform onto the renderer and
`draw_content`/`draw_children` run inside it. `on_draw` then uses `x`, `y`,
`width`, `height` freely — or, more often, literal offsets from its own origin.

This is not a new mechanism in this engine. `WorldView#draw`
(`lib/rgame/engine/world_view.rb:61-63`) already wraps the entire subtree in one
`renderer.translated` for the camera; this is the same thing one level further
down. Three things make it safe:

- `renderer.translated` already exists, and already short-circuits when both
  deltas are zero (`renderer.rb:240`), so organizational nodes at the origin pay
  nothing.
- Clips compose correctly. `ext/rgame_core/graphics/canvas.h` maps a pushed clip
  rect through the current transform before handing it to the screen-space clip
  stack, so a node clipping in its own local space does the right thing without
  knowing transforms exist.
- Recordings survive: a baked layer's offset is applied *before* the current
  transform, and recordings carry no clip of their own.

**`draw` keeps resolving the full transform.** The plan said it could drop to the
inherited half; that was wrong, and the correction is the one thing that cost
performance. Culling happens on the draw path and is world-space by nature — a
view is a camera rectangle in the world, so a node's local box says nothing about
whether it is on screen. Reusing what `update` resolved is stale in one real
case: a paused node under an ancestor that is still moving, which draws but does
not update, and which `spec/rgame/engine/node2d_paused_spec.rb` already covered.

Sites: 40 draw-path references lose their coordinates entirely, mostly becoming
`0`; `on_draw` bodies get shorter.

### 2. `control` drops the transform entirely

`on_control(actions)` receives no coordinates, and there is no pointer in this
engine by design (`lib/rgame/core/input.rb:33`). Nothing on the control path
reads a position. `Node2D#control` keeps the reduced resolve for
`abs_input_owner` and stops resolving the transform.

### 3. `update` — pick a resolution strategy

`update` genuinely needs world coordinates, and the hot consumer is collision:
`CircleCollider` exposes `cx`/`cy` as `node.abs_x`/`abs_y`, and `CollisionWorld`
calls them on insert, on every spatial-hash query and again per candidate pair
(`collision_world.rb:80`, `:98`). Read volume is several per collider per tick,
not one.

Measured by `tools/bench_resolve_origin.rb` (525-node tree, depth 4, 2000 ticks
per configuration):

| Workload | Eager ×3 (today) | Eager ×1 | Lazy uncached | Cached + dirty |
|---|---|---|---|---|
| collision-ish (20% move, 1200 reads) | 389 µs | 194 µs | 354 µs | **183 µs** |
| typical (10% move, 200 reads) | 352 µs | 131 µs | 64 µs | **52 µs** |
| draw-only (10% move, 0 reads) | 317 µs | 104 µs | **3 µs** | 5 µs |
| query-heavy (2% move, 4000 reads) | 660 µs | 482 µs | 1231 µs | **439 µs** |
| deep chain (depth 20, 1200 reads) | 102 µs | **91 µs** | 731 µs | 131 µs |

**The headline is the pass count, not the strategy.** `resolve_origin` runs
three times per tick today — once each in `control`, `update` and `draw`. Steps
1 and 2 delete two of them, which is −50% to −67% on its own, with no change of
strategy and no new machinery. Do that first and re-measure before deciding
anything else.

Against that new baseline (Eager ×1):

- **Lazy uncached is the one option the data rules out.** +83% on the
  collision workload, +156% query-heavy, and **+700% on a depth-20 chain**,
  because an uncached read costs O(depth) and collision reads the same node
  several times a tick. It only wins where nobody asks for a world position at
  all.
- **Cached + dirty** (the Godot/Unity approach) is better or equal in four of
  five workloads and worse only on the deep chain (+44%, on a 21-node tree at an
  unrealistic 57 reads per node per tick).

**Done: steps 1 and 2 landed, the eager pass stayed, and the staleness below was
fixed directly. Whether to adopt caching is still open, deferred until a profile
of a real game asks for it.**

Because `draw` kept its resolve (see step 1), the pass count went from three per
tick to **two**, not one — `control` is the one that went away. The public accessor is
identical under all three strategies, so this can be changed later without
touching a single caller.

**The staleness was fixed without changing strategy.** `x=`, `y=` and `angle=`
re-resolve the node's own transform on the write, so a node that moves itself is
immediately where it says it is, and its children — resolved after it in every
phase — pick the new value up in the same tick instead of a tick later. Three
examples in `node2d_spec.rb` under "moving a node during a phase" cover it; before
the fix the subtree read `[5, 15, 25]` where it should have read `[15, 25, 35]`.

The cost is one resolve per coordinate *write* rather than one per node per
phase, which is cheaper in every scene where most nodes are not moving.

### 4. Rename the storage

`@x` → `@rel_x` and `abs_x` → `world_x`; see "Naming" below. Independent of
steps 1-3 and lands after them.

### 5. Replace the cop

The plan expected the cop to shrink to `update` or disappear. Neither happened,
because step 1 created a **new** hazard that is the exact mirror of the old one:
with the transform pushed, a node that draws at its own position applies it
twice. It is as silent as the mistake it replaces, and it now has two spellings
rather than one — `world_x` doubles the whole ancestry, the camera included, and
`x` doubles the node's own offset.

So `Game/UseAbsoluteCoords` was replaced by **`Game/DrawInLocalSpace`**: in
`draw`/`on_draw`/`draw_content`/`draw_children`, a node may not read its own
transform in either space. A component asking *its node* by name
(`node.world_x`, for a cull box) has a receiver and is not flagged, which is
what keeps culling legal on the same path.

`update` is deliberately left unpoliced, and that is the half of the old cop that
genuinely went away: there both spellings are legitimate and no cop can tell them
apart. A node moving itself in its parent's frame wants `x`; one measuring a
distance wants `world_x`. Guessing would make the commonest movement idiom in the
engine an offence.

## Naming (decided)

Storage becomes `@rel_x` / `@rel_y` / `@rel_angle`, and the accessor keeps the
short name:

```ruby
attr_accessor :rel_x, :rel_y, :rel_angle
alias x rel_x
alias x= rel_x=
```

The definition site names the ivar it makes, and one visible `alias` line says
"same thing, shorter name". Aliasing also preserves the VM's special-cased
`attr_reader` — measurably faster than an explicit `def x = @rel_x` (0.292 s vs
0.318 s over 10M reads), which matters only at collision read volumes but costs
nothing to have.

It degrades gracefully if caching is adopted later: the writer must then
invalidate, so `attr_accessor` becomes `attr_reader` plus an explicit `rel_x=`
that does the dirty walk. The reader alias is untouched either way.

The old spelling `@x` stops existing, which is what lets step 5 shrink the cop.
It fails loudly enough in practice — a subclass reading `@x` gets `nil`, and the
next arithmetic raises `NoMethodError`.

**The resolved transform becomes `world_x` / `world_y` / `world_angle`**, from
`abs_x` / `abs_y` / `abs_angle`. `world_` says which space the value is in;
`abs_` said only "not the other one". It is ~6 call sites after step 1.

**`abs_band` and `abs_input_owner` keep their names**, and the difference is
worth stating rather than smoothing over. `world_*` means *expressed in world
space rather than parent space* — a transform. `abs_*` on those two means
*resolved by inheritance down the tree* — a band or an owner a node did not
declare and takes from its nearest ancestor that did. Two different mechanisms
that happened to share a prefix; a band is not in world space and `world_band`
would say nothing true.

## Where the plan was wrong

Two corrections, both found by the suite rather than by reading:

1. **`draw` cannot drop to the inherited-only resolve.** Culling is world-space
   and lives on the draw path. The plan's "Eager x1" saving is therefore "Eager
   x2", and what shipped costs ~120 ns per node-draw more than the old design
   rather than breaking even (measured below). Variant C in
   `tools/bench_node_draw.rb` is what it *would* cost if culling ever stopped
   needing a world coordinate at draw time: about 26 ns per node-draw cheaper
   than the old design.
2. **The cop was replaced, not shrunk** — see step 5. The plan reasoned that
   removing the old mistake left nothing to guard, and missed that the new
   arrangement has a mistake of its own.

One thing the plan under-sold: `on_draw` bodies do not merely lose a prefix, they
mostly lose their coordinates altogether. `renderer.rect(world_x, world_y, w, h)`
becomes `renderer.rect(0, 0, w, h)`. That weakens the argument that the short
name `x` matters for draw call sites — it is barely used there now — but the
alias costs nothing and `x` still reads well in `update`.

## Cost, as built

| Step | What it took |
|---|---|
| 1 | `Node2D#draw` + `#in_local_space`; `Sprite`, `AnimatedSprite`, `MenuItem` draw at their own origin; 4 examples |
| 2 | `Node2D#control` calls `resolve_inherited`; 3 specs that had used `control` to resolve coordinates moved to `update` |
| 3 | `resolve_origin` split into `resolve_inherited` + `resolve_transform`; coordinate writers re-resolve |
| 4 | `@x`->`@rel_x`, `abs_x`->`world_x` across `lib/`, `spec/`, `examples/`, `docs/` |
| 5 | `Game/DrawInLocalSpace` replaces `Game/UseAbsoluteCoords`, with its own spec |

A spec was written **before** step 1 and left unchanged throughout: a child under
a rotated, offset parent, in `node2d_spec.rb`. Every other tree in that file sits
at the origin unrotated, which `resolve_origin`'s `pa.zero?` fast path makes
blind to axis coupling, a transposed rotation and a dropped translation. Three
deliberate mutations of `resolve_origin` were each caught by it.

## Verification, as run

- `rake` — all three tiers: Check 325 checks / 0 failures, `rake spec` 973
  examples / 0 failures, `rake spec:core` 352 examples / 0 failures.
- `bundle exec rubocop .` — 249 files, no offenses.
- The examples, driven and **compared against a clean worktree at the previous
  commit**. `15_tiled_world` matched exactly: same 1647 sprite and 717 tilemap
  draws, same bands (3346 world / 478 hud / 239 overlay), same clips — with the
  positions moved out of the draw calls and into translates, which is the change.
  Split-screen still produces its two half-height clips. `14_asteroids` differed
  run to run on both sides, because it seeded itself from the system; collisions
  still fired on the new code (`boom`, `hurt`). It now takes `--seed N`, so a
  future before/after can compare it exactly too.
- Allocation: the draw path allocates **0 objects per call** through a
  non-recording renderer, at the origin, offset, and offset+rotated. The ~0.94
  objects/call on an update that moves a node by a float is Float boxing and
  predates this work — the baseline worktree measures the same.

## Measurements

`tools/bench_node_draw.rb`, real window under Xvfb, 525-node tree drawn twice per
frame (split-screen), 750 timed frames, order shuffled per frame. The timing
window closes before GL submission and every variant enqueues identical rects, so
the delta is transform bookkeeping:

| Variant | ns per node-draw | vs. the old design |
|---|---|---|
| the old design: resolve, draw at `world_x`/`world_y` | 1140 | — |
| **what shipped**: resolve, push the transform, draw at (0, 0) | 1260 | **+120 ns** (+0.76% of a 16.6 ms frame) |
| what it would be if draw stopped resolving | 1114 | −26 ns |
| what shipped, nodes at (0, 0) so the push is skipped | 1174 | +34 ns |

So local-space drawing costs about three quarters of one percent of a frame at a
thousand node-draws, and all of that is the resolve that culling still needs. It
is not free, and it is not close to mattering: even so it would take ~8,500
node-draws per frame to reach 1 ms.

Both benchmarks are Ruby 4.0.5 **without YJIT** (this Ruby has none, see
CLAUDE.md), and the extra cost is Ruby-side block and method dispatch — what YJIT
is best at, so a YJIT build would narrow it.
