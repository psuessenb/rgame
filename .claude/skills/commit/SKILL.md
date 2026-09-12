---
name: commit
description: The commit message format for this repository — an imperative summary line, one or two paragraphs of body, and no attribution trailers. Use whenever writing a git commit message, including amend, squash, fixup and any message written into a file for `git commit -F`.
---

# Writing a commit message

A summary line, a blank line, a body. These rules **override** the repository's
own history: 88 of its 123 commits are lowercase and bodyless, and that is the
old style, not the target.

## The summary line

Imperative mood, as if completing "this commit will ...". Capitalized, no
trailing punctuation. Reach for one of these verbs first:

| Verb | For |
|---|---|
| `Implement` | a step taken from a plan under `docs/plans/` |
| `Add` | new code, files or documentation that no plan called for |
| `Fix` | a defect in behaviour that already existed |
| `Remove` | deletion |
| `Refactor` | a change that keeps behaviour and changes structure |

A change that fits none of them uses whatever verb is accurate — `Rename`,
`Document`, `Extract`, `Bump`. Do not stretch one of the five: the summary
line's only job is to read correctly in `git log --oneline`, and a wrong verb
misleads the person scanning it.

## The body

One paragraph. Two at the most, and only when the change genuinely has two
things to say. Never three.

Say what the change does and, where it is not obvious, why. Prose only — no
bullets, no `Changes:` heading, no file-by-file inventory, because the diff
already lists the files. Cut filler: "this commit", "basically", "in order to",
"various improvements", "as requested". A sentence that would survive being
deleted should be deleted.

Omit the body only when the summary genuinely says everything, as in
`Fix input edges being consumed before a tick reads them`.

## No trailers

No `Co-Authored-By`, no `Assisted-By`, no "Generated with" line, no session
link. The message ends with its last paragraph.

## Worked example

```
Implement the letterbox scale mode

A window whose aspect ratio differs from the game's now gets black bars rather
than a stretched image. The renderer computes the largest integer-multiple
viewport that fits and centres it, so pixel art stays on whole pixels at every
window size.
```

Against that, `added pooling example.` is wrong three ways: lowercase, past
tense, trailing full stop.

## Scope

The message text only. What to stage, whether to split the work across several
commits, and whether to commit at all are decided the usual way.

Write the body from what you already know. When you made the change in this
session, `git diff --stat` is enough to confirm the scope; read the full diff
only when committing work you did not do yourself.
