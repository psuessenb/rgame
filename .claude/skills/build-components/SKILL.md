---
name: build-components
description: How to design a component in RGame::Engine::Components so it answers one question — the test for a second job and the tells of one, what is not a second job, how to split one by where its second half runs, how a component finds the siblings it uses, and the checks a review of existing components runs. Use whenever designing, adding, splitting or reviewing a component, sketching one in a plan, or giving one a new keyword, flag or sibling to read.
---

# Building a component

A component answers one question. CLAUDE.md's rule on
[layers](../../../CLAUDE.md#what-a-node-offers-is-a-component-not-a-layer) says
what a node offers is a component, and this skill says how to build one that
offers one thing. Its names follow [write-ruby-code](../write-ruby-code/SKILL.md).

## One job is one question

**The test for two jobs: would two games change it for two different reasons?**
A game changes where a node comes back for one reason, and how the return looks,
a blink or a splash, for another. `Respawn` did both until its flash became
`Blink`.

## The tells

Each of these shipped as a second job:

| Tell | The mistake behind it |
|---|---|
| a flag that turns half of it off | `Collectable`'s `free: false`, which made both doors in the repository "collected" |
| a header whose first sentence joins two jobs with "and" | `Respawn`: "and the flash that shows it has" |
| one value that several readers ask different questions of | `Grab` picked by `layer`, so a fixed crate nearer than a movable one left it holding nothing |
| a look built into a mechanic | `Respawn`'s flash and `Footing`'s shrink, which no game could change or turn off |
| a sibling required for only one of its jobs | `AnimatedSprite` raised without a `Mover`, so nothing could animate on the spot |
| a node holding a component for one of its jobs | a walker held a `Footing` to ride a platform, and carried a fall it could never take |

## What is not a second job

- **Feedback a game varies only by value.** `Collectable`'s `sound:` changes
  which sound plays, never what kind of thing happens.
- **An input action as a default.** `Hop` reads its `action:`, and with
  `action: nil` it only runs the arc.
- **Broad inside, where a split would make add order matter.** `Mover` answers
  where its step lands, and what the step pushes, drags and carries. Its second
  half must run after the step. A sibling can do that only from its own
  `_update`, wherever it sits in the list, and a `Blocking` sibling fired
  `on_unblocked` on two different ticks for two add orders. `Mover` is the named
  exception, and its header says so.
- **Cohesive around one thing it owns.** `Cutscene` takes the game and gives it
  back, for one lifetime. `TileWorld` answers what the map holds at a point, and
  its registry of `Platform`s stays with it, since a platform is floor.

## How to split one

By where the second half runs:

| The second half runs | It becomes | Example |
|---|---|---|
| on a node that updates | a component the game starts from a signal of the first | `Blink`, started from `Respawn`'s `on_respawned` |
| in the same update as what it drives | a subclass, through a hook | `WalkingSprite`'s `_choose_animation` picks the animation `AnimatedSprite` draws that tick |
| while the node is suspended | a sibling the first one drives | `Fall` shows its node's `FallLook` from a clock it lends the node's parent |

**Never a sibling that writes into another in the same phase.** Which one runs
first is then the add order, as with the `Blocking` sibling above.

## Siblings

- **Require at attach only a sibling it cannot work without**, with
  `require_sibling`, which raises naming both. Look up one it can do without
  when it uses it. `Footing` finds the node's `Fall` each time the node loses
  its footing, and the `Fall` finds its look after `on_fell`. Any add order then
  works, a game removes a piece to switch it off, and a game may choose a piece
  at each event.
- **No default for a missing sibling.** A component does nothing in its place.
  A `Fall` on a node with no look shows nothing. A default `Shrink` would hide
  the look a game swaps out.
- **Ask whether a node holds a component with `node.components.any?(Klass)`**,
  not `get_component`, which raises on two matches. `Targeting`'s `having:`
  could not use it for that reason. `any?` allocates nothing.

## A component that changes its node for a while

It gives back the value it found, never the default: `Footing`'s shrink ended
at scale 1, and a node drawn at 2 came back at 1. It gives it back in `_detach`
too, which runs both when the node leaves the tree and when the component leaves
the node.

## Reviewing existing components

For each component:

- Does it answer two questions? The test and the tells above.
- Does it duplicate state the node owns? (`Engine::Body` kept its own `x`/`y`.)
- Does it need a hand-written hook to hand its data to another component?
- Does it behave differently depending on a sibling's add order?
- Does it name a layer it may not name? A layer says what a thing is, and may
  narrow who acts, as `blocked_by:` and `by:` do. Choosing a node by what may be
  done to it chooses by a component.
- Is it a node pretending to be a component, or the reverse?

These read the interface. A misfit inside a method body that presents a clean
interface gets past them.
