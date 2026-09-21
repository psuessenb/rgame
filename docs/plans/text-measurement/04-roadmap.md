# Roadmap

**Steps 0–5 are implemented. Step 6 is detailed.**

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
`Typeface#text_lines(string, max_width)` calls the fit once per line, slices
each line with `rb_str_subseq` and steps past the space. `Game/NoLiteralText`
now names `text_lines` too, and `docs/api/text.md` has a "Breaking text into lines" section
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
- **The plan says nothing about newlines.** `text_lines` treats `"\n"` as a glyph,
  and `text.md` says so. That is a question for `Paragraph`, now open question
  5 in the README.
- **The method is `text_lines`, not `wrap`.** `wrap` is a common name, and
  the cop flags a literal first argument on any receiver. ActiveSupport's
  `Array.wrap('x')` would have been an offense. `text_lines` joins `text` and
  `text_width` as one family, so the cop's list names only this engine's text
  calls. Steps 4 and 5 should read `wrap` in their sketches as `text_lines`.
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

**Landed.** Step 3 landed after step 4, as the plan allowed. 3a builds
`Core::Font` on a typeface: `Font.new(app, typeface)` opens its own face from
the typeface's bytes through the new `rgame_font_open`, and `Font#typeface`
answers it. `Font.new(app, 18)` and `Font.new(app, 18, path:)` are sugar that
build the typeface first. 3b adds `Renderer#typeface`, and `font:` on `text`
takes a typeface, which resolves to one `Font` per typeface per renderer. 3c
makes `FakeRenderer` and `QuietRenderer` measure with `Typeface.default`, and
adds three examples to the `a_renderer` contract. Each is one commit.
`docs/api/text.md` has "Drawing with a typeface" and a rewritten "Fonts",
`docs/api/drawing.md` says the fake measures with the real font, and
`CHANGELOG.md` has an entry.

On a clean build, `make test` 380 checks, `rake spec` 2404 examples,
`rake spec:core` 427, all 0 failures, no warnings, and `rake docs:coverage`
finds no undocumented name. The measured acceptance evidence:

- **Rule 5, in a window:** `'Hamburgefonstiv'` at 24 px, centred in 256 px by
  its typeface's width and drawn with that typeface, puts all its ink inside
  the measured box. `spec_core/rgame/core/renderer_spec.rb` asserts it.
- **Rule 5, headless:** a `Node2D` measures a title in `on_update` and draws it
  in `on_draw` with the same typeface. Against the fake it lands centred to
  within 1e-9 px. `spec/rgame/engine/measured_text_spec.rb` asserts it.
- **Rule 4:** two `text` calls with one new typeface add **1** atlas page. A
  call with the renderer's own typeface adds **0**, because it resolves to the
  renderer's font.
- **The driven run:** `examples/localization` at `--seed 1` for 240 ticks gives
  a **byte-identical report** on `main` and on this branch: 1920 `text` calls,
  every string, and the first and last positions.
- **Mutations.** Building a new `Font` on every call fails the two registry
  examples. Putting back the fake's 8 px per character fails the contract
  example "answers the typeface it measures with".

What the sketch got wrong:

- **`rgame_font_load` stays.** The standalone binary in `src/main.c` opens its
  font by path. So the new function is `rgame_font_open`, from bytes, and
  `rgame_font_load` reads the file and calls it.
- **`Typeface#bytes` is a Ruby method over a private C one.** Step 1 left it
  out. It is public so `Core::Font` can call it, and tagged `@api private`.
  A method defined in C has no source location, so the coverage spec cannot
  see a tag on it. The C side is `rgame_typeface_data`, and the face now keeps
  its file's length.
- **Only `text` needs the registry.** A typeface answers `text_width` and
  `height` itself, so `text_width` and `text_height` pass it straight through.
  Rule 3 holds because the renderer calls the typeface's own method.
- **Two edges the plan did not list.** A size below 1 through the sugar still
  raises `Font::LoadError`, as before. The sugar checks it first, because
  `Typeface.new` raises `ArgumentError` for it. `path:` beside a typeface
  raises `ArgumentError`, since the typeface already names its file.
- **The window half of rule 5 cannot be a node.** `spec_core/` may not name
  `Engine`. So the window draws the centring directly with a typeface, and the
  node runs against the fake. A node drawing text in a real window is still
  exercised only by driven examples. Step 5's driven example is where that
  gets asserted.
