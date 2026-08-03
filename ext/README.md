# ext/

The project's two Ruby C extensions. They are split by **dependency**, and that
split is the rule for deciding where new code goes:

| | `rgame_core` | `rgame_util` |
|---|---|---|
| Ruby namespace | `RGame::Core` | `RGame::Util` |
| Required as | `rgame/core_ext` | `rgame/util_ext` |
| Entry point | `Init_core_ext` | `Init_util_ext` |
| Links | SDL2 + OpenGL + libm | nothing but Ruby |
| Holds | `App` (window, GL context, main loop) | `Tensor`, `Color` |

Anything that depends on SDL/OpenGL — or on something that does — belongs in
`rgame_core`. Everything else belongs in `rgame_util`. The point of the
split is that `RGame::Util` can be required, and its specs run, in a process
with no graphics libraries loaded and no display available:

```
ext/rgame_core/
  extconf.rb            # mkmf script -> Makefile; pkg_config("sdl2"), -lGL
  core_ext.c            # Ruby-facing glue: VALUE wrappers + trampolines
  app.c                 # engine: SDL window/GL context + main loop
  frame_loop.c/.h       # pure fixed-timestep + FPS logic (unit-tested)
  device_slots.c/.h     # pure controller-slot table, no SDL (unit-tested)
  input.c/.h            # pure button-id space + input snapshot (unit-tested)
  transform.c/.h        # pure 2D affine transform stack (unit-tested)
  clip.c/.h             # pure rects + intersecting clip stack (unit-tested)
  draw_queue.c/.h       # pure z-sort + batching of draw commands (unit-tested)
  canvas.c/.h           # pure transform+clip+queue composition (unit-tested)
  backend.h/.c          # the GL seam: function-pointer table + submit loop
  gamepad.c/.h          # thin SDL_GameController shim (open/close/poll)
  include/rgame/core.h  # the public C API
  example.rb            # manual/visual smoke test (opens a real window)

ext/rgame_util/
  extconf.rb            # mkmf script -> Makefile; no pkg_config, no -lGL
  util_ext.c            # entry point; calls each class's init
  tensor.c              # RGame::Util::Tensor — flat-array 3D grid
  color.c/.h            # pure RGBA packing, no ruby.h (unit-tested)
  color_ext.c           # RGame::Util::Color — the Ruby binding
```

## Why the engine lives here and not in `src/`

A gem's C extension is built by `gem install` running `extconf.rb` from
*inside its own directory* — it can't reach up to a sibling `src/`. Putting
the engine sources here means one copy serves both the gem and the standalone
binary the root `Makefile` builds. `src/` keeps only `main.c`, which stays out
of this directory precisely so mkmf doesn't compile its `main()` into the
extension.

## How it's wired

`extconf.rb` runs `mkmf` to generate a Makefile. mkmf's default is to compile
*every* `.c` in the extension's directory into a single loadable `.so` — for
`rgame_core` that's `core_ext.c` + `app.c` + `frame_loop.c` +
`device_slots.c` + `input.c` + `gamepad.c` + `transform.c` +
`clip.c` + `draw_queue.c` +
`canvas.c` + `backend.c`, linked
against SDL2 + OpenGL the same way the root `Makefile` links the standalone
binary. No prebuilt `librgame_core.a` in the middle, so there's one build step.

Not everything in a namespace comes from its extension: `RGame::Core::Input`,
`RGame::Core::Gamepad` and `RGame::Util::Controls` are pure Ruby in `lib/`,
layered on top. The tables
above list what each *extension* provides.

Both extensions name themselves under `rgame/` in `create_makefile`, which
namespaces them on the load path and leaves the bare name `rgame` to
`lib/rgame.rb`, the pure-Ruby entry point. Each `Init_` function calls
`rb_define_module("RGame")` — idempotent, so it returns the same module
whichever extension loads first.

The glue only ever calls the public API — the `rgame_app` struct stays opaque
here exactly as it does for `src/main.c`. The one interesting part is the
callback bridge: `rgame_app_run` owns the loop and calls C function pointers,
so `core_ext.c` installs small **trampolines** that call back into Ruby
procs (stashed as instance variables, which also keeps them alive for the GC).
See the comments in `core_ext.c` for the details and the current
exception-safety caveat.

## Build & run

From the project root:

```
make ext            # both extensions, each copied to lib/rgame/
make ext-core       # just this one
make ext-util       # just this one

ruby ext/rgame_core/example.rb   # opens a window; Esc or close to quit
```

`make ext-*` copies each built `.so` into `lib/rgame/`, which is where
`require "rgame/core_ext"` / `require "rgame/util_ext"` find it — mirroring
how rake-compiler installs a compiled extension into `lib/<gem>/`.

## Ruby API

```ruby
require "rgame"       # RGame::Util only — no SDL/GL loaded
require "rgame/core"  # adds RGame::Core, pulls in SDL2 + OpenGL

class MyGame < RGame::Core::App
  def initialize = super(width: 800, height: 600, caption: "title")

  def update(dt); end      # one fixed simulation tick
  def draw; end            # render one frame
  def needs_redraw?; end   # false skips the draw
  def button_down(id); end # discrete key press
end

app = MyGame.new
app.run                # loops until #close or the window is closed
app.ticks_ms           # => Integer, monotonic ms since startup
app.fps                # => Float, most recent FPS reading

# Symbolic actions, resolved through Input's binding table. The id vocabulary
# lives in RGame::Util::Controls — ids are values, so a game (or the engine
# layer, which may not name Core) can name one:
controls = RGame::Util::Controls
input = RGame::Core::Input.new(app)
input.down?(:fire)                                        # keyboard (the default)
input.down?(:fire, device: controls.gamepad(0))
input.axis(:move_x, device: controls.gamepad(0))          # => Float

# Rebinding is just a different table:
RGame::Core::Input.new(app, bindings: controls::DEFAULT_KEYBOARD.merge(fire: controls::KEY_RETURN))

# Which controllers are plugged in — a readout for menus, not the frame path:
pads = RGame::Core::Gamepad.new(app)
pads.count                                   # => 1
pads.each_connected { |slot, name| ... }     # "Player 2: <name>"

grid = RGame::Util::Tensor.new(width, height, depth, initial: nil)
grid[x, y, z] = value

colour = RGame::Util::Color.new(255, 128, 0)   # frozen, compares by value
RGame::Util::Color.coerce([255, 128, 0])       # nil / [r,g,b] / [r,g,b,a] / Color
```
