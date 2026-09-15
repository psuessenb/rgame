# Roadmap

**Status.** Nothing implemented. **Steps 0–3 are detailed. Steps 4–7 are rough**
and get re-planned when the step before them lands.

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

---

## Step 4 — `rgame new` generates a translated project *(rough)*

Templates for `assets/locales/en.yml`, a `Root` drawing a `Text`, a
`spec_helper.rb` that loads the tables and sets `:raise`, and
`spec/locales_spec.rb`. The generated README explains the locales directory.
`spec/rgame/cli/generated_project_spec.rb` already runs the generated suite for
real, so it becomes the acceptance test, plus one example that deletes a key
from a second locale and expects the generated suite to fail. The template
directory rule (no leading dot) is unaffected. `KEEP_DIRS` may no longer need
`assets`.

## Step 5 — `examples/localization`, and `docs/api/localization.md` *(rough)*

The example `basic-examples.md` #23 describes, re-planned against steps 0–3
by the write-example skill. English and German; a `Text` with a variable and one
with `count`; a `UI::Menu` language switch with `scope:`; a key deliberately
missing from German to show the fallback; the choice saved with `SaveFile` and
restored between `Game.new` and `start`. Slots are wide enough for both
languages, and the file says why (decision 8). The drive script asserts the
switch through the `text` calls before and after.

Docs: the new page, index rows in `docs/api/README.md`, `components.md`'s
"text in the player's language" row, the entry in `docs/api/examples.md`, and a
row in the README's examples table. Answer open question 3 here, because this is
the first example with locale files.

## Step 6 — every example draws keys *(rough)*

Mechanical, over the 24 examples. The acceptance test is the drive reports:
every example's `text` calls identical before and after, string for string,
because `en.yml` holds exactly the text that was hardcoded. Then decide open
question 4 (the cop). Likely split by the examples page's sections, one
sub-step each.

## Step 7 — fold back and delete the plan

- `docs/api/localization.md` checked against the code by the write-docs audit.
- CLAUDE.md: the `Text` house rule (from step 1), plus a sentence under "Current
  phase" that text is translated by default.
- `docs/plans/basic-examples.md`: #23 marked done with its landed note; the
  engine-work table row "a label keyed on a value *and* the locale" closed;
  `I18n` removed from "used nowhere at all".
- `docs/plans/possible-todos.md`: "Text measurement for the engine layer" stays,
  with its trigger now satisfied, so it is next.
- README: the 0.3 roadmap line "fix the I18n package" marked DONE.
- `docs/project_structure.md`: `i18n/` and `text.rb`.
- Every open question above resolved in place or moved into `docs/api/` or the
  code; then delete `docs/plans/i18n/`.
