# Roadmap

**Steps 0–2 are implemented. Step 3 is detailed. Steps 4–6 are deliberately
rough** and get re-planned
once the layer beneath them exists — see the note at the end.

```
0 glyph metrics split (C, pure)
      │
      ▼
1 Util::Typeface ──┬──→ 2 Typeface#wrap (C fit + Ruby lines)
                   │              │
                   └──→ 3 Core::Font on a typeface, renderer, fakes
                                  │           │
                                  ▼           ▼
                            4 Engine::Paragraph
                                  │
                                  ▼
                            5 UI::Label + an example
                                  │
                                  ▼
                            6 fold back, and delete this plan
```

> **The invariant every step preserves: a width measured anywhere equals the
> width drawn. One walk, one set of numbers.** From step 3 a spec says so across
> the two extensions; before that, `make test` says so within one.

Steps 0 to 3 are worth landing even if the rest is abandoned:

| Step | Defect it closes |
|---|---|
| 0 | `font.c` claims to be pure and links against the graphics layer |
| 1 | the engine layer cannot measure text at all |
| 2 | nothing in the project can break a string into lines |
| 3 | the headless suite asserts layout against invented widths |

---

## Step 0 — `rgame_glyph_metrics` (C, pure)

**Why now.** It is the cut that makes step 1 mechanical. `font.c` is documented
as touching "no atlas, no cache, no GL, no file I/O" and yet includes
`graphics/clip.h` and links `rgame_rect_make` — measured: it is the only link
error when the file is compiled alone. Separating the face's facts from the
atlas's turns the move into a file rename. Nothing moves in this step, so it
lands on its own and every suite stays green.

**Shape.**

```c
/* ext/rgame_core/text/glyph_metrics.h for now; moves to Util in step 1 */
typedef struct {
    int codepoint;
    int width, height;
    float advance;
    float bearing_x, bearing_y;
} rgame_glyph_metrics;

int rgame_typeface_glyph(const rgame_typeface *typeface, int codepoint,
                         rgame_glyph_metrics *out);
```

`rgame_glyph` in `glyph_cache.h` keeps its `page` and its `rgame_rect`, and
gains the metrics struct. `font_atlas.c` copies the size into the rectangle it
places; `app.c` reads the advance off the metrics.

**Rules the tests must pin.**

1. `rgame_typeface_glyph` reports a size and leaves placement to the caller.
2. A glyph with no ink — a space — still reports its advance.
3. A codepoint the font lacks still reports the `.notdef` box.

**Tests.** `test/test_font.c` — the existing glyph examples, retargeted at the
new struct. `test/test_glyph_cache.c` — unchanged behaviour through the new
shape.

**Verify.** `font.c` compiles and links with `-Iext/rgame_core` alone and no
graphics object, which is the thing that was not true before:

```
cc -O2 -std=gnu17 -Iext/rgame_core -c ext/rgame_core/text/font.c -o /tmp/font.o
```

Plus `make test`, `rake spec`, `rake spec:core`.

**Landed.** `ext/rgame_core/text/glyph_metrics.h` defines the struct as
sketched, and `rgame_typeface_glyph` fills one. `rgame_glyph` is now `metrics`,
`page` and `rect`, and the cache keys on `metrics.codepoint`. `font_atlas.c`
places a rectangle of the metrics' size and `app.c` reads the bearings through
`glyph.metrics`. `font.h` includes `glyph_metrics.h` in place of
`glyph_cache.h`, so nothing in the typeface's includes reaches
`graphics/clip.h` any more.

`make test` 363 checks, `rake spec` 2330 examples, `rake spec:core` 410, all 0
failures. A driven `examples/localization` at `--seed 1` ran 240 ticks and 240
frames with 1920 `text` calls and no missing keys. The acceptance check,
measured: before the change, `font.o` had one undefined engine symbol,
`rgame_rect_make`, and linking it with only the stb object failed on it. After
it, `nm -u` lists only libc and `stbtt_*`, and `font.o`, `stb_truetype_impl.o`
and an empty `main` link with `-lm`.

What the sketch got wrong:

- **The Verify command proved nothing.** `cc -c font.c` compiled before the
  change too. A missing definition is a link error, not a compile error. The
  real check is the link, or `nm -u font.o` showing no `rgame_` symbol. Step 1
  should verify the move the same way.