- **Eight UI specs asserted the invented widths.** They were in
  `text_button_spec.rb`, `icon_button_spec.rb` and `option_button_spec.rb`, and
  now derive each position from the typeface. `debug_overlay_spec.rb` passed
  untouched, as the plan predicted.
- **The driven run carries state between runs.** The example keeps the
  player's language in `~/.local/share/rgame-examples/language.json`. Both runs
  started with it removed, and it was put back afterwards. Overriding `HOME` to
  avoid it does not work: mise then installs a second Ruby, and the extensions
  refuse to load.

---

## Step 4 — `Engine::Paragraph`

**Why now.** It is the layer `UI::Label` draws from, and the first place a
translated text meets a width. It needs only step 2, so it does not wait on step
3: `Paragraph` holds a `Util::Typeface` and never a renderer. Steps 3 and 4 can
land in either order.

### What was measured before planning

Taken at `4f0c438`, Ruby 4.0.5.

| | |
|---|---|
| `Typeface#text_lines` on the 264-byte German paragraph at 520 px | 49 µs and 5 objects per call: 4 lines and the Array |
| `Text#with(name:)`, unchanged | 0 objects per call |
| a wrapper's `def with(...) = @text.with(...)`, unchanged | 0 objects per call |
| a wrapper's `def with(**) = @text.with(**)`, unchanged | 1 object per call, a Hash |
| `Text#to_s.equal?(previous)`, unchanged | 0 objects per call |
| YAML `key: \|` and `key: >` block scalars | end the String with `"\n"`; only `\|-` and `>-` do not |

At 49 µs a paragraph costs 0.3 % of a 16.7 ms frame, so time alone would not
justify a cache. The 5 objects per paragraph per frame do: that is the
allocation `Game/NoNeedlessAllocation` exists to keep off a draw path.

### What it resembles

- **Reuse.** `Text` already returns the *identical* frozen String until a
  variable or `I18n.generation` changes. `UI::OptionButton` relies on that
  contract to cache its column width (`option_button.rb:154`,
  `caption.to_s.equal?(@measured[at])`). `Paragraph` keys its cache the same
  way, so it compares no variables and reads no generation of its own.
  `Typeface#text_lines` does the breaking, and `allocate_nothing` is the
  allocation matcher `Text`'s specs use.
- **Extend.** The C fit gains the newline break (4a). `Paragraph` could do it
  in Ruby, but then `text_lines` would still measure `"\n"` as a glyph.
- **Reuse the rule, not the code.** `UI::Button#label=` takes a key or a
  `Text` (`button.rb:244`). `Paragraph.new` takes the same two forms. The
  button's one line also applies its `label_scope`, which a paragraph has no
  reason to carry, so nothing is extracted.
- **Genuinely new.** Grouping lines into pages. Nothing in the engine does it.

This corrects the design's cache. [03-design.md](03-design.md#layer-3--rgameengineparagraph)
has `Paragraph` compare the variables, the width, the typeface and
`I18n.generation`. The variables and the generation are `Text`'s to compare.
A second comparison of them would be a second cache that can disagree with the
first.

**Sub-steps, one commit each.**

- **4a — a newline ends a line.** `rgame_typeface_fit` stops at `"\n"` as well
  as at a space that overflows, and `Typeface#text_lines` steps past it.
  `docs/api/text.md` stops saying a newline is "a character like any other".
- **4b — `Engine::Paragraph`**, with `lines`, `with`, `width=` and `typeface`,
  and a section in `docs/api/text.md`. The coverage spec fails on an
  undocumented public class, so the docs cannot wait for step 6.
- **4c — pages.** `lines_per_page:`, `page` and `page_count`.

**Shape.**

```c
/* 4a: the line also ends at a newline, which belongs to no line.
 * text[*fit_length] is then '\n' rather than ' '. */
void rgame_typeface_fit(const rgame_typeface *typeface, const char *text, size_t length,
                        float max_width, size_t *fit_length, float *fit_width);
```

```ruby
@greeting = Engine::Text.new('npc.greeting', :name)
@speech   = Engine::Paragraph.new(@greeting, width: 520, lines_per_page: 3)
@notice   = Engine::Paragraph.new('gate.notice', width: 300)   # a key, no variables

@speech.with(name: @hero_name)   # => self
@speech.lines                    # => a frozen Array of frozen Strings
@speech.page_count               # => 2
@speech.page(1)                  # => the lines of page 1
@speech.width = 260              # re-breaks on the next read
@speech.typeface                 # => Util::Typeface.default, unless typeface: was given
```

