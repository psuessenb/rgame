# Sweeping the systems and components for architectural fit

**Status: nothing implemented. Step 1 is written out, step 2 is sketched pending a
measurement, and steps 3 and 4 are deliberately rough. Three of the uncalled
classes were decided in conversation after the first draft — see open question
1.**

Written out of a retrospective rather than a bug: the collision unification took
six steps to merge two systems that had each been correct on their own since the
day they were written, and the question is whether anything else in the engine
layer is sitting in the same position right now.

The requirements, in the words they arrived in:

> the whole Tiled map loading and collision originated in a very early build of
> this system (not in this Git repository) before the Node/Component system was
> properly built. This can hopefully be avoided by sweeping the systems/components
> once and look if everything we have now is a good fit for the Node/Component
> architecture.

And, added once the first draft existed:

> Prune the codebase and documentation from references to games - like in this
> case the tower defense game, but also Snake or tiled_world. Ignore plans, any
> reference is fair game in a plan document. Referencing examples is fine, too.
> Schedule this with the dead code removal.

## Verdict

**The hypothesis is half right, and the half that is wrong is the more useful
result.** The Tiled map stack is *not* a misfit — `TileMap`, `Tileset`,
`TileMapLayer` and `TileWorld` have each been reworked since the Node/Component
system landed, they name the layering rules in their own headers, and the sweep
found nothing in them to change. Collision was the misfit, and it has been fixed.

What the sweep did find is a **third thing, in the same shape as collision and one
step further along**: four components move a node, they answer the same question
about different things, and the blocking machinery the collision plan built is
wired to exactly one of them. `Velocity`, `PathFollow` and `ThrustController`
cannot be stopped by a wall, cannot declare `blocked_by:`, and cannot report
`on_blocked` — not because anyone decided they should not, but because
`CharacterBody` was the mover in the room when the resolver was built. Four files
in this repository already carry a non-blockable mover *and* a collider, and each
hand-rolls its own response.

This is exactly what CLAUDE.md's ["Before building: find the thing it
resembles"](../../CLAUDE.md) was written for, and it is worth noticing that the
guideline caught something on its first application to an area nobody suspected.

**And two smaller findings, which step 1 lands together.** The engine layer has a
speculative tail: seven classes have no caller anywhere outside their own specs.
One of them, `Engine::Body`, is the pre-Node/Component kinematics class the
user's hypothesis predicted — ported into three components and then left in the
tree, still required, still shipped. The other six are documented public API
that no game has exercised, and they do not share one answer. And the engine's
code and documentation describe themselves in terms of specific games — 67 lines
in 23 files name one outright, and two components describe their own purpose as a
tower-defense game's. That makes the engine's documentation depend on games it
does not ship.

## Hard constraints

1. **`RGame::Engine` may not name `RGame::Core`.** Everything here is engine
   layer. `Game/NoCoreInEngineLayer` enforces it.
2. **Nothing on the per-frame path may allocate.** Every mover runs per node per
   frame. `allocate_nothing` is the matcher that decides it.
3. **A missing system fails loudly.** `CharacterBody(blocked_by:)` raises at
   attach rather than falling back to free movement, and anything that
   generalizes blocking inherits that rule rather than softening it.
4. **Removing public API is a decision, not a tidy-up.** Six of the seven
   uncalled classes are documented in `docs/api/`. "Nobody calls it" is evidence,
   not a verdict — each removal here was taken in conversation, and open question
   1 holds the ones that were not.
5. **A sweep may not become a rewrite.** The engine layer works and its specs are
   green. Anything this plan proposes must be justified by a finding below, with
   a number attached.

## Decisions already taken

Not up for re-litigation inside the plan.

- **The tile map stack is in scope and came out clean.** It was the thing the
  sweep was called for; the answer is that it does not need changing. Recorded as
  finding A6 so it is a result rather than an omission.
- **`Engine::Body` goes.** Nothing references it, no documentation mentions it,
  and its three behaviours each live in a component that names it in a comment.
  See A1.
- **`Engine::Matrix` goes.** Decided in conversation. It is a flat 2D grid that
  nothing uses; the one grid the engine needs went to `Util::Tensor`.
