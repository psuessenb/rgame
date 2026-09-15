---
name: update-changelog
description: How to update CHANGELOG.md — what gets an entry (only what ships in the gem), one short paragraph per change with a link for the rest, editing an unreleased entry rather than adding a second one, and how to find what changed since the last release. Use whenever editing CHANGELOG.md, when a change to the gem's public surface lands, when checking the changelog before a release, or as part of a plan's last step.
---

# Updating the changelog

`CHANGELOG.md` tells someone *using* the gem what changed for them. It follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/): new work goes under
`## [Unreleased]`, sorted into `Added`, `Changed`, `Removed` and `Fixed`. Its
prose follows [write-prose](../write-prose/SKILL.md).

Released sections are history. Leave them alone.

## What gets an entry

**Only what ships in the gem gets an entry.** `rgame.gemspec` decides that
through its `packaged` globs: `lib/`, `ext/`, `exe/`, `examples/`, `docs/api/`,
`README.md`, `CHANGELOG.md` and `LICENSE`.

| Listed | Not listed |
|---|---|
| a new, changed or removed public class, method, keyword or default | Claude skills, `CLAUDE.md` |
| a behaviour change a game can observe | CI, the Makefile, RuboCop config and custom cops |
| a new C-backed capability (fullscreen, locales) | specs, `spec_core/`, the Check suite |
| a new example under `examples/` | `tools/`, drive scripts, `test_projects/` |
| a bug fix to something already released | plans under `docs/plans/` |
| a documentation error a user would have followed | rewording or restyling a page |

A refactor with no visible effect gets no entry, even inside `lib/`. Making a
public method private *is* visible, so it gets one.

## One change, one short paragraph

**No entry runs longer than a single short paragraph.** Open with a bold
summary sentence. Follow it with the names a user needs to find the change, and
for a breaking change, what to write instead. If you want to write more,
write only the summary and link the page in `docs/api/` that explains the rest:

```markdown
- **Menus open and close.** A menu answers `open?`, `open` and `close`, and
  emits `on_opened` and `on_closed`. See [docs/api/ui.md](docs/api/ui.md).
```

An entry never explains why a change was made. That belongs in the page it
links to.

A feature that grew over several pull requests is still several features to a
reader. Split it by what a game author would look for — buttons, layouts,
opening and closing — rather than writing one entry that lists every step.

## Describe the change since the last release

**If a change only touches something that has not been released yet, edit the
existing Unreleased entry instead of adding a new one.** A reader upgrading
from the last release never saw the intermediate state. So for them:

- A fix to an unreleased feature is not a fix. The feature's entry simply
  describes the fixed behaviour.
- A rename of an unreleased class is not a rename. The entry uses the new name,
  and the old one appears nowhere.
- A class added and removed within the same cycle appears nowhere.
- A breaking change is stated against the released API, not against the
  previous commit.

Before writing an entry, check the name against the last release:

```
git tag                                         # the last release, e.g. v0.2.0
git show v0.2.0:lib/rgame/engine/ui/menu.rb     # did this exist, and in what shape?
git ls-tree -r --name-only v0.2.0 lib/rgame/engine
```

## Checking the whole Unreleased section

When catching up — before a release, or when the changelog has fallen behind:

1. List what changed since the last tag in the shipped directories:
   `git diff --stat v0.2.0..HEAD -- lib ext exe examples docs/api README.md`.
2. Read the commit bodies: `git log --format='%h %s%n%b' v0.2.0..HEAD -- lib ext exe examples`.
3. For each public file, diff the signatures rather than the bodies. Comments
   are stripped on commit, so filter comment lines out of the diff, or they
   bury the real changes.
4. Sort every change into the table above, then into the four sections.
5. Check each existing Unreleased entry against the released API, and rewrite
   any that describe an intermediate state.
