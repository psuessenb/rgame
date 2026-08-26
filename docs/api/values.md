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

### The named palette

```ruby
Color::WHITE   Color::BLACK   Color::TRANSPARENT
Color::RED     Color::GREEN   Color::BLUE
Color::YELLOW  Color::CYAN    Color::MAGENTA
Color::ORANGE  Color::PURPLE  Color::BROWN     Color::PINK
Color::GRAY    Color::LIGHT_GRAY               Color::DARK_GRAY
```

All are opaque except `TRANSPARENT`, and all follow the CSS/X11 values, so
`Color::ORANGE` is the orange a colour picker would give you.

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

## `RGame::Util::Z`

The vocabulary of draw order: which band a thing is drawn in, and the arithmetic
that turns a band plus a position in the tree into the single number the renderer
sorts a frame by.

```ruby
RGame::Util::Z::BANDS     # => [:world, :hud, :overlay, :debug]
RGame::Util::Z::DEFAULT   # => :world
RGame::Util::Z::Z_MIN     # => -512, the smallest `z:` a drawing call may pass
RGame::Util::Z::Z_MAX     # =>  511
```

It lives here for the same reason [`Controls`](input.md) does: both the scene
graph (which decides a node's band) and the renderer (which turns one into a z)
have to name it, and neither may name the other's layer.

Games rarely touch it. What a game writes is a node's `z` and, occasionally, a
`band:` — see [the scene graph](scene_graph.md#draw-order). What it buys is that
`z` numbers cannot leak between nodes and bands cannot leak into each other:

| | |
|---|---|
| `SLOT` | 1024 — the room one node has for ordering its own drawing |
| `Z_MIN`…`Z_MAX` | what a `z:` on a drawing call may be; anything else raises |
| `STRIDE` | `2**40` — the gap between bands, which no `z:` can cross |

Every value is an integer below `2**42`, and the `double` the draw queue sorts on
is exact below `2**53`, so two different slots can never compare equal by
rounding — which would show up as two sprites swapping places between frames, and
would be very hard to recognise as a precision problem.