- **`Engine::Path` and `Components::PathFollow` stay, for the pathfinding
  example.** Decided in conversation: they are the output half of
  `examples/pathfinding`, the last unbuilt entry in the basic-examples plan, which
  already designs `AStar.find` to return a `Path`. If that example ends up not
  using them, they get a simpler example of their own rather than deletion. A2
  records the one thing about that pairing that step 2 has to answer first.
- **The codebase stops naming games.** Decided in conversation, and scheduled
  into step 1 beside the dead code. A7 sizes it and step 1b states what counts.
- **Generalizing the mover is the real work**, and it is step 2 rather than step
  1, because pruning first makes the inventory it has to reason over smaller and
  is independently worth landing.

## What was measured before planning

At `dc006ac`, over `lib/`, `examples/`, `test_projects/` and `spec/`.

| | |
|---|---|
| Components under `lib/rgame/engine/components/` | 22 |
| Non-component classes under `lib/rgame/engine/` | 35 |
| Components that move a node's position | **4** |
| Of those, components that can be blocked | **1** |
| Game files carrying a non-blockable mover *and* a collider | **4** |
| Engine classes with no non-comment caller in `lib/`, `examples/` or `test_projects/` | **7** |
| Of those, documented in `docs/api/` | 6 |
| Lines naming a game, outside plans and the games themselves | **67**, in 23 files |
| Components requiring a hand-written wiring hook | 0 |

The third and fourth rows are the finding. The last row is the one worth reading
twice: the trap that motivated the collision unification — a hook whose only job
is handing one component's data to another — **does not occur anywhere in the
repository today.** That failure mode is closed, and this plan is not about it.

## A. Findings

### A1. `Engine::Body` is dead, and it is the class the hypothesis predicted — *(measured)*

`lib/rgame/engine/body.rb` holds `x`, `y`, `vx`, `vy`, `angle`, `spin`, plus
`integrate`, `wrap!` and `offscreen?`. That is a node's transform and three
components' behaviour, in one object that predates both.

It is referenced by exactly one file in the repository, which is
`spec/rgame/engine/body_spec.rb`. No example, no test project, no other engine
class, and no page under `docs/api/` mentions it. It is still required by
`lib/rgame/engine.rb`, so it is loaded into every process that requires the
engine, and `spec.files` is a glob, so it ships in the gem.

The port is visible in the code that replaced it. Three component headers name
it:

| Component | Header says | What it does now |
|---|---|---|
| `Velocity` | "From `Body#integrate`" | integrates into `node.x` / `node.y` |
| `ScreenWrap` | "From `Body#wrap!`" | wraps the node against `WorldBounds` |
| `DespawnOffscreen` | "From `Body#offscreen?`" | frees the node past a margin |

So the class was correctly decomposed into the architecture and the original was
never removed. That is the exact shape the user's hypothesis describes, and it is
the only place the sweep found it intact.

### A2. Seven engine classes have no caller, and they are four different problems — *(measured)*

Counting non-comment references in `lib/`, `examples/` and `test_projects/`,
outside each class's own file. The first draft of this table said five; it
missed `Targeting` and `I18n`, because `examples/save_load_ids` *names*
`Targeting` in a comment and a grep that did not skip comments counted it.

| Class | Documented | Verdict |
|---|---|---|
| `Body` | no | dead — A1; removed in step 1 |
| `Matrix` | `toolbox.md` | unused — removed in step 1, by decision |
| `Resettable` | `toolbox.md` | built for a case the engine designed away — see below |
| `Path` | 2 pages | waiting for `examples/pathfinding` — kept, by decision |
| `PathFollow` | 2 pages | waiting for `examples/pathfinding` — kept, by decision |
| `Targeting` | `components.md` | unexercised, and described as a tower-defense part |
| `I18n` | `toolbox.md` | unexercised |

`docs/plans/basic-examples.md` had already listed `Matrix` and `Resettable` as
orphans and deleted a third, `Engine::Actor`, on the same evidence — so this is
not a new kind of cleanup, it is the same one finished.

