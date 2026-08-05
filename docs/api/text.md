# Text

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
```

That is the whole of it for most cases — the renderer has a font already, and
`text` uses it.

## Where text goes

`text(string, x, y, …)` puts the **top-left corner** of the line at `(x, y)`,
the same corner every other drawing method takes. Typography works from the
baseline; a caller placing a label does not have to.

```ruby
renderer.text(string, x, y, z: 10, color: nil, font: nil)
renderer.text_width(string, font: nil)   # => Float, pixels
renderer.text_height(font: nil)          # => Integer, the line height
```

**A string is one line.** Newlines are not special. Two lines are two calls,
stepped by `text_height`:

```ruby
lines.each_with_index do |line, i|
  @renderer.text(line, 10, 10 + (i * @renderer.text_height))
end
```

**`text_width` and `text` agree.** They walk the same code, so a label measured
and then centred lands where it was measured to:

```ruby
@renderer.text(label, (width - @renderer.text_width(label)) / 2, 20)
```

Unlike the drawing methods, `text_width` and `text_height` work **outside**
`draw` — measuring touches no GPU, and laying out a menu happens while updating.

## Fonts

```ruby
font = RGame::Core::Font.new(app, 18)                          # the shipped font
font = RGame::Core::Font.new(app, 18, path: 'assets/pixel.ttf')

font.height              # => 18
font.text_width('Hello') # => 38.7

renderer.text('Hello', 10, 10, font: font)
```

A `Font` is **one typeface at one pixel size**. Two sizes are two fonts. Like an
image, it belongs to the app whose GPU context holds its glyphs, and drawing it
through another app's renderer raises rather than painting blank boxes.

The renderer builds its own font at 18px on first use. Replace it and every
unqualified `text` call follows:

```ruby
@renderer.font = RGame::Core::Font.new(self, 24)
```

A file that cannot be read or is not a TrueType font raises
`RGame::Core::Font::LoadError`, naming the path.

### The default font, and what it covers

The engine ships **Liberation Sans** and uses it when no path is given. There is
no font-*name* lookup and no system font database — a font is a file.

That is a deliberate trade. Asking the operating system for "Arial" (which is
what Gosu does) means a different font on every machine, so a UI laid out on the
developer's box can overflow on a player's. Shipping one means text renders
identically everywhere, at the cost of ~400 KB in the gem.

| | |
|---|---|
| Covers | English, German, French, Italian, Spanish, Portuguese, Nordic, Polish — in full, including `ß`, `ẞ`, `« »`, curly quotes and `€`. Greek and Cyrillic too. |
| Does not cover | CJK, Arabic, Hebrew, Devanagari. Pass your own font file for those; no font of this size includes them. |

Text is UTF-8. A malformed byte draws one replacement character and the rest of
the string survives — a bad byte in a data file costs a visible box, not the
label.

## What it costs

Glyphs are rasterised the first time they are drawn and kept in a texture atlas
afterwards, so the cost is bounded by the **characters** a game uses, not by the
strings it draws. A score that changes every frame is free after the first ten
digits; a whole Latin character set fits on one 512×512 page, so a line of text
is one draw call.

A font that is only measured and never drawn allocates no video memory at all.

Nothing needs freeing — a font's atlas is released when the font is collected,
in either order relative to its app. `Font.debug_live_pages` reports how many
atlas pages exist and is there for tests, not for gameplay.

## What is not here

Markup (`<b>`, colour tags), bold and italic variants, multi-line layout, word
wrapping, text input, and right-to-left or complex shaping. A string is one line
of left-to-right glyphs.
