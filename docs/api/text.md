# Text

**The renderer comes with a font, and `text` draws with it.** Most games need
nothing more:

```ruby
require 'rgame'
require 'rgame/core'

class MyGame < RGame::Core::App
  def initialize
    super(width: 800, height: 600, caption: 'demo')
    @renderer = RGame::Core::Renderer.new(self)
  end

  def draw
    @renderer.text('Score: 1200', 10, 10)
  end
end

MyGame.new.run
```

## Where text goes

`text(string, x, y, …)` puts the **top-left corner** of the line at `(x, y)`.
Every other drawing method uses the same corner. Typography measures from the
baseline, but a caller placing a label does not have to.

```ruby
renderer.text(string, x, y, z: 10, color: nil, font: nil)
renderer.text_width(string, font: nil)   # => Float — pixels
renderer.text_height(font: nil)          # => Integer — the line height
```

**`string` is a String or anything with `to_str`**, such as an
[`Engine::Text`](toolbox.md#text--the-string-a-node-draws), which a node passes
as it is. `text` and `text_width` raise `TypeError` for `nil`, a number, or a
`to_str` that returns something other than a String.

**A string is one line.** `text` draws a newline as a glyph, not as a line
break. Break the string with [`text_lines`](#breaking-text-into-lines), then draw
each line with its own call, stepped by `text_height`:

```ruby
lines.each_with_index do |line, i|
  @renderer.text(line, 10, 10 + (i * @renderer.text_height))
end
```

**`text_width` and `text` agree.** They run the same code, so a label centred by
its measured width lands exactly there:

```ruby
@renderer.text(label, (width - @renderer.text_width(label)) / 2, 20)
```

**`text_width` and `text_height` also work outside `draw`**, unlike the drawing
methods. Measuring touches no GPU, and a menu lays itself out while updating.

A label built from a changing value, like a score, should come from
[`RGame::Engine::Text`](toolbox.md#text--the-string-a-node-draws). It renders
the string only when a variable or the language changes:

```ruby
@score = RGame::Engine::Text.new('hud.score', :score)   # once

renderer.text(@score.with(score: @points), 10, 10)     # every frame
```

## Fonts

```ruby
font = RGame::Core::Font.new(app, 18)                          # the shipped font
font = RGame::Core::Font.new(app, 18, path: 'assets/pixel.ttf')

font.height              # => 18
font.text_width('Hello') # => 38.7

renderer.text('Hello', 10, 10, font: font)
```

A `Font` is **one typeface at one pixel size**. Two sizes need two fonts. A font
belongs to the app whose GPU context holds its glyphs, like an image. Drawing it
through another app's renderer raises instead of painting blank boxes.

The renderer builds its own 18px font on first use. Replace it, and every `text`
call without a `font:` follows:

```ruby
@renderer.font = RGame::Core::Font.new(self, 24)
```

A file that is unreadable or not a TrueType font raises
`RGame::Core::Font::LoadError`, naming the path.

### Measuring without a window

**`RGame::Util::Typeface` measures text with no window, no GPU and no graphics
library.** It loads with `require 'rgame'`, so game logic and headless specs can
lay text out with it:

```ruby
require 'rgame'

face = RGame::Util::Typeface.default(18)   # the shipped font, opened once per size
face.height                                # => 18
face.text_width('')                        # => 0.0
face.text_width('AV') < face.text_width('A') + face.text_width('V') # => true — kerned
```

`Typeface#height` and `Typeface#text_width` are spelled as a `Font` spells them,
and return the same numbers. A `Font` and a `Typeface` built from the same file at
the same size measure every string to the same `Float`, because both run the same
C over the same bytes.

`Typeface.default` takes the size and defaults it to
`RGame::Util::Typeface::DEFAULT_SIZE`, which is 18. The renderer's own font uses
that size too. For any other file, pass its path:

```ruby
face = RGame::Util::Typeface.new('assets/pixel.ttf', 16)
```

A path resolves against the working directory. A file that is unreadable or not
a TrueType font raises `RGame::Util::Typeface::LoadError`, naming the path. A
size below 1 raises `ArgumentError`.

### Breaking text into lines

**`Typeface#text_lines(string, max_width)` returns the lines a string breaks
into, one String per line.** It breaks at the last space that fits, and at every
newline. Every line
measures no wider than `max_width`, with one exception: a word wider than the
whole line comes back whole rather than cut.

```ruby
require 'rgame'

face = RGame::Util::Typeface.default(18)
face.text_lines('The gate is shut for the night, traveller.', 180) # => ["The gate is shut for the", "night, traveller."]
face.text_lines('The gate is shut.', 180)                          # => ["The gate is shut."]
face.text_lines('Systemsprache verwenden', 50)                     # => ["Systemsprache", "verwenden"]
face.text_lines("The gate is shut.\nCome back at dawn.\n", 520)    # => ["The gate is shut.", "Come back at dawn."]
face.text_lines('', 180)                                           # => []
```

Each break takes the space or newline it replaced, so no line holds either.
Two spaces in a row, or a trailing space that does not fit, produce an empty
line, and so do two newlines in a row. One newline at the very end adds no
line: a YAML `|` block ends every string with one. `text_lines` never
hyphenates and never breaks inside a word.

`text_lines` runs the same C walk as `text_width`, so a line it returns measures
what `text_width` reports for it. It builds new Strings on every call, so call
it once when the text or the width changes, not in `draw`.

### A paragraph that follows the language

**`RGame::Engine::Paragraph` breaks a translated text into lines that fit a
width, and keeps them.** It takes a translation key or an
[`Engine::Text`](toolbox.md#text--the-string-a-node-draws), and a width in
pixels:

```ruby
require 'rgame'

RGame::Engine::I18n.load_hash(
  en: { gate: { notice: 'The gate is shut for the night, traveller.',
                greeting: 'Well met, %{name}. The gate is shut for the night.' } },
  de: { gate: { notice: 'Das Tor ist für die Nacht geschlossen, Wanderer.',
                greeting: 'Sei gegrüßt, %{name}. Das Tor ist für die Nacht geschlossen.' } }
)

notice = RGame::Engine::Paragraph.new('gate.notice', width: 180)
notice.lines # => ["The gate is shut for the", "night, traveller."]

greeting = RGame::Engine::Paragraph.new(RGame::Engine::Text.new('gate.greeting', :name), width: 300)
greeting.with(name: 'Ada').lines # => ["Well met, Ada. The gate is shut for the", "night."]

RGame::Engine::I18n.locale = :de
notice.lines   # => ["Das Tor ist für die Nacht", "geschlossen, Wanderer."]
greeting.lines # => ["Sei gegrüßt, Ada. Das Tor ist für die", "Nacht geschlossen."]
```

`Paragraph#lines` returns a frozen Array of frozen Strings, broken with
[`text_lines`](#breaking-text-into-lines). It breaks the text again only when the
String its `Text` returns is a different object, or when the width changed. A
`Text` returns the same String until a variable or the language changes, so a
paragraph follows both with no call of its own. An unchanged read returns the
same Array and allocates nothing, so a node may read `lines` in `on_draw`:

```ruby
def on_draw(renderer, _view)
  @notice.lines.each_with_index do |line, i|
    renderer.text(line, 0, i * renderer.text_height)
  end
end
```

| | |
|---|---|
| `Paragraph.new(text, width:, typeface:)` | `text` is a key, as a String or Symbol, or an `Engine::Text`. Anything else raises `TypeError`, so prose a player reads cannot arrive as a String no translation reaches. `typeface:` defaults to `Util::Typeface.default`, the face of the renderer's default font. |
| `Paragraph#with(**values)` | gives the `Text` its variables, as `Text#with` does, and returns the paragraph |
| `Paragraph#width=` | changes the width; the next read breaks the text again. The same width breaks nothing. |
| `Paragraph#width`, `Paragraph#typeface` | what the lines are fitted to |
| `Paragraph#page_count`, `Paragraph#page(index)`, `Paragraph#lines_per_page` | pages, below |

A width of zero or less raises `ArgumentError`, and one that is not a number
raises `TypeError`, both at construction and in `width=`. A `Text` with
variables raises `ArgumentError` from `lines` until its first `with`.

**`lines_per_page:` groups the lines into pages**, for a dialogue box that
shows a few lines at a time. `Paragraph#page` counts from 0:

```ruby
require 'rgame'

RGame::Engine::I18n.load_hash(
  en: { gate: { story: 'The gate is shut for the night, traveller. The road ahead is dark, ' \
                       'but the dawn will come and the gate will open again. Rest here until then.' } }
)

story = RGame::Engine::Paragraph.new('gate.story', width: 300, lines_per_page: 2)
story.page_count # => 2
story.page(0)    # => ["The gate is shut for the night, traveller.", "The road ahead is dark, but the dawn will"]
story.page(1)    # => ["come and the gate will open again. Rest", "here until then."]
story.page(5)    # => ["come and the gate will open again. Rest", "here until then."] — the last page
```

An index past either end answers the nearest page. A language switch can shorten
the text while a game shows its last page, and the box then shows the new last
page rather than raising or going blank. `page_count` is at least 1, so an empty
text is one empty page. Without `lines_per_page:` the whole text is one page.
Each page is a frozen Array, and an unchanged read of `page` or `page_count`
allocates nothing. A `lines_per_page` below 1 raises `ArgumentError`.

A paragraph holds a typeface, never a renderer. It draws nothing, so it lays text
out in `update` or in a headless spec as well as in `on_draw`.

### The default font, and what it covers

**The engine ships Liberation Sans and uses it when you pass no path.** It never
looks a font up by name and never asks a system font database. A font is a file.

This is a deliberate trade. Asking the operating system for "Arial" gets whatever
that machine keeps under the name, or a substitute. A UI laid out on the
developer's machine can then overflow on a player's. A shipped font renders
identically everywhere, and costs about 400 KB in the gem.

| | |
|---|---|
| Covers | English, German, French, Italian, Spanish, Portuguese, Nordic, Polish — in full, including `ß`, `ẞ`, `« »`, curly quotes and `€`. Greek and Cyrillic too. |
| Does not cover | CJK, Arabic, Hebrew, Devanagari. Pass your own font file for those; no font of this size includes them. |

Text is UTF-8. A malformed byte draws one replacement character, and the rest of
the string still draws. A bad byte in a data file costs one visible box, not the
whole label.

## What it costs

**The engine rasterises each glyph the first time it is drawn**, then keeps it in
a texture atlas. Cost therefore grows with the **characters** a game uses, not
with the strings it draws. A score that changes every frame costs no more glyph
work after the ten digits. A whole Latin character set fits on one 512×512 page,
so a line of text is one draw call.

A font that is only measured, never drawn, uses no video memory.

Nothing needs freeing. The engine releases a font's atlas when the font is
collected, whether before or after its app. `Font.debug_live_pages` returns how
many atlas pages exist. It serves tests, not gameplay.

## What is not here

rgame text has no markup (`<b>`, colour tags), no bold or italic variants and no
multi-line drawing. `Typeface#text_lines` breaks a string into lines, and the
caller draws each one. It has no text input, no right-to-left text and no complex
shaping. A string is one line of left-to-right glyphs.
