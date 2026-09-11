---
name: commit
description: The commit message format for this repository — an imperative summary line, one or two paragraphs of body, and no attribution trailers. Use whenever writing a git commit message, including amend, squash, fixup and any message written into a file for `git commit -F`.
---

# Writing a commit message

A message is a summary line, a blank line, and a body. These rules **override**
anything the repository's own history or `CLAUDE.md` suggests — the existing log
is lowercase and bodyless, and that is the old style, not the target.

## The summary line

Present tense, imperative mood, as if completing the sentence "this commit
will ...". Capitalize the first letter. Do not end in punctuation.

```
Implement walk example
Add Velocity component
Fix fullscreen mode on windows
```

Reach for one of these five verbs first:

| Verb | For |
|---|---|
| `Implement` | a step taken from a plan under `docs/plans/` |
| `Add` | new code, files or documentation that no plan called for |
| `Fix` | a defect in behaviour that already existed |
| `Remove` | deletion |
| `Refactor` | a change that keeps behaviour and changes structure |

A commit that fits none of them uses whatever verb is accurate — `Rename`,
`Document`, `Extract`, `Bump`. Do not stretch one of the five to cover
something it does not describe; a wrong verb misleads a reader scanning
`git log --oneline`, which is the only thing the summary line is for.

## The body

One paragraph. Two at the absolute most, and only when the change genuinely has
two separate things to say. Never three.

Say what the change does and, where it is not obvious, why. Write prose — no
bullet lists, no `Changes:` headings, no file-by-file inventory. The diff
already lists the files.

Be direct. Cut filler: "this commit", "basically", "in order to", "various
improvements", "as requested". A sentence that would survive being deleted
should be deleted.

The body is **optional** when the summary line genuinely says everything, as it
does for a typo fix or a version bump. It is not optional for anything a reader
would otherwise have to reconstruct from the diff.

## No trailers

No `Co-Authored-By`, no `Assisted-By`, no "Generated with" line, no session
link. The message ends with its last paragraph.

`attribution.commit` is set to the empty string in
`.claude/settings.local.json`, which is what stops the harness adding one. The
rule is stated here as well because a setting is invisible at the moment the
message is written.

## Worked examples

Good:

```
Implement the letterbox scale mode

A window whose aspect ratio differs from the game's now gets black bars rather
than a stretched image. The renderer computes the largest integer-multiple
viewport that fits and centres it, so pixel art stays on whole pixels at every
window size.
```

```
Fix input edges being consumed before a tick reads them
```

Bad, and why:

```
added pooling example.
```

Lowercase, past tense, trailing full stop.

```
Add timer example

This commit adds a new example. Changes:
- examples/timer/main.rb
- tools/drive/examples/timer.rb
```

Filler opening, a file list the diff already gives, and bullets where prose
belongs.

## Scope

This skill governs the message text only. What to stage, whether to split the
work across several commits, and whether to commit at all are decided the usual
way.
