# Value types

**Everything in `RGame::Util` is a value**: cheap, comparable, and owning no
window or GPU handle. Game logic can therefore hold these types as attributes.
They load with `require 'rgame'` and pull in no graphics library.

`SaveFile` touches the disk, and still belongs here. It holds a *path*, not an
open handle. It opens a file, reads or writes it, and closes it again. What
decides the namespace is ownership, not I/O.

```ruby
require 'rgame'
```

## `RGame::Util::Color`

`Color` is an RGBA colour. Instances are **frozen** and compare **by value**, so
you can share one freely and use it as a Hash key.

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

Every named colour except `TRANSPARENT` is opaque. They use the CSS/X11 values,
so `Color::ORANGE` matches the orange a colour picker gives you.

### Out-of-range components raise

```ruby
Color.new(300, 0, 0)   # ArgumentError: red must be in 0..255, got 300
```

Clamping would hide the bug that produced the 300.

### `Color.coerce`

**A colour is a `Color`, or it is `nil`.** `coerce` is the one place a `color:`
argument is normalised, and it has two cases:

```ruby
Color.coerce(nil)            # => Color::WHITE — an untinted draw
Color.coerce(Color::WHITE)   # => Color::WHITE — the same object, not copied
```

Anything else raises `TypeError`, including `[r, g, b]`. The components a
colour is built from are not a colour: a renderer coerces what it is handed, so
accepting them would build a `Color` on every draw call that passed them. Build
one and share it.

### Value semantics in practice

```ruby
a = Color.new(1, 2, 3)
b = Color.new(1, 2, 3)

a == b            # => true — two objects, one value
{ a => :hit }[b]  # => :hit
a.frozen?         # => true
```

A frozen colour is safe to hand to two sprites. Neither can change it under the
other.

## `RGame::Util::ColorRamp`

A `ColorRamp` builds the colours between two colours once, and answers one by
how far along it is. Every channel moves in a straight line, alpha included.

```ruby
require 'rgame'

Color = RGame::Util::Color
EMBER = RGame::Util::ColorRamp.new(Color.new(255, 240, 160), Color.new(255, 120, 0, 0), steps: 5)

EMBER.at(0)     # => Color.new(255, 240, 160) — the colour it was given
EMBER.at(0.5)   # => Color.new(255, 180, 80, 128)
EMBER.at(3)     # => Color.new(255, 120, 0, 0) — held at the end
EMBER.steps     # => 5
```

Building a `Color` allocates an object, so a colour built every tick is 60
objects a second. `at` returns one of the colours the ramp built, and
allocates nothing. So a particle whose colour changes with its age reads it
from a ramp in `_draw`.

| | |
|---|---|
| `ColorRamp.new(from, to, steps: 64)` | `steps` colours from `from` to `to`, both ends included. `steps` must be an Integer of at least 2, and `from` and `to` must be `Color`s. |
| `at(t)` | The colour nearest `t` of the way along. `at(0)` and `at(1)` return `from` and `to` themselves. A `t` below 0, or NaN, answers `from`, and above 1 answers `to`. |
| `from` `to` `steps` | What it was built with. |