**Why `Resettable` was never used — it was not overlooked.** Git has it arriving
in `3057e0e`, "old engine layer (reference for rewrite)", and it had no caller
even there: the only mentions in that tree are its own documentation. It builds
`Data`-like value classes with one in-place `reset`, for pooling value objects
without per-field setters. The engine then made two design choices that each
removed a place it could have been used:

- **What gets pooled is nodes, not values.** `Engine::Pool` and
  `Components::Pool` recycle `Node2D` subclasses, and a node carries components,
  children and a transform. A class generated by `Resettable.define` cannot be
  one. So every pooled thing in the repository — `Bullet` and `Rock` in
  asteroids, the motes in `examples/pooling` — writes its own `reset` on the node,
  and reaches the component state it needs through ordinary readers.
- **Signals carry no payload object.** `Signal.define(:index, :value)` uses the
  same generated fixed-arity trick `Resettable` does, but `emit` passes the
  fields as arguments, so there is no event value to pool either.

So it is not a misfit and not an oversight; it is a solution to a problem both of
its would-be callers were designed not to have. The recommendation is to remove
it, and that is left to open question 1 because it was not decided in
conversation. Its `toolbox.md` entry also points at "the Style notes in
`CLAUDE.md`", a section that does not exist, which is stale however the question
goes.

**`Path` and `PathFollow` are kept, and they collide with A3.** The pathfinding
example is designed around them: `AStar.find(grid, from, to)` returns an
`Engine::Path`, and the plan calls that "the design point worth stating out
loud". But what that example walks is a character — its entry reuses the
hero sheet and `town.tmx`, and routes around the map's solid tiles — and a
character in this engine is a `CharacterBody` blocked by tiles. `PathFollow` moves a node by assigning
`node.x` directly. Put both on the hero and the route is walked through whatever
the body would have stopped, with the body's intent ignored and its
`on_blocked` silent.

The route itself is safe, since A* only routes through walkable tiles. What breaks
is everything the body is there for: another character standing on the route,
a `WanderController` sibling, the walk animation reading the body's intent as a
facing. The shape that fits is a controller that steers a `CharacterBody` along a
`Path`, the way `WanderController` steers it toward a random direction — which
is step 2's question from the other side. **That has to be answered before the
pathfinding example is written**, or the example will teach the wrong mover.

**`Targeting` and `I18n` were not raised in conversation.** `Targeting` is also
the largest single target of step 1b, because its header describes it as a
tower's aiming — so it is kept by default, reworded by 1b, and its future is open
question 1. `basic-examples.md` says asteroids uses `Targeting`; it does not, and
never builds one.

### A3. Four components move a node, and one of them can be stopped — *(measured: this is the headline)*

Every one of these writes the node's position, once per frame, as its whole job:

| Component | How it moves the node | Can it be blocked? |
|---|---|---|
| `Velocity` | `node.x += @vx * dt` | **no** |
| `PathFollow` | `node.x = ` interpolated along a segment | **no** |
| `ThrustController` | writes `vx`/`vy` on a `Velocity` sibling | **no** |
| `CharacterBody` | `apply_move(dx, dy)`, through a `CollisionSystem` | yes |

They answer the same question about different things — *where does this node go
this step* — which is the test CLAUDE.md's "find the thing it resembles" states.
And the machinery that answers the follow-up question, *and what if something is
in the way*, is general: `CollisionSystem` takes a list of blocker sources and
knows nothing about character walking. It is reachable from exactly one of the
four, because `CharacterBody` is where it was built.

The consequences are not hypothetical:

- A rock cannot be stopped by a wall. A `Velocity` node declares no `blocked_by:`
  because the keyword does not exist on it.
- `on_blocked` / `on_unblocked` are unavailable to three of the four movers, so
  "I hit something solid" has one report for characters and none for anything
  else.
- The collision plan's own "what this does not deliver" recorded half of this
  from the other side: a collider moved by a `Velocity`, a `PathFollow` or an
  ancestor is bucketed where the last rebuild left it, because re-indexing is
  driven from `CollisionSystem#move` and those three never call it.

### A4. The composition already exists, and every instance hand-rolls it — *(measured)*

Four files carry a node with a non-blockable mover *and* a collider:

```
examples/collision/main.rb
test_projects/asteroids/bullet.rb
test_projects/asteroids/ship.rb
test_projects/asteroids/rock.rb
```

