# Value types

Everything in `RGame::Util` is a *value*: cheap, comparable, owning no window,
GPU handle or file. That is what makes them safe for game logic to hold as
attributes — they load with `require 'rgame'` and pull in no graphics libraries
at all.

```ruby
require 'rgame'
```

## `RGame::Util::Color`

An RGBA colour. Instances are **frozen** and compare **by value**, so one can be
shared freely and used as a Hash key.

```ruby
Color = RGame::Util::Color

Color.new(255, 128, 0)          # r, g, b — alpha defaults to 255
Color.new(255, 128, 0, 200)     # explicit alpha
Color.rgba(255, 128, 0, 200)    # the same thing, named
Color.from_packed(0xFF8000C8)   # 0xRRGGBBAA
```

| | |
|---|---|
| `r` `g` `b` `a` | Components, `0..255`. |
| `packed` | The `0xRRGGBBAA` form as an Integer. |
| `==`, `eql?`, `hash` | Value semantics. |
| `inspect` | `#<RGame::Util::Color r=1 g=2 b=3 a=4>` |

Named colours: `Color::WHITE`, `Color::BLACK`, `Color::TRANSPARENT`.

### Out-of-range components raise

```ruby
Color.new(300, 0, 0)   # ArgumentError: red must be in 0..255, got 300
```

Silently clamping would hide the bug that produced the 300.

### `Color.coerce`

Drawing calls accept a colour in several forms, and `coerce` is the single
place that conversion happens:

```ruby
Color.coerce(nil)               # => Color::WHITE — an untinted draw
Color.coerce([255, 128, 0])     # => opaque
Color.coerce([255, 128, 0, 64]) # => with alpha
Color.coerce(Color::WHITE)      # => returned unchanged, not copied
```

Anything else raises `TypeError`; a wrongly-sized array raises `ArgumentError`.

### Value semantics in practice

```ruby
a = Color.new(1, 2, 3)
b = Color.new(1, 2, 3)

a == b            # => true — two objects, one value
{ a => :hit }[b]  # => :hit
a.frozen?         # => true
```

Because a colour is frozen, handing the same one to two sprites is safe: nobody
can tint it out from under the other.

## `RGame::Util::Tensor`

A fixed-size three-dimensional grid, addressed as `[x, y, z]`. Backed by a
single flat array in C, so it stays compact for the sizes a tile map or a
lighting volume needs.

```ruby
grid = RGame::Util::Tensor.new(width, height, depth)
grid = RGame::Util::Tensor.new(16, 16, 4, initial: 0)   # fill value

grid[3, 4, 1] = :wall
grid[3, 4, 1]          # => :wall

grid.width             # also #height and #depth
```

Cells hold any Ruby object. `initial:` is optional and defaults to `nil`.

The layout is x-fastest, then y, then z, so one z-slice is a contiguous run —
worth knowing if you iterate a layer at a time and care about locality.

```ruby
grid.depth.times do |z|
  grid.height.times do |y|
    grid.width.times do |x|
      cell = grid[x, y, z]
      # ...
    end
  end
end
```
