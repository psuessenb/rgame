---
name: write-plan
description: How to write a plan under docs/plans — research and measurement first, a verdict up front, classes shaped by what a game asks rather than by the format or library behind them, then a roadmap whose steps are sized to one branch and one pull request each, with later steps left deliberately rough. Use when asked to plan a feature, a refactor, a port or a rework, when starting a new docs/plans document or folder, or when re-planning the next phase of an existing one.
---

# Writing a plan

A plan in this project is **not** a task list. Every plan that worked here was
mostly research — inventory, measurement, prior art, rejected alternatives — and
the roadmap at the end was the short part that fell out of it. Write it in that
order and the roadmap mostly writes itself. Write the roadmap first and it will
be fiction.

Plans live in `docs/plans/`. They are **working documents** that serve an
implementation or refactoring effort. So, unlike the reference documentation
([write-docs](../write-docs/SKILL.md)), they may name previous iterations of the
code, reference other engines and games, record what a prompt decided, and leave
questions open. They are also temporary. When the work lands, whatever is still
true moves into the real documentation, and the plan is deleted; git history
keeps it. A plan that outlives its refactor is a stale description of code that
no longer exists, so a roadmap schedules its own removal as its last step.

A plan's latitude is in what it may say, not in how it says it. Its prose follows
[write-prose](../write-prose/SKILL.md), as the reference documentation's does.

## One file, or a folder

| Shape | Use when | Layout |
|---|---|---|
| Single file | one subsystem, research fits in a few screens | `docs/plans/<topic>.md` |
| Folder | the research is several distinct investigations | `docs/plans/<topic>/` with numbered files |

A folder's files are numbered in **reading order**, and `README.md` is the index
and the brief:

```
docs/plans/<topic>/README.md          brief: goal, constraints, decisions, open questions
docs/plans/<topic>/01-current-state.md   what the code does today, and what blocks the goal
docs/plans/<topic>/02-prior-art.md       how other engines answer this, with sources
docs/plans/<topic>/03-design.md          the proposed design
docs/plans/<topic>/04-roadmap.md         the implementation order
```

The numbers are the order to *read*, not a fixed set. A port needs an inventory
where a rework needs a current-state analysis. What does not vary: the roadmap
is last, and it is a separate document from the design.

Start with a single file. Promote it to a folder when one section outgrows the
rest, not before.

## Research first, and measure it

The research half is what makes the roadmap trustworthy, and its rule is
simple: **numbers, not adjectives.**

Put a "What was measured before planning" section near the top of the roadmap
or the brief, as a two-column table, with the commit the numbers were taken at.
Count the actual call sites. Run the suite and record the example count and the
runtime. Grep for the thing you are about to sweep and paste the list.

This pays twice. It stops the plan budgeting from a guess, and it sometimes
kills a step outright — a sweep that sounded like the expensive part of a rework
turned out to be eleven definitions across eight files, a morning's work, and
only counting showed that.

**Measure what the design adds, not only what exists today.** A proposal's own
cost is the number most often assumed rather than taken. The Tiled plan's
transform added 2.8 ms to a 250×250×6 map against 15.1 ms the load already spent,
and that is what settled whether to cache its result.

Tag any finding you actually verified, so a reader can tell measurement from
expectation:

```markdown
### A3. The root Makefile hardcodes Linux — *(measured: this is what fails first)*
### A1. `#include <SDL2/SDL.h>` — optional robustness *(measured: not a blocker)*
```

One inventory earns its place every time, and it is the one a plan is most
likely to skip: **what already in this codebase resembles the thing being
planned.** Not what it can reuse — that answers itself — but what does a similar
enough job that one shape should cover both. See
[Before building: find the thing it resembles](../../../CLAUDE.md#before-building-find-the-thing-it-resembles)
for why; what a plan
owes is the three piles, in writing, with the "genuinely new" one justified
rather than assumed. A plan that cannot name what its subject resembles has
usually not looked.

Two research sections earn their place nearly every time:

- **Prior art.** How Unreal, Unity, Bevy, Godot, or whichever engines are
  relevant answer the same question, what they agree on, and — the useful part —
  **what none of them gives us**. Cite sources.
- **What was considered and rejected.** The alternative with its real
  attractions stated, then the specific reason it fails. A rejected option
  without a reason gets proposed again in three weeks.

### Generalisation: the worked example, and what it cost

Tile collision and body collision were built independently, and each was
correct. `TileCharacterBody` resolved a step against a grid; `BoxCollider`
reported overlapping pairs out of a spatial hash. Different indexes, different
questions, no shared code — and on that reading, two systems is right.

They answered the same question about different things: *what is in the way*.
Seen that way the duplication is obvious and it was expensive. The shape had two
owners, so a character wanting both built one box privately and handed it to the
other component in an `on_add` hook written for no other purpose — and forgetting
that hook was **silent** — precisely the failure
[Design out misuse](../../../CLAUDE.md#design-out-misuse-the-right-thing-must-be-the-easy-thing)
exists to refuse. Unifying it afterwards took six steps and touched every
collision file in the project.

### The same question, as a review of existing code

Applied to the whole engine layer the first time, it found a second instance: `Velocity`,
`PathFollow` and `CharacterBody` all answered *where does this node go this step*,
and only the last could be stopped by anything. They became three subclasses of
`Components::Mover`, which owns what happens after a step is computed. For each
class, the checks that sweep ran were:

- Does it duplicate state the node owns? (`Engine::Body` kept its own `x`/`y`.)
- Does it need a hand-written hook to hand its data to another component?
- Does it behave differently depending on a sibling's add order?
- Does it name a layer it may not name?
- Is it a node pretending to be a component, or the reverse?

These are interface-depth checks. A misfit inside a method body that presents a
clean interface gets past them.

## Optimise for the game, not for the source

**What the engine reads must not decide the shape of what a game calls.** A file
format, a library, a protocol or someone else's schema has a shape, and that
shape solves its own problem — storage, compatibility, or history. An engine
class answers a different question: what a game asks for, on a frame budget.

So a plan that adds support for anything external owes three parts, not two:

| | |
|---|---|
| **A faithful reading** | Keeps the source's names, units and coordinates. Checkable against the source's own reference. |
| **A transform** | Absorbs every convention the source has that the game does not want. Runs once, at load. |
| **A view shaped by its use** | Only what a game asks, named the way a game asks it. |

Two parts is the trap, and it is not visible from inside. The split gets written,
both halves are coherent, and the source's vocabulary walks straight through the
second one into the game. So apply the test to every name on the class a game
will call:

> **Does this name exist because the source exists?** If it does, the transform
> should have absorbed it.

### What legitimately crosses

Not everything in the source belongs to the source. Two things cross untouched:

- **What an author wrote for the game to read.** Custom properties a designer
  attached in an editor are already in the game's world. Translating them would
  be translation for its own sake.
- **Names two people share.** A layer called `canopy` is what a designer sees
  and what a programmer types. Replacing it with an index helps nobody.

The rule is about shape, not about contact. Reusing the library is fine. Letting
it pick your class's attributes is not.

### Three smells

1. **Two types whose attribute lists match row for row**, one inside and one
   outside. That is CLAUDE.md's parallel-vocabulary smell, pointed at a
   boundary rather than at two subsystems.
2. **A unit, an origin or an encoding that only makes sense in the source** —
   milliseconds where the engine speaks seconds, a bitfield, a coordinate
   measured from a different corner.
3. **A doc comment that has to explain the format to explain the method.** If
   the method cannot be described without it, the format is in the interface.

A fourth belongs to [Design out misuse](../../../CLAUDE.md#design-out-misuse-the-right-thing-must-be-the-easy-thing)
and is the same failure seen
from the caller: **a conversion every caller must remember**. If the transform
does not do it, each caller does, and the ones that forget produce a plausible
picture rather than an error.

### The worked example: the Tiled parser

rgame's Tiled plan was split correctly on the first pass — a faithful parse and a
runtime `TileMap` — and still let six of Tiled's words through to the game, `gid`
and milliseconds among them. The tell was smell 1: the runtime tileset class's
attributes matched the parsed tileset's, row for row.

**Absorbing all six made the layer below smaller, not larger.** The renderer's
signature stopped needing to change, solidity became an array read, the runtime
tileset class disappeared, and the shared contract lost more methods than it
gained. Expect that. A transform mostly collects work that was already being
done, in more places, later.

Hold it with a grep: the parse namespace may be named in its own directory and in
the transform, nowhere else.

## The verdict goes up front

A plan that answers a question states the answer in its first screen, under a
`## Verdict` heading, before the evidence. The reader who only reads the top
should come away with the decision, not the survey.

