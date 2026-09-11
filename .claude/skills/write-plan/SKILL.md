---
name: write-plan
description: How to write a plan under docs/plans — research and measurement first, a verdict up front, then a roadmap whose steps are sized to one branch and one pull request each, with later steps left deliberately rough. Use when asked to plan a feature, a refactor, a port or a rework, when starting a new docs/plans document or folder, or when re-planning the next phase of an existing one.
---

# Writing a plan

A plan in this project is **not** a task list. Every plan that worked here was
mostly research — inventory, measurement, prior art, rejected alternatives — and
the roadmap at the end was the short part that fell out of it. Write it in that
order and the roadmap mostly writes itself. Write the roadmap first and it will
be fiction.

Plans live in `docs/plans/`. Per CLAUDE.md they are **working documents**: they
may name previous iterations of the code, record what a prompt decided, and
leave questions open. They are also temporary, and a roadmap schedules its own
removal as its last step.

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

Tag any finding you actually verified, so a reader can tell measurement from
expectation:

```markdown
### A3. The root Makefile hardcodes Linux — *(measured: this is what fails first)*
### A1. `#include <SDL2/SDL.h>` — optional robustness *(measured: not a blocker)*
```

Two research sections earn their place nearly every time:

- **Prior art.** How Unreal, Unity, Bevy, Godot, or whichever engines are
  relevant answer the same question, what they agree on, and — the useful part —
  **what none of them gives us**. Cite sources.
- **What was considered and rejected.** The alternative with its real
  attractions stated, then the specific reason it fails. A rejected option
  without a reason gets proposed again in three weeks.

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

## Before writing

- **Read the code first.** Every strong section in these plans came from
  reading the actual file and counting, and the weak ones came from
  remembering.
- **Ask for the requirement in the user's own words** and keep it verbatim in
  the folder if it arrives that way. One plan here began as a five-bullet
  requirement file that the design answered point by point.
- **State what the plan does not cover**, explicitly. A "what this does not
  deliver" section per phase stops scope arriving later disguised as a bug.

## Worked examples, recoverable from git

Every earlier plan was folded back and deleted as intended, so the exemplars
live in history rather than the tree:

| Plan | Shape | Recover with |
|---|---|---|
| `gosu-replacement/` | brief + inventory + architecture + roadmap; 7 phases | `git show 6f3ed53:docs/plans/gosu-replacement/03-roadmap.md` |
| `ui-and-split-screen/` | brief + current state + prior art + design + roadmap | `git show b0af3c2:docs/plans/ui-and-split-screen/04-roadmap.md` |
| `engine-replacement/` | brief + roadmap, mostly mechanical | `git show 36396e6:docs/plans/engine-replacement/01-roadmap.md` |
| `local-space-transform.md` | single file: verdict, rejected options, prior art, plan | `git show 03448e4:docs/plans/local-space-transform.md` |
| `cross-platform-support.md` | single file, findings-led, every finding tagged measured | `git show 549f811:docs/plans/cross-platform-support.md` |
