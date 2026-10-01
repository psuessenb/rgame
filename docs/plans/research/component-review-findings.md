# What the component review found

Research: defects in components that the single-job components plan does not
change. Step 7 of that plan tested its `build-components` skill with a blind
review. Three times, a fresh subagent read only the skill and the 48 files in
`lib/rgame/engine/components/`, and listed every component that failed it. Two
more were the plan's own open questions, found while planning it and in its
step 6. Each finding here predates the plan, and the plan fixes none of them.
The plan is deleted, and `git show 1c57c4e:docs/plans/single-job-components.md`
reads it.

It is not a plan: it has no roadmap. A plan that takes up a finding moves it
there and deletes it here. The last one out deletes the file.

Everything here was read or measured at commit `1c57c4e`, on Ruby 4.0.5, at
1/60 s a tick. The two from the open questions were measured again at
`1ab9e66`, whose code differs from `1c57c4e` by one comment. The probes are
scratch scripts and are not committed.

## Verdict

**Two findings are bad design and ten are bugs.** A bug does something other
than what its comments say, or than what a game that builds its scene right
expects. Bad design works as documented, but in a shape the
[build-components](../../../.claude/skills/build-components/SKILL.md) skill
refuses, or one that reports a mistake as something else.

Nine of the ten bugs are measured, and the tenth is a sentence its own class
contradicts. Of the nine:

- four hold in one add order only, two of them in comments;
- two keep what they found of a sibling, and miss one removed or added later;
- two let another node move a node that should stay put: a falling crate, and
  a node respawned off a platform;
- one does not give back the value it changed.

None blocks other work. Two move a node a tick late in one add order, and
every game that uses them adds them in that order. A fix changes those games by
a tick. A fix for the falling crate may change `topdownplatformer`'s report.

## Bad design

### `ThrustController` answers two questions

