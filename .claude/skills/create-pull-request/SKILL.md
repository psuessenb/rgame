---
name: create-pull-request
description: How to open a pull request for this repository — the title, the four sections of the body, no attribution trailers, and the gh commands that open it and report its CI. Use whenever a branch is finished and needs a pull request, including every step of a docs/plans roadmap.
---

# Opening a pull request

Every branch meant to reach `main` gets a pull request, and every step of a
roadmap is a branch — see [implement-step](../implement-step/SKILL.md) for how
a step becomes one.

The pull request is where the work is explained. The commits say what each
change does; the pull request says what was attempted, what actually happened,
and what that means for whoever reads the plan next.

## The title

Same rules as a commit summary line — imperative, capitalized, no trailing
punctuation — spelled out in [commit](../commit/SKILL.md). It names what the
branch delivers as a whole, not its first commit.

For a roadmap step, include the step so it is findable from the plan:

```
Implement step 3 — View, Layout and the draw signature sweep
```

## The body

Four sections, in this order. It is longer than a typical pull request body
because it is doing a second job: everything here is what gets folded back into
the plan as the step's landed note.

```markdown
## What the plan said

<The step as it was written *before* implementing — the sketch, the acceptance
criterion, and the assumptions it rested on. Quote or summarise it faithfully,
including the parts that turned out to be wrong. Link the plan document.>

## What was implemented

<What actually shipped, in concrete names. The modules, the classes, the
signatures. Where a sub-step needed more than one commit, or was split
differently from the plan, say so.>

## What proved wrong

<Bulleted. Each assumption the sketch made that did not survive contact, what
replaced it, and what it means for the steps that follow. Three or four is
normal. "Nothing" is a legitimate answer and is worth stating explicitly, but
it is rare enough to be worth double-checking.>

## Verification

<The tiers run and what they reported, in numbers. The step's own acceptance
criterion and the measured evidence that it is met.>
```

For a branch that is not part of a plan, the first section has nothing to
restate: use **What this is for** instead, and keep the other three.

Write prose and bullets, not a file-by-file inventory. The diff already lists
the files.

## No attribution

No `Co-Authored-By`, no `Assisted-By`, no "Generated with" line, no session
link — in the body or the commits it contains.

`attribution.pr` and `attribution.commit` are both set to the empty string in
`.claude/settings.local.json`, which is what stops the harness adding one. The
rule is stated here as well because a setting is invisible at the moment the
body is written.

## Opening it

Push the branch and open the request with the body from a file, so the markdown
survives the shell:

```
git push -u origin <branch>
gh pr create --title "<title>" --body-file <path>
```

Write the body to a file first — in the scratchpad, not the repository — and
pass it with `--body-file`. Building the body inside the `gh` invocation means shell
quoting eats the markdown, and a heredoc leaves nothing to re-read if the call
fails.

`--base` is not needed while `main` is the default branch. Report the URL `gh`
prints; that is what the user opens.

## After opening

CI runs on pull requests and covers Linux, macOS and Windows
(`.github/workflows/ci.yml`). A green local run is not a green pull request: two
of the three platforms are only ever exercised there.

Report the CI result, read with `gh pr checks` from the branch. If it fails on
a platform you cannot reproduce locally,
read the log and say what broke rather than guessing at a fix — and see
[windows-portability](../windows-portability/SKILL.md), which catalogues the
failures that only appear off Linux.

Merging is the user's decision. Do not merge a pull request unless asked.
