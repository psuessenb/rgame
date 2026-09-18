# Current state

Everything here was read or measured at `cae9f96`, on macOS arm64, Ruby 4.0.5.

## What was measured before planning

| | |
|---|---|
| `rgame_typeface_open` + close, 410 KB font | **0.014 ms** — stb reads the table directory lazily |
| `rgame_typeface_measure`, `"Play"` | **0.43 µs** |
| `rgame_typeface_measure`, `"Systemsprache verwenden"` | **1.48 µs**, and **194.33 px** |
| Measuring, per character | **~65 ns** |
| Typeface code linked into a second `.so` (`-O2`) | **58.6 KB** — `util_ext.bundle` is 80 KB today |
| Shipped font | 410,712 bytes, **already copied once per open typeface**, per size |
| mkmf compiling a source from a sibling ext directory | **works** *(measured: built a throwaway extension that compiles `../sibling/*.c` via `$srcs` + `$VPATH`; objects land in its own directory)* |
| `font.c` → Core dependency | **one symbol**, `rgame_rect_make` *(measured: it is the only link error when font.c is compiled alone)* |
| `rgame_rect` users across `ext/`, `src/`, `test/` | 30 files, 88 `rgame_rect_make` calls |
| `renderer.text_width` call sites in `lib/rgame/engine/` | 6, across 3 files |
| Hand-rolled `renderer.text` calls in `examples/` | **76, across all 24 examples** |
| Existing wrapping, pagination or multi-line drawing | **none, anywhere** |
| Specs depending on the fake's invented widths | 2, both `debug_overlay`, both stubbing their own renderer |
| `test/test_font.c` | 698 lines, already run against the real shipped font |

The two that changed the design are the third and the sixth. Opening a face is
0.014 ms because `stbtt_InitFont` only reads the table directory, so a second
face over the same bytes is not a cost worth designing around. And `font.c`
touches Core through exactly one symbol, which is what makes the move a small
cut rather than a 30-file sweep.

## The text stack today

Five files under `ext/rgame_core/text/`, and the split is already almost the one
this plan wants:

| | Lines | Pure? | |
|---|---|---|---|
| `font.c` / `font.h` | 281 / 139 | **yes** — no GL, no SDL, no file I/O | metrics, rasterisation, UTF-8, the cursor |
| `atlas.c` | 59 | yes | where the next glyph goes on a page |
| `glyph_cache.c` | 142 | yes | which glyphs have been done |
| `font_atlas.c` | 385 | **no** | composes the three, owns GL textures, reads the file |

`font.h` already says why it is shaped this way, and the comment is the design
this plan finishes:

> "Typeface" rather than "font" because the public `rgame_font` (core.h) is the
> composed thing — this plus an atlas, a glyph cache and GL textures. This is
> only the part that knows what letters are shaped like.

It also states constraint 4 in full, and it is the reason line breaking cannot
be a Ruby loop that sums word widths:

> Measuring a string and drawing it must agree to the last fraction of a pixel,
> or every centred label in the game sits slightly off and nothing points at
> why. Two loops that both "sum the advances" drift the moment one of them gains
> a rounding rule or forgets kerning — so there is one loop, and both callers
> turn its crank.

`rgame_typeface_measure` is that loop run to the end and asked where it got to.
`app.c:726` is the same loop, turned one glyph at a time, placing quads.

## What blocks the goal

**The engine layer cannot reach any of it.** Three separate walls, and each one
alone is enough:

1. A `Core::Font` is a Core type, and `Game/NoCoreInEngineLayer` refuses the
   constant anywhere under `lib/rgame/engine/` or `spec/`.
2. A `Core::Font` needs an `app`, because it owns the glyph atlas as well as the
   face. There is no window while a scene is being built.
3. The renderer is the only measuring object a node is handed, and it **arrives
   in `draw`**. `Renderer#text_width` works outside a frame — `font_ext.c` says
   so deliberately — but a node has nothing to call it on until it is drawing.

So `docs/api/ui.md` records the consequence under "What this is not", and
`examples/localization` ends its header with it:

> The engine layer cannot measure text yet, so the buttons are a fixed width,
> chosen wide enough for the longer label in either language: "Use the system
> language". A third language with longer words would need a wider slot.

