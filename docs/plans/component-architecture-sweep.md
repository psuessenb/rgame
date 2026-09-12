# Sweeping the systems and components for architectural fit

**Status: steps 1 and 2 are implemented. Steps 3 and 4 are deliberately rough, and
step 3 needs its re-plan against what step 2 made possible. Every uncalled class has
since been decided in conversation — see open question 1.**

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
   not a verdict — every removal here was decided in conversation, and open
   question 1 records each answer.
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
- **`Engine::Resettable` goes.** Decided in conversation, on A2's account of why
  it never had a caller.
- **`Components::Targeting` stays**, reworded by step 1b so it stops describing
  itself as a tower's aiming.
- **`Engine::I18n` stays, and gets an example.** Decided in conversation:
  `examples/localization` is now the last entry of `docs/plans/basic-examples.md`,
  as example 23.
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
| Engine classes with no non-comment caller in `lib/`, `examples/` or `test_projects/` | **7** — 3 to remove, 4 kept |
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
| `Resettable` | `toolbox.md` | built for a case the engine designed away — removed in step 1, by decision |
| `Path` | 2 pages | waiting for `examples/pathfinding` — kept, by decision |
| `PathFollow` | 2 pages | waiting for `examples/pathfinding` — kept, by decision |
| `Targeting` | `components.md` | described as a tower-defense part — kept and reworded, by decision |
| `I18n` | `toolbox.md` | unexercised — kept, with `examples/localization` scheduled, by decision |

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
its would-be callers were designed not to have. It is removed in step 1a. Its
`toolbox.md` entry, which also pointed at a "Style notes" section CLAUDE.md does
not have, goes with it.

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

**`Targeting` is kept, and is the largest single target of step 1b**, because its
header, its `components.md` entry and its spec are written as a tower's aiming
throughout. **`I18n` is kept** and gets `examples/localization`, which also has
to settle how a label keyed on both a value and the locale avoids allocating —
recorded as an open question in that entry. `basic-examples.md` says asteroids uses `Targeting`; it does not, and
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
Each was put to the user instead, with the evidence attached, and four of the
seven answers were not deletion.

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

1. ~~**What happens to each uncalled class?**~~ **Settled, class by class.**
   - `Body` — removed, in step 1a. See A1.
   - `Matrix` — removed, in step 1a.
   - `Resettable` — removed, in step 1a, on A2's account of why it was never used.
   - `Path`, `PathFollow` — kept for `examples/pathfinding`, or a simpler example
     of their own if that one does not use them. The mover conflict A2 records
     goes to step 2.
   - `Targeting` — kept; reworded by step 1b.
   - `I18n` — kept; `examples/localization` added as the last basic example.