It answers how a ship handles, and which two input actions steer it. Its turn
and thrust come only from the actions `_control` reads by name
([thrust_controller.rb:31](../../../lib/rgame/engine/components/thrust_controller.rb#L31)).
It has no method a game can call to turn or thrust, so an AI ship cannot reuse
its handling. Such a ship would have to declare `:turn` and `:thrust` in an
input map, since `Actions#axis` raises for an action no map declares. Two of the
three rounds found it. The plan's own review had passed it, because its header
leaves firing out.

**Lean:** `Hop`'s shape. The actions stay as a default, and a method steers a
ship no player steers. `Hop` reads its `action:`, and with `action: nil` it runs
the arc only from `jump`.

### `Targeting` keeps a `CollisionWorld` that may be nil

`Targeting#_attach` keeps `node.system(CollisionWorld)`, which is nil on a scene
without one
([targeting.rb:48](../../../lib/rgame/engine/components/targeting.rb#L48)). Its
first update then raises `NoMethodError` for `nearest` on nil *(measured)*.
`Grab` and `Interactor` are subclasses, and fail the same way. A `Navigator` on
a scene without a `TileWorld` raises naming it. `possible-todos.md` records the
shape under
[Two loose ends from the naming plan](../possible-todos.md#two-loose-ends-from-the-naming-plan):
"The plain `system` lookup still returns nil where a system is required."
`Targeting` is one more caller.

**Lean:** `system!`, which raises with the class and where it looked.

## Bugs

### `ThrustController` writes its `Velocity` in the phase `Velocity` reads

Its `_update` adds thrust to its `Velocity`'s `vx` and `vy`
([thrust_controller.rb:36](../../../lib/rgame/engine/components/thrust_controller.rb#L36)),
and the `Velocity` moves the node in its own `_update`. So the first thrust moves
the ship on the tick it starts in one add order, and a tick later in the other.
With `accel: 600`, the ship stands at x 0.1667 after its first thrusting tick
when the controller comes first. It stands at 0 when the `Velocity` does
*(measured)*. `test_projects/asteroids`, its one user, adds the `Velocity`
first. Its header says it "composes with the normal phase order", which holds
for its `_control` only.

**Lean:** it sets what it changes in `_control`, as it already sets `spin`.
Drag and the top speed need `dt`, which `_control` is not given. So `Velocity`
may have to integrate an acceleration itself.

### `WanderController` sets its body's intent in the phase the body steps in

It rerolls a heading in `_update`, and hands it to its `CharacterBody` with
`set_intent`
([wander_controller.rb:38](../../../lib/rgame/engine/components/wander_controller.rb#L38)).
The body steps in its own `_update`. A new heading moves the body on tick 1 when
the controller comes first, and on tick 2 when the body does *(measured)*. All
five games that use it add the body first.

**Lean:** it rerolls in `_control`, where `PlayerController` sets intent, from
the timer its `_update` runs.

### `Hop` takes the node's elevation as its own

It writes its arc to `Node2D#elevation`, and sets it to 0 when it lands
([hop.rb:57](../../../lib/rgame/engine/components/hop.rb#L57)). Attaching lands
it too. A node standing at elevation 4 drops to 0 as its `Hop` attaches. A hop
with `peak: 10` from elevation 4 peaks at 10 and lands at 0 *(measured)*. It has
no `_detach`, so a node whose `Hop` is removed mid-hop stays in the air: at
8.889 after ten ticks of a 0.5 s hop *(measured)*.

**Lean:** it adds its arc to the elevation it found, and gives that back when it
lands and in `_detach`.

### `Footing` keeps the `Mover` it found

It finds its `Hop` and its `Mover` on its first update, and keeps both
([footing.rb:163](../../../lib/rgame/engine/components/footing.rb#L163)). A
`Mover` removed from a node riding a `Platform` is still called, and the next
carry raises `NoMethodError` for `world_x` on nil *(measured)*. The skill allows
such a cache only for a sibling read every tick, as the `Hop` is. Only a carry
reads the `Mover`.

**Lean:** it looks the `Mover` up in `ride`
([footing.rb:130](../../../lib/rgame/engine/components/footing.rb#L130)), which
only a carry calls.

### `Navigator` keeps the collider it found at attach

Its `_attach` looks for a `BoxCollider` once
([navigator.rb:59](../../../lib/rgame/engine/components/navigator.rb#L59)). On a
node already in the tree, each component attaches as it arrives. A collider
added there after a `Navigator` with `blocked_by: []` goes unseen, and the
`Navigator` plans as if the node were a point. With a 16×48 collider over
16-pixel tiles, `go_to` raises `ArgumentError` when the collider came first. It
plans a route when the collider came after *(measured)*. With any blocker in
`blocked_by:`, `Mover` requires the collider at attach, and raises naming the
add order.

**Lean:** it looks the collider up in `go_to`, which measures the node's anchor
on every call already.

### A falling crate can still be pushed

A `Fall` suspends its node, and a suspended node stops its own components.
Another node's mover still pushes it: neither `Mover#pushable`
([mover.rb:478](../../../lib/rgame/engine/components/mover.rb#L478)) nor
`Pushable#push` asks whether the crate is suspended. A hero walking west pushed
a crate into a gap at x 350, then on to x 340 over the 10 ticks after it
dropped *(measured)*. `topdownplatformer`'s crate drops on tick 414, and its
script holds right for about two ticks more, so a fix may change that report.
Open question 5 of the plan.

**Lean:** a `Mover` pushes no suspended node, so a falling crate stops a pusher
as a fixed one does. That holds for a node a cutscene suspends too, which is
why it is not the `Fall`'s job.

### A platform carries a node respawned off it

`Respawn#respawn` moves its node to its point, and leaves its `Footing` riding
([respawn.rb:71](../../../lib/rgame/engine/components/respawn.rb#L71)). The
platform carries the node on its next step, before the `Footing` updates and
leaves. A hero riding the shuttle, respawned by hand onto the bank at x 60,
stands at 60.5 a tick later *(measured)*. A hero suspended first, as a cutscene
would, keeps riding from the bank, since its `Footing` never updates: it stands
at x 90 after 60 ticks *(measured)*. No fall shows it, because `Fall#start` has
the `Footing` leave its platform. Only a game calling `respawn` on a riding node
does. Open question 6 of the plan.

**Lean:** `Respawn#respawn` has the node's `Footing` leave its platform, as
`Fall#start` does.

### The comment on `CameraFollow#_update` holds in one add order

It says the camera reads the node's position "from before whatever moves it this
tick"
([camera_follow.rb:32](../../../lib/rgame/engine/components/camera_follow.rb#L32)).
That holds when the camera comes before the node's mover. With a `CharacterBody`
added first, a node stepping from x 100 to 101 has the camera at 101 on that
tick, not 100 *(measured)*. The skill accepts the lag, since a camera's tick
shows nowhere on screen. Only the comment is wrong.

**Lean:** the comment says the camera trails by a tick in one order, and why
that shows nowhere.

### `Footing`'s header holds in one add order

It says a node that lands on a gap loses its footing on the tick it lands
([footing.rb:17](../../../lib/rgame/engine/components/footing.rb#L17)). The
comment on `initialize` says `coyote: 0` drops a node on its first tick off the
floor. With its `Hop` added after it, a node landing on tick 31 falls on tick
32. With its mover added after it, a node walking off falls at x 65, not 64. The
mover takes one more step after the fall suspends the node *(both measured)*.
`docs/api/components.md` repeats the landing claim. It states which add order
the coyote window's ticks hold for, and the header does not.

**Lean:** the header and the docs page say which add order each tick holds for.

### `TileWorld`'s first sentence says it draws the map

It names "drawing the map through the scene's camera" among what it owns
([tile_world.rb:6](../../../lib/rgame/engine/components/tile_world.rb#L6)). A
later paragraph says "It does not draw", and `TileMapLayer` draws the map
([tile_world.rb:35](../../../lib/rgame/engine/components/tile_world.rb#L35)).

**Lean:** the clause goes.
