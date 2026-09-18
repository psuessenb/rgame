---
name: write-spec
description: How to write an RSpec spec in this project — the mocking rules and the exception the scene graph forces, when a value is a `let` and when it stays a method or a local, and `describe` versus `context`. Use whenever adding or editing a spec under `spec/` or `spec_core/`, or when a change to `lib/` or `ext/` needs one.
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
  `def thing = @thing ||= ...`, which is `let` written by hand;
  `RSpec/InstanceVariable` misses it because the ivar hides inside a `def`.
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
