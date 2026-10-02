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
A reason is a question the component answers, whether or not a keyword for the
change exists yet. Where a node comes back and how the return looks, a blink or
a splash, are two, so `Respawn` answered two until its flash became `Blink`. A
longer coyote time and boarding only from the ground both change what `Footing`
counts as standing on, so `Footing` answers one.

## The tells

Each of these shipped as a second job. A tell sends a component to the test,
and the test decides. The walker below still holds a `Footing` only to ride,
and passes the test.

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
- **An input action as a default, where the job runs without it.** `Hop`
  reads its `action:`, and with `action: nil` it only runs the arc, from
  `jump`. A job that only an input can start answers a second question: who
  asks.
- **Cohesive around one thing it owns.** `Cutscene` takes the game and gives it
  back, for one lifetime. `TileWorld` answers what its map says: where it is
  solid, where its floor is, how big it is and how far its tiles have animated.
  Its registry of `Platform`s stays with it, since a platform is floor. Owning
  one thing excuses only what the test passes: no game changes either of them
  for a second reason.

**`Mover` is the one exception: two jobs, kept on purpose.** It answers where
its step lands, and what the step pushes, drags and carries. The second half
must run after the step. A sibling can do that only from its own `_update`,
wherever it sits in the list, and a `Blocking` sibling fired `on_unblocked` on
two different ticks for two add orders. What hands it the things that move
with the step comes with the exception: `Grab`'s crate, and a `Platform`'s
riders, each carried through its `Footing`. Its header says so.

## How to split one

By where the second half runs:

| The second half runs | It becomes | Example |
|---|---|---|
| on a node that updates | a component the game starts from a signal of the first | `Blink`, started from `Respawn`'s `on_respawned` |
| in the same update as what it drives | a subclass, through a hook | `WalkingSprite`'s `_choose_animation` picks the animation `AnimatedSprite` draws that tick |
| while the node is suspended | a sibling the first one drives | `Fall` shows its node's `FallLook` from a clock it lends the node's parent |

**Never a sibling that writes into another in the same phase.** Which one runs
first is then the add order, as with the `Blocking` sibling above. Reading what
a sibling changed this phase lags a tick in one add order, and the tick can
show: a camera that read its node so drew it a step off centre. Where such a lag
stays, the docs state it, as `components.md` states the tick it costs
`Footing`'s coyote window.

## Siblings

- **Require at attach only a sibling it would be wrong without**, in some
  scene it may stand in. `require_sibling` raises naming both, so an add order that
  hides it fails loudly. Look up one it can do without when it uses it.
  `Footing` finds the node's `Fall` each time the node loses its footing, and
  the `Fall` finds its look after `on_fell`. Any add order then works, a game
  removes a piece to switch it off, and a game may choose a piece at each
  event.
- **A sibling it reads every tick may be found on its first update instead**,
  as `Footing` finds its `Hop`. Any add order still works, but a sibling added
  later goes unseen, and one removed later is still called.
- **No stand-in for a missing sibling.** A component never does a missing
  sibling's job itself. A `Fall` on a node with no look shows nothing, where a
  default `Shrink` would hide the look a game swaps out. Freeing a node with no
  `Respawn` is the `Fall`'s own end, not a `Respawn`'s job.
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
- Does it find its siblings, and give back what it changes, as the two sections
  above say?
- Does it duplicate state the node owns? (`Engine::Body` kept its own `x`/`y`.)
- Does it need a hand-written hook to hand its data to another component?
- Does it behave differently depending on a sibling's add order?
- Does it name a layer it may not name? A layer says what a thing is. Where a
  contact picks the node, a layer may narrow who acts, as `blocked_by:`,
  `pushes:` and `Checkpoint`'s `by:` do. A component that picks a node among
  several picks by what the node holds, as `Grab` did not.
- Is it a node pretending to be a component, or the reverse?

These read the interface. A misfit inside a method body that presents a clean
interface gets past them.