None of them is wrong, because none of them wants blocking — asteroids is a game
about passing through things and exploding. But it means the composition is
routine rather than exotic, and that the first game that *does* want a blocked
projectile or a blocked patrolling enemy will write the response by hand, which is
where the collision plan's B2 came from last time.

### A5. "The edge of the world" still has two coordinate frames — *(carried, and still live)*

The collision unification measured this as B9 and deliberately stopped short of
fixing it. `ScreenWrap` and `DespawnOffscreen` read `WorldBounds` and act on
`node.x` / `node.y`; a bounds-blocked `CharacterBody` reads the same bounds and
acts on the **collision box**, which sits at an offset. A node carrying both is
therefore a contradiction, and the plan's resolution was to stop applying bounds
to anyone who had not asked, and to document the contradiction rather than
reconcile it.

That was the right call for a step that had to land. It leaves a genuine
architectural seam: two answers to "where is this node, for the purpose of the
world's edge", and the engine picks by which component you used. It is in scope
for this sweep because it is the same question this sweep is asking, and out of
scope for steps 1 and 2 because it deserves its own measurement.

### A6. The tile map stack is a good fit — *(measured: the hypothesis is not borne out here)*

The thing the sweep was called for, stated as a result so it is not mistaken for
an omission. `TileMap`, `Tileset`, `TileMapLayer` and `TileWorld` were each read
against the checklist below:

| Check | Result |
|---|---|
| Duplicates state the node owns | no |
| Needs a hand-written wiring hook | no |
| Order-dependent with a sibling | no |
| Names a layer it may not name | no — `TileMap`'s header cites the rule and stops at a path |
| A node pretending to be a component, or the reverse | no — `TileMapLayer` is a node because it draws in world space; `TileWorld` is a component because it is a scene-scoped answer |

`TileMapLayer`'s header records that it *was* reshaped for the architecture: there
used to be one node drawing a "below" band and an "above" band, relying on a
global z to slot actors between them, and it became a node per layer when draw
order became tree order. That is the port the hypothesis expected to find
outstanding, already done.

The checklist is header-and-interface depth, not line-by-line. Recorded as a
limit, not a claim of exhaustiveness.

### A7. The engine describes itself in terms of games it does not ship — *(measured)*

Counting lines that name a game — tower defense, Snake, Asteroids, `tiled_world`,
or a path under `test_projects/` — everywhere except `docs/plans/`, the games
themselves under `test_projects/`, and the drive scripts under
`tools/drive/test_projects/` that belong to them:

| Area | Lines |
|---|---|
| `spec/` | 22 |
| `docs/api/` | 17 |
| `tools/drive_test_project.rb` | 9 |
| `CLAUDE.md` | 8 |
| `lib/` | 5 |
| `examples/` | 2 |
| `.claude/skills/` | 2 |
| `README.md`, `docs/project_structure.md` | 1 each |
| **Total** | **67, in 23 files** |

Three kinds, and they want different fixes:

- **A game used as evidence.** "`test_projects/snake` mounts a broadphase and no
  bounds", "`test_projects/asteroids` never sets a size". The fact is general and
  the game is the proof. State the fact; point at an example where one proves it.
- **A game used as a worked example.** "`test_projects/tiled_world` is the
  both-at-once case", "see `test_projects/asteroids` for the whole loop". An
  example exists for nearly every one of these, and where it does not, the
  sentence can stand without it.
- **A component describing its purpose as a game's.** `Targeting` "picks an enemy
  for the owning node (a tower)"; `PathFollow` is "the seam a tower defense game
  uses to leak a life when an enemy reaches the base"; `Path` exists so "a
  tower-defense level can mask placement cells". These are the ones that matter
  most, because they tell a reader what the class is *for*, and what they say is
  narrower than what the class does.

The count above is names only. Vocabulary that only makes sense inside one game —
a snake eating fruit in `collision_world_spec.rb`'s layer symbols, a tower
leaking a life at the base — is in scope by the same rule and not in the number,
because telling it apart from generic illustration ("a bullet", "a crate") takes
reading rather than grepping. Step 1b states the line.

## B. Prior art