To fade a whole node rather than change its hue, set its
[`opacity`](scene_graph.md#opacity) instead.

## `RGame::Util::Tensor`

`Tensor` is a fixed-size three-dimensional grid, addressed as `[x, y, z]`. One
flat C array backs it, so it stays compact at the sizes a tile map or a lighting
volume needs.

```ruby
grid = RGame::Util::Tensor.new(width, height, depth)
grid = RGame::Util::Tensor.new(16, 16, 4, initial: 0)   # fill value

grid[3, 4, 1] = :wall
grid[3, 4, 1]          # => :wall

grid.width             # also #height and #depth
```

Cells hold any Ruby object. `initial:` is optional and defaults to `nil`.

**x varies fastest, then y, then z**, so each z-slice is one contiguous run. For
good locality, iterate a layer at a time:

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

## `RGame::Util::SolidGrid`

`SolidGrid` records which cells of a tile grid are solid, one byte per cell, in C.
**It is the single store of a tile world's solidity.**
[`TileWorld`](components.md#tileworld) builds one from its map. The blockers that
stop a walker and the search that plans a route both read it, so they never
disagree about a wall.

```ruby
fence = RGame::Util::SolidGrid.build(8, 3) { |col, row| col == 3 && row < 2 }  # asks once per cell, row by row
fence.solid?(3, 1)     # => true
fence.solid?(-1, 0)    # => false — outside the grid is open
fence.width            # => 8 — and #height

field = RGame::Util::SolidGrid.new(8, 3)                                        # every cell open
field.set_solid(3, 1, true)
field.set_solid(3, 1, true)
field.revision         # => 1 — the second write changed nothing
```

- **`revision` counts changes.** It advances only when `set_solid` changes a
  cell. Anything derived from the cells can then tell whether it is stale, such
  as a [`RouteSearch`](#rgameutilroutesearch)'s region labels.
- **Coordinates are Integers**; anything else raises `TypeError`. An Integer
  outside the grid, however large, is outside. `solid?` answers `false` there.
  `set_solid` raises `IndexError`, because a wall written nowhere does not exist.
- **The size is fixed.** A negative size, or more than `2**31 - 1` cells, raises
  `ArgumentError`. A zero size gives an empty grid. A grid cannot be `dup`ed,
  because a search holds on to the grid it was built over.
- **`SolidGrid.debug_live_grids`** returns how many grids hold cells. rgame's own
  suite uses it to check that a grid frees its cells.

## `RGame::Util::RouteSearch`

`RouteSearch` finds connected regions and A* routes over a `SolidGrid`, in C.
Games use [`Engine::NavGrid`](toolbox.md#navgrid--routes-over-a-tile-grid), which
wraps a `RouteSearch` and states the route rules.

```ruby
grid = RGame::Util::SolidGrid.build(8, 3) { |col, row| col == 3 && row < 2 }
search = RGame::Util::RouteSearch.new(grid)

search.find(0, 0, 7, 0)   # => [[0, 0], [1, 1], [2, 2], [3, 2], [4, 2], [5, 1], [6, 0], [7, 0]]
search.region(0, 0)       # => 0 — nil for a solid cell or one outside the grid
search.grid               # => the grid — which the search keeps alive
```

- **It reads its grid and never writes it.** Any number of searches may share a
  grid. Each sees a change on its next query. It recomputes region labels then,
  but only if the grid's `revision` moved.
- **A repeated query allocates nothing but its result.** The search allocates
  its per-cell buffers once. Its heap grows to the largest query so far and
  stays there. One search is therefore not safe to use from two threads at once.
- Coordinates follow `SolidGrid`'s rules. A non-Integer raises `TypeError`, and
  for a cell outside the grid `find` and `region` return `nil`.
- **`RouteSearch.debug_live_searches`** returns how many searches hold buffers,
  for leak checks in rgame's own suite.

## `RGame::Util::TileSweep`

`TileSweep` tests an axis-aligned box against the solid tiles of a `SolidGrid`,
at a given tile size, in C. Games use
[`Engine::TileBlockers`](internals.md#tileblockers--the-tile-grid-as-a-blocker-source).
Every mover that declares `blocked_by: [:tiles]` resolves against it.
`TileSweep` does the arithmetic underneath, and both of its queries share one
implementation.

```ruby
grid = RGame::Util::SolidGrid.build(20, 15) { |col, _row| col == 5 }   # a wall at x 80..96
sweep = RGame::Util::TileSweep.new(grid, 16, 16)

sweep.resolve_x(58.0, 32.0, 12, 6, 14.0)    # => 68.0 — flush against the wall
sweep.resolve_y(58.0, 32.0, 12, 6, 4.0)     # => 36.0
sweep.travel?(10.0, 32.0, 12, 6, 50.0, 0)   # => true
sweep.travel?(10.0, 32.0, 12, 6, 90.0, 0)   # => false
sweep.grid                                  # => the grid — which the sweep keeps alive
```

- **A box is a top-left corner and a size, in pixels.** Results are Floats.
  Outside the grid is open.
- **`resolve_x` and `resolve_y`** move the box along one axis. If the box would
  enter a solid tile, they snap it flush against that tile. They assume a step
  smaller than a tile.
- **`travel?`** answers whether the box can move `(dx, dy)` without any resolve
  stopping it short. It sweeps overlapping half-tile windows a quarter tile
  apart, resolving each in both axis orders. The answer holds for a walker that
  steps less than a quarter tile at a time.
- **It reads its grid and never writes it**, so the next call sees a
  `set_solid`. No query allocates.
- **Refusals.** A tile size that is not positive and finite raises
  `ArgumentError`. So does a travel too long to sweep, beyond `2**31 - 1`
  windows. A coordinate that is not a number raises `TypeError`. A non-finite
  coordinate raises `FloatDomainError`, except in a resolve that does not move:
  that returns the box where it is.
- **`TileSweep.debug_live_sweeps`** returns how many sweeps are allocated, for
  leak checks in rgame's own suite.

## `RGame::Util::Typeface`

A typeface at one pixel size, for measuring text without a window. It holds its
font data in memory and no handle, so a node may keep one. Two typefaces compare
by identity. `text_width` measures a string and `text_lines` breaks one into lines.
See [Measuring without a window](text.md#measuring-without-a-window) and
[Breaking text into lines](text.md#breaking-text-into-lines).

## `RGame::Util::Z`

`Z` is the vocabulary of draw order. It names the bands, and turns a band plus a
position in the tree into the single number the renderer sorts by.

```ruby
RGame::Util::Z::BANDS     # => [:world, :hud, :overlay, :debug]
RGame::Util::Z::DEFAULT   # => :world
RGame::Util::Z::Z_MIN     # => -512 — the smallest `z:` a drawing call may pass
RGame::Util::Z::Z_MAX     # =>  511
RGame::Util::Z.band?(:hud) # => true
```

It lives in `Util` for the same reason as [`Controls`](input.md). The scene
graph decides a node's band and the renderer turns it into a z. Both must name
`Z`, and neither may name the other's layer.

**Games rarely touch `Z`.** A game sets a node's `z` and, occasionally, a
`band:`; see [the scene graph](scene_graph.md#draw-order). `Z` guarantees that `z`
numbers cannot leak between nodes, and bands cannot leak into each other:

| | |
|---|---|
| `SLOT` | 1024 — the room one node has for ordering its own drawing |
| `Z_MIN`…`Z_MAX` | what a `z:` on a drawing call may be; anything else raises |
| `STRIDE` | `2**40` — the gap between bands, which no `z:` can cross |

Every value is an integer below `2**42`. The draw queue sorts on a `double`, which
is exact below `2**53`. Two different slots therefore never round to the same
key. If they did, two sprites would swap places between frames, and nobody would
suspect a precision problem.

## `RGame::Util::Blend`

`Blend` names the blend modes a renderer knows, and checks an opacity. The
renderer's `blended` and `faded` blocks check their arguments with it, so a bad
mode or opacity raises the same error wherever it is given.

```ruby
require 'rgame'

RGame::Util::Blend::MODES           # => [:alpha, :add]
RGame::Util::Blend.mode?(:add)      # => true
RGame::Util::Blend.mode?(:multiply) # => false
RGame::Util::Blend.opacity(0.4)     # => 0.4 — a number from 0 to 1, returned as given
```

`Blend.opacity` raises `ArgumentError` for a number outside 0..1, NaN included,
and `TypeError` for anything that is not a number. Check an opacity a game
hands you when it is set, not when it is drawn, so the error points at the line
that set it. See
[Blending and fading](drawing.md#blending-and-fading).

## `RGame::Util::SaveFile`

`SaveFile` stores a game's saved state as one JSON file.

```ruby
save = RGame::Util::SaveFile.new('slot1.json', game: 'sheepdog')

save.write(dog: [120, 80], sheep: [[40, 40], [90, 30]])
save.read      # => { dog: [120, 80], sheep: [[40, 40], [90, 30]] }
save.exist?    # => true
save.delete
```

`SaveFile.new(name, game: 'rgame', dir: nil)` places `name` in
`SaveFile.directory(game)`, or in `dir:` when given. `path` returns the full path.
`delete` does nothing when the file is already gone.

Keys come back as Symbols, so a game writes and reads one shape. JSON comes from
the standard library, so `SaveFile` adds no runtime dependency.

### Reading never raises

**`read` returns its default for any file it cannot use.** The default is `{}`,
or whatever you pass. That covers a file that is missing, empty, truncated, not
JSON, or JSON that is not an object. A directory in the way and an unreadable
file get the same answer.

This is why to prefer `SaveFile` over `JSON.parse(File.read(path))`. A save file
is the one input a game did not produce this run. It survives crashes, full
disks, killed processes, text editors, and copies from other machines. A game
that raises on any of those cannot start again. The player's only remedy is to
find and delete a file nobody told them about. Losing a save is bad; refusing to
launch is worse.

**Writing still raises.** A failed read has a sensible answer: "there is no
save". A failed write has none. Discarding progress without a word gets noticed
hours later, when the progress is gone.

### Writing is atomic

**`write` never leaves half a save.** It writes a temporary file beside the
target and renames it over the top. `File.rename` within one directory is atomic
on every platform the engine supports. A save is either the old one or the new
one.

A game most wants to save on the way out, which is also when it is most likely
to be killed. A plain `File.write` truncates first and fills in after. A crash in
between leaves a zero-byte file where the afternoon's progress was.

### Where saves go

`SaveFile.directory(game)` follows each platform's convention instead of
dropping a dotfile in the home directory:

| | |
|---|---|
| Linux | `$XDG_DATA_HOME/<game>`, or `~/.local/share/<game>` |
| macOS | `~/Library/Application Support/<game>` |
| Windows | `%APPDATA%\<game>` |

Pass `dir:` to store the file somewhere else. Specs do this.

### What it does not do

**`SaveFile` does not serialize a scene tree, and a game should not either.** A
scene is a recipe; a save file is state. The scene rebuilds itself identically
every run, and the save supplies the few facts that differ. `examples/save_load`
shows the pattern, matching objects back up without naming any node.
`examples/save_load_ids` shows the case that needs names, using
[`Components::Identity`](components.md#identity).
