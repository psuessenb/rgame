---
name: release
description: How to release a new version of the rgame gem — a release is a version bump merged to main, and CI tags, publishes four gems (three platform gems and the source gem) and creates the GitHub release; never gem push, rake release or a hand-made tag. Covers choosing the version, the changelog section CI requires, the README roadmap, Gemfile.lock, checking the published gems afterwards, and finishing a release that got only some of them up. Use whenever asked to release, publish or ship the gem, bump the version, cut a new version, or when a release job fails.
---

# Releasing the gem

**A release is a commit that bumps `RGame::VERSION` and reaches `main`.** The
`release` job in [.github/workflows/ci.yml](../../../.github/workflows/ci.yml)
does the rest.

**A version is four gems, not one.** `build-gem` and `source-gem` upload them —
one each for `arm64-darwin`, `x86_64-linux-gnu` and `x64-mingw-ucrt`, plus the
source gem — and the release job builds nothing itself. It downloads all four.

On every push to main it asks RubyGems which gems of the version in
[lib/rgame/version.rb](../../../lib/rgame/version.rb) are missing. If any are,
and this commit may release them, it tags `vX.Y.Z`, pushes the three platform
gems, pushes the source gem last, and creates the GitHub release. The comments
on that job explain each choice.

**Two questions decide a release, not one.** The first is what is missing. The
second is whose release it is, and the tag answers it: a version already partly
published belongs to the commit `vX.Y.Z` names, and no other commit may finish
it. That is why the tag goes in before the first `gem push` rather than after —
once a gem is up, the tag is the only record of which commit put it there.

## What the four gems are

The source gem is the one `rgame.gemspec` describes, and it compiles on install.
**A platform gem carries `core_ext` and `util_ext` already built**, ships no `.c`,
no `extconf.rb` and no `spec.extensions`, and therefore compiles nothing.
RubyGems picks by platform and Ruby version, so every other machine gets the
source gem and the behaviour it always had.

**SDL2 is linked statically into `core_ext`, from a pinned upstream release
fetched and checksummed at build time.** It is not vendored into `ext/`, and it
is not bundled beside the extension as a shared library — a static link needs no
loader configuration on any of the three platforms. `rakelib/sdl2.rake` builds
it; `ext/README.md` has the commands, including how to build the static path in a
checkout.

A platform gem is bounded to one Ruby ABI, so Ruby 4.1 falls back to the source
gem rather than load a binary it cannot. The macOS binaries target macOS 11.0 and
the Linux ones glibc 2.29, both the oldest that runs Ruby 4.0 there: **a platform
gem must never rule out a machine Ruby itself runs on.**

Three things hold this up without anyone remembering them.
`tools/platform_gem.rake` runs `tools/check_platform_gem.rb` on every gem it
builds, which opens the `.gem` archive and checks nine rules — the platform, the
two binaries and their extensions, that no source or `extconf.rb` is present, the
Ruby bound, SDL2's licence, the file list against the source gem's, the linkage,
and that neither binary needs a newer OS than the gem claims. CI's `smoke` job
then installs the gem on a runner with **no SDL2 and no compiler** and plays the
examples out of it through `tools/check_installed_gem.rb`, because a gem that
builds is not yet a gem that runs somewhere else. And the `test` job still builds
from source against a system SDL2 on all three platforms, so the source path
stays covered rather than becoming the untested fallback.

## Never publish by hand

- **No `gem push` and no `rake release`.** The gemspec sets
  `rubygems_mfa_required`, so a local push asks for a one-time password. It
  also skips the gate that holds the release until CI passes on Linux, macOS
  and Windows.
- **No hand-made tag.** The job tags itself, just before the first push, and
  then reads that tag to decide who owns the release. A tag you made by hand
  either names the wrong commit or tells the job that a release nobody has made
  is already claimed.
- **Do not rename `ci.yml`.** RubyGems trusts that workflow filename for
  trusted publishing. A rename breaks publishing until someone updates the
  trusted publisher on rubygems.org.

## 1. Choose the version