Every read goes through one check, and returns the cached Array when nothing
moved:

```ruby
def lines
  source = @text.to_s
  return @lines if source.equal?(@source) && @width == @broken_at

  break_lines(source)
end
```

`with` forwards with `(...)`, not `(**)`: measured above, the second allocates a
Hash on every call.

**Rules the tests must pin.**

4a:

1. A `"\n"` ends the line wherever it falls, even when the rest of the text
   would fit.
2. The newline belongs to no line, and `text[*fit_length]` is it.
3. `"a\n\nb"` is three lines, the middle one empty.
4. **One `"\n"` at the very end adds no empty line.** YAML's `|` and `>` end
   every String with one, so otherwise every paragraph written as a block
   scalar would gain a blank last line and could spill onto an extra page.
5. A word too wide for the line still ends at a newline, not at the next space.

4b:

1. **An unchanged read allocates nothing**: `lines`, and `with` given the same
   values, over 200,000 reads each, like `Text`'s.
2. **It breaks again exactly when the text's String or the width changes.**
   Pinned as a count of `text_lines` calls: once for any number of unchanged
   reads, and not at all for `width=` given the width it already has.
3. **A language switch re-breaks with no call on the paragraph.** Loading or
   switching moves `I18n.generation`, `Text` renders again, and the new String
   fails the identity check.
4. The first argument is a key (String or Symbol) or a `Text`. Anything else
   raises `TypeError`. There is no way to pass player-visible prose as a String.
5. A width of zero or less raises `ArgumentError`, at construction and in
   `width=`.
6. `lines` is frozen and so is each line. The same Array comes back until
   something moves.

4c:

1. Without `lines_per_page:` a paragraph is one page.
2. **`page_count` is at least 1**, so an empty text is one empty page. A
   dialogue box that advances "until the last page" needs no guard.
3. **`page(n)` clamps to the pages there are.** A language switch can shorten a
   paragraph while a game shows its last page. Raising there would crash a
   dialogue mid-scene, and returning nothing would blank it.
4. `page(n)` returns the same frozen Array on every unchanged read, and
   allocates nothing.
5. A `lines_per_page` below 1 raises `ArgumentError`.

**Tests.** `test/test_typeface.c`: a newline in a line that fits, directly
after an exact fit, two in a row, one at the end, and after a word too wide for
the line. `spec/rgame/util/typeface_spec.rb`: the same through `text_lines`,
and a string read from a YAML `|` block. `spec/rgame/engine/paragraph_spec.rb`:
every rule above, with `en` and `de` tables loaded through `I18n.load_hash`, and
the allocation examples.

**Verify.** `make test` and `rake spec`, plus `rake spec:core` for the doc
coverage. The acceptance test is a spec: a `Paragraph` built from one key, at
520 px, answers 3 lines under `en`, and 4 after `I18n.locale = :de`, with no
call on the paragraph in between.

**What this does not deliver.** No drawing, no alignment and no line height:
those are `UI::Label`'s, in step 5. No `typeface=`. Nothing swaps a paragraph's
face yet, and a setter is one more identity check if step 5 wants one. No `"\r"`
handling. YAML turns the line breaks in a file into `"\n"`, so a `"\r"` only
reaches `text_lines` if an author types one into a quoted string.

**Landed.** Step 4 landed before step 3, as the plan allowed. 4a is
`rgame_typeface_fit` stopping at `"\n"` and `Typeface#text_lines` stepping past
it. 4b is `Engine::Paragraph` in `lib/rgame/engine/paragraph.rb`, keyed on the
identity of the String its `Text` returns and on the width, as sketched. 4c adds
`lines_per_page:`, `page`, `page_count` and a `lines_per_page` reader. Each is one
commit. `docs/api/text.md` documents all three under "Breaking text into lines"
and "A paragraph that follows the language", and `CHANGELOG.md` has an entry.

`make test` 378 checks, `rake spec` 2398 examples, `rake spec:core` 413, all 0
failures. A clean rebuild of both extensions and the standalone binary gives no
warnings. The measured acceptance evidence:

- The story paragraph at 520 px answers **3 lines under `en` and 4 after
  `I18n.locale = :de`**, with no call on the paragraph between.
  `spec/rgame/engine/paragraph_spec.rb` asserts it.
