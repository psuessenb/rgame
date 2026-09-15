# Roadmap

**Status.** Steps 0–5 are implemented. **Steps 6–7 are rough**, and step 6 is
next, to be re-planned before it starts.

## Dependency shape

```
0 I18n tables ─┬─→ 1 Text ────────┬─→ 3 UI keys ──┬─→ 5 example + docs ─→ 6 examples migrate ─→ 7 fold back
               │                  │               │
               └─→ 2 loading + ───┴─→ 4 rgame new │
                     detection ───────────────────┘
```

Step 2 needs only step 0: it loads tables, and never touches `Text`. Step 4
needs 1 and 2. Step 5 needs 2 and 3. Steps 0, 1
and 2 are each worth landing on their own:

| Step | Defect it closes even if the plan stops there |
|---|---|
| 0 | `t` allocates up to 12 objects a call; plurals wrong for ru/pl/cs/ar; missing keys silent (C1–C4) |
| 1 | `CachedLabel` cannot follow both a value and the language (C7) |
| 2 | locale files cannot be loaded through the asset manager; a game ships in one language to everyone |

## The invariant every step preserves

> **Reading a `Text` whose inputs have not changed allocates nothing, and
> `require "rgame"` loads no graphics library.**

The first half is `allocate_nothing` in `spec/rgame/engine/text_spec.rb` from
step 1 on. The second is `spec/rgame/no_graphics_spec.rb`, which already exists.

---

## Step 0 — `Engine::I18n` rewritten: compiled tables, locale chains, CLDR plurals *(pure)*

**Why first.** Everything else reads tables through it, and its current shape
(C1–C4) is wrong in ways `Text` would inherit. It has no callers (C6), so it can
land alone without touching anything else.

**Shape:** the `I18n` block in [03-design.md](03-design.md), with `Template` and
`Plural` as internal classes in `lib/rgame/engine/i18n/`. Plural rules live in
`lib/rgame/engine/i18n/plural_rules.rb` as a frozen Hash from language to
lambda.

**Sub-steps:**

- **0a** Tables: `load` (Rails format, deep merge), `load_hash`, flattening,
  `Template` compilation, `t`, `available`, `reset`, and `generation` moving on
  load. Replaces the current file and its spec.
- **0b** Locales: `normalize`, `chain`, `default`, `choose`, and resolving
  through the chain.
- **0c** Plurals: CLDR categories, the rule table, `plural_rule`, `zero:`
  precedence, the rule chosen by the supplying language.
- **0d** Missing: the `missing` policy, `MissingKey`, `missing_keys(locale)`,
  and `spec/spec_helper.rb` setting `:raise` and resetting around each example.

**Rules the tests must pin:**

1. Rails' format: one file may hold two locales, and a second load deep-merges
   rather than replacing a locale.
2. `%{name}` interpolates, `%%{name}` is the literal `%{name}`, and a template
   with no variables resolves to the same frozen String every time.
3. `generation` moves on `load` and on a switch to a different locale, not on
   a switch to the same one.
4. `de_AT`, `de-at` and `:'de-AT'` normalize alike; the chain of `de-AT` is
   `de-AT, de, en`; switching to a locale with no table resolves through its
   chain.
5. `choose(['fr-CA', 'de-AT', 'en'])` with tables for `de` and `en` returns
   `:'de-AT'`. With none matching, it returns the default.
6. Per language: `ru` 1 → one, 3 → few, 5 → many, 21 → one; `pl` 22 → few,
   25 → many; `cs` 3 → few; `ar` 0 → zero, 2 → two, 11 → many, 100 → other;
   `ja` anything → other; `en` and `de` 1 → one, else other.
7. `zero:` wins for 0 in `en`, which has no zero category of its own.
8. A key reached through a fallback pluralizes by the fallback language's rule.
9. `:key` shows the key; `:raise` raises `MissingKey` naming key and chain; a
   callable's return value is shown.
10. `missing_keys(:de)` lists keys present under the default and absent from
    `de`'s whole chain, and does not list keys `de` gets from a parent.
11. `YAML.safe_load` refuses an object tag rather than instantiating it.

**Tests:** `spec/rgame/engine/i18n_spec.rb` (rules 1–5, 9–11),
`spec/rgame/engine/i18n/plural_rules_spec.rb` (rules 6–8, as a table per
language), `spec/rgame/engine/i18n/template_spec.rb` (rule 2).

**Verify.** `rake spec` green, and RuboCop clean on the new files. Recorded in
the landed note: `I18n.t('menu.title')` and a pluralized `t` measured with the
same bench as the brief, to show where the per-call cost now sits.
`Text` is what makes the frame path free, so `t` does not have to be.

**Landed.** `Engine::I18n` is rewritten over `I18n::Template`, `I18n::Plural`
and `I18n::PluralRules` in `lib/rgame/engine/i18n/`, one commit per sub-step,
plus two more: caching each locale's plural rule, and the docs. Public surface:
`load(yaml, source:)`, `load_hash`, `available`, `locale`/`locale=`,
`default`/`default=`, `normalize`, `chain`, `choose`, `generation`,
`missing`/`missing=`, `MissingKey`, `missing_keys`, `plural_rule`, `t`, `reset`.
`spec/spec_helper.rb` resets `I18n` and sets `missing = :raise` before every
example.

`rake spec`: 2174 examples, 0 failures. The three new spec files hold 53
(`i18n_spec.rb`), 134 (`plural_rules_spec.rb`, one example per language and
count) and 11 (`template_spec.rb`). RuboCop is clean on every touched file, with
one inline disable: `Performance/RedundantBlockCall` in `PluralRules.whole`,
whose `yield` would run after the method has returned. `spec_core/api_docs` is
green over the rewritten page.

The brief's bench, re-run at the end of the step (Ruby 4.0.5, no YJIT, 200,000
calls):

| Call | Before | After |
|---|---|---|
| `t('menu.title')`, a plain hit | 5 objects, 0.85 µs | **3 objects**, 0.50 µs |
| `t('greeting', name: 'Ada')` through the fallback | 10 objects, 1.71 µs | **6 objects**, 1.34 µs |
| `t('apples', count: 3)` | 12 objects, 2.10 µs | **6 objects**, 1.45 µs |

