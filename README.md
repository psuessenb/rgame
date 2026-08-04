# rgame

A small learning project: a 2D game engine written in C on top of SDL2 and
OpenGL, exposed to Ruby as C extensions, headed for a single gem that ships
both halves.

Everything Ruby-visible lives under the `RGame` module, split in two by what it
depends on:

| | `RGame::Core` | `RGame::Util` |
|---|---|---|
| For | anything depending on SDL/OpenGL (or on something that does) | everything else |
| C source | `ext/rgame_core/` | `ext/rgame_util/` |
| Extension | `rgame/core_ext` | `rgame/util_ext` |
| Links | SDL2 + OpenGL | nothing but Ruby |
| Holds today | `App` — window, GL context, fixed-timestep main loop; `Input`, `Gamepad`, `Image`, `Renderer`, `Recording` | `Tensor`, `Controls`, `Color` |

That split is load-bearing, not cosmetic: `require "rgame"` gives you
`RGame::Util` with **no graphics libraries loaded into the process at all**, so
pure-logic code and its specs run with no display and no SDL present.
`RGame::Core` is an explicit opt-in:

```ruby
require "rgame"       # RGame::Util only
require "rgame/core"  # adds RGame::Core, pulls in SDL2 + OpenGL
```

The engine opens a window, runs a fixed-timestep loop, reads keyboard and
controllers, loads PNGs onto the GPU and draws shapes and sprites through a
z-sorted batching renderer. Text and audio are still ahead. Its C sources build
two ways from one copy: a standalone binary (`build/rgame`, via the root
`Makefile`) and the `core_ext` extension (via `extconf.rb`).

There's no `.gemspec` yet — everything is used in place from a checkout.

**[docs/api/](docs/api/README.md) is the reference documentation** for using the
engine from Ruby: the frame loop, the hooks, input, and the value types. Start
there if you want to write a game rather than work on the engine.

## Requirements

### C engine

