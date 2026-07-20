# ext/

The Ruby C extension: a thin `VALUE`-level wrapper around the public engine
API in [include/rgame/core.h](../include/rgame/core.h).

```
ext/rgame/
  extconf.rb    # mkmf script -> generates the Makefile
  rgame_ext.c   # Ruby-facing glue: VALUE wrappers + callback trampolines
  example.rb    # manual/visual smoke test (opens a real window)
```

## How it's wired

`extconf.rb` runs `mkmf` to generate a Makefile that compiles `rgame_ext.c`
**together with** the core sources (`src/core.c`, `src/frame_loop.c`) into a
single loadable `rgame.so`, linked against SDL2 + OpenGL the same way the root
`Makefile` links the standalone binary. It compiles the sources directly
rather than linking a prebuilt `librgame_core.a`, so there's one build step.

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
