# Unifying the two collision systems

**Status: steps 1 and 2 are implemented; steps 3–6 are not.** Step 3 of the
roadmap is detailed; steps 4–6 are deliberately rough and should be re-planned
once the layer beneath them exists. Note step 2's landed note moves rule 3 of its
own list into step 4.

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

### D4. Blocking reports itself

Because of B4, the body announces what stopped it:

```ruby
body.on_blocked { |other| take_damage if other.layer == :spike }  # other is a collider, or :tiles
```

Which is `get_slide_collision` and `OnCollisionEnter2D` in this engine's idiom.
The spiky ball is then exactly what was asked for, and it is two lines with no
hand-rolled anything:

```ruby
add_component(FeetCollider.new(width: 12, height: 6, layer: :player))
body = add_component(CharacterBody.new(speed: 80, blocked_by: %i[tiles spike]))
body.on_blocked { |other| damage(1) if other != :tiles && other.layer == :spike }
```

`on_hit` and `on_separated` keep meaning overlap, and remain the right signals
for everything that should *not* block: pickups, triggers, hitboxes, the whole of
`examples/collision`. A game wanting both behaviours from one entity gives it two
colliders, which is the Godot idiom of a body with a child area and needs nothing
new here.

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

## F. Open questions

1. **How does the resolver see a fresh index?** B5 measures the hazard: an actor
   resolving mid-step queries a broadphase built before anything moved. Three
   candidates — inflate the query box by the maximum step (approximate, free);
   give `SpatialHash` a `remove` and have the body re-insert after moving (exact,
   costs a bucket scan per actor per step); or move the contact pass into a
   post-update traversal beside `sweep_freed` and rebuild the index there
   (exact, and it fixes B3 as a side effect, but it changes the documented
   ordering that `examples/collision` used to rely on). **Blocks step 4.** Decide
   it with a measurement, not an argument.
2. **Does `on_blocked` carry an edge like `on_hit`, or fire every blocked step?**
   Leaning every step: unlike an overlap, being blocked is a fact about *this*
   step's resolution and there is no natural "still blocked" state to track. But
   it makes the signal the one thing in the collision API that is not an edge,
   which wants stating loudly if it is chosen. Does not block anything before
   step 5.
3. **Does `ActorBlockers` need circles?** `CircleCollider` can be a blocker in
   principle, but snapping an axis-aligned box flush against a circle is not the
   same arithmetic and has no obviously right answer at the corners. Proposal:
   step 4 blocks against boxes only and says so, and a circle collider is a
   contact-only shape until somebody needs otherwise. Does not block anything.
4. **Should `cell_size` default from the tile map?** A scene with a `TileWorld`
   knows its tile size, and `CollisionWorld.new` with no argument could take it.
   Cosmetic, one line saved, and it couples two systems that are otherwise
   independent. Does not block anything.

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

## H. Roadmap

```
1 FeetCollider ──→ 2 CharacterBody(blocked_by:) ──→ 3 blocker sources ──→ 4 actor blocking ──→ 5 on_blocked ──→ 6 fold back
       │                      │                            │                      ↑
       └── one box, no handoff┘                            └── pure refactor ─────┘
                                                                          (open question 1 blocks here)
```

Steps 1–3 are worth landing even if 4 and 5 never happen:

| Step | Defect it closes |
|---|---|
| 1 | Trap 1 and 2 of B2 — the placeholder box and the raise |
| 2 | Trap 3 of B2 — the silent handoff hook; and a missing `CollisionWorld` starts failing loudly |
| 3 | Nothing user-visible; it is what makes 4 a small step instead of a large one |

> **The invariant every step must preserve: a node has exactly one collision
> shape, and exactly one component owns it.** Everything in B2 follows from that
> being false today.

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

### Step 4 — `ActorBlockers` *(rough — re-plan after step 3)*

Actors block actors. **Open question 1 must be settled first**, with a
measurement, because the index freshness decides whether this is a query, a
re-insert, or a new traversal phase. Expect the step to be mostly that decision
and a narrow amount of code after it.

### Step 5 — `on_blocked` *(rough)*

The body reports what stopped it, resolving open question 2 on the way. This is
what makes the spiky ball work and is the reason steps 1–4 were worth doing.

### Step 6 — fold the plan back and delete it

Real work, not tidy-up. `docs/api/components.md` gains `FeetCollider`, loses
`TileCharacterBody` and rewrites `CharacterBody`; `docs/api/systems.md` gains the
blocking-versus-overlap distinction; `docs/api/internals.md` gains the blocker
sources beside `TileCollision`. `examples/collision_tiles`'s header currently
says the two examples "share no code", which step 3 makes false and which is
worth rewriting rather than deleting — the two examples still answer different
questions, and saying *how* they now share a resolver is a better lesson than the
old separation was. Then delete this file.