- **`font_internal.h` got `rgame_glyph` through `font.h`.** Once `font.h` stopped
  including `glyph_cache.h`, both `font_internal.h` and `app.c` lost the type.
  `font_internal.h` now includes `glyph_cache.h` itself, since it names
  `rgame_glyph` in `rgame_font_glyph`.
- **Rule 1 is now enforced by the type**, so it has no test of its own. The old
  test asserted that `rect.x` and `rect.y` came back as zero. `rgame_glyph_metrics`
  has no position, so those two assertions were deleted rather than retargeted.
- **Rule 3 was only half pinned.** The `.notdef` test checked the advance and not
  the box, so it now also asserts a non-zero width and height.
- `test/test_glyph_cache.c`'s round-trip glyph now sets `width` and `height`
  apart from the rectangle's size. A cache that dropped either field would
  otherwise have passed.
- `docs/project_structure.md` lists the new header.

---

## Step 1 — `RGame::Util::Typeface`

**Why now.** This is the move the whole plan exists for, and everything else
waits on it. It lands as one branch because the C move, the build change and the
Ruby class are meaningless apart: an extension that compiles a file nothing
requires is not a step anyone can verify.

**Sub-steps, one commit each.**

- **1a — move the C.** `text/font.{c,h}` → `ext/rgame_util/typeface.{c,h}`,
  `glyph_metrics.h` with it, and `vendor/stb_truetype.h` plus
  `stb_truetype_impl.c` → `ext/rgame_util/vendor/`. Both `extconf.rb`s compile
  it; util's grows the `-w` vendored rule core already has. The root `Makefile`
  moves `FONT_OBJ` and the stb object into its util section.
- **1b — the Ruby class and its binding.** `ext/rgame_util/typeface_ext.c` and
  `lib/rgame/util/typeface.rb`, required from `lib/rgame/util.rb`.
  `Core::Font` keeps opening its own face from a path, untouched.
- **1c — the specs and the packaging.** `test/test_font.c` →
  `test/test_typeface.c`, `spec/rgame/util/typeface_spec.rb`, and the
  cross-extension agreement example in `spec_core/`.

**Shape.**

```ruby
RGame::Util::Typeface.new(path, pixel_height)   # File.binread, then C
RGame::Util::Typeface.default(pixel_height)     # the shipped font, memoised
#height      # => Integer
#text_width(string)  # => Float
#bytes       # @api private — what Core::Font opens its own face from
```

**Rules the tests must pin.**

1. A width is the real font's, not an approximation — `'Systemsprache
   verwenden'` at 18 px is 194.33 px, and the empty string is zero.
2. Kerning is applied: `text_width('AV') < text_width('A') + text_width('V')`.
3. `Util::Typeface#text_width` and `Core::Font#text_width` return **the same
   Float** for the same string, face and size. This is the guard the whole
   two-copies design rests on.
4. A file that is not a TrueType font raises, naming the path.
5. Malformed UTF-8 costs one replacement character, not the rest of the string.
6. `require "rgame"` still loads no graphics library.

**Tests.** `test/test_typeface.c` (the existing 698 lines, moved);
`spec/rgame/util/typeface_spec.rb` — widths, kerning, the shipped font, a bad
file, memoisation of `default`; `spec_core/rgame/core/font_spec.rb` — rule 3;
`spec/rgame/no_graphics_spec.rb` — unchanged, must stay green;
`spec/packaging_spec.rb` — the moved vendored sources and their licence ship,
and `lib/rgame/util/typeface.rb` with them.

**Verify.** `make ext` builds both extensions from one copy of the source.
`ruby -Ilib -e 'require "rgame"; RGame::Util::Typeface.default(18).text_width("x")'`
answers a Float with no window and no SDL. All four suites green, and the skip
count on `rake spec:core` unchanged from the previous run.

**Open question 3 blocks 1b**: `Typeface.default` needs a default pixel height,
`Renderer::FONT_SIZE` is 18, and Util may not name Core. Either Util owns the
number and Core reads it, or both declare it and a spec compares them — the
`Util::Controls` arrangement.