- A C compiler — `gcc` or `clang`
- `make`
- `pkg-config`
- SDL2 development headers (`sdl2` pkg-config package)
- OpenGL development headers/libs (provided by Mesa on Linux)
- [Check](https://libcheck.github.io/check/) (`check` pkg-config package) — C unit test framework, only needed for `make test`

PNG decoding needs no system library: `stb_image.h` is vendored in
`ext/rgame_core/vendor/` (public domain / MIT — see the README there).

### Ruby side

- **Ruby 4.0.5**, pinned in `.ruby-version`. Installed here with
  [mise](https://mise.jdx.dev) (`mise install` in the project root picks up
  `.ruby-version`); any version manager that reads `.ruby-version` works just
  as well.
- **Ruby development headers.** Version-manager builds (mise, rbenv, rvm,
  asdf) include them. On a distro-packaged Ruby, install `ruby-dev`
  (Debian/Ubuntu). These are what `extconf.rb` compiles against.
- **Bundler**, then `bundle install` for the dev/test gems (RSpec, RuboCop).

One wrinkle in `bundle install`: the `Gemfile` pins **gosu**, the library this
engine is being written to replace (see
[docs/c_engine_feature_specs.md](docs/c_engine_feature_specs.md)). No code in
`lib/`, `spec/`, or `ext/` requires it — it's kept as the reference point — but
it's a native extension, so installing it needs a handful of extra system
libraries beyond the ones the C engine itself uses. Drop it from the `Gemfile`
if you don't want to build it.

### Debian / Ubuntu

```
# C engine + tests
sudo apt install build-essential pkg-config libsdl2-dev libgl1-mesa-dev check

# only if you keep gosu in the Gemfile
sudo apt install libvorbis-dev libsndfile1-dev libmpg123-dev libfontconfig1-dev
```

### macOS (Homebrew)

```
brew install sdl2 pkg-config check

# only if you keep gosu in the Gemfile
brew install libvorbis libsndfile mpg123 fontconfig
```

OpenGL headers/libs ship with Xcode Command Line Tools (`xcode-select --install`).

## Build & run

```
make              # builds build/rgame (standalone C binary)
make run          # build and run it
make test         # build and run the Check unit tests (C, pure logic)
make ext          # build both Ruby extensions
make ext-core     # build only ext/rgame_core -> lib/rgame/core_ext.so
make ext-util     # build only ext/rgame_util -> lib/rgame/util_ext.so
make clean        # remove build artifacts, including both extensions'
```

`make run` opens a window with one of each drawing primitive in it — a rotating
square, a clipped rectangle, a circle, a thick line, and a baked strip replayed
every frame. `Esc` or closing the window quits. `ruby ext/rgame_core/example.rb`
is the same scene driven from Ruby.

The Ruby specs:

```
bundle install
make ext             # both extensions; the suites need the compiled .so files
rake spec            # headless specs: RGame::Util + RGame::Engine, no SDL loaded
rake spec:core       # RGame::Core specs; opens real windows, boots its own Xvfb
rake                 # everything: make test, rake spec, rake spec:core
bundle exec rubocop  # lint; configured in .rubocop.yml, which also loads the
                     # project's own cops from rubocop/cop/game/.
```

The two Ruby suites are two directories and two processes on purpose. `spec/`
must never load SDL — the engine layer's whole value is that it can be
specified with no window — and RSpec loads one root into one process, so a
single `require "rgame/core"` anywhere would define `RGame::Core` for every
other example in the run. Separate runners cannot be forgotten the way an
exclude rule can. `rake spec` needs `make ext-util`; `rake spec:core` needs
`make ext-core`.

Each `make ext-*` target compiles its extension and copies the resulting `.so`
into `lib/rgame/`, which is where `require "rgame/util_ext"` and `require
"rgame/core_ext"` look for it. That mirrors how rake-compiler installs a
compiled extension into `lib/<gem>/`. Without that step the specs can't even
load, since `RGame::Util::Tensor` now lives in C.

`rake spec` needs only `ext-util` — it never touches `RGame::Core`, which is
what keeps it runnable with no display and no SDL. To drive the *engine* from
Ruby by hand (opens a real window):

```
make ext-core
ruby ext/rgame_core/example.rb
```

## Project structure

The engine C lives under `ext/rgame_core/` — a Ruby C extension directory —
rather than a top-level `src/`. That's deliberate: `gem install` unpacks the gem
and runs each `extconf.rb`, which can only build sources inside its own
directory, so keeping the C there means one copy of the code serves both the
standalone binary and the gem.

```
ext/rgame_core/              RGame::Core — the SDL/GL half.
  include/rgame/core.h       Public C API (opaque handle, no SDL/GL types
                             leaked) — what both src/main.c and the extension
                             bind against.
  app.c                      Engine implementation: SDL window + OpenGL context
                             setup; owns the main loop and calls back to the
                             caller's update/draw callbacks.
  frame_loop.h/.c            Pure fixed-timestep + FPS logic, no SDL/GL — unit-
                             tested without a window (see CLAUDE.md's layering).
  device_slots.h/.c          Pure player-slot table for controllers: keeps a
                             player on the same slot across a disconnect. No SDL.
  input.h/.c                 Pure input snapshot + the flat button-id space
                             (keyboard and gamepad ranges). No SDL.
  transform.h/.c             Pure 2D affine transform stack — rotate, scale,
                             translate, composed. No SDL.
  clip.h/.c                  Pure rects and the intersecting clip stack, in
                             screen space. No SDL.
  draw_queue.h/.c            Pure z-sort and batching: collects draw commands,
                             orders them by z, merges what can share a GL call.
  canvas.h/.c                Pure composition of transform + clip + queue; the
                             seam the drawing API is written against.
  backend.h/.c               The layer-2 seam: a function-pointer table a real
                             GL backend or a recording fake plugs into, plus
                             the loop that drives it from a prepared frame.
  gamepad.h/.c               Thin SDL_GameController shim: opens/closes pads on
                             hot-plug and copies their state into the snapshot.
  texture.h/.c               Pure: refcounted texture sheets, the sub-rects
                             sprites cut out of them, and pixels -> UVs.
  primitives.h/.c            Pure: rects, thick lines, circles and sprites, in
                             terms of the canvas's triangles and quads.
  recording.h/.c             Pure: a baked block of drawing, kept between
                             frames and replayed as one call per texture.
  gl_backend.h/.c            The real GL calls — the only file that issues
                             them on the drawing path.
  image.c                    Decode a PNG and upload it — the thin GL shim
                             over texture.h. Views share one upload.
  stb_image_impl.c           Instantiates the vendored decoder; the one file
                             built without -Wall -Wextra.
  vendor/                    Third-party sources (stb_image.h) + their licences.
  core_ext.c                 Ruby glue: VALUE wrappers + callback trampolines,
                             and the extension's entry point.
  core_ext.h                 One init function per Ruby-visible class here.
  image_ext.c                RGame::Core::Image — the Ruby binding.
  renderer_ext.c             RGame::Core::Renderer — the drawing primitives.
  recording_ext.c            RGame::Core::Recording — baked, replayable draws.
  extconf.rb                 mkmf script; pkg_config("sdl2"), -lGL.
  example.rb                 Manual smoke test driven from Ruby.

ext/rgame_util/              RGame::Util — the graphics-free half, so pure-data
                             helpers can be required without pulling in SDL/GL.
  util_ext.c                 Entry point; hands RGame::Util to each class init.
  tensor.c                   RGame::Util::Tensor — flat-array 3D grid.
  color.c/.h                 Pure RGBA packing, no Ruby — Check-tested.
  color_ext.c                RGame::Util::Color — the Ruby binding over it.
  extconf.rb                 mkmf script; no pkg_config, no -lGL.

lib/rgame.rb                 `require "rgame"` — loads RGame::Util only.
lib/rgame/util.rb            Namespace loader.
lib/rgame/util/tensor.rb     Requires the compiled rgame/util_ext.
lib/rgame/util/controls.rb   Input id vocabulary (keys, pad buttons, axes,
                             device slots) + default bindings. Pure Ruby
                             values, so a game may name them without Core.
lib/rgame/util/color.rb      Requires the compiled rgame/util_ext for Color.
lib/rgame/core.rb            `require "rgame/core"` — opt-in, loads SDL/GL.
lib/rgame/core/app.rb        Requires the compiled rgame/core_ext.
lib/rgame/core/input.rb      Symbolic action -> button, over the C queries.
lib/rgame/core/gamepad.rb    Which controllers are plugged in, and their names.
lib/rgame/core/image.rb      Sprite-sheet slicing over the C-backed Image.
lib/rgame/core/renderer.rb   Keyword args, colours and transform blocks over
                             the C-backed Renderer.
lib/rgame/core/recording.rb  #draw over the C-backed Recording.
lib/rgame/*.so               Build artifacts, copied here by `make ext`.

src/main.c                   Standalone executable entry point — the C
                             equivalent of example.rb. Only talks to
                             rgame/core.h, never touches SDL/GL directly. Kept
                             outside ext/ so mkmf doesn't compile its main()
                             into the extension.

test/                        Check unit tests for the pure C logic (`make test`).
  test_main.c                Runs every suite; one binary, build/test_rgame.
  suites.h                   Each test_<x>.c exposes a Suite, declared here.
  support/                   Test-only helpers, e.g. the recording draw backend
                             that stands in for OpenGL.
spec/                        Headless RSpec specs: RGame::Util and
                             RGame::Engine (`rake spec`). Never loads SDL.
spec_core/                   RSpec specs for RGame::Core (`rake spec:core`).
                             Opens real windows; boots its own Xvfb.
docs/                        The feature spec the engine is being built out to.
  api/                       Reference documentation for using it from Ruby.
```

Three test suites: `make test` covers the C (Check), `rake spec` the headless
Ruby half, `rake spec:core` the parts that open a window. None needs a display
of its own — `spec:core` boots Xvfb itself. `rake` runs all three.

## Roadmap

1. **C core** (in progress) — SDL2 window, OpenGL rendering, basic app loop.
   Drawing primitives are the current gap.
2. **Ruby C extensions** (done in first form) — `RGame::Core::App` wraps
   `include/rgame/core.h`, so the engine can be driven from Ruby
   (`ext/rgame_core/example.rb`); `RGame::Util::Tensor` covers the
   graphics-free half.
3. **Pure-Ruby half** (started) — `lib/` holds the namespace loaders; so far
   the classes underneath them are all C-backed.
4. **Gem** — not started. Needs a top-level `.gemspec` with
   `spec.extensions = ["ext/rgame_core/extconf.rb",
   "ext/rgame_util/extconf.rb"]`, installing both compiled `.so`s into
   `lib/rgame/` the way `make ext` already does. One gem, both halves.

## Ruby API

See [ext/README.md](ext/README.md) for detail.

```ruby
require "rgame/core"

class MyGame < RGame::Core::App
  def initialize = super(width: 800, height: 600, caption: "title")

  def update(dt); end      # one fixed simulation tick
  def draw; end            # render one frame
  def needs_redraw?; end   # false skips the draw
  def button_down(id); end # discrete key press
end

MyGame.new.run
```

The util half, with no graphics libraries loaded:

```ruby
require "rgame"

grid = RGame::Util::Tensor.new(width, height, depth, initial: nil)
grid[x, y, z] = value
grid[x, y, z]
grid.width # => Integer, also #height / #depth
```
