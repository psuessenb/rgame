# Value types

Everything in `RGame::Util` is a *value*: cheap, comparable, and owning no
window or GPU handle. That is what makes them safe for game logic to hold as
attributes — they load with `require 'rgame'` and pull in no graphics libraries
at all.

`SaveFile` is the one that touches the disk, and it belongs here for the same
reason: it holds a *path*, not an open handle. It opens a file, reads or writes
it, and closes it again. The line is ownership, not I/O.

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

## `RGame::Util::SolidGrid`

Which cells of a tile grid are solid: a byte per cell, in C. It is the one store a tile
world's solidity lives in — [`TileWorld`](components.md#tileworld) builds one from its map,
and both the blockers that stop a walker and the search that plans a route read it, so the
two cannot disagree about a wall.

```ruby
fence = RGame::Util::SolidGrid.build(8, 3) { |col, row| col == 3 && row < 2 }  # asks once per cell, row by row
fence.solid?(3, 1)     # => true
fence.solid?(-1, 0)    # => false — outside the grid is open
fence.width            # => 8, and #height

field = RGame::Util::SolidGrid.new(8, 3)                                        # every cell open
field.set_solid(3, 1, true)
field.set_solid(3, 1, true)
field.revision         # => 1 — the second write changed nothing
```

- **`revision` counts changes.** It moves on a `set_solid` that changes a cell and on no
  other, so anything derived from the cells — a [`RouteSearch`](#rgameutilroutesearch)'s
  region labels — can tell whether it is stale.
- **Coordinates are Integers**; anything else is a `TypeError`. An Integer outside the grid,
  however large, is outside: `solid?` answers `false`, and `set_solid` raises `IndexError`,
  since a wall written nowhere is a wall that is not there.
- **The size is fixed.** A negative size, or one with more than `2**31 - 1` cells, is an
  `ArgumentError`; a zero size is an empty grid. A grid cannot be `dup`ed — a search keeps
  hold of the grid it was built over.

## `RGame::Util::RouteSearch`

Connected regions and A* routes over a `SolidGrid`, in C. The game-facing form is
[`Engine::NavGrid`](toolbox.md#navgrid--routes-over-a-tile-grid), which wraps one of these
and states the route rules; this is the value underneath.

```ruby
grid = RGame::Util::SolidGrid.build(8, 3) { |col, row| col == 3 && row < 2 }
search = RGame::Util::RouteSearch.new(grid)

search.find(0, 0, 7, 0)   # => [[0, 0], [1, 1], [2, 2], [3, 2], [4, 2], [5, 1], [6, 0], [7, 0]]
search.region(0, 0)       # => 0; nil for a solid cell or one outside the grid
search.grid               # => the grid, which the search keeps alive
```

- **It reads its grid and never writes it.** Any number of searches may read one grid, and
  each sees a change to it on its next query; region labels are recomputed then, only if the
  grid's `revision` has moved.
- **A repeated query allocates nothing but its result.** Its per-cell buffers are allocated
  once, and its heap grows to the largest query it has run and stays there. One search is
  therefore not safe to use from two threads at once.
- Coordinates follow `SolidGrid`'s rules: an Integer or a `TypeError`, and an Integer outside
  the grid is outside — `find` and `region` answer `nil`.

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

## `RGame::Util::SaveFile`

A game's saved state, as one JSON file.

```ruby
save = RGame::Util::SaveFile.new('slot1.json', game: 'sheepdog')

save.write(dog: [120, 80], sheep: [[40, 40], [90, 30]])
save.read      # => { dog: [120, 80], sheep: [[40, 40], [90, 30]] }
save.exist?    # => true
save.delete
```

Keys come back as Symbols, so a game writes and reads one shape. JSON comes from
the standard library, so this adds no runtime dependency.

### Reading never raises

`read` answers with its default — `{}`, or whatever you pass — for a file that
is missing, empty, truncated, not JSON, or JSON that is not an object. A
directory in the way and an unreadable file are the same answer.

That is the reason to use this rather than `JSON.parse(File.read(path))`. A save
file is the one input a game has that it did not produce this run: it survives
crashes, full disks, a killed process, an editor, and a copy from someone else's
machine. A game that raises on any of those cannot be started again, and the
player's only remedy is to find and delete a file nobody told them about. Losing
a save is bad; refusing to launch is worse.

**Writing still raises.** A failed read has a sensible answer — "there is no
save" — and a failed write does not: quietly discarding the player's progress is
noticed hours later, when it is gone.

### Writing is atomic

`write` writes a temporary file beside the target and renames it over the top.
`File.rename` within a directory is atomic on every platform the engine
supports, so a save is either the old one or the new one, never half of each.

The moment a game most wants to save is on the way out, which is also when it is
most likely to be killed — and a plain `File.write` truncates first and fills in
after, so a crash in between leaves a zero-byte file where the afternoon was.

### Where saves go

`SaveFile.directory(game)` follows each platform's own convention rather than
dropping a dotfile in the home directory:

| | |
|---|---|
| Linux | `$XDG_DATA_HOME/<game>`, or `~/.local/share/<game>` |
| macOS | `~/Library/Application Support/<game>` |
| Windows | `%APPDATA%\<game>` |

Pass `dir:` to put the file somewhere else entirely, which is what a spec does.

### What it does not do

It does not serialize a scene tree, and neither should a game. A scene is a
recipe and a save file is state: the scene rebuilds itself identically every
run, and the save supplies the few facts that differ. `examples/save_load` shows
the shape, matching objects back up without any node needing a name;
`examples/save_load_ids` shows the case that does need one, using
[`Components::Identity`](components.md#identity).