How other engines attach "something is in the way" to "this thing moves".

| Engine | Movers | Blocking available to |
|---|---|---|
| Godot 4 | `CharacterBody2D`, `RigidBody2D`, `AnimatableBody2D`, plain `Node2D` | any `PhysicsBody2D` via `move_and_collide`; a plain `Node2D` gets none |
| Unity 2D | `Rigidbody2D` (dynamic/kinematic), transform writes | `Rigidbody2D` only; a transform write teleports through colliders |
| Bevy | any system writing `Transform` | nothing built in; `bevy_rapier` adds `KinematicCharacterController` |
| bump.lua | the caller | **everything** — `world:move(item, x, y, filter)` is the only mover, and the filter decides per pair |

Two things worth taking and one worth refusing.

**Everyone separates "write the transform" from "move and be stopped", and the
second is opt-in.** Godot is explicit that setting `position` bypasses collision
entirely. So a generalization here should not make every mover collide; it should
make *asking* to be stopped available to every mover.

**bump.lua is the shape to copy**, as it was for the collision plan. One move
call, a filter that answers per pair, and the caller decides what the answer
means. The engine already has the pieces — `CollisionSystem#move` is that call,
and `blocked_by:` is that filter — reachable from one component instead of from
the movement seam.

**What none of them gives us** is a reason to fold the movers into one class.
Godot's four body types exist precisely because integrating a velocity, walking a
path and stepping a character are different jobs. The generalization is the
*seam*, not the class.

## C. What was considered and rejected

**Fold the four movers into one `Mover` component with a mode.** Tempting because
it makes the shared seam impossible to miss. Rejected on the prior art: every
engine surveyed keeps its movers separate, and a mode parameter that switches
between integrating a velocity and interpolating a path is two classes wearing a
trench coat. The duplication is in what they do *after* computing a step, not in
computing it.

**Give every mover a `blocked_by:` keyword.** The obvious generalization, and it
is probably part of the answer, but rejected as the whole of it because it
triplicates the attach-time resolution, the `CollisionSystem` construction and the
signal pair that `CharacterBody` already carries — three copies of the code that
step 2 exists to stop having one copy of in the wrong place.

**Delete every uncalled class because nothing calls it.** Rejected as a decision
this plan may not take alone: six of the seven are documented public API in a
published gem, and "no caller in this repository" is not the same as "no caller".
Each was put to the user instead, with the evidence attached, and two of the
answers were not deletion.

**Delete `test_projects/` rather than pruning references to it.** It would remove
every reference at once. Rejected because it was not asked for, and because
CLAUDE.md makes a driven test project the acceptance tier for wiring. Step 1b
prunes what *names* a game and leaves the directory and its harness alone.

**Do nothing, on the grounds that the engine works.** The honest option, and it
is what constraint 5 is protecting. Rejected for A3 specifically, on the grounds
that A3 is the same defect as the collision split at the same stage — two things
answering one question, both correct, with nothing yet forcing them together —
and the whole point of the retrospective was to catch the next one earlier than
six steps.

## D. Open questions

1. **What happens to each uncalled class?** Partly settled.
   - ~~`Matrix`~~ **Settled — removed, in step 1a.**
   - ~~`Path`, `PathFollow`~~ **Settled — kept for `examples/pathfinding`**, or a
     simpler example of their own if that one does not use them. The mover
     conflict A2 records goes to step 2.
   - **`Resettable`** — open. A2 explains why it has no caller, and recommends
     removal. Blocks step 1a's scope only.
   - **`Targeting`** — open, not yet raised. Step 1b rewords it either way; this
     is whether it keeps a place, gets an example, or goes.
   - **`I18n`** — open, not yet raised. `basic-examples.md` already suggests a
     localized-menu example for it.
2. **Where does the shared movement seam live?** Blocks step 2's design. Candidates:
   a module mixed into the movers, a `Motion` component the movers write through,
   or a method on `Node2D` itself. Measure before choosing, the way the collision
   plan measured its three candidates for index freshness.
3. **Should `on_blocked` be available to a mover with no character semantics?** A
   bullet stopped by a wall wants to explode, not to slide. Does the generalization
   carry the axis-separated slide, or is sliding the part that stays in
   `CharacterBody`? Does not block step 1.
