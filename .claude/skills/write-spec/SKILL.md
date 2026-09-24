---
name: write-spec
description: How to write an RSpec spec in this project — the mocking rules and the exception the scene graph forces, when a value is a `let` and when it stays a method or a local, `describe` versus `context`, and what an allocation spec has to reach. Use whenever adding or editing a spec under `spec/` or `spec_core/`, or when a change to `lib/` or `ext/` needs one.
---

# Writing a spec

`spec/rgame/engine/node2d_spec.rb` is the reference. Which suite a spec belongs
in, and what a fake owes the real thing it stands in for, are in
[verify](../verify/SKILL.md).

## Doubles

- **Use RSpec's mocking mechanisms rather than a `Struct` or `Data` stand-in**,
  and always a verified double — RuboCop enforces the second.
- **Except where the code under test keys on the class.** `Node2D`'s component
  registry matches on `is_a?` and `#system` looks the same way, and a verifying
  double is neither. Define a real subclass — `node2d_spec.rb` opens with five —
  rather than asserting against a mock of the inheritance machinery.
- **Never hand a double to `allocate_nothing`.** A double allocates on every
  call, so the matcher measures the double. Pass a plain object with explicit
  keyword params, as the `*_allocation` specs do.

## `let`, helpers and locals

Nested `describe` is free — no line limit is enabled, so nest wherever it reads
better.

- **A value shared by more than one example is a `let`.** Not
  `def thing = @thing ||= ...`, which is `let` written by hand.
  `spec/spec_style_spec.rb` fails on it, because no cop does: `@x ||= y` parses
  to `or-asgn` and `RSpec/InstanceVariable` searches for `ivar` nodes.
- **When a `let` puts a group over `RSpec/MultipleMemoizedHelpers`, disable the
  cop there and say why.** Do not turn the `let` back into a method to get under
  the limit — that is how the memoized helpers got written in the first place.
  The cop counts helpers inherited from enclosing groups, so one more `let` at a
  file's top level can put every group in that file over at once; the disable
  then belongs around the whole file, not around twenty groups.
- **A helper that takes arguments stays a method.** `let` cannot be
  parameterized, so this suite's factories — `tile_world(solid:)`, `npc_at(x, y)`
  — are the correct shape and not a `let` waiting to happen.
- **A value one example uses stays a local.** A `let` read once is indirection.

## `describe` the thing, `context` the situation

A condition gets a `context`, phrased `when`/`with`/`without`. The suite reads
flat because it has 580 `describe` to 2 `context` — `describe 'blocked_by:
%i[tiles npc]'` is a context — and `RSpec/ContextWording` never fires, because it
only inspects `context` blocks. New specs follow the rule; converting the
existing ones buys nothing.

## Allocation specs

`allocate_nothing` measures what one call allocates, and only on the branches
the spec's data reaches. So:

- **Reach every branch that can allocate.** `TileMap#frame_tile` allocated
  only when a frame other than the last was showing, and `SpatialHash` only in
  a cell it had never used. The specs that missed both showed only the last
  frame and reused the same cells. Measure a walk into new cells, and each
  frame of an animation.
- **Warm up past what happens once.** Ruby fills a method's caches on its first
  call, and a periodic path first runs when its period ends. A spec measuring
  something that closes a window each second warms up with
  `after_warmup(61)`. Give the reason in a comment, as `grab_spec.rb` does for
  the row boundary a drag crosses.
- **A cost per event is `retain_nothing`, not `allocate_nothing`.** A pooled
  node's spawn and reclaim allocate nothing per frame, and can still leave
  something behind each cycle. `pool_allocation_spec.rb` measures the cycle.