An allocation trace of the plain hit finds nothing allocated inside `I18n`, so
the 3 objects sit in the call itself (the keyword splat). What a `Text` pays on
a re-render is therefore the render, not the lookup.

What the sketch got wrong:

- **`load_hash` cannot take `source:`.** `load_hash(en: { ... })` without braces
  is parsed as keywords as soon as the method has any. It takes one Hash, as the
  design's signature already said; only `load` names a source.
- **YAML turns `on`, `off`, `yes`, `no` into booleans.** `on: On` loads as
  `true => 'On'`, and `yes` overwrote a sibling key in the measurement. The
  loader refuses a boolean or `nil` key or value by path, and says to quote it,
  rather than storing `"true"`. **This touches step 3**:
  `examples/menu_navigation`'s `'on'`/`'off'` captions must be quoted keys
  (open question 2).
- **"Every key is a category" is not enough to recognise a plural.**
  `numbers: { one: One, two: Two }` is plausible nesting. A Hash is a `Plural`
  only when every key is a category, every value is text, *and* `other` is
  present. A plural missing `other` therefore reads as nesting, and `t` reports
  it as a missing key.
- **A missing variable or `count` in `t` raises `ArgumentError`, whatever the
  missing policy.** The design put variable mismatches under the policy. That
  sentence is about a `Text`'s declared names, which step 1 still owns. For `t`,
  which receives keywords directly, a missing one matches Ruby's own "missing
  keyword". The policy's handler `answer_missing` is private; step 1 needs to
  reach it.
- **The plural rule lookup allocated 14 objects per call**, more than the code
  it replaced, because the chain of the supplying table was rebuilt each time.
  It is cached per locale and cleared by `plural_rule` and `reset`.
- **`reset` moves `generation` rather than zeroing it, and `default=` moves it
  too.** A `Text` built before a reset must never find its old generation
  current again.
- Smaller: `it`, `es`, `fr` and `pt` carry CLDR's `many` for exact millions (a
  table without `many` reads `other`); `plural_rule` accepts a regional locale
  (`'pt-PT'`), which wins over its language; `choose` ignores the default when
  matching, or every language would match `en`.

Documented in `docs/api/toolbox.md`'s I18n section, which this step rewrote
although the sketch listed no docs until step 5. Its example is headless and
asserted by `spec/api_docs`.

---

## Step 1 — `Engine::Text` replaces `CachedLabel` *(pure)*

**Why now.** It is the object every later step hands around, and it closes the
known issue. Doing the rename here, before steps 3–6 add callers, keeps the
sweep at its measured size: 7 sites.

**Shape:** the `Text` block in [03-design.md](03-design.md).

**Sub-steps:**

- **1a** `Text.new(key, *names, scope:)` with the generated `with`, `to_s`,
  `literal`, and resolution through `I18n`, including the variable-mismatch
  check under the missing policy.
- **1b** `Text.computed`, which is `CachedLabel`'s block form re-keyed on
  keywords and the generation.
- **1c** Delete `CachedLabel`. Move its 7 call sites in `examples/` to
  `Text.computed`, unless the text is already a key; that happens in step 6. Update
  `docs/api/text.md`, `toolbox.md` and `components.md`, and the house rule "A
  label built from a changing value" in CLAUDE.md, including its
  "two things it is not for" paragraph, which now reads against `Text`.

**Rules the tests must pin:**

1. `with` on unchanged keywords and an unchanged generation returns the
   *identical* String object and allocates nothing: `allocate_nothing` over
   200,000 reads, for zero, one and three names.
2. Changing any one keyword re-renders; changing none does not, even across a
   `load` of an unrelated locale that did not move the generation. That case
   checks that the test is real.
3. A locale switch re-renders on the next read, with no keyword change.
4. A missing keyword and an unknown keyword each raise `ArgumentError` naming it.
5. Two `Text`s with the same name list share one generated module.
6. A `Text` built before any table loads shows the missing answer, then the
   translation after `load`, with no call in between.
7. `scope: 'a'` with key `'b'` resolves `'a.b'`, and `scope=` re-resolves.
8. `literal` never consults `I18n`, and survives `I18n.reset`.
9. `computed`'s block runs once per change, not once per read.

**Tests:** `spec/rgame/engine/text_spec.rb`. The seven examples' drive reports
before and after 1c are compared.

**Verify.** `rake spec` green. Every example that had a `CachedLabel` drives to
a report byte-identical to before the change, with `--seed` where the example is
seeded. `rake docs:coverage` names no `CachedLabel`.

**Landed.** `Engine::Text` is in `lib/rgame/engine/text.rb`, and `CachedLabel`
and its spec are deleted. The step took three commits, one per sub-step. Public surface:
`Text.new(key, *names, scope:)`, `with`, `to_s`, `key`, `names`, `scope`/`scope=`,
`Text.literal`, `Text.computed`. Two additions to `I18n`: `render(key, names,
vars)`, the seam a `Text` reads through, and `VariableMismatch`. `Plural` grew
`names`. The six migrated examples use `Text.computed` with their English
strings; moving them to keys is still step 6.

