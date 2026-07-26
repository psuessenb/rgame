# rgame

A small learning project for using SDL2 and OpenGL from C — structured so
the core engine can later be exposed as a Ruby C extension.

Right now it's pure C: it opens a window and runs a fixed-timestep main
loop. There are no draw primitives yet, so the window just shows a blank
clear color. The Ruby bindings are a planned future step (see
`ext/README.md`), not implemented yet.

## Requirements

To build the current (C-only) version you need:

- A C compiler — `gcc` or `clang`
- `make`
- `pkg-config`
- SDL2 development headers (`sdl2` pkg-config package)
- OpenGL development headers/libs (provided by Mesa on Linux)
- [Check](https://libcheck.github.io/check/) (`check` pkg-config package) — C unit test framework, only needed for `make test`

### Debian / Ubuntu

```
sudo apt install build-essential pkg-config libsdl2-dev libgl1-mesa-dev check
```

### Fedora

```
sudo dnf install gcc make pkgconf-pkg-config SDL2-devel mesa-libGL-devel check-devel
```

### macOS (Homebrew)

```
brew install sdl2 pkg-config check
```

OpenGL headers/libs ship with Xcode Command Line Tools (`xcode-select --install`).

### Future requirement (Ruby extension phase, not needed yet)

- Ruby with development headers (`ruby-dev` on Debian/Ubuntu, or a Ruby
  version manager build that includes headers) — needed once `ext/` gets
  its `extconf.rb`.

## Build & run

```
make        # builds build/rgame
make run    # build and run
make test   # build and run the Check unit tests
make clean  # remove build artifacts
```

Controls: `Esc` or closing the window quits.

## Project structure

The engine itself lives under `ext/rgame/` — the directory a Ruby C extension
is built from. That's a deliberate choice: `gem install` unpacks the gem and
runs `ext/rgame/extconf.rb`, which can only build sources inside its own
directory, so keeping the C there means one copy of the code serves both the
standalone binary and the gem.

```
ext/rgame/
  include/rgame/core.h  Public C API of the engine (opaque handle, no SDL/GL
                        types leaked) — what both src/main.c and the Ruby
                        extension bind against.
  core.c                Engine implementation: SDL window + OpenGL context
                        setup; owns the main loop and calls back to the
                        caller's update/draw callbacks.
  frame_loop.h/.c       Pure fixed-timestep + FPS logic, no SDL/GL — unit-
                        tested without a window (see CLAUDE.md's layering).
  rgame_ext.c           Ruby glue: VALUE wrappers + callback trampolines.
  extconf.rb            mkmf script; generates the extension's Makefile.
  example.rb            Manual smoke test driven from Ruby.
src/main.c              Standalone executable entry point — the C equivalent
                        of example.rb. Only talks to rgame/core.h, never
                        touches SDL/GL directly. Kept outside ext/rgame/ so
                        mkmf doesn't compile its main() into rgame.so.
test/test_frame_loop.c  Check unit tests for the pure logic in frame_loop.c.
```

## Roadmap

1. **C core** (current) — SDL2 window, OpenGL rendering, basic app loop.
2. **Ruby C extension** — wrap `ext/rgame/include/rgame/core.h` with
   `ext/rgame/extconf.rb` + glue code so the engine can be driven from Ruby.
3. **Gem** — add a `.gemspec` (`spec.extensions = ["ext/rgame/extconf.rb"]`)
   and a `lib/` holding the pure-Ruby half of the API. One gem, both halves.