4. **Is A5 worth reconciling, or is documenting it the right permanent answer?**
   Does not block steps 1 or 2. Needs its own measurement of how many nodes could
   ever carry both.

## E. What this does not deliver

- **Any change to the tile map stack.** A6 is the finding; there is nothing to do.
- **A physics engine.** No mass, no impulse, no restitution. Blocking stops a
  mover and never moves what it hit, which is the rule the collision plan already
  states.
- **Continuous collision detection.** A fast bullet still wants contact signals
  rather than blocking, and generalizing the seam does not change the
  step-smaller-than-a-tile assumption underneath it.
- **A sweep of `RGame::Core`.** This is the engine layer only. Core's Ruby classes
  hold handles and answer a different set of questions.
- **A line-by-line audit.** A6's checklist is interface depth. A misfit hiding
  inside a method body that presents a clean interface would not have been caught.

## F. Roadmap

```
1 dead code + game references ──→ 2 the movement seam ──→ 3 the two frames (rough) ──→ 4 fold back
        │                          │
        └── independently useful ──┘
```

> **The invariant every step must preserve: a node's position is owned by the
> node.** `Engine::Body` is in this plan because it kept its own copy, and every
> mover here writes through `node.x` / `node.y` rather than shadowing them.

| Step | Defect it closes |
|---|---|
| 1 | A1 and A2 — dead classes loaded into every process and shipped in the gem; A7 — documentation that depends on games the engine does not ship |
| 2 | A3 and A4 — blocking reachable from one of four movers, with the composition already in four game files |
| 3 | A5 — two coordinate frames for the edge of the world |

### Step 1 — remove the dead code, and the references to games

First because both halves are decided, because they shrink what step 2 has to
read, and because both are worth landing if step 2 never happens. One branch, two
sub-steps, one commit each — they share a reason (the engine layer describing
things that are not there) but not a diff, and a reviewer should be able to read
the deletion without 67 rewordings in the way.

#### 1a — dead code

`Engine::Body` and `Engine::Matrix` go: each file, its `require_relative` in
`lib/rgame/engine.rb`, and its spec. `Matrix`'s section in `docs/api/toolbox.md`
goes with it, and the paragraph after it that points at `Tensor` for three
dimensions is reworded to stand on its own. The three component headers that say
"From `Body#integrate`" and its siblings lose that clause, because a reference to
a class that no longer exists is worse than none.

`Resettable` joins this sub-step if open question 1 settles as removal before the
branch is cut, and not otherwise. `Targeting` and `I18n` do not.

Rules the tests must pin:

1. `require "rgame"` succeeds with the files gone, which is what catches a missed
   `require_relative`.
2. `RGame::Engine::Body` and `RGame::Engine::Matrix` are not defined afterwards —
   an explicit example, so the removal is asserted rather than merely done.
3. `spec/packaging_spec.rb` still passes, since it re-derives what ships from the
   tree.

#### 1b — references to games

**What counts.** Anything outside `docs/plans/` that names a game —
tower defense, Snake, Asteroids, `tiled_world`, `hello_world`, or a path under
`test_projects/<game>` — or uses vocabulary that only makes sense inside one: a
tower, the base an enemy reaches, a snake and its fruit. Generic nouns used as
illustration stay: a bullet, an enemy, a crate, a rock, a villager.

**What does not.** Plans. References to `examples/`, which is the point of the
rewording. The games themselves and their drive scripts under
`tools/drive/test_projects/`, which belong to their project by the path-mirror
rule. And naming the **directory** `test_projects/` as a place — in
`docs/project_structure.md`, the README, the verify skill and CLAUDE.md's testing
section — because that names the acceptance tier, not a game. Where CLAUDE.md's
testing section uses a specific game as its illustration, the illustration moves
to an example the harness can drive.

**How.** By kind, per A7:

| Kind | Fix |
|---|---|
| A game used as evidence | state the fact; cite an example that shows it, or nothing |
| A game used as a worked example | point at the example that shows it |
| A component's purpose described as a game's | describe what the class does |
| A spec whose data is a game's | rename the data (`:snake`/`:fruit` layers become neutral ones) |

