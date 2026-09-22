---
name: write-docs
description: How to write reference documentation under docs/api and keep it matching the code — what a page may say (the current code, nothing else), searching every page when code changes, claims backed by a line of code, example conventions the doc specs check, and auditing a page. Prose style is write-prose. Use whenever creating or editing a page in docs/api/, when a code change needs its documentation updated, when a doc spec fails, when auditing documentation against the code, or when folding a finished plan back into the documentation.
---

# Writing documentation

Reference documentation lives in `docs/api/`. It ships inside the gem, so its
reader has installed rgame and has nothing else. Write every page for that
reader. They have only the current code and took no part in writing it. The page
should help them understand that code and use it.

The top-level `README.md` and `ext/README.md` stay where they are. They cover
setup and orientation, not reference material.

Plans under `docs/plans/` follow different rules. See
[write-plan](../write-plan/SKILL.md).

Load [write-prose](../write-prose/SKILL.md) before writing a page. Its style
rules decide how every sentence reads; this skill decides only what a page may
say.

---

## When code changes

**A change to public behaviour is not done until every page that mentions it is
right.** Stale pages are rarely the page that owns the class. They are other pages
that mention it in passing, written when it worked differently. So:

1. **Search all of `docs/api/`** for every class, method, option, signal and file
   name the change adds, renames, removes or changes. Fix every hit, on every page.
2. **Update the owning page.** A new public method, keyword, signal or reader gets a
   row or a sentence. A removed one loses it.
3. **Update the index entries.** A new page gets a row in the tables of
   `docs/api/README.md`, and its row there says what the page covers. A new example
   under `examples/` gets a `### name` entry in `docs/api/examples.md`.
4. **Trim "What this is not".** When a change fills a gap one of those sections
   names, remove it from the list.
5. **Name every new public class and method on a page, or take it out of the
   public API.** `spec_core/api_docs/coverage_spec.rb` fails on one no page names;
   `bundle exec rake docs:coverage` prints the whole list, and CI runs it too. Run
   it through `bundle exec rake`, not as `ruby tools/doc_coverage.rb`: outside the
   bundle it can load an installed rgame gem instead of this checkout. For each
   name, decide:
   - **A game author calls it** → document it.
   - **Only its own class calls it** → make it private. A C binding behind a Ruby
     wrapper is registered with `rb_define_private_method`.
   - **Another engine class calls it**, so Ruby needs it public → put
     `# @api private` in the comment above it. On a class, the tag covers
     everything inside.

## What a page may say

**Describe the code as it is now.** Do not describe how it got there. A page never
mentions:

- prompts, or decisions taken in them;
- implementations that no longer exist ("used to", "replaces the earlier…",
  "now", "still");
- throwaway example code written while building the feature;
- other game engines or games. Prior art belongs in plans, where it helps. The
  reference documentation leaves it out.

### Every claim has a line of code behind it

**Find the code that makes a sentence true before you write it.** Write from the
code, not from memory of the design. Three kinds of sentence go wrong most often:

- **Absolute claims.** A sentence with "only", "never", "every", "always", "no",
  "cannot", "without" or "yet" states something about the whole codebase. Search
  for the counterexample. "The only class directly under `RGame`" was false because
  `RGame::CLI` exists. If you cannot find the line that makes the claim true, cut
  the claim.
- **Options, modes and policies.** Document what **each** value does on **every**
  path: success, failure, a repeat call, `nil`, and what happens when the
  surrounding state changes (a device unplugged, a second track started, a seat
  already taken). Read each branch of the implementing method. A table that
  describes only the happy path of each row is the typical drift.
- **Defaults and lifecycles.** Say what exists without setup and what does not. A
  `Game` builds its renderer, asset manager and tile map loader; a plain `App`
  builds some of them lazily and never builds the loader. Check the constructor and
  the first-use path, not the class comment.

### Say which context a page is written for

**The reader writes a game on `RGame::Game`.** Lead with that path:

- **Engine-layer examples are scene code.** A node receives the renderer in
  `_draw` and plays sound through the `AudioOut` system. When a page drives `RGame::Core`
  from a plain `App` to show the calls, it says so.
- **Name the entry point.** State whether an example is a `Game` scene, a plain
  `App`, a spec, or a command in a repository checkout.
- **Label what exists only in the repository.** `spec/support/`, the RuboCop cops,
  `make` targets and `tools/` do not ship in the gem. Say "rgame's own suite" or
  "in a checkout" when a page mentions them.
- **Paths say what they resolve against.** `app.assets` resolves against
  `media_root`; `Image.new`, `audio.sample` and `SpriteSheet.load` resolve against
  the working directory.

## Code examples

**Every code example stands on its own and matches the current code.** Examples
follow the engine's own rules: they build labels with `Engine::Text`, draw
in local space, and never name `RGame::Core` from engine-layer code.

**An example's first line decides how the specs check it:**

| First code line | Kind | Checked by |
|---|---|---|
| `require 'rgame'`, and no windowed require below it | complete, headless | run in its own process; every `# =>` comment asserted |
| `require 'rgame/core'` or `require 'rgame/game'` anywhere | complete, windowed | parsed; a syntax error fails |
| anything else | fragment | not run; its page's prose names are still resolved |

So:

- **Make an example complete whenever you can.** Start it with `require 'rgame'`,
  define what it uses, and let it run from the repository root. A complete example
  is the only kind that proves its output.
- **Write `# =>` comments as `# => value — prose`.** The value is a Ruby expression
  or an `inspect` string starting with `#<`. A class name passes for an instance of
  that class. Everything after ` — ` is prose. A value followed by a comma or colon
  and prose (`# => 60, in tiles`) does not evaluate and fails.
- **Opt a complete example out only when it cannot run as it stands**, such as an
  RSpec file: put `<!-- doc-example: skip — reason -->` on the line before its
  fence.
- **Name things in prose with backticks and their real spelling**: `UI::Menu#open`
  for an instance method, `Transcript.from` for a module or class method,
  `Controls::KEY_A` for a constant. The reference spec resolves every such name.

## What the checks catch, and what they do not

Four checks run without anyone remembering them:

| Check | Fails when |
|---|---|
| `spec/api_docs/examples_spec.rb` (`rake spec`) | a headless example raises or returns something its `# =>` comment does not say; a windowed example does not parse |
| `spec/api_docs/index_spec.rb` (`rake spec`) | a page is missing from the index, an example is missing from `examples.md` or described but absent, or a link or heading anchor is broken |
| `spec_core/api_docs/references_spec.rb` (`rake spec:core`) | prose names a class, constant or method that does not exist |
| `spec_core/api_docs/coverage_spec.rb` (`rake spec:core`) | a public class or method is named on no page and not tagged `@api private`; `rake docs:coverage` prints the list |

A word that looks like a constant but is not one (a key name, a file name) goes in
the `allowed` list in the reference spec, with a comment saying why.

**No check catches a sentence that names real things and states the wrong
behaviour.** "`play_music` switches tracks" names a method that exists and passes
every spec. Only the claim rules above catch that, so apply them while writing.

## Auditing a page

To check an existing page against the code, go through it top to bottom:

1. **List the class's public API** and compare it with the page: public methods,
   constructor keywords, signals, constants. Add what a game author would call.
2. **Find the code for each claim.** For every sentence that states behaviour, open
   the method that implements it. Read every branch of any option or policy.
3. **Search for the counterexample** to every absolute claim.
4. **Check the context**: the entry point each example assumes, what exists without
   setup, and what only the repository has.
5. **Run the checks**: `bundle exec rspec spec/api_docs`, then
   `bundle exec rake spec:core` for the references and coverage.
