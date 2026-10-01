---
name: implement-step
description: How to implement one step of a roadmap under docs/plans — a branch per step, one commit per sub-step, verification at the end, a landed note recording what the sketch got wrong, and a pull request. Use when picking up the next step of a plan, when asked to implement step N, or when a plan's work is finished and needs folding back.
---

# Implementing a step

One step of a roadmap is one unit of work with one branch and one pull request.
[write-plan](../write-plan/SKILL.md) covers how plans and their steps are
written; this skill covers building a step once it exists.

## The loop

1. **Read the step, and everything above it.** The brief's constraints and
   decisions, the design, and every landed note on the steps before this one.
   Read the landed notes most carefully. They record where the plan has already
   turned out wrong, and usually why the current step's sketch needs adjusting.
2. **Re-plan it first if it is rough.** A roadmap details only its next few
   steps. If the step you are starting is one of the deliberately rough ones,
   first write it out in full against the code that now exists — see
   [write-plan](../write-plan/SKILL.md). Do not implement from a sketch written
   before its foundation existed.
3. **Branch.** One branch per step, cut from an up-to-date `main`.
4. **Implement, one sub-step at a time**, committing each.
5. **Verify.** The step ends green.
6. **Write the landed note** into the plan.
7. **Open the pull request** — see
   [create-pull-request](../create-pull-request/SKILL.md). A request to
   implement a step already approves the push and the pull request, so do not
   stop after the last commit to ask; one step did, and the user had to ask for
   it. Merging still waits for the user.

Do not start the next step in the same branch. If step 3's pull request is still
open and step 4 is unblocked, branch step 4 from step 3's branch and say so in
the pull request, rather than growing one branch into two steps.

## The branch

Name it after what the step delivers, in kebab-case, like the names already in
this repository:

```
git switch main && git pull
git switch -c input-map
```

Where the deliverable's name would be ambiguous on its own, prefix it with the
plan's topic: `split-screen-viewports`. Do not number the branch after the step:
re-planning renumbers steps, and a branch outlives that.

## One sub-step, one commit

**Each sub-step is a commit.** Step 3a is a commit, 3b is the next one, 3c the
one after. A step with no sub-steps is a single commit.

That makes a step reviewable. The plan chose each sub-step as a coherent
change, so the commit boundaries are decided before the work starts. If a
sub-step needs three commits to stay coherent, the plan split it wrongly: make
the commits, and say so in the landed note.

Commit messages follow [commit](../commit/SKILL.md). A sub-step's commit
summary names what that sub-step delivers, not the step it belongs to.

Do not carry unrelated fixes along. Something broken that the step does not
touch gets its own branch, or a note in the plan's open questions.

## Verifying

Every step ends green, and green means the tiers in
[verify](../verify/SKILL.md), not only the fastest one. Verify anything that
changes how the layers are wired together by *driving* a test project, not by
booting one.

The step's own `Verify` block in the plan holds its acceptance criterion: what
counts as passing for this step. Run it, and record what it reported, in
numbers. The landed note and the pull request body are built from that
measurement.

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

The note carries the same material as the pull request body, which
[create-pull-request](../create-pull-request/SKILL.md) specifies. It leaves out
the restatement of the sketch, since that is on the page directly above. In
practice: what shipped, the suite numbers, the measured acceptance evidence, the
bullets of what the sketch got wrong, and where it got documented.

Then update the document's status line at the top, so a reader knows where the
work stands without reading to the bottom: *"Steps 0–4 are implemented"*.

## Deviating from the plan

Expected, and not a failure. The plan was written against the code as it was
understood before the step existed.

- **Follow the code, not the sketch.** When the two disagree, the code wins and
  the note records the disagreement.
- **A decision the plan left open, taken during the step**, goes back into the
  plan's open questions, resolved in place, not only into the commit message.
- **A discovery that invalidates a later step** is worth stopping for. Say so in
  the pull request, and mark that later step as needing a re-plan.
- **"Just one field from the parser" is the design failing, not a shortcut.**
  When a step needs something a transform was supposed to absorb, the gap is in
  the transform and that is where the fix goes. Reaching past it — holding the
  source-shaped object, passing a raw id through, converting at the call site —
  puts the format back into the interface the plan took it out of, one field at a
  time. See
  [write-plan](../write-plan/SKILL.md#optimise-for-the-game-not-for-the-source).

## Finishing the plan

The last step of a roadmap is folding the plan back and deleting it.

Whatever is still true moves into CLAUDE.md or `docs/api/` (written per
[write-docs](../write-docs/SKILL.md)). The plan's steps have often updated the
documentation already; double-check now that it is up to date. Then the file or
folder goes; `git log` keeps the rest.

**An open question still open goes with the plan.** It has no answer to lose,
and one that matters comes back. It moves to
[`possible-todos.md`](../../../docs/plans/possible-todos.md) only with a trigger
that file's header accepts. Fold-backs used to move every open question there,
and the file filled with triggers like "a scene that needs it", which any entry
could claim.

**A measured bug the plan did not fix is the exception.** It neither goes with
the plan nor becomes a possible todo. Ask the user about each one before
deleting the plan, and let them decide what happens to it.

Then read all of `possible-todos.md`, not only the entries this plan touched.
Delete an entry the code has answered or made moot, and correct one whose
premise, numbers or examples no longer hold. Premultiplied alpha made the
multiply-blend entry's GL call draw black, and research for another feature
was what found it.

At fold-back, also read the plan's failures as a whole and turn them into a
guard or a skill change — see
[learn-from-mistakes](../learn-from-mistakes/SKILL.md), which expects to find
nothing most times.

That fold-back is itself a step, so it gets a branch and a pull request like any other.