2. ~~**Where does the shared movement seam live?**~~ **Settled — a base class,
   `Components::Mover`, that all three movers inherit.** Measured against a sibling
   component (order-dependent) and a `Node2D` method (collision in every node's base
   class), at equal cost. See [step 2, re-planned](#re-planned-against-the-code-after-step-1).
3. ~~**Should `on_blocked` be available to a mover with no character semantics?**~~
   **Settled — yes, and the slide travels with it**, because it is
   `CollisionSystem`'s axis order and that class does not change. A bullet reacts to
   `on_blocked`. See [step 2, re-planned](#re-planned-against-the-code-after-step-1).
4. **Is A5 worth reconciling, or is documenting it the right permanent answer?**
   Does not block steps 1 or 2. Needs its own measurement of how many nodes could
   ever carry both.
5. **Should `on_blocked` say which axis was stopped?** A bouncing projectile needs
   it, and `CollisionSystem#blocked_x`/`#blocked_y` already know. Nothing in the
   repository bounces. Does not block anything.
6. **Where does a path-walking character get its facing?** `AnimatedSprite` reads
   `move_x`/`move_y` off a `CharacterBody`, and `PathFollow` has no intent. Blocks
   the pathfinding example's animation, not its walk.

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

`Engine::Body`, `Engine::Matrix` and `Engine::Resettable` go: each file, its
`require_relative` in `lib/rgame/engine.rb`, and its spec. Two sections of
`docs/api/toolbox.md` go with them. The paragraph after `Matrix`'s, which points
at `Tensor` for three dimensions, is reworded to stand on its own, and `Pool`'s
entry stops recommending `Resettable` for re-initialising an acquired object —
what it recommends instead is what every pooled node in the repository already
does, a `reset` of its own. The three component headers that say
"From `Body#integrate`" and its siblings lose that clause, because a reference to
a class that no longer exists is worse than none.

`Targeting`, `I18n`, `Path` and `PathFollow` are not touched here.

Rules the tests must pin:

1. `require "rgame"` succeeds with the files gone, which is what catches a missed
   `require_relative`.
2. `RGame::Engine::Body`, `Matrix` and `Resettable` are not defined afterwards —
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

**Landed.** Two commits, one per sub-step. 1a deleted `Engine::Body`, `Matrix` and
`Resettable` with their requires and specs, and added `spec/rgame/engine_spec.rb`
asserting the three constants stay undefined. 1b reworded every reference to a game
outside the exemptions and added `spec/game_references_spec.rb`, which keeps it that
way. `rake spec` is 1284 examples, 0 failures — 1296 before, minus the 18 deleted
examples, plus 3 for the removal and 3 for the guard, so the count moved by exactly
that. `make test` 326 checks, 0 failures; `rake spec:core` 367 examples, 0 failures.

The acceptance evidence is the driven runs: all 28 scripts under `tools/drive/`, at
`--ticks 240 --seed 7`, on this branch and on a worktree of `main`. Every report is
byte-identical to `main`'s whenever the two runs drew the same number of frames. The
two `tiled_world` scripts that did not always match flipped between 239 and 240
frames on **both** trees, and grouping the reports by frame count gave one hash per
group across both trees. That is the frame skip the verify skill already warns
about, not this change. The guard was checked by adding a file naming a test
project in a path and a game in prose, and it failed on both lines and let
`snake_case` through.

What the sketch got wrong:

- **The guard does not scan a list of directories.** Rule 1 listed eight places, and
  that list already missed `tools/drive_test_project.rb`, which A7 counted at nine
  lines. The spec scans every file `git ls-files --cached --others
  --exclude-standard` returns, minus its exemptions. That is the same derive-don't-list
  reasoning as `packaging_spec.rb`, and it means a new top-level document is covered
  without anyone editing the spec. It turned up one exemption the plan did not name:
  `CHANGELOG.md`, which records releases under the names the examples had then.
- **A whole-word match needs one stated exception.** `\b` treats `_` as a word
  character, so it would miss `tiled_world_2p.rb`. With letters and digits as the
  only boundary, `snake_casing` in `.rubocop.yml` matches instead. The spec strips
  `snake_case` before matching and says why, and an example pins both directions.
- **The vocabulary reached further than A7's count.** `fruit` was not only in
  `collision_world_spec.rb`. It was also in `collision_box_spec.rb` and in
  `CollisionWorld#cell_empty?`'s header and `components.md` entry ("may the fruit
  spawn on this square?"). A tower's fire rate became a turret's, which is generic
  and keeps the example.
- **Two illustrations have no example to move to, so they narrowed.** The
  `tiled_world` sentence that a split-screen game collapses to one view for a
  cutscene was dropped, because no example calls `solo!`. And `systems.md`'s
  "whole loop" pointer now goes to `examples/collision`, which registers, overlaps
  and separates but does not spawn and despawn the way asteroids did.
  `examples/pooling` spawns and despawns but has no collision. Neither is this step's
  to fix.
- **A driven comparison over the stateful examples is not reproducible without
  `RGAME_SAVE_DIR`.** `save_load`, `save_load_ids` and `menu_navigation` write to the
  real data directory unless it is set, so a run reads what the previous one saved.
  The first comparison here showed all three differing from `main` for that reason
  alone. Their drive scripts say to set it, but only in a comment. Nothing in the
  harness enforces it, which is the kind of remembered rule CLAUDE.md's "Design out
  misuse" rejects. Out of scope here; the obvious fix is the harness giving every run
  a fresh temporary directory unless one is passed.

Smaller deviations. `Matrix`'s `toolbox.md` section became a short "Grids" section,
because the paragraph pointing at `Tensor` needed a heading to stand under. The
removal examples went into a new `spec/rgame/engine_spec.rb` rather than a file that
did not exist. Rule 1 of 1a has no example of its own, because `spec_helper`'s
`require "rgame"` is already that check. CLAUDE.md's harness illustration moved to
`examples/collision_tiles`, whose two scripts (`collision_tiles.rb` and
`collision_tiles_spike.rb`) show `--script` just as `tiled_world`'s did.

Documented in `docs/api/toolbox.md` (grids, `Pool`, `Path`, `Timer`, the camera, the
collision recipe), `components.md`, `systems.md`, `scene_graph.md` and `input.md`,
and in CLAUDE.md's current-phase and testing sections. `docs/plans/basic-examples.md`
still says asteroids uses `Targeting`, as step 4 already records. It is a plan, so
the guard does not look at it.

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

#### Re-planned, against the code after step 1

**The three candidates were built and measured** at `bd172ce`, as prototypes in a
scratch script over a real `CollisionWorld`. Each was a `Velocity` pressed into a
16×400 wall collider, run for 300,000 frames of `node.update`, three rounds. All
three reach one shared core, which is `CharacterBody`'s blocking half pulled out
as it stands:

| Candidate | Free step, ns/frame | Blocked step, ns/frame | Allocations per frame | Order-dependent |
|---|---|---|---|---|
| today's `Velocity` (reference) | 522–567 | — | 0 | — |
| A — shared by the movers themselves (module or base class) | 493–513 | 7,203–7,443 | 0 | no |
| B — a `Blocking` sibling component the mover writes through | 465–473 | 7,360–7,907 | 0 | **yes** |
| C — `Node2D#move_by`, the node owning `blocked_by` | 487–515 | 7,405–8,097 | 0 | no |

**Cost does not choose between them.** The spread inside one candidate across rounds
is wider than the spread between candidates, and none allocates. Every free step is
within noise of today's, so constraint 2 holds whichever wins.

**B fails on order, measured.** A step has two edges, opening it (which makes this
step's blocker list the previous one) and closing it (which reports what ended). A
sibling component can close the step only from its own `update`, which runs wherever
it sits in the component list. With the mover added first, `on_unblocked` fired on
the tick the mover walked away. With the `Blocking` component added first, it fired
one tick later. Two add orders gave two behaviours, and nothing said so. That is
precisely the "order-dependent with a sibling" check A6 applies, failed.

**C is order-free but puts collision into the base of every node.** `Node2D` would
have to name `BoxCollider`, `CollisionWorld`, `TileWorld` and `WorldBounds`. HUDs
and menus are `Node2D`s too. `on_blocked` would move from the body to the node, which
changes `CharacterBody`'s documented signals and `examples/collision_tiles`, a public
API change that buys nothing A does not.

**A wins, as a base class rather than a mixin:** `Components::Mover`. All three
movers are already `Component`s, and a module would need its own initialize hook
for `blocked_by:`, which the base class gets from `super`. It keeps
`CharacterBody`'s API as it is: `blocked_by:`, `on_blocked`/`on_unblocked` and
`apply_move` stay where they are and simply become inherited. The step bookkeeping
follows CLAUDE.md's blank-hook rule. `Mover#update` opens the step, calls the
subclass's `take_step(dt)` and closes it, so no mover can forget either edge.

**Open question 3 is answered by constraint, not by taste: the slide travels.** It
is `CollisionSystem`'s axis-separated order, and `CollisionSystem` does not change.
What it means for a bullet is that `on_blocked` fires on the step it hits the wall,
and a bullet that wants to stop queue-frees itself there. It slides for zero frames
it is still alive in. A mover that keeps pressing keeps its intent too: a blocked
`Velocity` does not zero its `vx`. Bouncing wants to know which axis was stopped,
which `on_blocked` does not say; that is left open (question 5) rather than widening
a signal nobody has asked to widen.

**`ThrustController` needs nothing.** It writes a `Velocity`, so a ship is blocked
by declaring `blocked_by:` on the `Velocity`. So the movers are three and not four,
and that is the count this step makes blockable.

**The sketch's acceptance criterion cannot be run as written.** A rock in
asteroids carries a `CircleCollider`, blocking is box-versus-box, and asteroids has
no wall. The criterion is kept in substance, a one-line `blocked_by:` on a
`Velocity` stopping at a wall with no hand-written response, and asserted by spec
instead of by editing a game.

##### 2a — `Components::Mover`, extracted from `CharacterBody`

A pure extraction: nothing a `CharacterBody` does changes, and its 739-line spec is
the proof. The shape:

```ruby
class Mover < Engine::Component
  signal :on_blocked, Engine::Signal.define(:by)
  signal :on_unblocked, Engine::Signal.define(:by)

  def initialize(blocked_by: [])     # resolved nowhere until on_attach
  def on_attach                       # collider, then systems; raises naming self.class
  def update(dt)                      # open the step, take_step(dt), report what ended
  def apply_move(dx, dy)              # the seam: direct write, or through the resolver
  def collision_box / x / y / x= / y= # the world-space actor adapter

  private

  def take_step(dt) = nil             # the blank hook each mover fills in
  def blocking? = !@collision.nil?
  def last_move_blocked?              # either axis stopped on the most recent apply_move
end
```

`CharacterBody < Mover` keeps `speed`, the intent and `take_step`. Its raise
messages keep matching the existing specs, with the class name read from `self`.

##### 2b — `Velocity` is a `Mover`

`Velocity.new(vx:, vy:, spin:, blocked_by: [])`. `take_step` hands `vx*dt, vy*dt`
to `apply_move`; `spin` always writes the angle directly, since a box does not
rotate.

##### 2c — `PathFollow` is a `Mover`

`PathFollow.new(path:, speed:, blocked_by: [])`. The walk still computes where the
node should be, then gets there through `apply_move`. **A blocked step does not
advance the walk:** progress is rewound to where the step started, so a follower
held behind something waits and resumes rather than jumping ahead once it is let go.
`on_finished` fires only once the last waypoint was actually reached. Unblocked, it
keeps writing positions absolutely, exactly as today, so the existing spec is
untouched. `on_attach` still places the node on the first waypoint absolutely,
because a spawn position is a placement, not a step.

This answers A2 partly. The pathfinding example *can* walk a blocked route with
`PathFollow`, but `AnimatedSprite` reads its facing from a `CharacterBody` sibling,
so a hero walking a path would still not animate. That is question 6, and it
belongs to the example rather than to this step.

Rules the tests must pin:

1. **One contract for every mover.** A shared example group,
   `spec/support/shared_examples/a_mover.rb`, is run by `character_body_spec`,
   `velocity_spec` and `path_follow_spec` against one scene: a real `CollisionWorld`
   and a wall collider. Every mover must:
   - pass through the wall when nothing is declared
   - stop flush with `blocked_by: [:wall]`
   - fire `on_blocked` once, with the wall's collider, however long it presses
   - fire `on_unblocked` once when the wall leaves
   - raise at attach with no `BoxCollider`, and with no `CollisionWorld`
   - allocate nothing on a blocked step
2. **Both at once.** A spec mounts a `CharacterBody` and a blocked `Velocity` in one
   scene, each declaring the other's layer, and asserts they stop each other. This is
   CLAUDE.md's "what does a caller using both of us look like" test. Nothing in the
   repository builds that scene today.
3. **Free movers are unchanged.** The existing `velocity_spec`, `path_follow_spec`
   and `path_follow_allocation_spec` pass without edits.
4. **The blocked `PathFollow` waits.** Held for N ticks and then released, it
   arrives N ticks later than an unheld one, and does not skip the stretch it was
   held on.

Verify: `rake spec` green, counted up only by the new examples. Every driven run
under `tools/drive/` is byte-identical to `main` at `--ticks 240 --seed 7`, with
`RGAME_SAVE_DIR` set per run, because nothing that did not declare `blocked_by:` may
start colliding. The same benchmark, re-run against the real classes, puts a free
`Velocity` step within noise of the reference row above.

**Landed.** Four commits: the re-plan above, then one per sub-step. 2a added
`Components::Mover` and cut `CharacterBody` to its intent, its speed and
`take_step`, with its spec untouched. 2b made `Velocity` a `Mover` and added the
shared `a mover` group and `mover_spec.rb`. 2c made `PathFollow` a `Mover` with the
rewind. Each sub-step carried its own documentation. `rake spec` is 1320 examples, 0
failures. That is 1284 before, plus 27 from the contract run against three movers, 4
in `mover_spec`, 3 for the held `PathFollow` and 2 for the blocked `Velocity`, so the
count moved by exactly the new examples. `make test` is 326 checks, 0 failures, and
`rake spec:core` 367 examples, 0 failures.

The acceptance evidence:

- **Nothing that did not ask started colliding.** All 28 scripts under `tools/drive/`
  ran at `--ticks 240 --seed 7`, each with a fresh `RGAME_SAVE_DIR`, on this branch and
  on a worktree of `main`. 27 reports were byte-identical on the first pass. The 28th,
  `tiled_world`, drew 239 frames against `main`'s 240, the frame skip step 1 recorded;
  four re-runs on the branch drew 240 and were byte-identical to `main`.
- **A one-line `blocked_by:` stops a `Velocity` at a wall** with no handler. The
  contract asserts it flush at x = 184, with `on_blocked` once and `on_unblocked` once.
  `mover_spec` asserts it for a `ThrustController` ship, and for a walking
  `CharacterBody` and a blocked `Velocity` stopping each other.
- **The contract catches what it is for.** With `Velocity#take_step` writing the node
  directly, 4 of its examples failed. With `PathFollow`'s rewind removed, 4 failed.

What the sketch got wrong:

- **A free step is not free.** "At the same cost it does today" does not hold, and the
  re-plan's table said it did. Run interleaved against `main` for six rounds, taking
  the best of three in each, a free `Velocity` step was 470–496 ns on `main` and
  538–554 ns on the branch. That is 51–84 ns more, about 12%, every round. The table
  above compared separate process runs, and the drift between runs hid a gap that
  size. The cost is one extra dispatch: `Mover#update` calls `take_step`, which calls
  `apply_move`. Inlining the free write into `Velocity#take_step` measured 3–47 ns
  over `main` in five interleaved rounds, but it copies `apply_move`'s free branch into
  every mover and reads the base class's `@collision`. It was not taken. At a thousand
  free movers that is about 60 µs of a 16.7 ms frame. Constraint 2, no allocation,
  holds: every allocation measurement read zero.
- **The driven comparison needs `media/` in the worktree.** It is git-ignored, so a
  fresh worktree of `main` has none, and seven test projects crashed loading assets
  there. Step 1's note did not record this. A symlink to the checkout's `media/` fixed
  it.
- **`PathFollow` finishing goes through the same path as walking.** The old `finish`
  placed the node itself. It now reaches the last waypoint the way every step does, so
  a blocked follower cannot finish short of it. Unblocked, the positions are the same,
  and the existing spec passed unedited.
- **Two RuboCop exceptions.** `RSpec/MultipleMemoizedHelpers` is disabled inline, with
  reasons, around the two-mover scene in `mover_spec.rb` and the held-follower scene in
  `path_follow_spec.rb`. The shared group got under the limit by making its `dt` a
  method.

Consequences for later steps. **Step 3's premise is now true:** any `Velocity` or
`PathFollow` can declare `:bounds`, so the nodes that can carry both edge frames are
no longer only characters. Its re-plan starts from that. **Step 4's note to
`basic-examples.md` changes:** the pathfinding example can walk a blocked route with
`PathFollow(blocked_by:)`, but open question 6 still leaves that walker without a
facing.

Documented in `docs/api/components.md`, which has a new `Mover` section holding
everything about blocking that used to sit under `CharacterBody`, plus the `Velocity`
and `PathFollow` entries. Also in `systems.md` and `internals.md`, where blocking is
now described as the movers' rather than one component's, and in the headers of
`Mover`, `Velocity`, `PathFollow`, `ContactSet`, `ActorBlockers`, `TileWorld` and
`BoxCollider`.

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
against the architecture and passed. And `docs/plans/basic-examples.md` should be told
two things this sweep found: asteroids does not use `Targeting`, and
`examples/pathfinding` should walk its route through a `CharacterBody` rather than
a `PathFollow` — or whatever step 2 settled instead.

Then delete this file.
