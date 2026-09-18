# Design

Four layers, each landing on the side of a line it already had to be on.

```
UI::Label            a node: draws one page of lines, with a style behind it
      |
Engine::Paragraph    a Text + a width -> lines and pages, cached against
      |              the variables, the language and the width
      |  holds a Util value outright — allowed
Util::Typeface       a face at one size: what a string measures, where it breaks
      ^              pure, headless, no handle, no graphics library
      |  built from, never reaches up
Core::Font           that face plus an atlas, a glyph cache and GL textures
```

## The extension boundary, settled

**Both extensions compile `ext/rgame_util/typeface.c`. Nothing crosses the `.so`
boundary in C.**

`ext/rgame_core/extconf.rb` already carries `-I$(srcdir)/../rgame_util`, and a
throwaway extension confirmed mkmf compiles a sibling directory's sources
happily: add the glob to `$srcs`, add the directory to `$VPATH`, and the objects
land in the extension's own directory. Two objects, one source — the same
arrangement the root `Makefile` already has with the standalone binary.

What crosses is Ruby:

```ruby
Core::Font.new(app, typeface)   # asks the typeface for its bytes and its size,
                                # then opens its own rgame_typeface from them
```

Identical code over identical bytes cannot measure differently. It costs
0.014 ms and one 410 KB copy per font — against a font already copied once per
size. A spec in `spec_core/` asserts the two agree, string for string, so the
claim is checked rather than argued.

Rejected: exporting a C symbol from `util_ext` and linking `core_ext` against
it. `ext/rgame_util/color.h` already refused that, in writing, for this exact
reason — and the macOS static-SDL build exports only `_Init_core_ext`.

## Layer 1 — `RGame::Util::Typeface`

A value: a parsed face at one pixel size. No app, no window, no handle, nothing
to release.

```ruby
tf = RGame::Util::Typeface.new('assets/pixel.ttf', 18)
tf = RGame::Util::Typeface.default(18)      # the shipped font, memoised per size

tf.height                    # => 18     the line height to step by
tf.text_width('Score: 1200') # => 78.4   Float, pixels
tf.wrap(string, 520)         # => ['The gate is shut for the', 'night, traveller.']
```

**`height` and `text_width` are spelled the way `Core::Font` spells them**, so
the two are interchangeable wherever something only measures — and
`Game/NoLiteralText` already flags a String literal passed to `text_width` on
any receiver, so the new type is covered by the existing cop with no edit.

`new` reads the file in Ruby with `File.binread` and hands the bytes to C, which
already takes bytes. **No file I/O enters `util_ext`**, and `read_whole_file`
eventually leaves `font_atlas.c`.

### The C: one more crank on the same walk

