# Single-job components

**Status:** Steps 1–5 are implemented. Step 6 is re-planned at `91b7269` and
ready. Step 7 is rough, and is re-planned before it starts. Step 8 folds the
plan back and deletes it.

## Verdict

**A component answers one question. What a node offers is a component on it,
never its collider's layer.** Five components answer two questions today, and
two select nodes by layer. One of them, `Grab`, does both:

- **`Grab`** picks what to hold by layer, and only then looks for a `Pushable`.
  A fixed crate nearer than a movable one makes it hold nothing *(measured)*. It
  picks by `Pushable` instead, through a `having:` that replaces `Targeting`'s
  `layer:`. `Targeting` also stops picking its own node, which it does today
  when given no `layer:` *(measured)*.
- **`Collectable`** detects a touch and takes the node, and `free: false` turns
  the second job off. Both doors in the repository use it that way, and are
  "collected". The flag goes, and a door says what it does with `on_hit`.
- **`AnimatedSprite`** draws a sheet's frames and picks a walk cycle from a
  `Mover`, and raises without one. It plays the animation it is given, and a
  subclass, `WalkingSprite`, picks the walk through a hook. Sprites and the
  map's animated tiles share one class that answers "which frame shows after
  t seconds". Each keeps its own clock.
- **`Respawn`**'s flash becomes `Components::Blink`, started from
  `on_respawned`, as the user proposed.
- **`Footing`** splits in three. It keeps what the node stands on and when that
  drops it, coyote time included. A `Fall` takes the node out of play and
  brings it back, and anything can start one: a gap, a cutscene, a trapdoor. A
  `FallLook` on the node, such as `Shrink`, says what the fall looks like. The
  falling node is suspended, so nothing on it updates, and the `Fall` runs the
  look from beside it. Each piece is added by the game, with no default in its
  place (decisions 10 and 11).

`Mover` answers two questions too, and stays as it is. Splitting it would make
the order of adds matter, so it is the named exception.

The plan ends in a `build-components` skill, written from what the fixes found
and linked from `write-plan` and `write-ruby-code`. Its rule on layers goes
into CLAUDE.md first, as step 1.

## The request

In the user's words, on 2026-09-29:

> We make this properly, not what's worth today, but what is the clean design
> going forward.
>
> 1. This will become a plan: Make single job components.
> 2. Step 1 of the plan is the record the rough rule "a component asking "may I
>    do X to that node?" should check for a component on the node, never for
>    its layer". It's only a single sentence, so it can live in CLAUDE.md
> 3. The goal of the plan is to have a `build-components` skill, linked from
>    the `write-plan` skill and probably `write-ruby-code` and/or
>    `implement-step`.
> 4. We start with the S in SOLID here, and future plas might incorparate the
>    other principles (the OLID) as well.
> 5. `Grab` and `Collectable` need to be fixed.
> 6. `AnimatedSprite` as well, and be use-able without the mover. Maybe it can
>    share internals with the animated tiles of the map?
> 7. `Footing` and `Respawn` need to be look at, but if it makes them actively
>    worse, we leave them alone. For `Respawn` my current read is that this
>    _can_ be separated rather easily with a signal: The Respawn notiifies that
>    a respawn happened, the node listens on it and triggers the flash
>    animation. Not sure if the same would work for the `Fooing` as well?

It followed a review of what caused the interaction-verbs rework. The old
`Interactor` found what to press by the target collider's `layer:`, so one
value answered "what does this collide as" and "can a hero press this". A node
holds one collider, so a chest could answer one verb.

## Goal

Every component in `RGame::Engine::Components` answers one question. Every
component that selects a node by what it may do to it selects by a component
on that node. A `build-components` skill says how to keep it so, and the next
component is built to it rather than fixed afterwards.

## Hard constraints

1. The engine layer stays pure Ruby and headless. Nothing here names a Core
   class.
2. The per-frame paths allocate nothing: `Targeting#_update`, `Grab#_control`,
   `AnimatedSprite#_update` and `#_draw`, `Blink#_update`, and a fall from its
   start to its end, `Shrink` included.
3. A split moves work between components. It does not change what a game
   draws. Every driven example and test project reports the same as on `main`,
   unless a step names the difference.