Read `CHANGELOG.md` against [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Before 1.0, a breaking change bumps the minor version, and so does a new
feature. A release of fixes only bumps the patch version.

Ask the user to confirm the version. RubyGems never takes a version back.

## 2. Catch up the changelog

Run "Checking the whole Unreleased section" from
[update-changelog](../update-changelog/SKILL.md) first. The Unreleased section
becomes the release notes on GitHub, word for word.

## 3. Write the release commit

One commit, in the shape of `b07b8f1 Publish version 0.2.0`:

1. **`lib/rgame/version.rb`** — the new version. Change nothing else in that
   file.
2. **`CHANGELOG.md`** — insert `## [X.Y.Z] - YYYY-MM-DD` directly below
   `## [Unreleased]`, and leave the Unreleased heading empty. Update the link
   footer:

   ```markdown
   [Unreleased]: https://github.com/psuessenb/rgame/compare/vX.Y.Z...HEAD
   [X.Y.Z]: https://github.com/psuessenb/rgame/compare/vPREVIOUS...vX.Y.Z
   ```

   **CI fails the release when the changelog has no section for the version**,
   and it checks before `gem push`. A missing heading stops the release; it
   does not publish a gem without notes.
3. **`README.md`, the Roadmap section** — delete every entry marked `DONE`. If
   no entry remains, replace the list and its introduction with one sentence:
   there is currently no roadmap for the next version.
4. **`Gemfile.lock`** — run `bundle install`. The lock records the gem's own
   version twice, and a stale lock fails `bundle` in CI.

Run `rake spec` before committing. `spec/packaging_spec.rb` is the check that
matters here. Write the message with the [commit](../commit/SKILL.md) skill.

## 4. Get it to main

Pushing to main publishes the gem, so **ask the user before you push or
merge**. The release commit may go through a pull request (see
[create-pull-request](../create-pull-request/SKILL.md)) or straight onto main.
CI publishes nothing from a branch.

A pull request runs only the test tiers; the gems are built on main. So for a
release that goes through a pull request, **run the full workflow on the branch
before merging**:

```
gh workflow run CI --ref <branch>
```

That builds all four gems and plays two examples out of each platform gem on a
runner with no SDL2 and no compiler, without publishing. Read `build-gem` and
`smoke`: a binary that needs a library the user does not have, or an OS newer
than the gem claims, fails there. On main the `release` job waits for both, so a
gem that fails them is never published — but the version is then stuck until a
fix lands.

## 5. Check the release

Watch the run on main:

```
gh run list --branch main --limit 1
gh run watch <run-id>
```

The `release` job should print the four platforms it is about to push, source
gem last:

```
rgame X.Y.Z is not on RubyGems — pushing arm64-darwin, x86_64-linux-gnu, x64-mingw-ucrt, ruby.
```

Once it passes, confirm all three results:

```
curl -s https://rubygems.org/api/v1/versions/rgame.json |
  ruby -rjson -e 'JSON.parse($stdin.read).select { _1["number"] == "X.Y.Z" }.each { puts _1["platform"] }'
gh release view vX.Y.Z                  # body matches the changelog section
cd "$(mktemp -d)" && gem install rgame -v X.Y.Z && ruby -e 'require "rgame"; puts RGame::VERSION'
```

**The first must list four platforms.** `gem search -r '^rgame$'` prints one
line for the version whatever it holds, so it cannot tell you a platform gem is
missing.

Run the last line outside the checkout. On a covered platform it installs
without a compiler, which is the whole point; on any other it compiles the
source gem, which is the check that the published source still builds with none
of the repository's files around it.

## When the release job fails before it publishes

**Fix the cause and push again. Do not bump the version.** The job asks RubyGems
what exists on every push, so the next push to main picks the release up where
it stopped. This holds while nothing has been published: with no gem of the
version up, the job lets any commit release it.

| Failure | Cause |
|---|---|
| `CHANGELOG.md has no section for X.Y.Z` | The heading is missing or spelled differently from `version.rb`. |
| `RubyGems answered NNN — refusing to guess` | RubyGems was unreachable. Re-run the job. |
| `FAIL rule 2: no gem for <platform>` | One of the four gems never arrived. The release refuses a short set rather than publishing three quarters of a version. |
| fails at setup, before any step | A `uses:` pin does not resolve. See the comment on the credentials step. |
| `gem push` rejected | The trusted publisher on rubygems.org no longer matches the repository or the workflow filename. |
| tagged, but `gh release create` failed | The gems are published. Create the release by hand with the changelog section as its body. |

## Finishing a partial release

A release is four pushes, so the third can fail with two already up. The version
is then partly on RubyGems and `vX.Y.Z` names the commit that put it there.

**Re-run the failed run. Do not push a new commit.** Only the commit the tag
names may finish a release, and a new commit on main moves HEAD away from that
tag — the job would refuse. A re-run keeps the same commit, so the job finds
what is missing and pushes only that:

```
rgame X.Y.Z is missing 1 of its 4 gems, and vX.Y.Z names this commit — pushing ruby.
```

If the failure needs a code change rather than a retry, **bump the version.**
The tag cannot follow the fix onto a new commit, and RubyGems never takes a
published gem back, so the partly-released version stays as it is and the fix
ships as the next one.

Two refusals say the job decided a release was not this commit's:

| Message | What it means |
|---|---|
| `... but vX.Y.Z names <sha> and HEAD is <sha>. That release belongs to another commit` | The version is partly published and this is not the commit that started it. Bump the version. |
| `vX.Y.Z names <sha>, and no gem of rgame X.Y.Z is on RubyGems` | A tag exists that no gem followed — a run that tagged, then failed every push. Delete the tag to release this commit, or bump the version. |

Neither fails the run. A version released before platform gems existed is
missing three of them for good, so refusing is a quiet no-op rather than a red
`main`.
