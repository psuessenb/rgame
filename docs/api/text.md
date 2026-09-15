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

**A string is one line.** A newline has no special meaning. Draw two lines with
two calls, stepped by `text_height`:

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

rgame text has no markup (`<b>`, colour tags), no bold or italic variants, no
multi-line layout and no word wrapping. It has no text input, no right-to-left
text and no complex shaping. A string is one line of left-to-right glyphs.
