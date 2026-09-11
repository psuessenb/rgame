---
name: implement-step
description: How to implement one step of a roadmap under docs/plans — a branch per step, one commit per sub-step, verification at the end, a landed note recording what the sketch got wrong, and a pull request. Use when picking up the next step of a plan, when asked to implement step N, or when a plan's work is finished and needs folding back.
---

# Implementing a step

One step of a roadmap is one unit of work with one branch and one pull request.
How plans and their steps are written is [write-plan](../write-plan/SKILL.md);
this is what happens once a step exists and it is time to build it.

## The loop

1. **Read the step, and everything above it.** The brief's constraints and
   decisions, the design, and every landed note on the steps before this one.
   The landed notes are the part to read most carefully: they record where the
   plan has already turned out to be wrong, and they are usually the reason the
   current step's sketch needs adjusting.
2. **Re-plan it first if it is rough.** A roadmap details only its next few
   steps. If the step you are starting is one of the deliberately rough ones,
   the first task is writing it out properly against the code that now exists —
   see [write-plan](../write-plan/SKILL.md). Do not implement from a sketch that
   was written before its foundation existed.
3. **Branch.** One branch per step, cut from an up-to-date `main`.
4. **Implement, one sub-step at a time**, committing each.
5. **Verify.** The step ends green.
6. **Write the landed note** into the plan.
7. **Open the pull request** — see
   [create-pull-request](../create-pull-request/SKILL.md).

Do not start the next step in the same branch. If step 3's pull request is still
open and step 4 is unblocked, branch step 4 from step 3's branch and say so in
the pull request, rather than growing one branch into two steps.

## The branch

Named after what the step delivers, in kebab-case, matching the names already in
this repository:

```
git switch main && git pull
git switch -c input-map
```

Where the deliverable's name would be ambiguous on its own, prefix it with the
plan's topic: `split-screen-viewports`. Do not number the branch after the step;
step numbers get renumbered when a plan is re-planned, and a branch outlives
that.

## One sub-step, one commit

**Each sub-step is a commit.** Step 3a is a commit, 3b is the next one, 3c the
one after. A step with no sub-steps is a single commit.

This is what makes a step reviewable: the sub-steps were chosen in the plan
because each is a coherent change, and the commit boundaries are already
decided by the time the work starts. If a sub-step turns out to need three
commits to stay coherent, that is a signal the plan split it wrongly — make the
commits, and say so in the landed note.

Commit messages follow [commit](../commit/SKILL.md). A sub-step's commit
summary names what that sub-step delivers, not the step it belongs to.

Do not carry unrelated fixes along. Something broken that the step does not
touch gets its own branch, or a note in the plan's open questions.

## Verifying

Every step ends green, and green means the tiers in
[verify](../verify/SKILL.md), not just the one that is fastest to run. Anything
that changes how the layers are wired together is verified by *driving* a test
project, not by booting one.

The step's own `Verify` block in the plan says what specifically counts as
passing for this step — an acceptance criterion the step was written to meet.
Run it, and record what it actually reported, in numbers. That measurement is
what the landed note and the pull request body are built from.

If verification fails in a way the plan did not anticipate, that is content:
fix it, and record it. A step whose verification was quietly narrowed until it
passed is worse than a failing one.

## The landed note

When the step is done, append a `**Landed.**` note to that step in the plan.

**Do not edit the sketch to match what happened.** The gap between what was
planned and what shipped is the most valuable thing in the document, and it is
what the next step needs. Correct the sketch in place only when it states
something actively false that a later reader would follow off a cliff, and say
in the note that you did.

The note carries the same material as the pull request body —
[create-pull-request](../create-pull-request/SKILL.md) specifies it — minus the
restatement of the plan's sketch, which is already on the page directly above.
In practice that is: what shipped, the suite numbers, the measured acceptance
evidence, the bullets of what the sketch got wrong, and where it got documented.

Then update the document's status line at the top, so a reader knows where the
work stands without reading to the bottom: *"Steps 0–4 are implemented"*.

## Deviating from the plan

Expected, and not a failure. The plan was written against the code as it was
understood before the step existed.

- **Follow the code, not the sketch.** When the two disagree, the code wins and
  the note records the disagreement.
- **A decision the plan left open, taken during the step**, goes back into the
  plan's open questions, resolved in place, not just into the commit message.
- **A discovery that invalidates a later step** is worth stopping for. Say so in
  the pull request, and mark that later step as needing a re-plan.

## Finishing the plan

The last step of a roadmap is folding the plan back and deleting it, and it is
real work rather than a tidy-up.

Whatever is still true moves into CLAUDE.md, `docs/api/`, or a comment at the
code it describes. Then the file or folder goes; `git log` keeps the rest. A
plan that outlives its work is a stale description of code that no longer
exists.

The thing to hunt for is **anything a landed note records that exists nowhere
else** — a deliberate deviation from the obvious implementation, a decision
whose reasoning the code does not show, a bug that a test now guards without
saying why. Those are the rescues, and a plan of any size usually has three or
four. Everything else is history, and git already has it.

That fold-back is itself a step, so it gets a branch and a pull request like any
other.
