# Single-job components

**Status:** Step 1 is implemented. Steps 2–4 are detailed. Steps 5–7 are
rough, and each is re-planned before it starts. Step 8 folds the plan back and
deletes it.

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
- **`Footing`**'s shrink cannot leave that way. A falling node is suspended, so
  nothing on it updates, a listener's component included. Step 6 decides
  between a look object the fall drives and leaving `Footing` as it is, against
  criteria stated there.

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
   `AnimatedSprite#_update` and `#_draw`, `Blink#_update`, and whatever step 6
   gives a fall.
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

### `Footing`'s look cannot leave through a signal

**A falling node is suspended, and a suspended node stops its own components.**
`Node2D#update` returns at once for it. A component that listened to `on_fell`
and shrank the node would stop the moment it started. That is why the fall
runs from `Engine::Fall`, a node `Footing` lends to the falling node's parent.

The shrink can still leave `Footing`, as an object the `Fall` drives:

```ruby
# What a fall looks like. The Fall calls `show` each tick of the fall with how
# far through it is, from 0 to 1, and `finish` once it ends, landed or cut short.
module Footing::Shrink
  def self.show(node, progress) ...   # scale from 1 toward 0, eased :in
  def self.finish(node) ...           # scale back to 1
end

Footing.new(coyote: 0.1, fall: 0.4, look: Footing::Shrink)   # the default look
```

Whether that is better or worse is step 6's question, with its criteria stated
there. The duration stays in `Footing`: `fall:` is how long the node is out
of play, which is a rule of the game, not a look.

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
  - a sibling required for only one of its jobs (`AnimatedSprite`'s `Mover`).
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
  - an object the owner drives, when the node is suspended (`Footing`'s look,
    if step 6 lands it).

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
  this is the user's signal approach. But with no listener the node would
  freeze and then vanish. Every caller would have to wire the shrink to keep
  today's fall, which is a rule to remember.

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

## Roadmap

```
1 the rule ─→ 2 Grab by Pushable ─┐
              3 Collectable ──────┤
              4 AnimatedSprite ───┼─→ 7 build-components ─→ 8 fold back
              5 Blink ─→ 6 Footing's look ┘
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

### Step 5 — `Blink` (rough)

`Respawn`'s blink becomes `Components::Blink`, started from `on_respawned`.
[The design](#blink-started-from-on_respawned) has the expected shape.

- Callers: the four `Respawn.new(flash:)`.
- Docs: `components.md`'s `Respawn` section and a new `Blink` section.
- Changelog: the unreleased "Falling into a gap" entry says "flashing", and
  `Blink` gets an `Added` entry.

**Verify:** `pits`, `moving_platforms` and `topdownplatformer` report the same
as on `main`, including `pits`' 590 `sprite` draws in 650 ticks.

### Step 6 — `Footing`'s look (rough)

Decide whether the shrink leaves `Footing` as a look object the `Fall` drives,
sketched in [the design](#footings-look-cannot-leave-through-a-signal).
Re-planned once step 5 has landed. It goes ahead only if all four hold:

- the five `Footing.new` calls stay as they are;
- the look answers two methods, `show` and `finish`, and the `Fall` calls
  nothing else on it;
- `pits`, `moving_platforms` and `topdownplatformer` report the same as on
  `main`, their `scaled` counts included;
- a fall still allocates nothing, per `footing_allocation_spec`.

Otherwise `Footing` stays as it is. The skill then records why: the look of a
suspended node belongs to what runs beside it.

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
  That is `TileWorld`'s, unless open question 4 was answered yes.
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
