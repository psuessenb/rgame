# What the component review found

Research: defects in components that the single-job components plan does not
change. Step 7 of that plan tested its `build-components` skill with a blind
review. Three times, a fresh subagent read only the skill and the 48 files in
`lib/rgame/engine/components/`, and listed every component that failed it. Each
finding here predates the plan, and the plan fixes none of them. The plan is
deleted, and `git show 1c57c4e:docs/plans/single-job-components.md` reads it.

It is not a plan: it has no roadmap. A plan that takes up a finding moves it
there and deletes it here. The last one out deletes the file.

Everything here was read or measured at commit `1c57c4e`, on Ruby 4.0.5, at
1/60 s a tick. The probes are scratch scripts and are not committed.

## Verdict

**Two findings are left, and both are bad design.** Each works as documented,
but in a shape the
[build-components](../../../.claude/skills/build-components/SKILL.md) skill
refuses, or one that reports a mistake as something else. Neither blocks other
work.

The review found ten bugs as well. Pull requests #184 to #193 fix them, one
each, and `git show 73a74a2:docs/plans/research/component-review-findings.md`
reads them as they were filed.

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