- `lines`, `with` given the same values, and `page` with `page_count` each
  allocate **0 objects over 200,000 reads**.
- `text_lines` runs **once** for three unchanged reads, **not at all** after
  `width = 180.0` on a paragraph at 180, and **twice** for two reads each of
  two names.
- Three mutations were run against the spec. `with(**)` in place of `with(...)`
  fails the allocation example. Dropping the width from the cache check fails
  "breaks again at a new width". Removing the refresh from `page` fails four
  examples.

What the sketch got wrong or left open:

- **Identity is a cost, not a behaviour.** Comparing the Strings with `==`
  instead of `equal?` survives every example, because both give the same lines.
  `equal?` stays: it compares one pointer, and `==` compares every byte of an
  unchanged text on every read.
- **The trailing-newline rule lives in `text_lines`, not in the fit.** The fit
  sees one line at a time and cannot tell the last newline from the others. The
  loop in `typeface_ext.c` stops after a newline that ends the string, and the
  Check helper `wrap_counting_lines` mirrors it.
- **A newline wins over the overflow test.** A line that fits exactly and is
  followed by `"\n"` would overflow on the newline's own advance. The fit checks
  for the newline first, so that line ends at the newline and not at the space
  before its last word. A Check test pins it.
- **`lines.join(' ')` no longer gives back every string.** It still does for
  a string without newlines. `text.md` now says each break takes the space or
  newline it replaced.
- **`page` counts from 0.** The sketch's `page(1) # => the lines of page 1`
  did not say. Ruby's indices count from 0, and `docs/api/text.md` says so.
- **Two refusals the plan did not list.** A width that is not a number and a
  `lines_per_page` that is not an Integer raise `TypeError`, next to the
  planned `ArgumentError`s.
- **The `docs/api/README.md` row for Text** now names `Util::Typeface` and
  `Engine::Paragraph`. Step 2 had left `Typeface` out of it.

## Step 5 — `UI::Label` and an intro example

**Why now.** Steps 3 and 4 give a node everything it needs to lay out a
paragraph: `Paragraph` breaks and pages the text, and a renderer draws the
typeface the paragraph measured with. Nothing yet puts the two together, and no
example draws more than one line from a translation. This step is the caller
CLAUDE.md asks for: a node that uses `Paragraph` and the renderer together,
driven in a real window.

### What was measured before planning

Taken at `031fcf0`, Ruby 4.0.5, with the default typeface at 24 px.

| | |
|---|---|
| a 327-byte English intro, one line in the table, at 440 px | 8 lines, 3 pages of 3 |
| its 403-byte German translation at 440 px | 10 lines, 4 pages of 3 |
| the same two at 520 px | 7 and 8 lines, 3 pages each |
| `text_lines` on the German text at 520 px | 88 µs per call |
| a draw of one page, centred, looping with `while` | 0 objects per draw over 200,000 |
| the same with `each_with_index` | 1 object per draw |
| a draw of 3 centred lines, each measured every frame | 15 µs |
| callers that step `y` by a line height today | 1, `DebugOverlay#draw` |

At 440 px the German intro needs a page more than the English one, which is
what the example should show. Measuring each line on every draw costs 15 µs, or
0.09 % of a frame, so `Label` measures in `on_draw` and caches no offsets.

### What it resembles

- **Reuse.** `Paragraph` does the breaking, the paging, `with` and `width=`.
  `Util::Typeface` measures each line for alignment. The renderer draws a
  typeface passed as `font:` (step 3). `Components::Timer` turns the example's
  pages, and `reset` restarts it when the player turns one by hand.
- **Considered, and not generalised.** `UI::TextButton` centres a label in a
  slot, and `centred_x` does the arithmetic `align: :center` does. A
  `TextButton` could draw through a `Label`, but its label is one line
  centred vertically in a slot, and nothing asks for a button whose label
  breaks. The two share one line of arithmetic, not a question.
- **`DebugOverlay`'s rows are not a second caller for open question 2.** It
  right-aligns a label beside a number it draws itself, digit by digit, and
  steps three fixed rows. A renderer call that draws an Array of lines would
  not fit it.
- **Genuinely new.** A node that draws one page of a paragraph.

### Where this departs from the design