4. No split makes the order of `add_component` calls matter. That is one of
   the five checks in
   [write-plan](../../.claude/skills/write-plan/SKILL.md#the-same-question-as-a-review-of-existing-code).
5. The public API may break against 0.4.0 where the clean design needs it.
   There is no deprecation path, and every break gets a `Changed` or `Removed`
   entry in the changelog.

## Decisions already taken

Taken in conversation on 2026-09-29, and not up for re-litigation here:

1. **The clean design going forward decides, not what a fix is worth today.**
   A split that changes no game code is still in scope.
2. **This plan applies SOLID's S.** Later plans may add O, L, I and D, and the
   skill grows with them.
3. **Step 1 records the rough rule in CLAUDE.md**, as one sentence.
4. **The deliverable is a `build-components` skill**, linked from `write-plan`,
   and from `write-ruby-code` or `implement-step`.
5. **`Grab`, `Collectable` and `AnimatedSprite` are fixed**, and
   `AnimatedSprite` works without a `Mover`.
6. **`Footing` and `Respawn` are examined.** One that a split makes actively
   worse stays as it is.
7. **`Mover` stays as it is, flagged as the exception.** It answers where its
   step lands, and what else moves with it: what the step pushes, drags and
   carries, through three wirings. A split would put the second job in a
   sibling. That brings back the add-order dependence its header records for
   blocking, which constraint 4 refuses. No split that avoids it is known, and
   finding one is not worth the effort now. The skill and `Mover`'s own header
   say so, and the fold-back leaves a todo for a later look.
8. **`examples/quests_and_dialogue` talks through an `Interaction`.** Its
   header teaches starting a conversation by layer, which is the shape the
   rule forbids a component. See step 2c.
9. **The example of an animation with no `Mover` is a spinning coin in
   `examples/collectables`**, on a sheet authored here. See step 4c.

Taken in conversation on 2026-09-30, while re-planning step 6:

10. **`Footing` splits into `Footing`, `Fall` and a `FallLook`, designed as if
    the task were set today.** In the user's words: "What we want is a
    component-split that gets the job done, not one that preserves as much as
    possible from the current design." So step 6 no longer keeps the five
    `Footing.new` calls as they are, and the look may answer more than two
    methods. See [the design](#footing-finds-the-floor-a-fall-takes-the-node-out-of-play).
11. **The look is explicit.** A `Fall` shows the `FallLook` its node holds, and
    a node with none shows nothing as it falls. No default stands in for a
    missing look: "It should be explicit, not have some implicit fallback." A
    default would hide the look a game swaps out.

## Open questions

1. ~~**`examples/quests_and_dialogue` starts a conversation by layer.**~~
   **Settled: it talks through an `Interaction`.** See decision 8.
2. ~~**Which sheet animates without a `Mover` in an example?**~~ **Settled: a
   spinning coin in `examples/collectables`, on a sheet authored here.** No
   sheet in `examples/assets/` animates anything but the hero's walk, and no
   map outside the spec fixtures has an animated tile. The hero sheet, played
   by name on the spot in `examples/sprite`, was the other candidate. See
   decision 9.
3. ~~**`Mover`.**~~ **Settled: it stays out, flagged as the exception.** See
   decision 7.
4. **`TileWorld`.** The request does not list it, and decision 1 argues for
   it. It reads the map for solidity, occupancy, routes, gaps, bounds and the
   tile clock. It also keeps a registry of `Platform`s, the one thing it holds
   that is not read from the map. `Platform` registers there, and `Footing`
   and `GapBlockers` ask it which platform stands where. **Lean:** the
   registry is a later plan's question. Blocks nothing before step 7. Decide by
   the time step 7 is re-planned. A yes inserts rough steps before it, and a
   no, or no answer, moves it to `possible-todos.md` at step 8.
5. **A falling node can still be pushed.** Suspension stops a node's own
   components, not another node's mover. A hero walking into a crate pushed it
   from x 65 to 75 over the 10 ticks after it dropped *(measured at
   `91b7269`)*. Neither `Mover#pushable` nor `Pushable#push` asks whether the
   crate is suspended. The defect predates this plan, and the split neither
   causes nor cures it. **Lean:** a `Mover` pushes no suspended node, so a
   falling crate stops a hero as a fixed one does. That holds for a node a
   cutscene suspends too, which is why it is not the `Fall`'s job.
   `topdownplatformer`'s script holds right until about tick 416, and its
   crate drops on 414, so the fix may change that report. Blocks nothing in
   step 6. Decide before step 8, which otherwise moves it to
   `possible-todos.md`.

## What was measured before planning

At `78e99d0`, on Ruby 4.0.5 without YJIT. The two scratch specs are not
committed. Step 2 turns both into examples.

| | |
|---|---|
| `rake spec` | 4,525 examples, 0 failures, 39.5 s |
| Components | 43 files, 5,028 lines, in `lib/rgame/engine/components/` |
| `Grab`, with a fixed crate 12.8 px away and a `Pushable` one 25.3 px away, both on `:crate` | holds nothing: its target is the fixed crate *(measured)* |
| `Targeting.new(range: 64)`, no `layer:`, beside one other collider | targets its own node *(measured)* |
| `Targeting.new` outside specs and docs | 0 |
| `Grab.new` | 2, both `layer: :crate`: `examples/push_pull/main.rb:122`, `test_projects/adventure/hero.rb:65` |
| `Collectable.new` | 4. The 2 with `free: false` are both doors: `examples/doors/main.rb:115`, `test_projects/adventure/door.rb:31` |
| `on_hit` handlers in games that filter by layer | 6: `quests_and_dialogue` 2, `collision` 1, `asteroids` 3 |
| `AnimatedSprite.new` | 18: 13 in examples, 5 in test projects, each on a node with a `Mover` |
| Lines naming `AnimatedSprite` | `docs/api/` 21 in 5 pages, `lib/` 6 outside its own file, `examples/` 23, `test_projects/` 5 |
| Sheets in `examples/assets/` with an animation but a walk | 0 of 6 |
| Maps with an animated tile, outside spec fixtures | 0 |
| `Footing.new`, `Respawn.new` | 5 and 4. Every `Respawn` passes `flash:`, 1.0 three times and 0.5 once |
| Files naming `Respawn`'s flash | `respawn.rb`, `components.md`, `examples.md`, `examples/pits`, `examples/moving_platforms`, two `topdownplatformer` files, three drive scripts |
| A suspended node | `control` and `update` return at once, `draw` runs: `node2d.rb:516` and `:529` |
| Examples in the specs this plan changes | `grab` 15, `targeting` 6, `collectable` 17 (5 lines name `free: false`), `animated_sprite` 21, `respawn` 18, `footing` 25 |
| Allocation specs | none for `AnimatedSprite`, `Animator` or `AnimationSet`. `Respawn`'s flash in `respawn_spec`, `Footing` in `footing_allocation_spec`, `TileMap#frame_tile` in `tile_map_allocation_spec` |
| A component filter on each broadphase candidate | 26.0–28.5 µs a tick at 40 colliders, against 25.7 µs for a layer filter, 0 objects *(measured for interaction verbs at `117a423`; `git show 6526120:docs/plans/interaction-verbs.md`)* |
| Frame timing | `AnimationSet#col` divides elapsed time by an even frame length. `TileMap#frame_tile` searches cumulative end times (`tile_map.rb:259`) |

## What each component answers

The review read all 43 files.

**Two questions, fixed here:**

| Component | Its job | Its second job | The tell |
|---|---|---|---|
| `Grab` | hold a crate while a button is down | decide what may be held, by layer | picks by layer, then checks for a component |
| `Collectable` | notice a touch from `by:` | be taken: free the node | `free: false` turns the second job off |
| `AnimatedSprite` | draw a sheet's animation | pick a walk from a `Mover`'s heading | raises without a `Mover` it needs only for the second |
| `Respawn` | bring the node back to its point | blink it | its header: "and the flash that shows it has" |
| `Footing` | find the floor, and drop the node into a gap | shrink it as it falls | `fall:` must be positive, so the shrink cannot be turned off |

Step 6's re-plan found a third job in `Footing`: the fall itself, which takes
the node out of play and brings it back. `topdownplatformer`'s walker adds a
`Footing` only to ride the ring, and carries a fall it can never take.

`Collectable`'s `sound:` is not a second job. A game varies a pickup's sound
only by which one, and a keyword holds that. A game varies a blink or a shrink
in kind: a splash, a burn, a shimmer.

**Two questions, left:** `Mover`, as the flagged exception of decision 7, and
`TileWorld`, open question 4.

**One question**, including three that look busy:

- `Hop` reads its action and runs the arc, and `action: nil` separates the two.
- `Cutscene` takes the game and gives it back, for as long as it runs.
- `ThrustController` leaves firing out, and says so in its header.
- `ActionTrigger`, `BoxCollider`, `CameraFollow`, `CharacterBody`,
  `Checkpoint`, `CircleCollider`, `Collider`, `CollisionWorld`,
  `DespawnOffscreen`, `Facts`, `FactsDatabase`, `FeetCollider`, `Identity`,
  `Interaction`, `Interactor`, `MapTile`, `Navigator`, `OccupiesCell`,
  `Particles`, `PathFollow`, `Platform`, `PlayerController`, `Pool`,
  `Pushable`, `RandomSource`, `ScreenWrap`, `Sprite`, `Targeting`, `Timer`,
  `Tween`, `Velocity`, `WanderController`, `World`.

## Where a layer answers "may I"

Everything that reads a collider's `layer`:

| Reader | Asks | By | Verdict |
|---|---|---|---|
| `Mover` `blocked_by:` | what stops my step | the blocker's layer | fine: what a thing is |
| `Mover` `pushes:` | which blocker my step moves | layer, then a `Pushable` on it | fine: the contact picks the node, and a fixed crate on `:crate` is a wall |
| `Collectable` `by:`, `Checkpoint` `by:` | who takes me, whose point I set | the toucher's layer. `Checkpoint` then requires a `Respawn` | fine: narrows who acts |
| `on_hit` handlers in games | what touched me | the other collider's layer | fine |
| `Grab` `layer:` | which node I may hold | layer, and the `Pushable` only after picking | breaks the rule |
| `Targeting` `layer:` | which node I aim at | layer | breaks the rule |
| `CollisionWorld#nearest(layer:)` | a query, not a component | layer | fine. Its one caller, `quests_and_dialogue`, asks "may I talk" with it, and moves to an `Interaction` in step 2c |
| `examples/collectables`' `:interactable` | a name | none | a layer named after a verb. The chest's layer now only stops the hero |

The line it draws: **a layer says what a thing is, and may narrow who acts.
Choosing a node by what may be done to it chooses by a component.** `Grab` and
`pushes:` both check for a `Pushable`. Only `Grab` picks the nearest candidate
before checking, so a nearer fixed crate swallows a grab and never a push.

## Prior art

| Engine | What a thing collides as | What it offers | Playing an animation, and choosing one |
|---|---|---|---|
| Godot | `collision_layer` and `collision_mask`, bitmasks, several per body | groups, many per node | `AnimatedSprite2D.play(name)`; a script or an `AnimationTree` chooses |
| Unity | one layer per GameObject, and one tag | components, found with `GetComponent` | an Animator's state machine chooses; a clip plays |
| Bevy | collision groups in the physics crates | marker components, queried with `With<T>` | the game's own system advances an atlas index |
| Unreal | collision channels and object types | gameplay tags, a container per actor | an Animation Blueprint's state machine chooses |

They agree on both halves of the verdict. What a thing collides as is a
category, and what it offers is a set: groups, components, tags. None puts
the choice of animation inside the thing that plays it. None of them refuses a
selection by category either, so the rule stays a written one here too. No
cop can read "may I do X to that".

Sources: Godot [groups](https://docs.godotengine.org/en/stable/tutorials/scripting/groups.html),
[collision layers](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html#collision-layers-and-masks),
[AnimatedSprite2D](https://docs.godotengine.org/en/stable/classes/class_animatedsprite2d.html);
Unity [layers](https://docs.unity3d.com/Manual/Layers.html),
[tags](https://docs.unity3d.com/Manual/Tags.html),
[Animator Controller](https://docs.unity3d.com/Manual/class-AnimatorController.html);
Bevy [`With`](https://docs.rs/bevy/latest/bevy/ecs/query/struct.With.html);
Unreal [gameplay tags](https://dev.epicgames.com/documentation/en-us/unreal-engine/using-gameplay-tags-in-unreal-engine).

## Design

### `Grab` picks by `Pushable`, through `Targeting`'s `having:`

`Targeting` takes the component class a target must hold, in place of a layer,
and never picks its own node:

```ruby
class Targeting < Engine::Component
  POLICIES = %i[nearest].freeze

  # `having` is the component class, or module, a target's node must hold:
  # what the owner may do to a target is a component on it, never its layer.
  # Raises ArgumentError for an unknown policy, and for a `having` that is not
  # a Module.
  def initialize(range:, having:, policy: :nearest)

  sealed_reader :target
end
```

`CollisionWorld#nearest` gains the two filters that `Targeting#pick` passes
through, beside the `layer:` a query keeps:

```ruby
# `having` keeps only colliders whose node holds that component, and `except`
# leaves out one node, such as the asker's own. Allocation-free.
def nearest(x, y, r, layer: nil, having: nil, except: nil)
```

`Grab` and `Interactor` pass their own component. The `Interactor` keeps its
own pass and ignores `policy:` as before. That is an L problem, for a later
plan.

```ruby
class Grab < Targeting
  def initialize(range:, action: :grab, policy: :nearest)
    super(range:, policy:, having: Pushable)
```

```ruby
add_component(Components::Grab.new(range: GRIP, layer: :crate))   # at 78e99d0
add_component(Components::Grab.new(range: GRIP))                   # after
```

### `Collectable` takes its node, and a door says what it does

`Collectable.new(by:, sound: nil)` always frees its node. The flag's only
callers were doors, and a door connects its own collider:

```ruby
# at 78e99d0
add_component(Components::BoxCollider.new(width:, height:, offset_x: -width / 2.0, offset_y: -height,
                                          layer: :door))
add_component(Components::Collectable.new(by: :hero, free: false)).on_collected { move(it.node) }

# after
add_component(Components::BoxCollider.new(width:, height:, offset_x: -width / 2.0, offset_y: -height,
                                          layer: :door))
  .on_hit { |other| move(other.node) if other.layer == :hero }
```

`examples/quests_and_dialogue`'s signpost already does it this way.

### `AnimatedSprite` plays; `WalkingSprite` walks

**The sprite plays what it is given.** A subclass chooses through a hook,
which the sprite calls in its own `_update` before it advances the frame. So
the choice and the frame land on the same tick, whatever order the node's
components were added in. A sibling component calling `play` could not do
that. See [Considered and rejected](#considered-and-rejected).

```ruby
class AnimatedSprite < Engine::Component
  include Engine::Culling

  hook :_choose_animation

  # `animation` is the one it plays first. Attach raises ArgumentError when
  # the sheet has no animation of that name, listing the ones it has.
  def initialize(sheet:, animation:, z: 0, anchor: :bottom)

  # The animation playing now.
  def animation

  # Plays `name` from its first frame, or carries on when `name` is already
  # playing. Once attached, raises ArgumentError for a name the sheet lacks.
  def play(name)

  # The animation to play this update, or nil to carry on. A subclass answers
  # from its node's state, and the frame it picks draws on the same tick.
  def _choose_animation = nil
end

# Plays walk_left, walk_right, walk_up or walk_down while its node's Mover
# heads somewhere, and stand while it does not.
class WalkingSprite < AnimatedSprite
  def initialize(sheet:, z: 0, anchor: :bottom)
    super(sheet:, animation: :stand, z:, anchor:)
  end

  def _choose_animation = ...   # AnimatedSprite#walk_animation at 78e99d0, moved
end
```

```ruby
add_component(Components::AnimatedSprite.new(sheet: 'hero.json'))   # at 78e99d0
add_component(Components::WalkingSprite.new(sheet: 'hero.json'))    # after

add_component(Components::AnimatedSprite.new(sheet: 'coin.json', animation: :spin, anchor: :center))   # new
```

**Sprites share their frame timing with the map's animated tiles, and nothing
else.** Both ask which frame of a looping sequence shows after some seconds.
`AnimationSet#col` answers with even frames, and `TileMap#frame_tile` with a
duration per frame. One class answers for both, so a sheet with per-frame
durations, or an animation that plays once, is one change rather than two.
The rest stays apart on purpose:

- **The clock.** A map's tiles run on `TileWorld`'s one clock, so water ripples
  in step and pauses with the world. An actor's animation restarts when it
  changes.
- **The frames.** A tile animation's frames are tile ids. A sheet's are cells
  of a row.
- **The component.** `MapTile` already draws an animated tile on a node, for
  an object a designer placed in Tiled.

```ruby
# Which frame of a looping sequence shows after some seconds. A sheet's
# animation and a map's animated tile both ask it. Each keeps its own clock
# and its own frames, and hands in only the seconds.
#
# @api private
class FrameTimes
  # `count` frames of `seconds` each: a sheet's animation at its fps.
  def self.even(count, seconds)

  # One duration a frame, in seconds: a Tiled tile's animation.
  def initialize(durations)

  # The frame showing after `elapsed` seconds. It loops, and at a frame's exact
  # end the next one shows. Allocates nothing.
  def index_at(elapsed)

  # Seconds one loop takes.
  attr_reader :length
end
```

An even sequence divides, as `AnimationSet` does at `78e99d0`, rather than
summing end times. At 6 fps a frame lasts 1/6 s, which a Float cannot hold
exactly, and summing could move a frame change by a tick.

### `Blink`, started from `on_respawned`

**The user's read holds.** `Fall#land` resumes the node before it calls
`Respawn#respawn`, so a component on the node updates from that tick on. The
blink leaves `Respawn` and becomes a component a game starts from the signal
`Respawn` already emits. A hit that makes a hero blink starts the same
component.

```ruby
class Blink < Engine::Component
  # Seconds one blink shows the node, and seconds it hides it.
  INTERVAL = 0.1

  def initialize(interval: INTERVAL)

  # Blinks the node's opacity for `seconds`, shown first, then gives back the
  # opacity it found. A blink under way starts again, and still gives back the
  # opacity it found first.
  def start(seconds)
  def stop
  def blinking?
end
```

```ruby
add_component(Components::Respawn.new(flash: 1.0))                        # at 78e99d0

blink = add_component(Components::Blink.new)                               # after
add_component(Components::Respawn.new).on_respawned { blink.start(1.0) }
```

`Respawn` keeps its point, `set_point`, `respawn` and `on_respawned`, and
loses `flash:`, `flashing?`, `BLINK` and its `_update`.

### `Footing` finds the floor; a `Fall` takes the node out of play

Re-planned at `91b7269`, for decision 10. Three components, one question each:

| Component | Answers | A game changes it for |
|---|---|---|
| `Footing` | what the node stands on, and when standing on nothing drops it | a longer grace, a platform to ride |
| `Fall` | how long the node is out of play, and what happens then | a longer fall, a fall from a cutscene or a trapdoor |
| a `FallLook`, such as `Shrink` | what the fall looks like | a splash, a burn, a sink |

**Riding stays in `Footing`.** Boarding tells the platform what the node stands
on, and `Platform` does the carrying.

**A falling node is suspended, and a suspended node stops its own
components.** `Node2D#update` returns at once for it (`node2d.rb:529`). So a
look on the node cannot count the fall's time itself. The `Fall` runs it from a
node lent to the falling node's parent, as `Engine::Fall` runs the shrink at
`91b7269`. A suspended node still draws, so a look may draw what it likes in
`_draw`.

**Each piece finds the next by its class, as the fall finds `Respawn` today.**
`Footing` starts the node's `Fall` as the node loses its footing. The `Fall`
shows the node's `FallLook`, and ends with its `Respawn`. Each looks the next
one up when it needs it. So no add order matters, nothing is wired by hand,
and a game removes a piece to switch it off:

- a node with no `Fall` stands over the gap, riding what it rode;
- a fall with no look shows nothing while the node holds still;
- a fall with no `Respawn` frees the node.

Nothing stands in for a missing piece (decision 11).

**A falling node rides nothing.** A `Footing` never drops a node that stands on
a platform, but a cutscene can start a fall there. So `Fall#start` has the
node's `Footing`, if it has one, leave its platform, as `Footing#drop` does at
`91b7269`. It is the one call from `Fall` back to `Footing`.

```ruby
# What its node stands on: the ground, a Components::Platform it rides, or a
# gap. It watches the centre of the node's BoxCollider box against the scene's
# TileWorld. A node that stands over a gap for more than `coyote` seconds, out
# of the air, loses its footing, and its Fall starts, if it has one.
class Footing < Engine::Component
  SLACK = 1e-9

  sealed_reader :coyote

  # The Components::Platform the node rides, or nil.
  sealed_reader :platform

  # `coyote` is in seconds, 0 or more, or it raises ArgumentError.
  def initialize(coyote: 0.1)

  def coyote=(seconds)
  def standing?

  # Seconds of coyote time left: `coyote` while standing, counting down off
  # the floor, and 0 in the air and once the node has lost its footing.
  def coyote_left
end
```

```ruby
# Takes its node out of play for `duration` seconds, then brings it back. It
# suspends the node and shows its FallLook, if it has one. At the end it hands
# the node to its Respawn, or frees a node with none.
#
# A Footing starts it as the node walks into a gap, and a game or a cutscene
# can start one anywhere. It answers on_finished and finish, so a cutscene's
# `hold` step waits on it.
class Fall < Engine::Component
  # Fired as the fall starts, which is where a game takes a life.
  signal :fell

  # Fired once the fall has ended: the node stands on its respawn point, or
  # is freed.
  signal :finished

  sealed_reader :duration

  # `duration` must be a positive number of seconds, or it raises ArgumentError.
  def initialize(duration: 0.4)

  # Starts a fall, and returns self. Does nothing during a fall. Raises for a
  # node outside the tree.
  def start

  # Ends a fall under way as its end would: the node comes back or is freed.
  # Does nothing when none is under way.
  def finish

  def falling?
end
```

```ruby
# What a fall looks like. Its node's Fall calls #start as the fall starts,
# #show every tick with how far through the fall it is, from 0 to 1, and
# #finish once as it ends, however it ends. The node is suspended all the
# while, so a look never counts time itself. It may draw in `_draw`, which a
# suspended node still runs.
class FallLook < Engine::Component
  def start; end
  def show(progress); end
  def finish; end
end

# Shrinks its node toward its origin, where it stands, easing in, and gives
# back the scale it found.
class Shrink < FallLook
  def start = @rgame_found = node.scale
  def show(progress) = node.scale = @rgame_found * (1 - (progress * progress))
  def finish = node.scale = @rgame_found
end
```

`FallLook`'s three methods are plain names, not hooks. The `Fall` calls them
through an interface, as a `Menu` calls its navigation's.

```ruby
add_component(Components::Footing.new(coyote: COYOTE))                    # at 91b7269
blink = add_component(Components::Blink.new)
add_component(Components::Respawn.new).on_respawned { blink.start(1.0) }

add_component(Components::Footing.new(coyote: COYOTE))                    # after
add_component(Components::Fall.new)
add_component(Components::Shrink.new)
blink = add_component(Components::Blink.new)
add_component(Components::Respawn.new).on_respawned { blink.start(1.0) }
```

```ruby
TRAPDOOR = Engine::Cutscene::Script.build do
  run { |c| c.open_trapdoor }
  hold { |c| c.hero.get_component(Components::Fall).start }   # a skip respawns the hero
end
```

What a game can do, before and after:

| | At `91b7269` | After |
|---|---|---|
| A hero that falls and comes back blinking | 3 components | 5 |
| A different look | impossible | its own `FallLook` in place of `Shrink` |
| A look that draws, such as a splash | impossible | `_draw` on the look |
| Riding with no fall, as the walker does | carries a fall it never takes | `Footing` alone |
| A fall from a cutscene or a trapdoor | impossible: `Footing#drop` is private | `Fall#start` |
| Hovering over gaps while still riding | impossible | no `Fall` |
| A node at scale 2 | falls from 0.999 and comes back at 1 *(measured)* | falls from 2 and comes back at 2 |
| Taking a life | `Footing#on_fell` | `Fall#on_fell` |

**The cost is two lines on every node that falls.** A missing one shows on the
first fall and nowhere else. Without a `Fall` the node stands over the gap.
Without a look it holds still, then comes back.

### The `build-components` skill

Written last, from what steps 2–6 found, per
[write-skill](../../.claude/skills/write-skill/SKILL.md). What it is expected
to hold, each line subject to write-skill's cut:

- **One job is one question**, and the test for two: would two games change it
  for two different reasons?
- **The tells, each with the mistake behind it:**
  - a flag that turns half of it off (`free: false`);
  - a header whose first sentence joins two jobs with "and" (`Respawn`'s);
  - one value that several readers ask different questions of (`layer`);
  - a look built into a mechanic (the flash, the shrink);
  - a sibling required for only one of its jobs (`AnimatedSprite`'s `Mover`);
  - a node that holds a component for one of its jobs (the walker's `Footing`
    rides, and never falls).
- **No default for a missing sibling.** A component uses the sibling that does
  a job, and does nothing in its place when there is none (`Fall` and
  `FallLook`, decision 11).
- **The counterweight.** Some things are not a second job:
  - feedback a game varies only by value (`sound:`);
  - an input action as a default (`Hop`'s `action:`);
  - broad inside, where a split would make add order matter (`Mover`, the
    named exception, with decision 7's reason);
  - cohesive around one lifetime (`Cutscene`).
- **How to split, by where the second half runs:**
  - a signal, when it runs on a node that updates (`Blink`);
  - a hook, when the choice must land in the same update as what it drives
    (`WalkingSprite`);
  - a sibling the owner drives, when the node is suspended (`FallLook`, run by
    `Fall`).

  The shape to avoid is a sibling writing into another in the same phase.
- **Layers against components.** It links CLAUDE.md's rule, and adds that a
  layer may narrow who acts (`blocked_by:`, `by:`).
- **write-plan's five interface checks move here.** They are checks on
  components. `write-plan` and CLAUDE.md's "Before building" link to them.

## Considered and rejected

- **Keep `Targeting`'s `layer:` beside `having:`.** A turret narrowing to
  `:enemy` reads naturally, and 0.4.0's constructor keeps working. But `layer:`
  alone is the shape of the `Grab` bug, and offering it invites the bug. A game
  that narrows further holds a component of its own, even an empty one.
- **`Grab` runs its own broadphase pass, as the `Interactor` does.** That would
  be a second copy of `nearest`'s running minimum. `having:` serves `Grab` and
  a turret alike.
- **A `Touch` component for doors, `Touch.new(by: :hero).on_touched { ... }`.**
  The layer filter would be a required keyword, so a door could not forget it.
  `Collectable` and `Checkpoint` could build on it too. But its whole job is
  one `if` over data `on_hit` already hands over, and six hand-written filters
  show games write it without trouble. Revisit if a bug traces to a missing
  filter.
- **`AnimatedSprite` walks by default when its node has a `Mover`.** Every
  caller would stay as it is. But what it does would depend on whether a
  sibling exists, and write-plan's checks refuse that.
- **Walking as a sibling component that calls `play`.** It is pure
  composition. But the choice and the frame would then advance in two
  `_update`s, so the order of adds decides whether a new animation shows its
  first tick. `Mover`'s header records the same order dependence for a
  `Blocking` sibling.
- **A chooser object handed in, `AnimatedSprite.new(animation: WalkCycle.new)`.**
  It needs no subclass. But it is a second interface for what a hook already
  does in this codebase (`Mover#take_step`, `UI::Button`'s focus hooks). And a
  game's own chooser would need a way to reach the node, which a hook has for
  free.
- **One clock for sprites and tiles.** Map tiles share the world's clock so
  they move in step and pause with the world. An actor's animation restarts on
  each change.
- **`Respawn` keeps `flash:` as a shortcut to a `Blink`.** That is two ways to
  blink, and blinking code in `Respawn` again.
- **`Footing` emits the fall's progress each tick, and a listener draws the
  look.** A listener is a block, so it runs while the node is suspended, and
  this is the user's signal approach. But a block cannot draw. It keeps no
  state but what it closes over, so giving back the scale it found takes a
  variable of the game's. A `FallLook` is a component: it draws, keeps its own
  state, and the `Fall` finds it with no wiring.
- **The look handed to the `Fall`, `Fall.new(look: Shrink)`.** It was step 6's
  first sketch, on `Footing`. It needs no base class, and no add order touches
  it. But the look sits outside the tree, so it cannot draw a splash. Swapping
  it means building the `Fall` again. A component is how this engine already
  says what a node has.
- **A default `Shrink` for a node with no look.** Every falling node would
  need one line fewer. Decision 11 refuses it: what a `Fall` shows would depend
  on whether a sibling exists. That is why `AnimatedSprite` does not walk by
  default.
- **The look as a subclass of `Fall`, through hooks,** as `WalkingSprite`
  subclasses `AnimatedSprite`. A node would need one component, not two. But
  the class a game adds would do both jobs again. `WalkingSprite` needs a hook
  because its choice must land in the same update as the frame. Here the `Fall`
  calls the look itself, so no order needs protecting.
- **Looks that run through a suspension**, flagged on their class. A look could
  then count its own time, as `Blink` does. But a suspend would stop only part
  of a node, chosen by a flag every component carries. And a look's time is
  the fall's: its progress is how far the fall has run.
- **A fall that stops the node's movers instead of suspending it.** The look
  could then run on the node. But every mover, controller and `Hop` would have
  to ask whether its node is falling. `suspend` exists to spare them that
  rule.
- **The game wires `Footing` to `Fall`,** as it starts a `Blink` from
  `on_respawned`. It is the plainest composition. But a `Fall` is what a gap
  under a `Footing` is for, and a missing wire leaves the node standing on
  air. A lookup by class needs no wire, as the fall's lookup of `Respawn`
  needs none.

## What this does not deliver

- **A split of `Mover`.** It stays whole, flagged as the exception (decision
  7).
- **`TileWorld`**, unless open question 4 says otherwise.
- **O, L, I and D.** The `Interactor` takes `policy:` and ignores it. A node
  holding a `Grab` and an `Interactor` cannot ask `get_component(Targeting)`
  for either. Both are for later plans.
- **Sheet animations with a duration per frame, or that play once.**
  `FrameTimes` makes each one change, and nothing asks for either.
- **A connection that ends with its node.** `Collectable` and `Checkpoint`
  still disconnect from their collider by hand. `possible-todos.md` holds it.
- **A `FallLook` that plays a sheet's animation.** `AnimatedSprite` advances in
  its node's update, which a fall suspends. A look that shows frames draws them
  itself, from `progress`.
- **A look alone, outside a fall.** A cutscene reuses the whole `Fall`, and
  nothing but a `Fall` runs a `FallLook`.
- **A crate that cannot be pushed while it falls.** Open question 5.

## Roadmap

```
1 the rule ─→ 2 Grab by Pushable ─┐
              3 Collectable ──────┤
              4 AnimatedSprite ───┼─→ 7 build-components ─→ 8 fold back
              5 Blink ─→ 6 Fall ──┘
```

Steps 3, 4 and 5 depend on nothing before them. Step 6 follows 5, because
both change what happens as a fall ends. Step 7 waits for all of them,
because the skill is written from their landed notes.

> **A split moves work between components. It does not change what a game
> draws.** Every drive report matches `main`'s, except where a step names the
> difference.

Worth landing even if the plan stops early:

| Step | Closes |
|---|---|
| 1 | a rule that exists nowhere, so the next component repeats the mistake |
| 2 | `Grab` holding nothing behind a nearer fixed crate, and `Targeting` aiming at its own node |
| 3 | two doors that are "collected" |
| 4 | a sprite animation that cannot exist without a `Mover` |
| 5 | a blink that only a respawn can start |
| 6 | a fall that only a gap can start, a look no game can change, and a node at scale 2 that comes back at 1 |

### Step 1 — The rule, in CLAUDE.md

Every component written while this plan runs is subject to the rule, and
step 2 applies it, so it goes first. It is one sentence.

A subsection of CLAUDE.md's "Design out misuse", after "A name says which
mechanism it is":

```markdown
### What a node offers is a component, not a layer

**A component asking "may I do X to that node?" checks for a component on the
node, never for its layer**: a node has one layer, and can offer many things.
```

**Tests:** none. No code changes.

**Verify:** `git diff --stat main` lists CLAUDE.md alone.

**Landed.** The branch is `component-not-layer`, in one commit. The subsection
follows "A name says which mechanism it is", worded as sketched. At that
commit, `git diff --stat main` lists `CLAUDE.md` alone, with 5 lines added. No
spec reads CLAUDE.md. `rake spec` passes 4,525 examples, as at planning.

- **The Verify line holds for the commit, not the branch.** This note adds the
  plan to the branch's diff, in a commit of its own.
- **No skill states the rule.** Nothing under `.claude/skills/` weighs a layer
  against a component, so CLAUDE.md holds the rule alone until step 7 links
  it.

### Step 2 — `Targeting#having`, and a `Grab` that picks by `Pushable`

The rule's first application, and the only live bug the review found.

- **2a. The engine and its two callers.** `Targeting` takes `having:` in place
  of `layer:`. `CollisionWorld#nearest` takes `having:` and `except:`. `Grab`
  passes `Pushable`, the `Interactor` passes `Interaction`, and `Grab` loses
  `layer:`. `examples/push_pull` and `test_projects/adventure/hero.rb` follow
  in the same commit, or the tree is red between the two.
- **2b. Docs and changelog.** `components.md`'s `Targeting`, `Grab` and
  `CollisionWorld` sections, and every other line in `docs/api/` naming
  `Targeting`'s `layer:`. The changelog's `Grab` entry is unreleased, and is
  checked for `layer:`. `Targeting` shipped in 0.4.0 and gets a `Changed`
  entry. `examples/collectables` renames its chest's layer from
  `:interactable` to `:chest`, and its header's sentence about `blocked_by`
  follows.
- **2c. `examples/quests_and_dialogue` talks through an `Interaction`**
  (decision 8). The hero gets an `Interactor` reading `ui_confirm` within
  `TALK_RANGE`. The smith becomes a `Smith`, whose `Interaction` answers
  `ui_confirm` with `talk`. The village starts the conversation when the smith
  says it was hailed, and its `_control` loses the `nearest` query. The
  header's "the two ways a conversation starts" and the example's entry in
  `docs/api/examples.md` follow. `CollisionWorld#nearest` then has no caller
  in the examples, and `components.md` still documents it.

The shape of 2a and 2b is in
[the design](#grab-picks-by-pushable-through-targetings-having). The smith of
2c:

```ruby
# The smith. Enter within the hero's reach calls `talk`, and the village,
# which holds the conversation, hears it as `hailed`.
class Smith < Thing
  signal :hailed

  def initialize(**)
    super(size: 24, layer: :npc, **)
    add_component(Components::Interaction.new(ui_confirm: :talk))
  end

  def talk = hailed_signal.emit
end

# in Village#build_village
add_node(Smith.new(color: SMITH_COLOR, x: 320, y: 150)).on_hailed { talk_to_smith }
```

The smith keeps `:npc`, because the hero is `blocked_by` it. The `Interactor`
measures from the hero's origin to the smith's box centre, as the `nearest`
query did, and leaves out the hero's own node.

**Rules:**

1. `Targeting` picks the nearest node holding `having`, and passes over a
   nearer node that holds none.
2. `having` matches by `is_a?`, as `get_component` does, so a module such as
   `Collider` or a base class such as `Mover` matches every node holding one.
   A node holding two matches is one candidate, not a raise.
3. `Targeting` never picks its own node, whatever it holds.
4. `having:` is required, and must be a Module. Anything else raises
   `ArgumentError` at construction.
5. `Grab` holds the `Pushable` behind a nearer node on the same layer that has
   none.
6. `Grab.new(layer: :crate, range: 24)` raises `ArgumentError`.
7. `Targeting#_update` allocates nothing with `having` set, and neither does
   `Grab#_control`.

**Tests:**

- `spec/rgame/engine/components/targeting_spec.rb`: its six examples lose
  `layer:`. Rules 1–4 and 7 are added.
- `spec/rgame/engine/components/collision_world_spec.rb`: `nearest` with
  `having:`, with `except:`, and both allocating nothing.
- `spec/rgame/engine/components/grab_spec.rb`: `hero_at` drops `layer:`.
  Rules 5 and 6 are added, 5 from the scratch spec.

**Verify:** rule 5 passes where the scratch spec failed. `push_pull`,
`adventure` and `collectables` report the same as on `main`. So does
`quests_and_dialogue` under `--texts`, "Any work going?" from tick 143 among
the rest of its script's list. If the conversation now starts a tick later,
the step says so, and the script's header follows. `rake spec`,
`rake spec:core` for the docs' references, and `rake drive:allocations` are
green.

**Landed.** The branch is `targeting-having`, with one commit per sub-step.
`Targeting.new(range:, having:, policy: :nearest)` and
`CollisionWorld#nearest(x, y, r, layer: nil, having: nil, except: nil)` are as
sketched. `Grab.new(range:, action: :grab, policy: :nearest)` passes
`Pushable`, and the `Interactor` passes `Interaction`. `rake spec` passes 4,540
examples, 15 more than `main`: 8 in `targeting_spec.rb`, which has 14, 4 in
`collision_world_spec.rb`, 2 in `grab_spec.rb`, and the `Targeting` example in
`components.md`. `rake spec:core` passes 555. `rake drive:allocations` passes
all 44 projects.

Rule 5's example fails where the scratch spec failed. With `having: Collider`
in place of `Pushable`, `Grab` targets the fixed crate as `main` did, and the
example reports `[110.0, 100.0, nil]`: the hero walked, the crate stayed, and
nothing was held. Driven with `--seed 4242 --texts`, `push_pull`,
`collectables`, `adventure` and `quests_and_dialogue` report the same as `main`,
line for line. "Any work going?" shows for 23 frames from tick 143, so the
`Interactor` starts the conversation on the tick the `nearest` query did, and
the script's header stands.

- **`get_component` could not be the filter.** Rule 2 makes a node holding two
  matches one candidate, and `get_component` raises on two. `nearest` asks
  `node.components.none?(having)`, which matches by `is_a?` through
  `Module#===` and allocates nothing. `Node2D` needed no new method.
- **Rules 4 and 6 needed no code for `layer:`.** Ruby raises `ArgumentError`
  for an unknown keyword, so `Targeting` and `Grab` refuse `layer:` because
  they no longer name it. `Targeting` checks only that `having` is a Module.
- **`quests_and_dialogue` allocates one object more over its run**: 1,862
  against 1,861, on 47 ticks against 44, under a budget of 120 a second. The
  traces put the new ones at Ruby filling call caches the first time the
  `Interactor`, `Interaction#perform` and the signal run, where `main` filled
  them for `nearest`. `adventure` allocates 2,007 against 2,005, on the same 60
  ticks. `push_pull` and `collectables` allocate the same as `main`.
- **The changelog's `Grab` entry named no layer**, so it stayed as it was.
- **Two lines the plan did not list changed.** A comment in `collectables`
  called a node with an Interaction "an interactable", and now says what it
  means. The village's `@collision` lost its only reader, and went.
- **For step 4: a worktree of `main` needs `media/` to compare against.** It is
  gitignored, and without it `adventure` plays a stand-in track, so the two
  reports differ in their music lines. Both runs must also draw every tick. One
  pair of runs each drew 1,639 frames of 1,640 and differed in draw counts. A
  rerun drew all 1,640 and matched.

Documented in `docs/api/components.md` under `Targeting`, with an example the
doc specs run, and under `Grab` and `CollisionWorld`. `docs/api/examples.md`
follows for `collectables` and `quests_and_dialogue`, and `CHANGELOG.md` has a
`Changed` entry for `Targeting`.

### Step 3 — `Collectable` takes its node, and doors say what they do

`free: false` turns half of `Collectable` off, and both of its callers are
doors, which read as "collected". No sub-steps: one commit.

- `Collectable.new(by:, sound: nil)`. Its header loses the chest and the door.
- `examples/doors` and `test_projects/adventure/door.rb` connect their
  collider's `on_hit`, as in [the design](#collectable-takes-its-node-and-a-door-says-what-it-does).
- `components.md`'s `Collectable` section loses the chest example and "`free:
  false` is the chest". `tile_maps.md`'s door example, `examples.md`'s `doors`
  entry and the `doors` header follow. The changelog's entry is unreleased and
  loses "unless `free: false`".

**Rules:**

1. `Collectable.new(by: :hero, free: false)` raises `ArgumentError`.
2. A touch from `by:` emits `collected`, plays the sound and frees the node,
   as at `78e99d0`.

**Tests:** `spec/rgame/engine/components/collectable_spec.rb` loses its
`free: false` examples, and gains rule 1. Rule 2 is already pinned.

**Verify:** `doors` and `adventure` report the same as on `main`. `rake spec`
and `rake spec:core` are green.

**Landed.** The branch is `collectable-takes-its-node`, in one commit.
`Collectable.new(by:, sound: nil)` and both doors are as sketched. `rake spec`
passes 4,539 examples, one fewer than `main`: `collectable_spec.rb` has 16, down
from 17. `rake spec:core` passes 555, and `rake drive:allocations` passes all 44
projects.

Driven with `--seed 4242 --texts`, `doors` (900 ticks) and `adventure` (1,640)
report the same as `main`, line for line. Each run goes through a door: `doors`
moves the hero five times, and `adventure` crosses from the town to the garden.
With `_detach`'s disconnect removed, the pooled coin reports 3 collections in
place of 2. With `queue_free` removed, 3 examples fail.

- **Rule 1 needed no code.** Ruby raises `ArgumentError` for an unknown
  keyword, as for step 2's `layer:`.
- **Three of the spec's `free: false` examples used it only to keep a coin.**
  "Fires once" keeps its check with the coin freed. It still passes with
  `queue_free` removed, so it pins the edge, not the free. The pooled-node
  example takes a coin from a `Pool` twice, now the only way a `Collectable` is
  taken twice. The chest the `Interactor` opens holds no `Collectable`, and a
  coin inside it keeps the two components in one scene. Two chest examples
  replace three, and "keeps it with free: false" went.
- **The header keeps one sentence on a thing touched and kept**, where the plan
  said it loses the door. It says such a thing connects `on_hit`, so a reader
  looking for `free:` learns where it went. `components.md` shows a door's
  `on_hit` in place of the chest.
- **Three lines the plan did not list used a chest as a square collectable**:
  `Collectable`'s header, `Collider`'s, and `components.md`'s `Collider`
  section. They say "a key" now. The `doors` drive script's header gave "no
  sound" as the reason a door plays nothing, and now says only that it plays
  nothing.
- **`adventure` allocates 41 objects fewer, on 2 more ticks**: 1,966 against
  2,007, on 62 ticks against 60, under a budget of 90 a second. Ticks 1,032 and
  1,214 each allocate one object, untraced. `doors` allocates 580 against 628,
  on the same 16 ticks, since a door no longer builds a `Collectable`.
- **For step 4: tracing inside the allocation probe froze the machine twice.**
  The probe runs with GC off, and a patch calling `ObjectSpace.dump_all` on
  every tick grew memory until the machine hung. Trace from the probe's own
  list of sites, or with one dump at the end of the run.

Documented in `docs/api/components.md` under `Collectable` and `Collider`,
`tile_maps.md`'s door, and `examples.md`'s `doors` entry. `CHANGELOG.md`'s
unreleased `Collectable` entry loses "unless `free: false`".

### Step 4 — `AnimatedSprite` plays what it is given, and `WalkingSprite` walks

The largest caller sweep, 18 constructions, and independent of steps 2 and 3.

- **4a. `Engine::FrameTimes`.** `AnimationSet` and `TileMap` answer "which
  frame" through it. No caller changes.
- **4b. `AnimatedSprite` and `WalkingSprite`.** The 18 constructions become
  `WalkingSprite` in the same commit.
- **4c. Docs, an example and the changelog.** `components.md` gains a
  `WalkingSprite` section and rewrites `AnimatedSprite`'s. So do the 21 lines
  in `docs/api/` and the 6 in `lib/` that name it. The changelog gets a
  `Changed` entry, since `AnimatedSprite` shipped in 0.4.0.

  `examples/collectables`' coin spins (decision 9). A sheet authored here,
  `examples/assets/coin.png` and `coin.json` with one `spin` animation, is
  recorded in `examples/assets/README.md`, whose file count follows. The coin
  draws it with `AnimatedSprite.new(sheet: 'coin.json', animation: :spin,
  anchor: :center)` in place of its circle, and its collider stays as it is.
  The example's header and `docs/api/examples.md` name `AnimatedSprite`
  among what it exercises.

The shapes are in [the design](#animatedsprite-plays-walkingsprite-walks).

**Rules for 4a:**

1. An even sequence answers what `AnimationSet#col` answers at `78e99d0`, on
   every tick of 10 s at 60 ticks a second, at 1, 6 and 8 fps.
2. A varied sequence answers what `TileMap#frame_tile` answers at `78e99d0`,
   over the same ticks, for `tile_map_spec`'s animated tile.
3. `index_at` loops, and at a frame's exact end shows the next frame.
4. `index_at` allocates nothing on any frame of a loop, even or varied.

**Rules for 4b:**

1. `AnimatedSprite` draws `animation` on a node with no `Mover`.
2. `play(name)` restarts `name` from its first frame. Playing the current
   animation carries on.
3. A name the sheet lacks raises `ArgumentError`: at attach for `animation:`,
   and at `play` once attached. The message lists the sheet's animations.
4. What `_choose_animation` returns draws on the same tick.
5. `WalkingSprite` faces as `AnimatedSprite` does at `78e99d0`. Every heading
   example in `animated_sprite_spec` moves over unchanged.
6. `WalkingSprite` raises at attach without a `Mover`, and with two.
7. `_update` and `_draw` allocate nothing, for both classes, on every frame of
   a walk and while standing.

**Tests:**

- `spec/rgame/engine/frame_times_spec.rb`: rules 1–4 of 4a.
- `spec/rgame/engine/components/animated_sprite_spec.rb` keeps its drawing and
  culling examples, and gains rules 1–4 of 4b.
- `spec/rgame/engine/components/walking_sprite_spec.rb` takes the heading
  examples, and rules 5–6.
- `spec/rgame/engine/components/animated_sprite_allocation_spec.rb`, new,
  covers rule 7. Nothing measures an animated sprite's allocations today but
  `rake drive:allocations`.

**Verify:** every project with a walker reports the same as on `main`, with
`--seed` where its script asks for one:

- examples: `walk`, `collectables`, `collision_tiles`, `game_menu`,
  `moving_platforms`, `cutscene`, `cutscene_skip`, `doors`, `input_glyphs`,
  `pits`, `split_screen`, `jump_topdown` and `pathfinding`;
- test projects: `adventure`, `topdownplatformer` and the `tiled_world`
  scripts.

`rake drive:allocations` is green.

`collectables` is the named difference. Each coin draws a `sprite` where it
drew a `circle`, and the coin's frame moves on as it spins. Everything else
in its script's header holds, "Coins: 0" through "Coins: 4" at the same ticks
included, and the header says what changed.

**Landed.** The branch is `walking-sprite`, with one commit per sub-step.
`AnimatedSprite.new(sheet:, animation:, z: 0, anchor: :bottom)` with
`animation`, `play` and `_choose_animation`, and
`WalkingSprite.new(sheet:, z: 0, anchor: :bottom)`, are as sketched.
`FrameTimes` differs, below. `rake spec` passes 4,563 examples, 24 more than
`main`: 8 in `frame_times_spec.rb`, 13 in `walking_sprite_spec.rb`, 4 in
`animated_sprite_allocation_spec.rb` and 2 for `coin.json`, less 3 in
`animated_sprite_spec.rb`, which has 18. `rake spec:core` passes 555, and
`rake drive:allocations` passes all 44 projects.

Driven with `--seed 4242 --texts`, and `--seed 1` for `topdownplatformer`,
every walker reports the same as `main`, line for line: the 13 examples, the
`cutscene_skip` script, `adventure`, `topdownplatformer`, and `tiled_world`
under all six of its scripts. `collectables` differs as named. Its 1,287
`circle` draws are 1,287 `coin.json` sprites, and the `sprite` line's columns
run 0 to 7 where the hero's walk reaches 5. The texts, their ticks and the 4
sounds are unchanged. An even `FrameTimes` that searched ends made by
multiplying, instead of dividing, failed rule 1 at 6 fps, as the plan
predicted. The allocation spec fails all 4 examples with an Array made in
`_draw`, and only the turning walker's with one made in `play`.

- **`FrameTimes.new` takes each frame's end, not its duration.** `TileMap`
  holds ends that `from_tiled` works out from whole milliseconds, and adding
  the seconds up moves one: 0.1 + 0.25 + 0.05 is 0.39999999999999997, not 0.4.
  `length` went, since nothing asks for it.
- **`FrameTimes.even` returns a class of its own.** As a subclass it built two
  Arrays of ends it never read, once per animation each time a walker
  attached. `drive:allocations` showed it: `doors` rose from 45.5 to 47.9
  objects a second, and `adventure` from 80.9 to 84.1. The fix is folded into
  4a's commit. With it, `doors` allocates 46.3 and `adventure` 82.0, on the
  same share of ticks as `main`: one `Even` an animation, for each hero a door
  moves. `collectables` allocates 29.3 against 22.7. Run with a budget of 1,
  the probe lists where: the three coins the chest spills, each resolving
  `coin.json` and building an `AnimationSet` and an `Even` as its sprite
  attaches.
- **4b carried the docs.** `toolbox.md` builds a walker in a headless example,
  so `rake spec` failed without it, and `spec:core`'s coverage would fail on
  `WalkingSprite`, `play` and `animation`. Every page in `docs/api/` and every
  example header moved into 4b, and 4c is the coin and the changelog.
- **`AnimationSet` gained `include?` and `names`**, which the sprite checks a
  name with and lists in its error. `internals.md` documents both.
- **`WalkingSprite` checks its sheet for all five animations at attach.** Rule
  3 alone would raise on the first step that way, minutes into a game.
  `play` before attach takes any name, and attach checks it, which the plan
  left open.
- **`culling_spec.rb` built a `CharacterBody` only because the sprite needed
  one**, and no longer does. `QuietRenderer` gained `sprite`, for the
  allocation spec.
- **For step 5: two traps in comparing reports.** `topdownplatformer` differs
  from a worktree of `main` in its tilemap id alone: an absolute path, cut to 20
  characters before any path can be replaced. And `asteroids`' allocations vary
  between runs, from 6.2 to 31.5 objects a second on `main`, so compare it over
  several runs or not at all.

Documented in `docs/api/components.md` under `AnimatedSprite`, rewritten, and
a new `WalkingSprite`, and in `internals.md` under `AnimationSet`. `toolbox.md`,
`scene_graph.md` and `examples.md` name `WalkingSprite` for their walkers, and
`examples.md`'s `collectables` entry names the spinning coin.
`examples/assets/README.md` records `coin.png` and `coin.json`, drawn by
`tools/draw_coin.rb`. `CHANGELOG.md` has a `Changed` entry for
`AnimatedSprite` that names `WalkingSprite`.

### Step 5 — `Blink`, started from `on_respawned`

`Respawn` blinks the node as it brings it back, so only a respawn can blink a
node. The blink becomes `Components::Blink`, and a game starts it from
`on_respawned`, which `Respawn` already emits. It comes before step 6, because
both change what happens as a fall ends. Re-planned at `c5fd993`, where it
measured:

| | |
|---|---|
| `Respawn.new(flash:)` in games | 4: `examples/pits` and `examples/moving_platforms` at 1.0, and `topdownplatformer`'s hero at 1.0 and its crate at 0.5 |
| `Respawn.new` in specs | 9 in 5 files: `flash: 0.5` five times, `flash: 0` twice, `flash: -1` once, and once with none |
| `flashing?` | 5 reads: 4 in `respawn_spec.rb`, 1 in `footing_spec.rb` |
| `respawn_spec.rb` | 18 examples. 7 are the flash's: 6 under "the flash", and the refusal of a negative `flash:` |
| Prose naming the flash | `respawn.rb`'s header, `components.md`'s `Respawn` section, the `pits` header, `examples.md`'s `pits` entry, two changelog entries, and all three drive scripts' headers |
| Other blinks | none. `examples/collision`'s crate, `examples/sound`'s ring and `adventure`'s storm flash a colour, and none hides a node |
| `Respawn` in 0.4.0 | absent, so its changelog entry changes in place |

**What it resembles.**

- **Reused:** `Node2D#opacity`, which the blink writes as `Respawn` does, and
  `on_respawned`, which fires once the node stands on its point.
- **Considered for extending:** `FrameTimes.even(2, interval)` answers the same
  question, which of two looks shows after t seconds. It gives `Respawn`'s runs
  only if the caller adds `Respawn::SLACK` to the time. Without it, every
  change lands a tick late: 6, 6, 6, 6 and 6 ticks where `Respawn` gives 5, 6,
  6, 6 and 6 *(measured)*. The slack would have to move into `FrameTimes`, and
  that shifts sprites' frames too, which this step must not. So `Blink` keeps
  `Respawn`'s line of arithmetic, moved as it is.
- **New:** nothing. `Blink` is `Respawn`'s flash, moved.

Two sub-steps:

- **5a. `Components::Blink`**, with its spec, a `components.md` section and an
  `Added` changelog entry. Nothing calls it yet.
- **5b. `Respawn` loses its flash.** `flash:`, `flash`, `flashing?`, `BLINK`,
  `SLACK` and `_update` go. The four callers start a `Blink` from
  `on_respawned` in the same commit. The specs, `components.md`'s `Respawn`
  section, the `pits` and `moving_platforms` headers, `examples.md`, the drive
  scripts' headers and the changelog's "Falling into a gap" entry follow.

```ruby
class Blink < Engine::Component
  # Seconds one blink shows the node, and seconds it hides it.
  INTERVAL = 0.1

  # `interval` must be a positive number of seconds, or it raises ArgumentError.
  def initialize(interval: INTERVAL)

  # Blinks the node's opacity for `seconds`, shown first, then gives back the
  # opacity it found. A blink under way starts again, and still gives back the
  # opacity it found first. `seconds` must be positive, or it raises
  # ArgumentError and a blink under way carries on.
  def start(seconds)

  # Ends a blink under way and gives back the opacity it found. Does nothing
  # when none is under way.
  def stop

  def blinking?
end
```

```ruby
add_component(Components::Respawn.new(flash: 1.0))                        # at c5fd993

blink = add_component(Components::Blink.new)                               # after
add_component(Components::Respawn.new).on_respawned { blink.start(1.0) }
```

**Rules:**

1. `start(0.5)` blinks as `Respawn.new(flash: 0.5)` does at `c5fd993`. At 60
   ticks a second the node shows for 5 ticks, hides for 6, shows for 6, hides
   for 6, and shows for 7, the last with the opacity it found.
2. `interval:` sets both spells. At 0.05, the node hides for 3 ticks at a time.
3. A blink gives back the opacity it found, and `blinking?` turns false: at its
   end, at `stop`, and when its node leaves the tree. `stop` with no blink
   under way changes nothing.
4. A `start` during a blink starts it again, and gives back the opacity found
   by the first.
5. A non-positive `interval:` raises `ArgumentError` at construction. A
   non-positive `seconds` raises at `start`, and a blink under way carries on.
6. `Respawn.new(flash: 1.0)` raises `ArgumentError`.
7. A fall that ends in a respawn starts a `Blink` connected to `on_respawned`,
   in either add order, and the node walks on the tick after it lands.
8. `Blink#_update` allocates nothing over a whole blink, and a fall that ends
   in a respawn and a blink allocates nothing.

**Tests:**

- `spec/rgame/engine/components/blink_spec.rb`, new: rules 1–5, and 8 for
  `Blink` alone. `respawn_spec.rb`'s flash examples move here.
- `spec/rgame/engine/components/respawn_spec.rb` loses its 7 flash examples
  and gains rule 6. "Says so once, as the flash starts" checks the point
  instead.
- `spec/rgame/engine/components/footing_spec.rb`: the two add-order examples
  add a `Blink` to each order and check `blinking?`, for rule 7.
- `spec/rgame/engine/components/footing_allocation_spec.rb`: the fall ending in
  a respawn gains its `Blink`, for rule 8.
- `checkpoint_spec.rb` and `platforming_spec.rb` drop `flash:`.

**Verify:** `pits`, `moving_platforms` and `topdownplatformer` report the same
as on `main`: `pits`' 590 `sprite` draws in 650 ticks, `moving_platforms`' 9150
in 1020, and `topdownplatformer`'s 3273 `rect`s under `--seed 1 --texts --ticks
1654`. `rake drive:allocations` is green, and the three allocate about what
they do on `main`.

**Landed.** The branch is `blink`, with the re-plan in a commit of its own and
one commit per sub-step. `Blink.new(interval: 0.1)` with `start`, `stop` and
`blinking?`, and a `Respawn.new` that takes nothing, are as sketched. `rake
spec` passes 4,571 examples, 8 more than `main`: 12 in `blink_spec.rb` and the
`Blink` example in `components.md`, less 5 in `respawn_spec.rb`, which has 13.
`rake spec:core` passes 555, and `rake drive:allocations` passes all 44
projects.

Driven with `--seed 4242 --texts`, and `--seed 1 --texts --ticks 1654` for
`topdownplatformer`, all three report the same as `main`, line for line, but
for `topdownplatformer`'s tilemap path. `pits` draws its 590 `sprite`s in 650
ticks, `moving_platforms` its 9150 in 1020, and `topdownplatformer` its 3273
`rect`s. Without the slack, 3 of `blink_spec.rb`'s examples fail. A `_detach`
that keeps the blink fails 2, and a restart that reads the opacity again fails
1. An Array made in `Blink#_update` fails the allocation example in
`blink_spec.rb` and the fall with a blink in `footing_allocation_spec.rb`.

- **Rule 6 raises, but does not name `flash:`.** Ruby names an unknown keyword
  only for a method that takes keywords, and `Respawn#initialize` takes none.
  So `Respawn.new(flash: 1.0)` raises "wrong number of arguments (given 1,
  expected 0)". Hard constraint 5 rules out a message written for the old
  keyword, and the spec pins this one.
- **The first allocation example measured no blink.** `allocate_nothing`
  calls its block 5 times to warm up, then about 1,000 times more. A block
  running one blink to its end finished it while warming up, so every measured
  call found no blink, and an Array made per update passed. Each call now
  starts a blink and runs it whole. For step 8: an allocation spec over
  something that ends starts it again inside the block.
- **All three projects allocate a little less than on `main`**, on the same
  share of ticks, and the same in two runs of each side. `pits` allocates 11.8
  objects a second against 12.6, `moving_platforms` 7.0 against 7.4, and
  `topdownplatformer` 6.4 against 6.7. Run with a budget of 1, the probe lists
  the difference in `pits`: on `main`, the first respawn builds the `respawned`
  signal inside the measured window, since nothing connects to it. Here the
  game connects at construction.
- **`Blink#_detach` also covers the `Blink` leaving its node**, which the plan
  named only for the node leaving the tree. Both give the opacity back, and
  `blink_spec.rb` pins each.
- **For step 6: `footing_allocation_spec.rb`'s fall ending in a respawn now
  carries a `Blink`.** Step 6's allocation criterion measures a fall with it.
  Nothing here changed `Fall`.

Documented in `docs/api/components.md` under a new `Blink`, with an example
the doc specs run, and under `Respawn`, rewritten. The `pits` and
`moving_platforms` headers and their `examples.md` entries name `Blink`.
`CHANGELOG.md` has an `Added` entry for `Blink`, and its unreleased "Falling
into a gap" entry has `Respawn` emit `on_respawned` in place of flashing.

### Step 6 — `Components::Fall`, `FallLook` and `Shrink`, out of `Footing`

`Footing` finds the floor, decides the drop and runs the fall. No game can
change its shrink or turn it off, and nothing but a gap can start a fall. The
fall leaves as a `Fall`, and its look as a `FallLook`, per
[the design](#footing-finds-the-floor-a-fall-takes-the-node-out-of-play). It
follows step 5, because both change how a fall ends. Re-planned at `91b7269`,
for decisions 10 and 11, where it measured:

| | |
|---|---|
| `Footing.new` in games | 5. 4 are on nodes that fall: the `pits` and `moving_platforms` heroes, and `topdownplatformer`'s hero and crate. 1 is on a node that never does: `topdownplatformer`'s walker, `blocked_by: :gaps` |
| `Footing.new` in specs | 11 in 7 files |
| `fall:` | 9 times in `footing_spec.rb`, once each in `footing_allocation_spec.rb`, `checkpoint_spec.rb` and `components.md` |
| `on_fell` | 1 connection in a game, `topdownplatformer`'s hero. 3 in `footing_spec.rb`. Prose: 4 lines in `components.md`, 2 in `checkpoint.rb`, 1 each in `footing.rb`, `respawn.rb` and the `pits` header |
| `falling?` | 18 reads in 4 spec files: `footing_spec.rb` 11, `platforming_spec.rb` 5, `platform_spec.rb` and `wander_controller_spec.rb` 1 each |
| `footing_spec.rb` | 42 examples. 11 are the fall's: 10 under "the fall", and the refusal of a `fall:` that is not positive |
| `footing_allocation_spec.rb` | 5 examples, 2 of them falls |
| `Engine::Fall` | named by `footing.rb` alone, and `@api private` |
| A node at scale 2 | falls from 0.999 and comes back at 1 *(measured)*. `Engine::Fall` tweens from 1.0 (`fall.rb:20`) and sets 1 at the end (`fall.rb:52`) |
| Drive reports on `main` | `pits`, `--seed 4242 --texts --ticks 650`: 590 `sprite`, 698 `scaled`. `moving_platforms`, `--seed 4242 --texts --ticks 1020`: 9150 `sprite`, 1044 `scaled`. `topdownplatformer`, `--seed 1 --texts --ticks 1654`: 3273 `rect`, 1750 `scaled` |
| Prose naming the fall | the headers of `footing.rb`, `respawn.rb` and `checkpoint.rb`; `components.md`'s `Footing`, `Respawn` and `Checkpoint` sections; `tile_maps.md`'s gaps; `scene_graph.md`'s `scale`; `examples.md`'s `pits` and `moving_platforms` entries; the `pits`, `moving_platforms` and `jump_topdown` headers; the changelog's unreleased "Falling into a gap" entry |
| `Footing` in 0.4.0 | absent, so its changelog entry changes in place |

**What it resembles.**

- **Reused:** `Node2D#suspend`, and `Engine::Fall`'s node lent to the falling
  node's parent, which becomes the `Fall`'s clock. An `Engine::Tween` counts
  the fall's progress, as it counts the shrink at `91b7269`. `Respawn#respawn`
  ends it. A cutscene's `hold` waits on anything answering `on_finished` and
  `finish` (`cutscene.rb:290`), as `Components::Tween`, `PathFollow` and
  `ScreenFade` do.
- **Considered for extending:** `Blink` is the nearest sibling, a look that
  marks a moment and gives back what it found. `Shrink` takes the give-back,
  but not the clock: a `Blink` runs from its node's update, which a fall
  suspends. `Components::Tween` is a one-shot with `on_finished`, as a `Fall`
  is, and rides its own node's update for the same reason.
- **New:** `FallLook`, a component another component runs. `Pushable` and
  `Platform` come nearest: each moves only when another component calls it.

Two sub-steps:

- **6a. `Fall`, `FallLook` and `Shrink`**, with their specs and
  `components.md` sections. `Fall`'s clock is `Engine::Fall`, copied and
  renamed `Fall::Clock`. Nothing starts a `Fall` yet, and `Footing` falls as at
  `91b7269`.
- **6b. `Footing` loses its fall.** `fall:`, `falling?`, `on_fell`,
  `fall_ended` and `Engine::Fall` go, and `Footing` starts the node's `Fall`
  instead. The four falling nodes add a `Fall` and a `Shrink` in the same
  commit, and `topdownplatformer`'s hero connects `on_fell` to its `Fall`. The
  specs, the prose in the table above and the changelog entry follow.

The sketches are [in the design](#footing-finds-the-floor-a-fall-takes-the-node-out-of-play).
The one class they leave out:

```ruby
class Fall < Engine::Component
  # Moves the fall on by `dt` seconds: shows the look, and ends the fall once
  # `duration` has run. The Clock calls it.
  #
  # @api private
  def advance(dt)

  # The node a Fall lends to its node's parent for each fall. It updates while
  # the falling node is suspended, and pauses when the parent does.
  #
  # @api private
  class Clock < Engine::Node2D
    def initialize(fall)
    def _update(dt)
  end
end
```

**Rules:**

1. A node with a `Footing`, a `Fall` and a `Shrink` falls as a `Footing` does
   at `91b7269`, tick for tick. The drop, each tick's scale and the respawn
   come on the same ticks, and the node walks on the tick after it lands.
2. A `Footing` with no `Fall` never suspends its node. The node stands over
   the gap and rides what it rode, and `coyote_left` reads 0 once the coyote
   time has run out. A `Fall` added then starts on the node's next update.
3. `Fall#start` works with no `Footing`, wherever the node stands. It
   suspends the node, shows its look, and ends with its `Respawn`, or frees
   it. During a fall it does nothing and returns self. It raises for a node
   outside the tree.
4. A `hold` step on `fall.start` ends as the fall ends. A skip calls `finish`:
   the node stands on its respawn point, or is freed, and `on_finished` fires
   once.
5. `on_fell` fires once as a fall starts, before the look's first `show`.
   `on_finished` fires once, after the respawn or the free. A `Respawn`
   removed in `on_fell` frees the node.
6. `Shrink` scales the node from the scale it found toward 0, eased in. It
   gives that scale back at the fall's end, at `finish`, and when the node
   leaves the tree mid-fall. A node at scale 2 comes back at 2.
7. A fall with no `FallLook` changes nothing drawn. The node holds still at
   its scale for `duration` seconds, then comes back. Two `FallLook`s on one
   node raise as the fall starts.
8. A fall started on a platform leaves it. The platform carries the node no
   further, and the node comes back where its `Respawn` puts it.
9. A node taken from its parent mid-fall comes out resumed, at the scale its
   look found, and `on_finished` does not fire. That holds in every add order
   of its `Footing`, `Fall` and `Shrink`.
10. A fall pauses with the world around its node, and leaves no trace in the
    parent once it ends.
11. `Fall.new(duration: 0)` raises `ArgumentError`. So does
    `Footing.new(fall: 0.4)`, naming `fall`.
12. A fall allocates nothing, from the drop to the respawn and its blink,
    `Shrink` included. A `Footing` over a gap with no `Fall` allocates
    nothing either.

**Tests:**

- `spec/rgame/engine/components/fall_spec.rb`, new: rules 3–5, 7 and 9–11
  for a `Fall` started by hand. `footing_spec.rb`'s 10 fall examples move
  here, onto a node with a `Footing`, a `Fall` and a `Shrink`, for rule 1.
- `spec/rgame/engine/components/shrink_spec.rb`, new: rule 6, called by hand
  and under a `Fall`.
- `footing_spec.rb` loses the fall's 11 examples and gains rule 2 and
  `Footing`'s half of rule 11. Its add-order examples put a `Fall` and a
  `Shrink` before the rest and after.
- `spec/rgame/engine/components/fall_allocation_spec.rb`, new:
  `footing_allocation_spec.rb`'s 2 falls move here, with a `Shrink`, for rule
  12. `footing_allocation_spec.rb` gains the node over a gap with no `Fall`.
- `cutscene_spec.rb`: a `hold` on a `Fall`, watched to its end and skipped,
  for rule 4.
- `platforming_spec.rb`: the heroes and the crate gain a `Fall` and a
  `Shrink`, and a fall started on the shuttle checks rule 8.
- `checkpoint_spec.rb`, `platform_spec.rb` and `wander_controller_spec.rb`
  read `falling?` from a `Fall`, or check the node is not suspended where it
  has none.

**Verify:**

- `pits`, `moving_platforms` and `topdownplatformer` report the same as on
  `main`, with the flags above: `pits`' 590 `sprite` and 698 `scaled`,
  `moving_platforms`' 9150 `sprite` and 1044 `scaled`, and
  `topdownplatformer`'s 3273 `rect` and 1750 `scaled`.
- `rake drive:allocations` is green, and the three allocate about what they
  do on `main`.
- `git grep -nE 'Engine::Fall\b|fall: [0-9]|Footing#on_fell'` lists nothing
  outside `docs/plans/`.

### Step 7 — The `build-components` skill (rough)

Written from the landed notes of steps 2–6, per
[write-skill](../../.claude/skills/write-skill/SKILL.md), under
`.claude/skills/build-components/SKILL.md`. The expected contents are
[in the design](#the-build-components-skill).

**`Mover` is flagged as the exception** (decision 7), with the reason, in two
places. The skill names it where it states the counterweight. `Mover`'s own
header says it answers two questions on purpose, beside its note on why
blocking lives in a base class.

Links to it:

- **`write-plan`**, where a sketch loads `write-ruby-code`, and where its five
  interface checks stood;
- **`write-ruby-code`**, one line at the top;
- **CLAUDE.md**'s list of skills, and its "Before building" sentence that
  points at the five checks.

`implement-step` gets no link unless the re-plan finds a reason. It re-plans
through `write-plan` and writes code through `write-ruby-code`, so a third
pointer would repeat both.

### Step 8 — Fold the plan back and delete it

- Check `components.md`, `examples.md` and the other pages against the landed
  code, per [write-docs](../../.claude/skills/write-docs/SKILL.md).
- Move each open question still open to `possible-todos.md`, with its trigger.
  That is `TileWorld`'s, unless open question 4 was answered yes, and the
  falling crate's push, unless open question 5 was.
- Add a todo for `Mover`'s second job (decision 7). Its trigger is a fourth
  thing a step moves along, such as a tow rope or a vehicle, or a bug traced
  to one of the three wirings.
- Run [learn-from-mistakes](../../.claude/skills/learn-from-mistakes/SKILL.md)
  over every step's "What proved wrong".
- Delete this plan.

**Verify:** `CHANGELOG.md`'s Unreleased section describes `Targeting`, `Grab`,
`Collectable`, `AnimatedSprite`, `WalkingSprite`, `Respawn` and `Blink` as a
0.4.0 user reads them, per
[update-changelog](../../.claude/skills/update-changelog/SKILL.md). `rake spec`
and `rake spec:core` are green.