The one place this changes more than wording is `Targeting`, whose header,
`components.md` entry and spec are written as tower defense throughout. Its
behaviour does not change; its description does.

Rules the tests must pin:

1. A spec in `spec/` greps `lib/`, `docs/api/`, `spec/`, `spec_core/`,
   `examples/`, `.claude/skills/`, `README.md` and `CLAUDE.md` for the game names
   and fails naming the file and line. It lives beside
   `spec/packaging_spec.rb`, for the reason CLAUDE.md gives for that spec: a rule
   that depends on someone remembering it is the wrong design, and this one would
   otherwise last until the next example cites a test project. The exemptions are
   listed in the spec, so adding one is a visible decision.
2. The spec's own list of game names is derived from `test_projects/`' directory
   names, plus `tower defense`, so a new test project is covered without editing
   it.
3. No spec's behaviour changes. `collision_world_spec.rb`,
   `contact_set_spec.rb` and `targeting_spec.rb` change names and data only.

Tests: the new guard spec, plus the rules above for 1a in
`spec/rgame/engine/engine_spec.rb` or wherever reads better once the files are
open.

Verify: `rake spec` green — the guard passes, and the example count moves only by
the deleted specs and the new guard examples; `rake spec:core` and `make test`
untouched. Every driven run byte-identical to `main` at `--ticks 240 --seed 7`,
which is the acceptance criterion for both halves: deleting unreferenced classes
and rewording comments must be invisible, and a byte-identical report is what
proves it. Then grep once more by hand for the vocabulary kind, which the guard
spec deliberately does not attempt.

### Step 2 — the movement seam

The real work, and the reason the sweep was worth doing. Sketched rather than
settled, because open question 2 has to be measured first — the collision plan's
own lesson is that the candidate the plan expects to win is not always the one
the numbers pick.

What is settled going in:

- **The movers stay four classes.** Section C rejects folding them, and the prior
  art agrees.
- **Blocking stays opt-in.** A mover that declares nothing keeps writing the
  node's position directly, at the same cost it does today, which is constraint 2
  and also what Godot and Unity both do.
- **`CollisionSystem` does not change.** It already takes a list of sources and
  knows nothing about characters. What changes is who can reach it.

What has to be decided by measurement, before the shape can be written:

1. Whether the seam is a module, a component or a method on `Node2D`
   (open question 2). Build all three against the real classes and compare what a
   blocked `Velocity` costs per frame, the way B6 compared index strategies.
2. Whether the axis-separated slide travels with the seam or stays in
   `CharacterBody` (open question 3). A bullet that slides along a wall instead of
   stopping is a bug in every game that has ever had bullets.

The acceptance criterion is known even though the shape is not: **a rock in
`test_projects/asteroids` can be given `blocked_by:` and stop at a wall, in one
line, with no hand-written response** — and every existing driven run stays
byte-identical, because nothing that did not ask may start colliding.

Re-plan this step properly once step 1 has landed and the three candidates have
been measured.

### Step 3 — the two coordinate frames *(rough)*

A5. Reconcile "where is this node for the purpose of the world's edge", or decide
that documenting the contradiction is the permanent answer (open question 4).

Deliberately left rough. It depends on what step 2 does to the movers — if a
`Velocity` can be bounds-blocked afterwards, the number of nodes that can carry
both frames goes up sharply, and that changes the answer.

### Step 4 — fold the plan back and delete it

Whatever is still true moves into CLAUDE.md, `docs/api/` or a comment at the code
it describes; the rest is history and `git log` has it.

Two things are already known to be owed. **A6 is the one finding with no code
change behind it**, and a negative result that nobody records gets re-investigated
in six months — `docs/api/` should say somewhere that the tile map stack was swept
against the architecture and passed. And whatever open question 1 resolves to,
`docs/api/toolbox.md`'s `Resettable` entry needs to stop pointing at a CLAUDE.md
section that does not exist. And `docs/plans/basic-examples.md` should be told
two things this sweep found: asteroids does not use `Targeting`, and
`examples/pathfinding` should walk its route through a `CharacterBody` rather than
a `PathFollow` — or whatever step 2 settled instead.

Then delete this file.