Alongside it, in the brief or the file header:

- **The goal**, in a sentence or two.
- **Hard constraints** — numbered, because later sections refer to them by
  number. The invariants of this codebase belong here when they bind: the
  layering rules, the zero-graphics load, the public API that must not move.
- **Decisions already taken**, each with its reasoning, under the explicit
  statement that they are not up for re-litigation inside the plan. This is
  where a decision taken in conversation gets written down so it survives.
- **Open questions**, numbered, each saying whether it blocks anything.

When an open question is settled, **resolve it in place**: strike the heading
through, state the answer, and link to the decision that now holds it.

```markdown
1. ~~**Default font.**~~ **Settled — the engine ships a font.** See
   ["The default font is vendored, not looked up"](#the-default-font-is-vendored-not-looked-up).
```

Deleting the question instead loses the fact that it was ever open, and it gets
asked again.

## The roadmap

Open with a **dependency shape** — an ASCII diagram of which step unblocks
which — so the ordering rationale is visible rather than implied:

```
0 harness ─→ 1 input ─→ 2 player ─→ 3 view ─→ 4 two views ─┬─→ 5 solo + pause ─┐
                 │                     │                    │                   ├─→ 6 per-player UI
                 └── independently useful ──────────────────┘                   ┘
```

Then, where it applies, **the invariant every step must preserve**, stated as a
blockquote and backed by a spec:

> **`control` and `update` run exactly once per node per tick, whatever the
> player count. Only `draw` multiplies.**

If several early steps are worth landing even if the whole plan is abandoned,
say so in a table of `step → defect it closes`. It converts a long plan into
several short ones and is honest about what the reader is committing to.

### Detail the next few steps only

**Plan steps 0–3 in detail and leave 4–6 rough.** Then re-plan each rough step
once the layer beneath it exists. This is not laziness and it is not an
estimate-avoidance trick; it is the one habit that measurably worked in every
plan here. A re-planned step routinely overturns something an earlier step
recorded as fact, and a step written out before its foundation existed has
always had to be rewritten anyway.

Say which steps are rough, in the document, at the top.

### What a step contains

Steps are numbered; sub-steps take a letter (`1a`, `1b`). **A step is a size,
not a topic: it is one branch and one pull request, and each of its sub-steps is
one commit.** Split a step at the boundaries where a commit would naturally
fall, and a step that needs no splitting has no sub-steps and is one commit.
[implement-step](../implement-step/SKILL.md) is what happens to it from there.

A step has, in this order:

1. **A heading that names the deliverable**, not the activity — the module or
   the file, with `(pure)` or a similar tag when the layering matters.
2. **Why it is here and why now**, in a paragraph. The dependency it satisfies,
   or the mistake it prevents.
3. **The concrete shape.** Write the struct, the header, the class skeleton or
   the method signature in a fenced block. A step whose API cannot be sketched
   yet is a step that is not ready to be detailed.
4. **The rules the tests must pin**, as a numbered list, when the step has
   behaviour worth stating independently of its implementation.
5. **Tests**, naming the file and listing each case in a phrase.
6. **Verify** — the acceptance criterion for this step specifically, and the
   command that decides it. The standing tiers are in
   [verify](../verify/SKILL.md) and do not need restating per step; what the
   step owes is the thing that is true afterwards and was not true before.

### Leave room for what happens next

Two things get written into a roadmap *after* it is planned, and the document
should expect them.