**Landed.** `ext/rgame_util/` now holds `typeface.{c,h}`, `glyph_metrics.h` and
`vendor/stb_truetype{.h,_impl.c}` with a README for them, and both extensions
compile them. `RGame::Util::Typeface` has `new(path, pixel_height)`,
`default(pixel_height = DEFAULT_SIZE)` memoised per size, `#height`,
`#text_width`, `#inspect` and `Typeface::LoadError`. Open question 3 went to
Util: `Typeface::DEFAULT_SIZE` is 18, and `Core::Renderer::FONT_SIZE` reads it.
`Core::Font::DEFAULT_PATH` reads `Typeface::DEFAULT_PATH` the same way, so the
shipped font's path is also stated once.

On a clean build, `make test` 363 checks, `rake spec` 2347 examples,
`rake spec:core` 413, all 0 failures, and `make` builds the standalone binary.
Neither suite reports pending examples, before or after. The measured
acceptance evidence:

- `ruby -Ilib -e 'require "rgame"; RGame::Util::Typeface.default(18).text_width("x")'`
  answers `8.055944442749023` with no `libSDL2` or `libGL` mapped.
- `'Systemsprache verwenden'` at 18 px is `194.33392333984375`, as the plan
  predicted.
- A gem built with `rake build` and installed into a scratch gem home compiles
  both extensions from source. There `Core::Font` and `Util::Typeface` return
  the same `194.33392333984375`.
- The installed `core_ext.so` exports none of the 67 `rgame_typeface_*` and
  `stbtt_*` symbols.

What the sketch got wrong:

- **"Nothing crosses the `.so` boundary in C" was false as built.** Ruby loads
  extensions with `RTLD_GLOBAL`, and both `.so` files exported the shared
  functions. `LD_DEBUG=bindings` showed Core's `rgame_typeface_open` and
  `rgame_typeface_measure` binding to **Util's** copy. So rule 3's spec compared
  a copy with itself on Linux. Core now compiles its copy with
  `-fvisibility=hidden` (not on Windows, where only `Init_core_ext` is exported
  anyway), and binds to it at link time.
- **The two copies were not compiled alike.** Util builds with
  `-ffp-contract=off` and Core did not. Forcing contraction on in Core's copy
  (`-mfma -ffp-contract=fast`) moved `'Systemsprache verwenden'` at 18 px from
  `194.33392333984375` to `194.3339080810547`, and the agreement spec failed.
  That check is what showed the spec has teeth. Util had the flag since
  pathfinding, whose A* breaks ties between equally cheap routes by comparing
  sums. Core never needed it for drawing. Core now builds everything with
  `-ffp-contract=off`, and so does the root `Makefile`, so the Check suite tests
  the C as the gems compile it. This matters on the arm64 macOS runner, where
  compilers contract by default. A flag set only on the shared files was tried
  first. It would have left the flag stated twice, and needed remembering for
  the next shared file.
- **`VPATH` finds targets, not just sources.** Adding `../rgame_util` to Core's
  `VPATH` made make find Util's own `typeface.o`, judge it up to date, and then
  link a `typeface.o` that did not exist in Core's directory. Core names the
  shared sources with explicit rules instead. The same trap waits for any future
  source shared across the two extensions.
- **A flag change in `extconf.rb` rebuilds nothing.** mkmf's objects do not
  depend on the Makefile, and the root `make ext` does not descend when the
  `.so` is newer than every source. Changing the flags needed the two objects
  deleted by hand. A checkout built before this step also needs `make clean`:
  `build/stb_truetype_impl.d` still names the old source path.
- **`#bytes` did not ship.** Nothing calls it until step 3, so it stays out of
  a public API it would have had to document. Step 3 adds it, or whatever
  `Core::Font.new(app, typeface)` turns out to need.
- **`docs/api` could not wait for step 6.** `spec_core/api_docs/coverage_spec.rb`
  fails on an undocumented public class. So `docs/api/text.md` gained "Measuring
  without a window" and `docs/api/values.md` a `Typeface` section here. Step 6
  extends them rather than writing them.
- `test/test_font.c` became `test/test_typeface.c` in 1a, not 1c, because the
  Makefile had to name it for 1a to build. The packaging spec's `color.h`
  example grew to name every Util file Core compiles.
