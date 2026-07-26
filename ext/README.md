# ext/

The Ruby C extension **and** the engine it wraps. `rgame_ext.c` is a thin
`VALUE`-level wrapper around the public engine API in
[rgame/core.h](rgame/include/rgame/core.h).

```
ext/rgame/
  extconf.rb            # mkmf script -> generates the Makefile
  rgame_ext.c           # Ruby-facing glue: VALUE wrappers + trampolines
  core.c                # engine: SDL window/GL context + main loop
  frame_loop.c/.h       # pure fixed-timestep + FPS logic (unit-tested)
  include/rgame/core.h  # the public C API
  example.rb            # manual/visual smoke test (opens a real window)
```

## Why the engine lives here and not in `src/`

A gem's C extension is built by `gem install` running `extconf.rb` from
*inside its own directory* — it can't reach up to a sibling `src/`. Putting
the engine sources here means one copy serves both the gem and the standalone
binary the root `Makefile` builds. `src/` keeps only `main.c`, which stays out
of this directory precisely so mkmf doesn't compile its `main()` into
`rgame.so`.

## How it's wired

`extconf.rb` runs `mkmf` to generate a Makefile. mkmf's default is to compile
*every* `.c` in this directory into a single loadable `rgame.so` — which is
exactly `rgame_ext.c` + `core.c` + `frame_loop.c` — linked against SDL2 +
OpenGL the same way the root `Makefile` links the standalone binary. No
prebuilt `librgame_core.a` in the middle, so there's one build step.

The glue only ever calls the public API — the `rgame_app` struct stays opaque
here exactly as it does for `src/main.c`. The one interesting part is the
callback bridge: `rgame_app_run` owns the loop and calls C function pointers,
so `rgame_ext.c` installs small **trampolines** that call back into
Ruby procs (stashed as instance variables, which also keeps them alive for the
GC). See the comments in `rgame_ext.c` for the details and the current
exception-safety caveat.

## Build & run

```
cd ext/rgame
ruby extconf.rb      # writes ./Makefile
make                 # builds ./rgame.so
ruby example.rb      # opens a window; Esc or close to quit
```

Or from the project root: `make ext` (see the root `Makefile`).

## Ruby API

```ruby
require "rgame"

app = Rgame::App.new(800, 600, "title")
app.run(
  ->(dt) { ... },     # update: fixed-timestep tick, dt is the fixed step
  -> { ... },         # draw: render one frame
  -> { true },        # needs_redraw (optional): false skips the draw
)
app.ticks_ms          # => Integer, monotonic ms since startup
app.fps               # => Float, most recent FPS reading
```
