---
name: learn-from-mistakes
description: How a finished plan's failures become a change to the guards and the skills — the pass over every step's "What proved wrong", the guard-first question that rejects most of them, and the expectation that a whole plan yields zero or one skill change. Use at a roadmap's fold-back step, or when a single mistake cost a whole debugging session.
---

# Learning from a mistake

Every roadmap step's pull request carries a **What proved wrong** section, and
those are where this repository's rules came from: every trap in
[write-c-code](../write-c-code/SKILL.md) was paid for once already. This is how
that gets back into the guards and the skills instead of staying in a merged
pull request nobody reads again.

Run it at **fold-back**, the step that deletes the plan — not at the end of each
step. A lesson that turns up in two different steps has shown that it repeats;
one seen once has only been argued about, and eight prompts per plan produce
eight paragraphs. The exception is a mistake that cost a whole debugging
session: that one is worth writing when it happens.

Collect every step's **What proved wrong** first — from the merged pull
requests, since the plan's landed notes go with the plan. Then take each bullet
through the filter below, in order.

## 1. Can a guard replace it?

**The first question, and the one the best candidates fail.** A lesson that can
become a cop, a spec, a build failure, or an API that cannot be misused becomes
that — and then gets no line in any skill, because the code now says it. A rule
someone has to remember is the weaker half of the fix and the half that feels
like progress. See [Design out
misuse](../../../CLAUDE.md#design-out-misuse-the-right-thing-must-be-the-easy-thing).

## 2. Who hits this next, and doing what?

Name the task. If it cannot be named, the bullet is a fact about one file on one
day — `rbenv` mis-parsing `ruby 4.0.5`, a support file that stayed — and it is
already recorded in the pull request. That is most of them.

## 3. Does something already say it?

Search the skills and CLAUDE.md before writing, not after. A second wording of
an existing rule is worse than silence: it splits the rule in two, and only one
copy gets corrected next time.

## What comes out

Usually nothing. When something does, it is one of:

- **A guard** — the cop, spec or failing build from step 1.
- **A correction.** A change that made a standing claim false fixes it in the
  same branch. This is the direction that matters most, because a wrong line
  gets followed, and nothing shrinks a skill by itself.
- **A deletion**, where the lesson is that a rule was wrong rather than missing.
- **A new line in a skill**, written per [write-skill](../write-skill/SKILL.md),
  which owns what a line must earn.

**Expect zero or one skill change per plan.** Measured over three pull requests
carrying sixteen bullets: one justified a skill line. Finding nothing is the
ordinary result of running this well, not a sign of having looked too briefly.