## What already resembles this

The three piles, as CLAUDE.md asks for them.

### Reuse it

- **`Engine::Text`** — a translated string cached against its variables and
  `I18n.generation`, re-rendered only when one moves, allocating nothing on an
  unchanged read. A wrapped paragraph needs exactly that contract with one more
  input, the width.
- **`Util::SaveFile`** — the precedent for a Util class that is plain Ruby with
  no C behind it. `Util::Typeface` will be a thin Ruby class over a C one, but
  the file reading belongs on the Ruby side for the same reason: no handle.
- **`Engine::Animator` and `Engine::Timer`** — accumulate elapsed seconds in
  `update` and hand the number to `draw`. Whatever reveals characters over time
  later is this shape, not a clock read.
- **`UI::ShapeStyle` and `UI::NineSliceStyle`** — a panel behind a label is a
  style, and both already exist.

### Extend or generalise it

- **`ext/rgame_util/color.h` is the whole answer to the extension boundary.**
  Its comment: the accessors are `static inline` in the header "because the
  engine half of the project needs them too … Core and Util are separate shared
  objects, so a real function would mean linking one into the other; an inline
  definition costs nothing and keeps a single source of truth". That decision,
  applied to a module too big to inline, is "both extensions compile the same
  source". `ext/rgame_core/extconf.rb` already carries `-I$(srcdir)/../rgame_util`
  and `spec/packaging_spec.rb` already asserts that `color.h` ships for it.
- **`Util::Controls` is the same move, already made.** Integers that started in
  Core because the C defines them, moved to Util because an id is a value and a
  game's config has to name one. `spec/rgame/util/controls_spec.rb` parses the C
  header and compares every one, so duplication with a guard beat putting a
  value out of reach. A typeface is the same argument with a bigger value.
- **`rgame_glyph` is two things wearing one name.** `codepoint`, `advance`,
  `bearing_x`, `bearing_y` and the glyph's size are facts about the face.
  `page` and the rectangle's `x`/`y` are facts about an atlas. `font.c` fills
  the first set and leaves the second at zero; `font_atlas.c` fills the second.
  Splitting them is what frees `font.c` from `graphics/clip.h`.
- **`UI::OptionButton#column_width` and `DebugOverlay#label_width`** are
  hand-rolled measure-and-cache, at draw time, invalidated by String identity.
  Both are correct and both stay; they are the idiom `Paragraph` formalises.

### Genuinely new

- **Line breaking.** Nothing in the project breaks a string. This is the
  conclusion the inventory reaches rather than the assumption it starts from.
- **Pagination** — grouping lines into pages that fit a height.
- **A non-interactive node that draws text.** Every one of the 24 examples
  writes its own `renderer.text` calls, 76 of them. `UI::` holds only menus,
  buttons and styles; a label would be its first node with no focus and no
  activation.

## What a caller using both looks like, and what exercises it

CLAUDE.md's acceptance test for a new subsystem sitting next to an old one:
count the scenes that mount both. Here the two are *measurement* and *drawing*,
and the count is **zero** — nothing in `examples/`, `test_projects/` or either
spec suite measures a string and then draws it at the position it measured,
across the layer boundary. `UI::TextButton#centred_x` comes closest and does
both inside one `on_draw`, on the same renderer, so it cannot disagree with
itself.

That is the test this plan writes first, and it is why the roadmap puts the
cross-layer agreement spec at the end of step 3 rather than at the end.

## The build, and what the move touches

- **`ext/rgame_core/extconf.rb`** globs `app graphics text input audio ruby`,
  adds each to `$VPATH`, and appends a `-w` rule per vendored library so
  third-party code compiles with warnings off. It already includes
  `../rgame_util`.
- **`ext/rgame_util/extconf.rb`** is nine lines: the mkmf default, flat, no
  subdirectories, no vendored code.
- **The root `Makefile`** builds every source a second time for the standalone
  binary and the Check suite. `FONT_OBJ`, `VENDOR_OBJS` and `TEST_OBJS` name the
  files that move.
- **`spec/packaging_spec.rb`** globs `ext/*/vendor/**/*`, so vendored code under
  `ext/rgame_util/vendor/` ships with no edit — and asserts it, which is the
  point.