- A driven `examples/localization` run (240 ticks, 240 frames, 1920 `text`
  calls) first drew `"Lokalisierung"` where step 0's drew `"Localization"`.
  That is the example's saved language pick, not this step: its drive script
  picks German, and the next run loads it.

---

## Step 2 — line breaking

**Why now.** It is the one piece of new C, it is independently useful, and
`Paragraph` cannot be designed against a `wrap` that does not exist.

**Shape.**

```c
void rgame_typeface_fit(const rgame_typeface *typeface, const char *text, size_t length,
                        float max_width, size_t *fit_length, float *fit_width);
```

```ruby
typeface.wrap(string, max_width)   # => [String, …]   one String per line
```

**Rules the tests must pin.**

1. Every returned line measures no wider than `max_width` — **except** a single
   word that is wider than the whole line, which is returned whole rather than
   cut.
2. The lines concatenate back to the input, with each break standing for the
   space it replaced. Nothing is lost and nothing is duplicated.
3. Breaking happens at spaces only. No hyphenation, no breaking inside a word.
4. Wrapping is linear: the fitting lengths sum to the input length. Pinned as a
   call count, not a timing.
5. A string that fits returns one line; an empty string returns no lines.
6. `wrap` never disagrees with `text_width`: each returned line, measured, is
   the width the fit reported.

**Tests.** `test/test_typeface.c` — `rgame_typeface_fit` against the real font,
including the long-word case and a fit of exactly the available width;
`spec/rgame/util/typeface_spec.rb` — `#wrap` in English and German over the same
width, showing the two break differently, which is the whole reason this exists.

**Verify.** `make test` and `rake spec`. A German paragraph and its English
source, wrapped to 520 px, produce different line counts — asserted, not
observed.

**Landed.** `rgame_typeface_fit` sits in `ext/rgame_util/typeface.{c,h}` with
the sketched signature. It walks `rgame_text_cursor`, records each space as a
break, and stops at the first glyph that overflows once it has a break. The line
excludes the break space, and `text[*fit_length]` is that space.
`Typeface#wrap(string, max_width)` calls the fit once per line, slices each line
with `rb_str_subseq` and steps past the space. `Game/NoLiteralText` now names
`wrap` too, and `docs/api/text.md` has a "Breaking text into lines" section
whose example the doc specs run.

`make test` 373 checks, `rake spec` 2359 examples, `rake spec:core` 413, all 0
failures. Both extensions and the standalone binary build without warnings. The
measured acceptance evidence:

- The German paragraph wraps to **4 lines** at 520 px, its English source to
  **3**. `test/test_typeface.c` and `spec/rgame/util/typeface_spec.rb` both
  assert it.
- A sweep of widths from 60 to 600 px over the English paragraph checks the fit
  at every line. Each line measures what the fit reported, as `==` on the
  Float. Each line is no wider than the width, unless it holds no space. One fit
  runs per line.
- Flipping the overflow test from `>` to `>=` fails exactly one check,
  `a_line_of_exactly_the_available_width_fits`.

What the sketch got wrong:

- **The design's example width does not break its example.** `'The gate is shut
  for the night, traveller.'` measures 274.05 px at 18 px, so it fits on one
  line at 520. It breaks into the design's two lines at 180. The spec and
  `text.md` use 180.
- **Rule 4 cannot hold as written.** The break space is not part of any line,
  so the fitting lengths sum to the input length minus one byte per break. The
  Check sweep pins that sum and one call per line. Each call also re-walks the
  word that overflowed, so the work is linear plus one word per line.
- **Rule 2 decides the edge cases, and they produce empty lines.** Two spaces
  in a row, or a trailing space that does not fit, give an empty line. Without
  it, `lines.join(' ')` would lose a byte. The spec asserts the join for
  `'a  b'`, `'gate '` and `' gate'`.
- **A space that overflows is not an overflow.** A line exactly as wide as the
  width, followed by a space, ends before that space. A Check test pins it.
- **The plan says nothing about newlines.** `wrap` treats `"\n"` as a glyph,
  and `text.md` says so. That is a question for `Paragraph`, now open question
  5 in the README.
- **One sentence per language does not show the difference.** The Verify
  paragraph needs three sentences before German takes more lines than English
  at 520 px.

---

## Step 3 — `Core::Font` on a typeface, the renderer, and the fakes

