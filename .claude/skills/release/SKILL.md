---
name: release
description: How to release a new version of the rgame gem — a release is a version bump merged to main, and CI publishes, tags and creates the GitHub release; never gem push, rake release or a hand-made tag. Covers choosing the version, the changelog section CI requires, the README roadmap, Gemfile.lock, and checking the published gem afterwards. Use whenever asked to release, publish or ship the gem, bump the version, cut a new version, or when a release job fails.
---

# Releasing the gem

**A release is a commit that bumps `RGame::VERSION` and reaches `main`.** The
`release` job in [.github/workflows/ci.yml](../../../.github/workflows/ci.yml)
does the rest. On every push to main it asks RubyGems whether the version in
[lib/rgame/version.rb](../../../lib/rgame/version.rb) exists. If not, it waits
for all three platforms to pass, then builds and pushes the gem, tags `vX.Y.Z`
and creates the GitHub release. The comments on that job explain each choice.

## Never publish by hand

- **No `gem push` and no `rake release`.** The gemspec sets
  `rubygems_mfa_required`, so a local push asks for a one-time password. It
  also skips the gate that holds the release until CI passes on Linux, macOS
  and Windows.
- **No hand-made tag.** CI tags after a successful push, so a tag never names a
  version RubyGems lacks.
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

## 5. Check the release

Watch the run on main:

```
gh run list --branch main --limit 1
gh run watch <run-id>
```

The `release` job should print `rgame X.Y.Z is not on RubyGems — releasing.`
Once it passes, confirm all three results:

```
gem search -r '^rgame$'                 # lists X.Y.Z
gh release view vX.Y.Z                  # body matches the changelog section
cd "$(mktemp -d)" && gem install rgame -v X.Y.Z && ruby -e 'require "rgame"; puts RGame::VERSION'
```

Run the last line outside the checkout. It is the only check that the published
gem compiles both extensions without the repository's files around it.

## When the release job fails

**Fix the cause and push again. Do not bump the version.** The job asks
RubyGems what exists on every push, so the next push to main picks up the
release where it stopped.

| Failure | Cause |
|---|---|
| `CHANGELOG.md has no section for X.Y.Z` | The heading is missing or spelled differently from `version.rb`. |
| `RubyGems answered NNN — refusing to guess` | RubyGems was unreachable. Re-run the job. |
| fails at setup, before any step | A `uses:` pin does not resolve. See the comment on the credentials step. |
| `gem push` rejected | The trusted publisher on rubygems.org no longer matches the repository or the workflow filename. |
| tagged, but `gh release create` failed | The gem is published. Create the release by hand with the changelog section as its body. |