- **Landed notes.** Each implemented step grows a `**Landed.**` note recording
  how the result differed from the sketch. Do not pre-write them, and do not
  plan a step so tightly that there is no room to say it came out otherwise.
- **A status line at the top**, saying which steps are implemented and which are
  still rough.

Both are maintained by [implement-step](../implement-step/SKILL.md), which also
covers what a landed note has to say.

## The last step is deleting the plan

Every roadmap ends with a numbered step that folds the plan back into the real
documentation and deletes it. Write that step into the roadmap when you write
the roadmap; it is real work rather than a tidy-up, and a plan that does not
schedule its own removal does not get removed.
[implement-step](../implement-step/SKILL.md) covers how to carry it out.

That step also checks `CHANGELOG.md` against everything the plan shipped, and
updates it where an earlier step did not. The rules are in
[update-changelog](../update-changelog/SKILL.md). Write this into the step's
**Verify**, so it cannot be skipped.

## Before writing

- **Read the code first.** Every strong section in these plans came from
  reading the actual file and counting, and the weak ones came from
  remembering.
- **Ask for the requirement in the user's own words** and keep it verbatim in
  the folder if it arrives that way. One plan here began as a five-bullet
  requirement file that the design answered point by point.
- **State what the plan does not cover**, explicitly. A "what this does not
  deliver" section per phase stops scope arriving later disguised as a bug.

## Question rounds, between research and writing

After reading the code and before writing any plan document, settle what only
the user can decide. This is a loop, and each round ends your turn:

1. **Write the questions** to `docs/plans/<topic>-questions.md`. Where the
   research already turned up viable options, present them as lettered choices,
   each with its trade-off and your recommendation. Where it is genuinely open,
   ask plainly. Leave space under each question for the answer.
2. **Score your confidence** at the top of the file: the probability that the
   user's answers would *not* materially change the design or the roadmap's
   detailed steps. Beneath it, list what is holding the score down.
3. **Stop.** End the turn and tell the user the file is ready. Do not answer
   the questions yourself, and do not start the plan.
4. **Read the answers**, research anything they open up, and re-score. Below
   90%, write the next round into the same file under a new heading and go back
   to 3. At 90% or above, write the plan.

Only ask what changes the plan now. A question that cannot be answered until an
earlier step has landed is not a question-round question; it goes into the
plan's **Open questions**, marked with what it waits on.

When the plan is written, move every answered question into the brief: as a
**Decision already taken** with its reasoning, or visibly built into the
design. Then delete the questions file. A question dropped without being
recorded gets asked again.

## Worked examples, recoverable from git

Every earlier plan was folded back and deleted as intended, so most exemplars
live in history rather than the tree:

| Plan | Shape | Recover with |
|---|---|---|
| `gosu-replacement/` | brief + inventory + architecture + roadmap; 7 phases | `git show 6f3ed53:docs/plans/gosu-replacement/03-roadmap.md` |
| `ui-and-split-screen/` | brief + current state + prior art + design + roadmap | `git show b0af3c2:docs/plans/ui-and-split-screen/04-roadmap.md` |
| `engine-replacement/` | brief + roadmap, mostly mechanical | `git show 36396e6:docs/plans/engine-replacement/01-roadmap.md` |
| `local-space-transform.md` | single file: verdict, rejected options, prior art, plan | `git show 03448e4:docs/plans/local-space-transform.md` |
| `cross-platform-support.md` | single file, findings-led, every finding tagged measured | `git show 549f811:docs/plans/cross-platform-support.md` |
| `basic-examples.md` | single file, a catalogue rather than a roadmap: one entry per example, each with its landed note | `git show 92e04a5:docs/plans/basic-examples.md` |
| `i18n/` | brief + current state + prior art + design + roadmap; a step inserted mid-plan, and decisions taken in later question rounds | `git show 92e04a5:docs/plans/i18n/04-roadmap.md` |
| `tiled-format/` | brief + current state + prior art + design + roadmap; still live at the time of writing. The design is the worked example for [optimising for the game](#optimise-for-the-game-not-for-the-source) | `git show 7efe148:docs/plans/tiled-format/03-design.md` |