**Why now.** Until the renderer can be handed a typeface, a node can measure
with one face and draw with another, and nothing reports it. This is also where
the cross-layer acceptance test finally has both halves to test.

**Sub-steps.**

- **3a — `Core::Font` takes a typeface.** `rgame_font_open_bytes` replaces the
  path read in `font_atlas.c`; `Font.new(app, typeface)` is the constructor and
  the two documented forms become sugar. `font.typeface` answers the face.
- **3b — the renderer resolves a typeface.** `renderer.typeface`, and `font:`
  accepting either a `Typeface` or a `Font` through a registry keyed by the
  typeface, built lazily against the app.
- **3c — the fakes measure for real**, and the contract says they agree.

**Rules the tests must pin.**

1. `Font.new(app, 18)` and `Font.new(app, Typeface.default(18))` measure
   identically.
2. `Font::LoadError` still names the path for an unreadable or non-TrueType
   file, through the sugar.
3. `renderer.text_width(s, font: typeface)` equals
   `typeface.text_width(s)` — the renderer adds nothing.
4. Two calls with the same typeface resolve to the same `Font`; the registry
   does not build one per call.
5. **The acceptance test.** A node measures a string with a `Util::Typeface`,
   draws it through a renderer at the position it computed, and the drawn extent
   lands inside the box it measured — asserted against the fake in `spec/` and
   against a real window in `spec_core/`. **Nothing in the project does this
   today**; it is the caller CLAUDE.md says to write first.

**Tests.** `spec_core/rgame/core/font_spec.rb`, `spec_core/rgame/core/renderer_spec.rb`,
`spec/support/shared_examples/a_renderer.rb` (new examples, run against both),
`spec/support/fake_renderer.rb` and `spec/support/quiet_renderer.rb` updated.
`spec/rgame/engine/debug_overlay_spec.rb` and its allocation spec stub their own
widths and should keep passing untouched — if they do not, the fake changed more
than intended.

**Verify.** All four suites. Then a driven run of an example that draws text,
before and after, with `--seed` and `--texts`, showing identical strings:

```
ruby tools/drive_test_project.rb examples/localization/main.rb --ticks 240 --seed 1 --texts
```

---

## Step 4 — `Engine::Paragraph` *(rough)*

Pure Ruby in the engine layer, holding a `Util::Typeface`. `Engine::Text`'s
cache with one more key. Lines, pages, `page_count`, and an allocation example
proving an unchanged read allocates nothing — modelled on `Text`'s.

Re-plan once step 2 has shipped a real `wrap`, and settle open question 1 (does
a width ever change after construction) with `UI::Label` in view.

## Step 5 — `UI::Label` and an example *(rough)*

The node, and the first example in the project to draw more than one line.
Likely `examples/localization` grown a paragraph, since it already ships two
languages and already says in its header that this is what it cannot do — that
header comment comes out here. A driven run with `--texts` is the acceptance
test.

Re-plan once `Paragraph` exists, and settle open question 2 (does the renderer
want a multi-line draw call) with a real caller in hand.

## Step 6 — fold back, and delete this plan

- `docs/api/text.md` — measuring outside `draw`, `Util::Typeface`, wrapping.
- `docs/api/values.md` — `Typeface` as a Util value.
- `docs/api/ui.md` — `UI::Label`, and "What this is not" rewritten: buttons are
  still not sized to their text, and that is now a choice rather than a limit.
- `docs/api/localization.md` — a translated paragraph wraps per language.
- `docs/plans/possible-todos.md` — the "Text measurement" entry comes out.
- `CHANGELOG.md` — checked against everything this plan shipped, per
  [update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
- `docs/plans/text-measurement/` — deleted. Git history keeps it.

**Verify.** `rake spec` covers whether `docs/api/`'s examples run and its links
resolve; `rake spec:core` covers whether every public name is documented. Both
green, and no file under `docs/plans/text-measurement/` remains.

---

## Why 4–6 are left rough

Per [write-plan](../../../.claude/skills/write-plan/SKILL.md): a re-planned step
routinely overturns something an earlier step recorded as fact. Two candidates
are visible already — whether `Paragraph` should cache per width or freeze it,
and whether `UI::Label`'s line loop belongs on the renderer. Both are answerable
with the layer beneath in hand and guesswork before that.