`rake spec`: 2214 examples, 0 failures (was 2174; `text_spec.rb` holds 44,
`cached_label_spec.rb`'s 6 are gone). `rake spec:core`: 376 examples, 0 failures,
which resolves every name the rewritten pages mention. RuboCop is clean on every
touched file.
`rake docs:coverage` names no `CachedLabel` and reports 39 gaps, as before the step.

Measured at the end of the step (Ruby 4.0.5, no YJIT, 200,000 calls):

| Call | Objects | Time |
|---|---|---|
| `Text#to_s`, unchanged | **0** | 0.07 µs |
| `Text#with(score:)`, unchanged | **0** | 0.10 µs |
| `Text#with(a:, b:, c:)`, unchanged | **0** | 0.12 µs |
| `Text.computed(:score)#with`, unchanged | **0** | 0.10 µs |
| `Text#with(score:)`, a new value every call | 5 | 1.81 µs |
| `Text.computed(:score)#with`, a new value every call | 3 | 0.48 µs |

An unchanged read costs about what comparing an Integer did in the brief
(0.07 µs). The `extend`ed module measured the same as the singleton-class method
the design measured.

Drive reports, 900 ticks, `--seed 1`, before and after 1c: `collision`,
`pathfinding`, `pooling`, `sound` and `split_screen` byte-identical.
`collision_tiles` first reported 898 frames before and 900 after. Its per-frame
draw counts were identical. Three more runs of each version gave 900 frames every
time, so the 898 was frame timing on a busy machine, not the change.

What the sketch got wrong:

- **Six call sites, not seven.** `collision`, `collision_tiles`, `pathfinding`,
  `pooling`, `sound`, `split_screen`. The seventh "site" was a comment in
  `examples/input_glyphs`, which now names `Text.computed`.
- **Rule 2's "a `load` of an unrelated locale that did not move the generation"
  cannot happen.** Step 0 moves the generation on every load. The spec pins the
  opposite instead: an unrelated load re-renders an equal but not identical
  String. That example is what proves the identity assertions can fail.
- **The mismatch check needs an `I18n` entry point, not the private
  `answer_missing`.** `I18n.render` resolves, checks the declared names in both
  directions (a placeholder not declared, a declared name never printed, and a
  plural without `:count`), and answers a mismatch through the missing policy.
  Under `:raise` it raises the new `I18n::VariableMismatch` rather than
  `MissingKey`, because the key is not missing.
- **`to_s` on a `Text` with names raises `ArgumentError`**, naming the keywords
  `with` needs. The design listed `to_s` only for a `Text` with no names. A
  silent `#<RGame::Engine::Text…>` on screen was the alternative.
- **Names are sorted before the module is looked up**, so `(:name, :level)` and
  `(:level, :name)` share one. A name that cannot be a Ruby local variable
  (`:Name`, `:end`) raises `ArgumentError` at construction, because the
  generated `with` could not declare it.
- **`literal` and `computed` are private subclasses, `Text::Literal` and
  `Text::Computed`.** 1c made them, and the generated-module cache, private
  constants, so `rake docs:coverage` does not ask to document internals. Both ignore `scope=` and report a `nil` scope. **This
  touches step 3:** `Menu` may set a scope on every button's `Text` whose
  `scope` is `nil`. For a literal that set is a no-op, not an override.
- **`Text` is documented in `docs/api/toolbox.md`**, where the `CachedLabel`
  section was, beside the I18n section. `localization.md` is still step 5's
  page. `text.md`, `components.md`, `examples.md`, the house rule in CLAUDE.md,
  the write-docs skill's style examples, the `NoInterpolationInHotPath` cop's
  comment and `allocate_nothing`'s comment were updated too.

---

## Step 2 — Locale files through the asset manager, and the player's language *(Core + glue)*

**Why here.** It depends only on step 0. It carries the plan's only C, and the
only cross-platform risk (open question 5), so it lands early enough for CI to
tell us.

**Shape:** "Loading, in `RGame::Game`" in [03-design.md](03-design.md).

```c
/* core.h */
/* Writes the user's preferred locales into `out`, most preferred first, as
 * "de-AT,en" with no trailing comma. Returns the length written, 0 when SDL
 * reports none, or the size needed when `capacity` is too small. */
size_t rgame_preferred_locales(char *out, size_t capacity);
```

**Sub-steps:**

- **2a** `AssetManager#glob(pattern)`: relative, sorted, and an empty list for a
  missing directory. Specced in `spec_core/` against a temporary tree, with the
  injected-loader style `asset_manager_spec.rb` already uses.
- **2b** `rgame_preferred_locales` in `ext/rgame_core/app/locale.c`, bound as
  `App#preferred_locales` in `core_ext.c`. First measure open question 5: does
  it need `SDL_Init`, and what do the three runners return? If it needs no app,
  it becomes a module function rather than an `App` method.
- **2c** `Game.new(locales:)`: the `:locale` loader, loading in `initialize`,
  and `I18n.choose(preferred_locales)`.

**Rules the tests must pin:**

1. `glob` returns the same list whatever order the file system yields.
2. `glob` of a directory that does not exist is `[]`.
3. Two files that both define `en` merge in `glob` order.
4. A `Game` whose media root has no `locales/` starts, with no tables.
5. With `LANG=de_DE.UTF-8` under Xvfb and `de` and `en` tables, a fresh `Game`
   is in `:de`; with `LANG=C` it is in the default. If SDL reads the variable
   differently, the spec states what it does read.
6. The `:locale` loader goes through the asset manager's cache: loading the same
   file twice parses it once.
7. `preferred_locales` returns Strings and never `nil` elements. Buffer
   truncation is covered by a Check test calling the function with a capacity
   of 3.

**Tests:** `spec_core/rgame/core/asset_manager_spec.rb` (1–2),
`spec_core/rgame/game_locales_spec.rb` (3–6), `spec_core/rgame/core/app_spec.rb`
(7), and `test/test_locale.c` for the buffer contract.

**Verify.** `make test`, `rake spec`, `rake spec:core` green locally, and CI
green on all three platforms. The landed note records what each runner's
`preferred_locales` returned. The verify skill's leak check is clean over the
`SDL_free` path.

**Landed.** One commit per sub-step. What shipped:

- **`AssetManager#glob(pattern)`**: relative to the media root, sorted, `[]` for
  a missing directory, an absolute pattern as it stands. It loads nothing.
- **`RGame::Core.preferred_locales`**, a module function.
  `rgame_preferred_locales` in `core.h` has `snprintf`'s contract. Its joining
  is the pure `rgame_locale_append` in `app/locale.{c,h}`, and
  `ruby/locale_ext.c` binds it.
- **`Game.new(locales: 'locales')`**: a `:locale` loader, every `.yml` under the
  directory loaded through `glob`, then
  `I18n.locale = I18n.choose(RGame::Core.preferred_locales)`.

Documented in `assets.md`, `app.md` and `game.md`, with a pointer from the
toolbox's I18n section.

Local: `make test` 363 checks; `rake spec` 2215 examples; `rake spec:core` 400
examples; all 0 failures. The new Core examples are 6 in `asset_manager_spec.rb`,
6 in `core/locale_spec.rb` and 12 in `game_locales_spec.rb`. The whole Check suite
is clean under ASan + UBSan + bounds-strict. The locale suite is also clean with
`CK_FORK=no` and a 120-entry `LANGUAGE`, so the `SDL_free` path ran under the
sanitizer. Removing the terminating NUL fails 5 of 10 locale checks. Drive
reports of `sound`, `split_screen` and `pathfinding` are byte-identical to
step 1's.

CI was green on all three platforms. Each runner's `preferred_locales`, and what
the probe let run:

| Runner | `RGame::Core.preferred_locales` | LANG examples |
|---|---|---|
| Linux (Xvfb) | `[]` | all 7 ran; `spec:core` 400 examples |
| macOS | `["en-US"]` | 7 skipped by `needs_lang_locale`; 389 examples |
| Windows | `["en-US"]` | 7 skipped by `needs_lang_locale`; 391 examples |

What the sketch got wrong:

- **Open question 5: `SDL_GetPreferredLocales` needs no `SDL_Init`.** Measured
  on SDL 2.0.20 under Linux, and it held on the macOS and Windows runners, which
  call it before any window opens. So it is `RGame::Core.preferred_locales`, not
  `App#preferred_locales`, and rule 7's example is in
  `spec_core/rgame/core/locale_spec.rb`, not `app_spec.rb`.
- **Rule 5's `:de` is `:'de-DE'`.** Step 0's `choose` returns the preferred
  locale unshortened, so the chain is `de-DE, de, en` and the German table shows.
- **`game_locales_spec.rb` cannot build a `Game` in-process.** `Game` names
  Engine. `spec_core/` may not, by the cop and because every later example would
  run with Engine loaded. Each example builds its game in a child process that
  requires `rgame/game`, as `references_spec.rb` already did. That also keeps a
  `LANG` from leaking into other examples. `spec_core/support/locale_environment.rb`
  runs the child.
- **SDL on Linux reads `LANG`, then `LANGUAGE`, and ignores `LC_ALL`.**
  `LANG=C` gives no locales. `LANG=POSIX` gives `POSIX`, and SDL's own 128-byte
  buffer truncates a long `LANGUAGE` into an entry like `f`. `preferred_locales`
  passes all of that through; `choose` finds no table for the junk. macOS and
  Windows ignore `LANG`, so the LANG-driven examples sit behind a probe,
  `LocaleEnvironment.follows_lang?`, rather than a `host_os` check.
- **Rule 7's buffer test covers the pure function**, which does not depend on
  what the machine prefers. A smoke test on the real one compares capacity 3
  with a whole buffer. SDL never fills the binding's 256-byte buffer, so its
  resize loop was checked by hand, with the buffer shrunk to 4 bytes.
- **Reading a table needs no encoding flag.** Psych reads its input as UTF-8
  under `LANG=C` and skips a BOM itself. Both are pinned by examples.
- **For step 3 and later: `Game` sets `I18n.locale` in `initialize`,
  overwriting anything set before `Game.new`**, as the design intends. Tables
  accumulate across two `Game`s in one process, because `I18n` is global and
  `Game` does not reset it.

---

## Step 3 — UI widgets take keys *(pure)*

**Why here.** It needs `Text` (step 1), and step 5's example is a menu. It
closes C8 and C9.

**Shape:** "UI widgets" in [03-design.md](03-design.md).

**Sub-steps:**

- **3a** `Button#label` holds a `Text`, and `TextButton`, `PanelButton`,
  `IconButton` and `OptionButton` draw `label.to_s`.
- **3b** `Menu.new(scope:)` and the "a button's own scope wins" rule. Decide open
  question 1 here: `Menu`-only, or inherited down the tree.
- **3c** `OptionButton` re-resolves captions and re-measures its column on a
  generation change. Decide open question 2 against `examples/menu_navigation`,
  which moves to keys in this sub-step, because it is the example the widget
  change breaks.
- **3d** `docs/api/ui.md`: every `label:` example becomes a key, and a section
  on scopes and literals is added.

**Rules the tests must pin:**

1. `label: 'play'` in a `Menu` with `scope: 'title_menu'` draws the
   `title_menu.play` translation; a switch redraws it with no rebuilt button.
2. `label: Text.literal('Ada')` draws `Ada` in every locale.
3. A button with its own `Text.new('x', scope: 'other')` keeps `other` in a
   scoped menu.
4. `OptionButton`'s column width after a switch to longer captions is the new
   maximum, not the old one.
5. An `OptionButton` draw allocates nothing while the locale and value are
   unchanged. The existing per-frame assertion keeps holding.

**Tests:** the existing `spec/rgame/engine/ui/*_spec.rb` files, updated to keys
with a table loaded through `load_hash`, plus the rules above in
`menu_spec.rb`, `text_button_spec.rb` and `option_button_spec.rb`.

**Verify.** `rake spec` green. `menu_navigation`, `game_menu`, `radial_menu`,
`quick_wheel` and `skill_bar` drive to reports whose `text` calls match the
pre-change reports string for string. Only the two migrated examples change
source.

**Landed.** One commit per sub-step. What shipped:

- **`Button#label` holds an `Engine::Text`.** A String or Symbol is a key the
  button builds one from, and a `Text` is kept as it is, variables included.
  `TextButton`, `PanelButton`, `IconButton` and `OptionButton` draw `label.to_s`.
- **`Text#to_s` on a `Text` with names** returns what its last `with` rendered,
  and renders those values again after a locale switch or `scope=`. Before the
  first `with` it raises as before. Added after review, so that a game can build a
  label with variables and update it from `update`.
- **`Menu.new(scope:)`** and a new **`Button#label_scope`**. The menu sets
  `label_scope` as a button is added, unless the button has one. A button applies
  it to labels and captions it built from keys, including a key assigned later.
- **`OptionButton`**: `display:` returns a key or a `Text`, and
  `OptionButton::DISPLAY` is the default. `caption` answers the `Text`. The value
  column is measured again whenever a caption's String changes, compared by object
  identity on each draw.
- **`docs/api/ui.md`**: every `label:` is a key, plus a new section, "Labels are
  translation keys", with a headless example asserted by `spec/api_docs`. The
  toolbox's `Text` scope section points to it.

`make test` 363 checks; `rake spec` 2268 examples (was 2215); `rake spec:core`
400 examples; all 0 failures. `spec/rgame/engine/ui/` holds 440 (was 397), and
`text_spec.rb` 52 (was 44).
RuboCop is clean on every touched Ruby file. `rake docs:coverage` reports 39 gaps,
as before.

Rules 1–5 are pinned in `menu_spec.rb` (1, 3), `text_button_spec.rb` (1, 2) and
`option_button_spec.rb` (4, 5). Four mutations were each caught: dropping the
"unless it has one" check in `Menu#add`, re-scoping a `Text` the button was
handed, and twice never re-measuring the column. The last fails three examples: a
locale switch, a scope change, and a `with` with new values. Dropping the "before
the first `with`" guard in `Text#to_s` fails two. Comparing captions with `==`
instead of `equal?` is an equivalent mutant: it is correct, but compares contents
instead of one object identity.

Drive reports, 600 ticks, `--seed 1`, for `menu_navigation`, `game_menu`,
`radial_menu`, `quick_wheel` and `skill_bar`: byte-identical to `main` after 3a,
after 3c and at the end. The report shows only each call's first and last
arguments, so "string for string" was checked with a probe prepended to
`RGame::Core::Renderer#text`, which counted every distinct string drawn. All five
logs were identical to `main`'s, such as `menu_navigation`'s 19 strings with
their counts. `test_projects/tiled_world`, whose inventory builds `PanelButton`s,
drives without error.

What the sketch got wrong:

- **Three examples change source, not two, and `menu_navigation` does not move
  to a table.** `label` answering a `Text` broke `examples/skill_bar`, which
  looked its caption up by `menu.focused.label`; it now reads `label.key`.
  `menu_navigation` changed only its percentage captions, which became literals.
  A key with no table shows as itself under `:key`, so its English-text keys
  still draw what they drew. Giving it a real table would answer open question 3,
  which is step 5's. Moving it to keys like `settings.volume` is therefore step 6.
- **Open question 1: `scope` stays a `Menu` option.** It does not inherit down the
  tree.
- **A `Text` a button is handed is never re-scoped.** The design had the menu set
  the scope on any label `Text` whose scope was nil. That would mutate a caller's
  object. One `Text` shared by two scoped menus would then read the first menu's
  scope in both, depending on build order. Only labels built from keys take the
  menu's scope. Rule 3 holds as written, and a scopeless `Text` in a scoped menu
  resolves unscoped.
- **The scope needed a home on the button: `label_scope`.** A menu sets it once,
  at `add`. A key assigned with `label=` afterwards, and an `OptionButton`'s
  captions, both need to find it later.
- **Open question 2: a Symbol value is its own key, and anything else is a
  literal.** A String that `display` returns is a key, as the design said. `[0,
  50, 100]` therefore draws numbers without a table, and `%i[off low high]`
  translates. `menu_navigation`'s `display` for `true`/`false` returns `'on'` and
  `'off'`, which are keys. A table must quote them, as step 0 found.
- **A label with variables is allowed, which changes step 1's `to_s`.** The
  first version refused one at assignment, because `to_s` raised on a `Text` with
  names. After review `to_s` returns the last `with`'s rendering instead, so a game
  owns the values and the button stays unaware of them. That supersedes step 1's
  bullet "`to_s` on a `Text` with names raises". What it costs: the values belong
  to the `Text`, so two nodes sharing one show the last `with` either gave. The
  toolbox and CLAUDE.md say so.
- **`OptionButton` re-measures by String identity, not by generation.** A caption
  with variables can change without the generation moving. A `Text` never edits a
  String in place, so a new String on any caption is the signal. That covers a
  locale switch and a scope change too, and makes the generation check redundant.
- **The UI specs needed more than tables.** About 40 examples used a label to
  identify a button (`menu.focused.label == 'Two'`) and now compare `label.key`.
  The rest load their drawn labels through `load_hash`, because the suite raises
  on a missing key.
- **For step 6:** the "string for string" check needs the `text` probe above,
  since the drive report does not list every string. It lived in the scratchpad
  for this step. Step 6 compares 24 examples, so it may be worth adding to
  `tools/drive_test_project.rb` as an option.

---

## Step 4 — `rgame new` generates a translated project *(CLI templates)*

**Why here.** It needs `Text` (step 1) and `Game`'s loading (step 2), and both
have landed. It is the step that makes requirement 1 true for a *new* user: the
first file they open draws a key, and the first `rake` they run fails on a key a
language lacks. Nothing later depends on it, so it lands before the example and
the docs page, which then link to a generator that already does what they say.

### What was measured before re-planning

At `78b6387`, Ruby 4.0.5 without YJIT.

| Measurement | Result |
|---|---|
| templates under `lib/rgame/cli/templates/` | 12 |
| `NewProject::KEEP_DIRS` | `['assets']`, its only entry |
| `cli_spec.rb` + `generated_project_spec.rb` | 20 examples, 1.45 s; the two subprocess examples are most of it |
| what the generated `Root` draws | the constant `GREETING = 'Hello from <name>!'` |
| `I18n.reset` then `I18n.load` of a 1-key table | 0.034 ms |
| the same for 1,000 keys | 8.1 ms: YAML parse 5.0 ms, compile 2.9 ms (`load_hash` of a parsed Hash) |
| names in the generated project's `game.rb` that say where tables are | 0: `media_root: 'assets'`, and `locales:` left at its default, `'locales'` |

### The generated project, after this step

```
tictactoe/
├── assets/
│   └── locales/
│       └── en.yml           replaces assets/.keep
├── nodes/root.rb            draws a Text
└── spec/
    ├── spec_helper.rb       loads assets/locales before every example, under :raise
    ├── locales_spec.rb      every locale has every key the default has
    └── nodes/root_spec.rb   asserts the English string, so the table is really read
```

```yaml
# assets/locales/en.yml.tt
en:
  root:
    greeting: "Hello from <%= app_name %>!"
```

```ruby
# nodes/root.rb.tt
class Root < RGame::Engine::Node2D
  def initialize
    super
    @greeting = RGame::Engine::Text.new('root.greeting')
  end

  def on_draw(renderer, _view)
    renderer.text(@greeting.to_s, 20, 20)
  end
end
```

```ruby
# spec/spec_helper.rb.tt, after the existing requires
LOCALES = Dir[File.expand_path('../assets/locales/**/*.yml', __dir__)]
          .sort.to_h { |path| [path, File.read(path)] }.freeze

RSpec.configure do |config|
  config.before do
    RGame::Engine::I18n.reset
    LOCALES.each { |path, yaml| RGame::Engine::I18n.load(yaml, source: path) }
    RGame::Engine::I18n.missing = :raise
  end
end
```

```ruby
# spec/locales_spec.rb.tt
RSpec.describe RGame::Engine::I18n do
  it 'has a table for the default locale' do
    expect(described_class.available).to include(described_class.default)
  end

  it 'gives every locale every key the default locale has' do
    missing = described_class.available.to_h { [it, described_class.missing_keys(it)] }
    expect(missing.reject { |_locale, keys| keys.empty? }).to be_empty
  end
end
```

Three choices in that shape, and why:

- **Only `en.yml`.** A second, English-copy `de.yml` would be a translation
  nobody asked for, and the first thing a user did would be delete it. Adding a
  language is adding a file, which the generated README says, and the locales
  spec starts meaning something the moment there are two.
- **Tables are re-read into `I18n` before every example, not once.** `I18n` is
  global, so a spec that switches the locale, loads a table or calls `reset`
  would otherwise change what every later example sees, depending on order. The
  engine's own `spec_helper` resets for the same reason. The cost is linear in
  keys: 0.03 ms for the generated table, 8 ms for a thousand. The file contents
  are read once, so the per-example cost is the parse and compile, not the disk.
  If a real game's suite finds that slow, `I18n` needs a snapshot, which is open
  question 6.
- **One summary example, not one example per locale.** `I18n.available` is empty
  when the spec file is loaded, because tables load in a `before` hook, so
  examples cannot be generated per locale. The failure message still names each
  locale and its keys: `{de: ["root.greeting"]}`.

The spec helper names `assets/locales` a second time; `game.rb` names it only by
`media_root` plus `Game`'s default. `game.rb` cannot be required from `spec/`,
because it loads SDL. The generated comment in the spec helper points at the
dependency, and a moved directory fails loudly: every drawn key raises
`MissingKey`.

**Sub-steps:**

- **4a** The templates above, `KEEP_DIRS` and its `.keep` loop deleted (no empty
  directory is left to keep), and the specs below.
- **4b** Docs: the generated `README.md.tt` (the layout gains `assets/locales/`,
  and a short section on adding a key, adding a language, and what the locales
  spec does), `docs/api/cli.md` (the tree, the `root.rb` and spec listings, the
  `KEEP_DIRS` paragraph, a section on the generated translation setup), and the
  toolbox's I18n section, which points to `cli.md` for the spec setup.

**Rules the tests must pin:**

1. The generated project holds `assets/locales/en.yml` with the project's name
   substituted, which parses through `I18n.load`, and no `assets/.keep`.
2. The generated suite passes and RuboCop is clean. Both examples exist already
   and must stay green without an inline disable in a generated file.
3. With a complete `de.yml` added, the suite still passes. That is what keeps
   rule 4 from passing for the wrong reason, such as a load error.
4. With a `de.yml` that lacks `root.greeting`, the suite fails, and its output
   names `de` and `root.greeting`.
5. With `root.greeting` removed from `en.yml`, the suite fails with `MissingKey`
   naming `root.greeting`.
6. A spec that loads a table and switches the locale in one example leaves the
   next example, run in defined order, with the project's own tables in the
   default locale.
7. Nothing under `nodes/` or `spec/` names `RGame::Core`. The existing example
   covers the two new files without change.

**Tests:** `spec/rgame/cli_spec.rb` (1, and the updated file list), and
`spec/rgame/cli/generated_project_spec.rb` (2–6), each of 3–6 writing its files
into the generated project before running its suite.

**Verify.** `rake spec` green, RuboCop clean on every touched file. Then drive a
generated project, as the wiring tier requires: generate into the scratchpad,
run `tools/drive_test_project.rb` on its `main.rb` with `--script`, and record
in the landed note that `text` draws `"Hello from tictactoe!"`, not
`"root.greeting"`. Then add a German table and drive it again with
`LANG=de_DE.UTF-8`, and record that it draws the German string.

**What this step does not deliver:** a language switch or a saved language in
the generated project (the example shows both), and a link to
`docs/api/localization.md`, which does not exist until step 5.

**Landed.** Two commits, one per sub-step. What shipped:

- **Templates.** `assets/locales/en.yml.tt`, `spec/locales_spec.rb.tt`, and
  changed `nodes/root.rb.tt`, `spec/nodes/root_spec.rb.tt` and
  `spec/spec_helper.rb.tt`, all as sketched. `NewProject::KEEP_DIRS` and its
  `.keep` loop are deleted.
- **Docs.** The generated README gains `assets/locales/` in its layout and a
  "Text on screen" section. `docs/api/cli.md` gains "Text comes from a
  translation table" and its listings follow the templates. The toolbox's
  missing-keys section links to it.

`make test` 363 checks; `rake spec` 2273 examples (was 2268); `rake spec:core`
400 examples; all 0 failures. The CLI specs are 25 examples in 2.56 s (were 20 in
1.45 s): 4 new subprocess runs and one in-process table check. RuboCop is clean on
every touched Ruby file, and the generated project is clean under its own
configuration. `rake docs:coverage` reports 39 gaps, as before.

Rules 1–7 are pinned. Three mutations of the spec helper template were each
caught by exactly the example meant for it: dropping `I18n.reset` (rule 6),
dropping `missing = :raise` (rule 5), and a greeting in `en.yml` that no longer
matches the root spec (rules 1–3 fail together).

Driven, as the wiring tier requires. A project generated into the scratchpad,
30 idle ticks through `tools/drive_test_project.rb --script`:

| Tables | Environment | `text` drew |
|---|---|---|
| `en.yml` | default | `"Hello from tictactoe!"` |
| `en.yml` + a `de.yml` | `LANG=de_DE.UTF-8` | `"Hallo von tictactoe!"` |
| `en.yml` + a `de.yml` | `LANG=C` | `"Hello from tictactoe!"` |

What the sketch got wrong:

- **The generated RuboCop configuration needed an exclusion.**
  `RSpec/SpecFilePathFormat` wants `RSpec.describe RGame::Engine::I18n` at
  `spec/r_game/engine/i18n_spec.rb`. The spec checks data, not a source file, so
  the generated `.rubocop.yml` excludes `spec/locales_spec.rb` with that reason.
  Rule 2 forbids an inline disable; a string description would trade the offence
  for `RSpec/DescribeClass`.
- **No `.sort` on the glob.** `Dir[]` sorts since Ruby 3.0, and
  `Lint/RedundantDirGlobSort` refuses it in the generated project.
- **Rule 6's example runs a spec file of its own**, `spec/leak_spec.rb` written
  into the project, with `--order defined`. The generated suite's own order is
  random, so the leak could not be pinned from its existing files.
- **Docs came in 4b as planned**, but `cli.md` also states the reload cost, and
  that a missing key in the game falls back to the default's text while a key no
  table has shows as itself, so the reader knows the specs are stricter than the
  game.

## Step 5 — `examples/localization`, and `docs/api/localization.md` *(example + docs)*

**Why here.** It needs step 2's loading and step 3's `Menu` scope, and both have
landed; it does not need step 4, and follows it only so that the page can link
to a generator that already does what it describes. It is the example
`basic-examples.md` #23 describes, re-planned against steps 0–3, and it answers
open question 3, which blocks step 6.

**Open question 3 is settled here: an example's tables live beside its
`main.rb`.** `examples/localization/locales/{en,de}.yml`, loaded with
`Game.new(locales: File.join(__dir__, 'locales'))`. `locales:` already accepts
an absolute path (step 2), so no engine change is needed. The alternative, one
shared `examples/assets/locales/` with keys namespaced per example, loads every
example's tables into every example. It works only while each example remembers
its namespace, and a collision would show one example's text in another with no
error. A directory per example makes the collision impossible.

### The example's shape

```
examples/localization/
├── main.rb
└── locales/
    ├── en.yml
    └── de.yml      lacks one key on purpose
```

```yaml
en:
  hud:
    apples:
      zero: No apples
      one: "%{count} apple"
      other: "%{count} apples"
    player: "Picked by %{name}"
    hint: Left and right change the count   # absent from de.yml
  language:
    title: Language
```

What `main.rb` shows, one point each:

- **A `Text` with `count`**, driven by Left/Right: `No apples`, `1 apple`,
  `3 apples`; `0 Äpfel`, `1 Apfel`, `3 Äpfel` in German, which has no `zero:`
  and shows that an explicit `zero:` is per table.
- **A `Text` with a variable** that is not the count.
- **A key missing from `de.yml`** that shows the English text in German, and the
  header says why that is the right failure and that the generated project's
  locales spec would refuse it.
- **A `UI::Menu` with `scope: 'language'`** holding one button per available
  locale. The language names are `Text.literal('English')` and
  `Text.literal('Deutsch')`: a language is named in its own language, whichever
  is current, which is exactly what `literal` is for.
- **The choice saved with `Util::SaveFile`** and restored between `Game.new` and
  `start`, overriding the OS choice.
- **Slots wide enough for both languages**, with a sentence saying why: the
  engine layer cannot measure text yet (decision 8).

Which button class the menu uses follows `examples/menu_navigation`, which uses
`PanelButton` over `examples/assets/ui.json`. The header lists the keys, and
nothing reads F1, F2 or a key the default map already uses for movement.

**Sub-steps:**

- **5a** `tools/drive_test_project.rb --texts`: a report section listing every
  distinct String passed to `text`, with its count, in first-drawn order. Step
  3's check needed a scratch probe for this. Step 6 compares 24 examples string
  for string, and this example's drive script asserts a switch, so the probe
  belongs in the harness.
- **5b** The example, its two tables, and `tools/drive/examples/localization.rb`.
- **5c** Docs. A new `docs/api/localization.md`: the YAML format and where files
  go, `Text` with variables and `count`, plural rules, scope (linking `ui.md`),
  the missing-key policy, loading and `locales:`, OS detection
  (`RGame::Core.preferred_locales`, `I18n.choose`), a saved language, and specs
  (the generated `spec_helper` and `missing_keys`, linking `cli.md`). The
  toolbox's I18n section moves there. The toolbox keeps its `Text` section, which
  is about caching, with a link. Also: a row in `docs/api/README.md`,
  `components.md`'s "text in the player's language" row repointed, an entry in
  `docs/api/examples.md`, a row in README.md's examples table, the links step 4
  wrote to the toolbox repointed, and `basic-examples.md` #23 marked done with
  what the example decided (the write-example skill's finishing step).

**Rules the drive script must show** (its header states them, read off a real
run):

1. `--texts` lists the English strings before the switch and the German ones
   after it, and `hud.hint`'s English string in both.
2. The apple count's strings include the `zero:` form in English and `0 Äpfel` in
   German.
3. With `RGAME_SAVE_DIR` left from the first run, a second run of a script that
   does nothing draws German from the first frame.
4. No string is the key itself: `--texts` shows no `hud.` or `language.`.

**Verify.** The drive runs above, recorded in the landed note, and a run of the
example directly (not under the harness) with the allocation probe the
write-example skill describes, reading zero objects per frame while nothing
changes. `rake spec` green, including `spec/api_docs` over the new page's
headless examples; `rake spec:core` green, which resolves every name the page
mentions. `rake docs:coverage` reports no new gaps. RuboCop clean on the example
and the harness.

**Landed.** One commit per sub-step. What shipped:

- **`tools/drive_test_project.rb --texts`**: a "texts drawn" section listing each
  distinct String passed to `text`, with its count and the tick it first
  appeared on. CLAUDE.md and the verify skill mention it.
- **`examples/localization`**: `main.rb` with a `Language` class (the save, the
  OS's preference, `restore`, `pick`, `follow_system`) and a `Screen` node.
  `locales/en.yml` and `locales/de.yml` sit beside it. Two drive scripts:
  `localization.rb` and `localization_saved.rb`.
- **`docs/api/localization.md`**, with the toolbox's I18n section moved into it.
  Rows and links in `README.md`, `docs/api/README.md`, `examples.md`,
  `components.md`, `game.md`, `app.md`, `ui.md`, `internals.md` and `cli.md`,
  a link in the generated README, and `basic-examples.md` #23 marked done.

`make test` 363 checks; `rake spec` 2273 examples; `rake spec:core` 400
examples; all 0 failures. `spec/api_docs` runs the page's headless example, and
`spec:core` resolves every name it mentions. `rake docs:coverage` reports 39
gaps, as before. RuboCop is clean on the example, both scripts and the harness.

The drive runs, 140 ticks, `LANG=en_US.UTF-8`, no save:

| `--texts` shows | Ticks |
|---|---|
| "Localization", "3 apples", "Current locale: en-US", "Language", "Use the system language" | from 0 |
| "2 apples", "1 apple", "No apples" | from 11, 17, 23 |
| "Lokalisierung", "0 Äpfel", "Aktuelles Gebietsschema: de", "Sprache", "Systemsprache verwenden" | from 42, 80 frames each |
| "1 Apfel" | from 53 |
| "Left and right change the count", "English", "Deutsch" | all 140 frames |

Rules 1, 2 and 4 hold: the hint is English in both languages, English has "No
apples" and German "0 Äpfel", and no string is a key. The run ended with
`language.json` holding `"de"`. Rule 3: `localization_saved.rb`, 30 idle ticks
against that directory, drew "Lokalisierung", "3 Äpfel" and "Aktuelles
Gebietsschema: de" from tick 0, with no English frame. Under `LANG=C` the locale
line reads "Current locale: en", as the script's header says.

Run directly under a headless display, not under the harness, with GC disabled
from tick 100 to tick 400: **1 object allocated over 300 ticks**, so nothing per
frame. The drive run exits 0, so no top-level proc holds the window. The longest
button label measures 194 pixels ("Systemsprache verwenden") in a 280-pixel slot.

What the sketch got wrong:

- **The YAML sketch's `hud.player: "Picked by %{name}"` had no value to show.**
  The variable is the current locale instead: `hud.locale`, "Current locale:
  %{locale}", read with `I18n.locale.name`, which allocates nothing. The first
  German draft said "Sprache:", which is "Language", and became "Aktuelles
  Gebietsschema".
- **Two literal buttons would have left `scope:` with nothing to do.** A literal
  has no key. The menu has a third button, `label: 'system'`, which reads
  `language.system` and returns to the OS's language, deleting the save. That
  needs `RGame::Core.preferred_locales`, so `main.rb` passes it to `Language`
  rather than a node naming Core.
- **A saved language goes through `choose`**, as `choose([saved, *preferred])`.
  A saved locale with no table then gives the OS's pick rather than the default,
  and an empty or non-String value is ignored. `localization.md` shows the same
  guard.
- **Rule 3 needed its own script**, `localization_saved.rb`, because a run
  cannot restart itself. The `--script` pair follows `collision_tiles_spike.rb`.
- **The examples page entry and README row landed in 5b, not 5c.**
  `spec/api_docs/index_spec.rb` fails while an example is missing from
  `examples.md`, so 5b was not green without them.
- **The allocation probe is not in the write-example skill.** The skill counts
  live `App`s at exit. Allocations were counted with `GC.stat` in a scratch script,
  and the live-App question was answered by the drive run exiting 0.
- **The toolbox keeps `Text` whole**, with a link to the new page. Its variables,
  scope and caching sections are about `Text` rather than tables, and
  `localization.md` links to them.

## Step 6 — every example draws keys *(rough)*

Mechanical, over the 24 examples. Each migrated example gets a
`locales/en.yml` beside its `main.rb`, as step 5 settled, and passes
`locales: File.join(__dir__, 'locales')`. The acceptance test is the drive
reports with step 5's `--texts`: every example's strings identical before and
after, because `en.yml` holds exactly the text that was hardcoded. `Text.computed`
labels from step 1 move to keys where the text is words rather than a number.
Then decide open question 4 (the cop). Likely split by the examples page's
sections, one sub-step each.

## Step 7 — fold back and delete the plan

- `docs/api/localization.md` checked against the code by the write-docs audit.
- CLAUDE.md: the `Text` house rule (from step 1), plus a sentence under "Current
  phase" that text is translated by default.
- `docs/plans/basic-examples.md`: the engine-work table row "a label keyed on a
  value *and* the locale" closed; `I18n` removed from "used nowhere at all".
  (#23 is marked done by step 5.)
- `docs/plans/possible-todos.md`: "Text measurement for the engine layer" stays,
  with its trigger now satisfied, so it is next.
- README: the 0.3 roadmap line "fix the I18n package" marked DONE.
- `docs/project_structure.md`: `i18n/` and `text.rb`.
- Every open question above resolved in place or moved into `docs/api/` or the
  code; then delete `docs/plans/i18n/`.