[03-design.md](03-design.md#layer-4--rgameengineuilabel) sketched `Label` before
`Paragraph` existed. Three things change:

- **No `style:`.** The intro draws on a black screen, and nothing else asks for
  a panel behind a label yet. A style takes a button state, which a label does
  not have. The dialogue plan adds one when its box needs it.
- **`width:` is required.** `Paragraph` needs a positive width, and a label
  without one is one line, which `renderer.text` already draws. The 76
  hand-rolled `renderer.text` calls in `examples/` stay as they are.
- **Open question 2 is settled: no multi-line draw call.** `Label` is the only
  caller, and its loop is five lines. A renderer method would also need
  `FakeRenderer`, `QuietRenderer` and the `a_renderer` contract to follow it.

**Sub-steps, one commit each.**

- **5a — `UI::Label`**, with its spec and a section in `docs/api/ui.md`.
  `QuietRenderer#text` gains `font:`, which `Label` passes and the allocation
  spec needs. `CHANGELOG.md` gets an entry.
- **5b — `examples/intro`.** One long line of intro text in `locales/en.yml`
  and `locales/de.yml`, shown a page at a time. A drive script, an entry in
  `docs/api/examples.md` and a row in `README.md`.

**Shape.**

```ruby
@intro = UI::Label.new(text: 'intro.story', x: 100, y: 150, width: 440,
                       typeface: Util::Typeface.default(24), lines_per_page: 3,
                       align: :center, color: UI::Label::COLOR)

@intro.with(name: @hero)   # => self, for a Text with variables
@intro.page                # => 0
@intro.page += 1           # clamps to the last page
@intro.page_count          # => 3
@intro.last_page?          # => false
@intro.width = 400         # re-breaks on the next draw
```

`text:` is a key or an `Engine::Text`, as `Paragraph` takes it. `typeface:`
defaults to `Util::Typeface.default`, `lines_per_page:` to one page, `align:` to
`:left`, and `color:` to the label colour `UI::TextButton` uses. `Label` reads
no input. Its owner turns the page.

`on_draw` draws the current page from the label's top-left corner:

```ruby
def on_draw(renderer, _view)
  lines = @paragraph.page(@page)
  index = 0
  while index < lines.size
    line = lines[index]
    renderer.text(line, line_x(line), index * @typeface.height, font: @typeface, color: @color)
    index += 1
  end
end
```

`while`, not `each_with_index`: measured above, the second allocates on every
draw.

**Rules the tests must pin.**

1. **It draws the lines of the current page**, one `text` call each, from its
   top-left corner. Each line sits one `typeface.height` below the last and is
   drawn with `font: typeface`.
2. **`align:` places each line against the width.** `:left` at 0, `:center` at
   `(width - line_width) / 2`, `:right` at `width - line_width`. Any other value
   raises `ArgumentError` at construction.
3. **A language switch redraws with no call on the label.** The acceptance
   test: one key at 440 px and 24 px draws 3 pages under `en` and 4 after
   `I18n.locale = :de`.
4. **`page=` clamps to the pages there are**, so `page += 1` on the last page
   stays there. `page` reads clamped too, after a switch that shortens the
   text. `page_count` is at least 1, and `last_page?` is true on it.
5. **`width=` sets the node's width and the paragraph's**, and the next draw
   breaks again. A width of zero or less raises `ArgumentError`, as
   `Paragraph`'s does.
6. **`with` forwards to the text and returns the label.**
7. **An unchanged draw allocates nothing**, over 200,000 draws against
   `QuietRenderer`, with `align: :center`.
8. `text:` that is neither a key nor a `Text` raises `TypeError`, as
   `Paragraph` does.

**Tests.** `spec/rgame/engine/ui/label_spec.rb`: every rule above against
`FakeRenderer`, with `en` and `de` tables loaded through `I18n.load_hash`, and
the allocation example against `QuietRenderer`.

**The example.** `examples/intro/main.rb` shows a black screen and the intro,
three lines at a time, centred. **Enter** (`ui_confirm`) turns the page. A
`Components::Timer` also turns it every 6 seconds, and Enter resets that timer,
so a page turned by hand gets its full time. On the last page the timer stops
and the hint at the bottom goes away. The header says what it does not solve:
no typewriter reveal, no fade, and nothing after the last page.

`tools/drive/examples/intro.rb` presses Enter once, then lets the timer turn the
remaining pages. Its header states what the report shows, read off a real run.

**Verify.** `rake spec`, and `rake spec:core` for the doc coverage. Then two
driven runs with `--texts`:

```
LANG=en_US.UTF-8 ruby tools/drive_test_project.rb examples/intro/main.rb --ticks 1200 --texts
LANG=de_DE.UTF-8 ruby tools/drive_test_project.rb examples/intro/main.rb --ticks 1200 --texts
```

The English run draws 8 distinct lines of the story and the German run 10. The
second page appears at the tick Enter was pressed, and each later page 6
seconds after the one before. No key shows under "missing or mismatched keys".

**What this does not deliver.** No panel behind a label, and no vertical
alignment: the example places the block with its own arithmetic. No reveal or
fade, which belong to the dialogue plan. No change to any button.

**Landed.** 5a is `UI::Label` in `lib/rgame/engine/ui/label.rb`, with the
sketched shape, a section in `docs/api/ui.md` and a `CHANGELOG.md` entry.
`QuietRenderer#text` takes `font:`. 5b is `examples/intro`, with `en.yml` and
`de.yml` holding the story as one line each, a drive script, an entry in
`docs/api/examples.md` and a row in `README.md`. Between the two is a commit
the plan did not have: a fix to `Components::Timer`, below.

`make test` 380 checks, `rake spec` 2424 examples, `rake spec:core` 427, all 0
failures. The measured acceptance evidence:

- **The spec:** the intro story at 440 px and 24 px draws **3 pages under `en`
  and 4 after `I18n.locale = :de`**, with no call on the label between.
  `spec/rgame/engine/ui/label_spec.rb` asserts it.
- **An unchanged draw** of a centred page allocates **0 objects over 200,000
  draws** against `QuietRenderer`.
- **The driven runs**, 1200 ticks each with `--texts`. English draws **8
  distinct story lines** and German **10**, with no missing keys. Enter at tick
  120 turns the first page on tick 121. The timer turns each later page 360 or
  361 ticks after the one before. The hint shows until the last page: 481
  frames in English, 842 in German. These runs are also the node drawing text
  in a real window that step 3's note left to this step.
- **Mutations.** `each_with_index` in place of the `while` loop fails the
  allocation example. `page=` without its clamp fails "keeps the page it
  stopped on when a switch adds pages".

What the sketch got wrong:

- **A one-shot timer could not re-arm itself.** The sketch had Enter call
  `reset` on a repeating timer, and the timer stop on the last page. Stopping a
  repeating timer means removing it from inside its own signal, while the node
  is looping over its components. A one-shot the root re-arms after each turn
  stops by itself. But `Components::Timer` marked a one-shot done *after*
  emitting `on_timeout`, so a `reset` in the handler was undone and the timer
  fired once. It now marks it done before emitting. The fix is its own commit,
  with two examples in `spec/rgame/engine/components/timer_spec.rb` and a
  "Fixed" entry in `CHANGELOG.md`.
- **Rule 4 needed an example the sketch did not name.** Without the clamp in
  `page=`, every listed example still passed, because `page` reads clamped. The
  case that tells them apart is a page set past the end in English, then a
  switch to German's extra page. Unclamped, the label jumps to a page the
  player never turned to.
- **The one-tick difference in the timer's turns is not drift.** Enter re-arms
  the timer during `control`, before that tick's update adds its step. The
  timer re-arms itself during `update`, after it. The drive script's header
  says so, so a reader does not take 361 for a bug.
- `docs/api/ui.md` mentions `examples/intro` from 5b, not 5a, so no commit
  names an example that does not exist yet.

## Step 6 — fold back, and delete this plan

**Why now.** Steps 0–5 have shipped, so the plan describes code that exists and
will start drifting from it. What is still true moves into the reference
documentation, what is still open moves to `docs/plans/possible-todos.md`, and
the folder goes. The fold-back is also where
[learn-from-mistakes](../../../.claude/skills/learn-from-mistakes/SKILL.md) reads
every step's "What proved wrong" as a whole.

### What was measured before planning

Taken at `492e79a`. A search outside `docs/plans/text-measurement/` for the
plan's name and for claims that text cannot be measured found these:

| Where | What it says, and why it is wrong now |
|---|---|
| `CLAUDE.md`, "What exists" | "Text measurement is the gap". `Util::Typeface`, `Paragraph` and `UI::Label` exist |
| `docs/api/ui.md`, "What this is not" | buttons are not sized to their text *because engine code has nothing to measure with*. The first half is a decision now, and the reason is false |
| `docs/api/localization.md`, "What this is not" | "Text is not measured in the engine layer" |
| `docs/api/text.md`, "What is not here" | "no multi-line drawing … the caller draws each one". `UI::Label` draws them |
| `examples/localization/main.rb`, header | "The engine layer cannot measure text yet" |
| four specs | name "the text-measurement plan" or "step N" of it: `paragraph_spec.rb`, `measured_text_spec.rb`, `label_spec.rb`, `spec_core/.../renderer_spec.rb` |
| `docs/plans/possible-todos.md` | the "Text measurement for the engine layer" entry, whose work this plan did |
| `docs/plans/research/roadmap-complexity-estimate-v0.5.0.md` | "Text measurement gates two items", pointing at that entry |

`docs/api/values.md` already has a `Typeface` section, and `docs/api/text.md`
already covers measuring, breaking, `Paragraph` and drawing with a typeface.
Both only need checking.

**The lessons, collected from every step's "What proved wrong".** Run through
learn-from-mistakes, one survives the first filter and it is a guard, not a
skill line:

- **A driven run reads what the last run saved.** In step 1 the
  `examples/localization` report drew German because an earlier run had saved
  that choice. In step 3 comparing two runs meant moving the saved file aside
  by hand. `docs/plans/possible-todos.md` already has the fix, "The drive
  harness owns the save directory", and its trigger is "the first time a report
  differs for this reason". It has now happened twice.
- The rest are covered or were one-offs. Numbers in a sketch that were never
  measured (steps 2 and 4) are what write-plan's "numbers, not adjectives"
  already says. Specs that survived a mutation (steps 4 and 5) are the verify
  skill's mutation testing. A C method that cannot carry `@api private` is
  what write-docs' "a C binding behind a Ruby wrapper" rule already avoids. The
  timer that could not re-arm itself was fixed in code, with a spec.

**What moves to `possible-todos.md`.** A new entry, "Text layout past a label",
holds what the plan left open, each with its trigger:

- **Ascent and descent on `Typeface`** (open question 4). Trigger: a caller
  aligning two faces on one line.
- **Breaking between characters**, for scripts without spaces. Trigger: a font
  shipped or loaded that covers one.
- **A panel behind a label, and vertical alignment** (dropped from step 5).
  Trigger: the dialogue box.

Content-sized buttons are not a todo. The user decided buttons keep their fixed
sizes, and `docs/api/ui.md` states it.

**Sub-steps, one commit each.**

- **6a — the drive harness owns the save directory.**
  `tools/drive_test_project.rb` sets `RGAME_SAVE_DIR` to a fresh temporary
  directory unless the caller set one, deletes it afterwards, and names it at
  the top of the report. The write-example and verify skills stop telling the
  reader to set it, and say when to pass one: to keep a save across two runs,
  as `localization_saved.rb` does. The drive script headers that say to set it
  say that instead. The possible-todos entry comes out.
- **6b — the reference documentation.** Every row of the table above except the
  two plan files: `CLAUDE.md`, `ui.md`, `localization.md`, `text.md`, the
  `examples/localization` header, and the four spec comments, which say what
  they assert without naming the plan.
- **6c — the open work.** The "Text measurement" entry comes out of
  `possible-todos.md`, and "Text layout past a label" goes in. The research
  estimate says measurement has landed. `CHANGELOG.md` is checked against
  everything steps 0–5 shipped, per
  [update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
- **6d — delete `docs/plans/text-measurement/`.**

**Rules the tests must pin.**

1. A driven run with no `RGAME_SAVE_DIR` saves into a directory that did not
   exist before the run and does not exist after it.
2. A run given `RGAME_SAVE_DIR` uses it and leaves it in place.

**Tests.** The harness has no spec of its own, so both rules are checked by
driving `examples/localization` twice with nothing set: both reports draw
English from tick 0, and `~/.local/share/rgame-examples/` is untouched. Then
twice with one directory passed, as `localization_saved.rb` expects: the second
run starts in German.

**Verify.** `rake spec` for `docs/api/`'s examples and links, `rake spec:core`
for the doc coverage and the names the pages mention, both green. A search for
`text-measurement` outside git history finds nothing, and no file under
`docs/plans/text-measurement/` remains. `CHANGELOG.md` has an entry for every
public name steps 0–5 added.
