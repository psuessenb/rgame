# rgame

A small learning project for using SDL2 and OpenGL from C — structured so
the core engine can later be exposed as a Ruby C extension.

Right now it's pure C: it opens a window and draws a rotating triangle.
The Ruby bindings are a planned future step (see `ext/README.md`), not
implemented yet.

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

```
include/rgame/core.h   Public C API of the engine (opaque handle, no SDL/GL
                        types leaked) — this is also what the future Ruby
                        extension will bind against.
src/core.c              Engine implementation: SDL window + OpenGL context
                        setup, update/render loop internals.
src/main.c               Standalone executable entry point. Only talks to
                        include/rgame/core.h, never touches SDL/GL directly.
src/internal.h           Pure-logic helpers shared by core.c and the tests
                        (not part of the public API).
test/test_core.c        Check unit tests for the pure logic in src/internal.h.
ext/                    Reserved for the future Ruby C extension.
```

## Roadmap

1. **C core** (current) — SDL2 window, OpenGL rendering, basic app loop.
2. **Ruby C extension** — wrap `include/rgame/core.h` with `ext/rgame/extconf.rb`
   + glue code so the engine can be driven from Ruby.