The existing walk gains one function, shaped after
[`TTF_MeasureString`](https://wiki.libsdl.org/SDL3_ttf/TTF_MeasureString):

```c
/*
 * How much of `text` fits in `max_width`, broken at the last space before the
 * overflow. Writes the fitting length in bytes and the width it reached.
 *
 * A word longer than `max_width` gets the whole word rather than being cut, so
 * a caller always makes progress and a long URL overflows visibly instead of
 * looping forever.
 */
void rgame_typeface_fit(const rgame_typeface *typeface, const char *text, size_t length,
                        float max_width, size_t *fit_length, float *fit_width);
```

It is `rgame_text_cursor` again, stopped early, so it cannot disagree with
`rgame_typeface_measure` or with the loop in `app.c` that places the quads —
constraint 4, held structurally rather than by care.

**Linear overall.** Each call walks only the text that fits, so the fitting
lengths sum to the length of the paragraph however many lines it breaks into.
The Ruby binding loops, slicing one String per line with `rb_str_subseq`. A
variant that wrote every break offset in one pass would need a worst-case buffer
for no gain.

### The glyph struct splits

`font.c` reaches into Core through exactly one symbol, `rgame_rect_make`,
filling a rectangle whose `x` and `y` are always zero — because where a glyph
lands on a page is the atlas's decision, as `font.h` says. So the struct is two
things wearing one name, and separating them is what frees the file:

```c
/* ext/rgame_util/glyph_metrics.h — facts about the face */
typedef struct {
    int codepoint;
    int width, height;              /* the bitmap this would rasterise to */
    float advance;
    float bearing_x, bearing_y;     /* y from the top of the line box */
} rgame_glyph_metrics;

/* ext/rgame_core/text/glyph_cache.h — those, plus where they went */
typedef struct {
    rgame_glyph_metrics metrics;
    int page;
    rgame_rect rect;                /* the placed rectangle on that page */
} rgame_glyph;
```

`rgame_rect` does **not** move. It is a value and Util is where values belong,
so this will be asked again — but it is 30 files and 88 call sites to serve one
caller that only ever passes `(0, 0, w, h)`.

## Layer 2 — `RGame::Core::Font`, built on a typeface

```ruby
Core::Font.new(app, typeface)            # the real constructor
Core::Font.new(app, 18)                  # sugar: Typeface.default(18)
Core::Font.new(app, 18, path: 'x.ttf')   # sugar: Typeface.new(path, 18)

font.typeface                            # the face it was built from
```

Both documented forms keep working. What changes is that **a `Font` always has a
typeface**, so "wrap with the face you draw with" stops being a rule and becomes
a fact about the object.

`Font::LoadError` keeps its meaning: the sugar rescues what `Typeface.new`
raises for an unreadable or non-TrueType file and re-raises it naming the path,
so a game's `rescue RGame::Core::Font::LoadError` is untouched.

## The renderer, and how a node draws what it measured

```ruby
renderer.typeface                        # the face `text` uses when none is named
renderer.text(line, x, y, font: tf)      # `tf` may be a Typeface or a Font
renderer.text_width(line, font: tf)
```

A `Typeface` passed as `font:` resolves to an atlas-backed `Core::Font` through a
registry keyed by the typeface, built lazily against the renderer's app — the
same shape `lookup(:image, id)` already has. So an engine node holds a value,
hands it to the renderer, and the renderer finds the handle. The node never
names a Core type and never asks what class answered.

**Both fakes stop inventing widths.** `FakeRenderer#text_width` and
`quiet_renderer.rb` measure with `Util::Typeface.default`, which `spec/` may
hold. The `a_renderer` contract gains an example that measuring and drawing
agree, and it runs against both implementations — so the headless suite finally
predicts the game's layout instead of approximating it.

## Layer 3 — `RGame::Engine::Paragraph`

`Engine::Text` with one more input. It holds a `Text`, a width and a typeface,
and answers lines and pages.

```ruby
@greeting = Engine::Text.new('npc.greeting', :name)
@speech   = Engine::Paragraph.new(@greeting, width: 520, lines_per_page: 3)

@speech.with(name: @hero_name)   # => self, so it chains
@speech.lines                    # => ['Good evening, Alma.', 'The gate is shut …']
@speech.page_count               # => 2
@speech.page(0)                  # => the lines of page 0
```

**It re-wraps when, and only when, one of its inputs moves**: a variable, the
width, the typeface, or `I18n.generation`. An unchanged read returns the same
frozen Array and allocates nothing — the property `Text` already has, extended
by one key, and specced the way `Text`'s is.

**`with` returns `self`, not a String.** `Text#with` returns the one value it
has; a paragraph has lines, pages and a count, so returning the object is what
lets a caller ask for the one it wants.

**The first argument is a key or a `Text`, never a bare String** — the same rule
`UI::Button#label=` follows. So `Paragraph.new('npc.greeting')` is a key,
`Paragraph.new(Text.literal(player_name))` is text that must not translate, and
there is no form that puts a player-visible String at the call site. That is why
`Game/NoLiteralText` needs no new entry for the constructor; it gains `wrap`
only, for `tf.wrap('some prose', 300)`.

**Pagination is here, not on the node.** Grouping lines into pages is arithmetic
over the line count, it is pure, and it is assertable headlessly in every
language the game ships. Deciding *which* page is showing, and what advances it,
is the caller's — which is how TextMeshPro splits it too.

## Layer 4 — `RGame::Engine::UI::Label`

The first node in `UI::` with no focus and no activation. It draws text.

```ruby
add_node(UI::Label.new(text: 'npc.greeting', x: 40, y: 260, width: 520,
                       lines_per_page: 3, style: UI::ShapeStyle::DEFAULT))
```

- **`width:` is optional.** Without it nothing wraps and the label is one line,
  which is what those 76 hand-rolled `renderer.text` calls in `examples/` are.
- **`style:` draws behind at `z: 0`, the lines at `z: 1`** — `UI::TextButton`'s
  arrangement, so the label reads on a panel.
- **`page` selects which page is drawn** when the label is paginated, and
  `page_count` answers how many there are. Nothing here reads input.
- **`align:` is `:left`, `:center` or `:right`**, applied per line against the
  label's width.

A dialogue box is then a `Label`, a `ui_confirm`, and `page += 1` — and that box
belongs to the dialogue plan, next to the beat queue and the branching choices
it will share a design with.

## What holds this together

| Rule | What keeps it |
|---|---|
| Measured equals drawn | one C walk; a `spec_core/` example comparing `Typeface#text_width` with `Font#text_width` |
| Engine names no Core type | `Paragraph` holds a `Util::Typeface`; `Game/NoCoreInEngineLayer` |
| No graphics library in `require "rgame"` | `spec/rgame/no_graphics_spec.rb`, unchanged |
| The fake does not drift | both renderers measure with the same real face, through `a_renderer` |
| Nothing allocates per frame | an allocation example on `Paragraph`, like `Text`'s |
| Everything new ships | `spec/packaging_spec.rb`, whose `ext/*/vendor/**/*` glob already covers the moved vendored code |
