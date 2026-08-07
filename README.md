# RGame

A small 2D game engine written in Ruby and C, on top of SDL2, OpenGL and miniaudio.

## Why does this exist and should you use it?

RGame is the product of both my lazyness and me looking for something that did not exist. Coming from Ruby on Rails, I wanted to write games while not learning a new language. There are Ruby game engines, but none offered me the option to write modern, standard Ruby and proper specs for the game logic. The closest I found was Gosu, and this project initially started as a "high level engine on top of Gosu", but eventually the limitations of Gosu drove me into rewriting this layer myself.

RGame puts a lot of emphazis on testing and being testable: It separates the layers that talk to SDL2/OpenGL from the high level engine concepts, so the whole game logic is testable headless.

It also tries to marry the beauty of Ruby with the hard performance requirements of games: Hot paths have no per-frame allocation, because garbadge collection is what really slows down Ruby interpreation, and math-heavy use-cases are backed by C code instead of Ruby classes.

Should you use it, though? If you're looking for something mature, free, and more battle-tested take a look at Godot instead. If you're looking for something mature and battle-tested in Ruby land, take a look at dragonruby instead (it's not free, but it's probably worth the price).

If you're just starting with game development and planning on making the next big indie hit, might as well pick this one as the engine for the game you never finish!

In all seriousness, though: This is a hobby project of mine, and while it might develop into something actually useful, at the time of writing it's a playground. If you search for something I searched and found nothing, you can try this. I would be really happy if someone else actually uses it, but at this point I can't really recommend it for anything else than small projects and/or learning the ropes of game development.

## Hello world

```
require 'rgame/game'

class Scene < RGame::Engine::Node2D
  def on_draw(renderer)
    renderer.text('Hello world!', 250, 200)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Hello world!'
)

game.start
```

You can learn more about how it works in the [documentation](docs/api/README.md).

# Where does stuff live

Everything Ruby-visible lives under the `RGame` module, split in two by what it
depends on:

| | `RGame::Core` | `RGame::Util` |
|---|---|---|
| For | anything depending on SDL/OpenGL (or on something that does) | everything else |
| C source | `ext/rgame_core/` | `ext/rgame_util/` |
| Extension | `rgame/core_ext` | `rgame/util_ext` |
| Links | SDL2 + OpenGL + pthread | nothing but Ruby |
| Holds today | `App` — window, GL context, fixed-timestep main loop; `Input`, `Gamepad`, `Image`, `Renderer`, `Recording`, `Font`, `Audio`, `Sample`, `Song` | `Tensor`, `Controls`, `Color` |

That split is load-bearing, not cosmetic: `require "rgame"` gives you the value
types *and* the scene graph with **no graphics libraries loaded into the process
at all**, so game logic and its specs run with no display and no SDL present.
`RGame::Core` is an explicit opt-in:

```ruby
require "rgame"       # RGame::Util + RGame::Engine, no graphics
require "rgame/core"  # adds RGame::Core, pulls in SDL2 + OpenGL
require "rgame/game"  # all of it, wired — what a game writes
```

The engine opens a window, runs a fixed-timestep loop, reads keyboard and
controllers, loads PNGs onto the GPU, draws shapes, sprites and text through
a z-sorted batching renderer, and plays Ogg Vorbis and WAV. `RGame::Game` puts
those together with a scene graph, and the two games under `examples/` run on
it. Its C sources build two ways from one copy: a standalone binary (`build/rgame`, via the root
`Makefile`) and the `core_ext` extension (via `extconf.rb`).

Both halves ship as one gem — `rgame.gemspec` builds both extensions — though
nothing is published yet, so it is installed from a checkout or a built `.gem`.

**[docs/api/](docs/api/README.md) is the reference documentation** for using the
engine from Ruby: the entry point, the frame loop, input, drawing, text, audio,
assets and the value types. Start there if you want to write a game rather than
work on the engine.

## Requirements

### C engine

- A C compiler — `gcc` or `clang`
- `make`
- `pkg-config`
- SDL2 development headers (`sdl2` pkg-config package)
- OpenGL development headers/libs (provided by Mesa on Linux)
- [Check](https://libcheck.github.io/check/) (`check` pkg-config package) — C unit test framework, only needed for `make test`

PNG decoding, text and audio need no system libraries: `stb_image.h`,
`stb_truetype.h`, `stb_vorbis.c` and `miniaudio.h` are vendored in
`ext/rgame_core/vendor/` (public domain / MIT), and the default font ships in
`lib/rgame/fonts/` (SIL OFL 1.1). miniaudio finds ALSA or PulseAudio at runtime,
so there is nothing to install for sound either. See the README in
`ext/rgame_core/vendor/` for all of it.

`tools/` holds development tools that are not part of the engine and are not
built by `make` — currently one, which generates the audio suite's `.ogg`
fixture and needs `libvorbisenc` to run.

### Ruby side

- **Ruby 4.0.5**, pinned in `.ruby-version`. Installed here with
  [mise](https://mise.jdx.dev) (`mise install` in the project root picks up
  `.ruby-version`); any version manager that reads `.ruby-version` works just
  as well.
- **Ruby development headers.** Version-manager builds (mise, rbenv, rvm,
  asdf) include them. On a distro-packaged Ruby, install `ruby-dev`
  (Debian/Ubuntu). These are what `extconf.rb` compiles against.
- **Bundler**, then `bundle install` for the dev/test gems (RSpec, RuboCop).

Nothing else — the engine has no runtime Ruby dependencies, and the `Gemfile`
holds only development gems.

### Debian / Ubuntu

```
sudo apt install build-essential pkg-config libsdl2-dev libgl1-mesa-dev check
```

### macOS (Homebrew)

```
brew install sdl2 pkg-config check
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
square, a clipped rectangle, a circle, a thick line, a baked strip replayed
every frame, and a line of accented text. `Esc` or closing the window quits.
`ruby ext/rgame_core/example.rb` is the same scene driven from Ruby, and takes
an optional sound file — `ruby ext/rgame_core/example.rb theme.ogg` binds Space
to play it as a sample and Return to start and stop it as looping music. That is
the only place a real sound device is driven; everything automated runs against
a null or offline one.

The Ruby specs:

```
bundle install
make ext             # both extensions; the suites need the compiled .so files
rake spec            # headless specs: RGame::Util, the engine layer, packaging
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

## Packaging

Both extensions and the Ruby layer ship as one gem, built from `rgame.gemspec`:

```
rake build                      # package into pkg/rgame-<version>.gem
gem install pkg/rgame-0.1.0.gem # compiles both extensions on this machine
```

`gem install` runs each `extconf.rb` and installs the resulting `.so` into the
gem's own `lib/rgame/`, which is the same layout `make ext` produces in a
checkout — so `require "rgame"` and `require "rgame/core"` behave identically
either way, including the guarantee that the first of those loads no graphics
libraries. The system dependencies are the same ones the C engine needs
(SDL2, OpenGL, pkg-config, a compiler); `extconf.rb` aborts with the package to
install if one is missing, rather than failing later at the link step.

What ships is a glob over `lib/`, `ext/` and `docs/api/`, not a hand-written
list: a new C source or a runtime asset dropped into either tree is packaged
without being registered anywhere. `spec/packaging_spec.rb` holds that up from
the other side — it asserts every source, header and data file is in the gem and
that no build artifact, spec directory or plan is, so the parts of this that
would otherwise be a checklist fail the suite instead.

The version is `RGame::VERSION` in [lib/rgame/version.rb](lib/rgame/version.rb).
Nothing is published to RubyGems.

## Project structure

The engine C lives under `ext/rgame_core/` — a Ruby C extension directory —
rather than a top-level `src/`. That's deliberate: `gem install` unpacks the gem
and runs each `extconf.rb`, which can only build sources inside its own
directory, so keeping the C there means one copy of the code serves both the
standalone binary and the gem.

```
ext/rgame_core/              RGame::Core — the SDL/GL half. The sources are
                             grouped by subsystem, one folder each, and a file
                             names the folder it includes from: graphics/canvas.c
                             says #include "graphics/clip.h".
  include/rgame/core.h       Public C API (opaque handle, no SDL/GL types
                             leaked) — what both src/main.c and the extension
                             bind against.
  app/                       The window, the context and the loop.
    app.c                    Engine implementation: SDL window + OpenGL context
                             setup; owns the main loop and calls back to the
                             caller's update/draw callbacks.
    app_gl.h                 Private: the GL context behind the opaque handle.
    frame_loop.h/.c          Pure fixed-timestep + FPS logic, no SDL/GL — unit-
                             tested without a window (see CLAUDE.md's layering).
  graphics/                  Everything on the drawing path.
    transform.h/.c           Pure 2D affine transform stack — rotate, scale,
                             translate, composed. No SDL.
    clip.h/.c                Pure rects and the intersecting clip stack, in
                             screen space. No SDL.
    draw_queue.h/.c          Pure z-sort and batching: collects draw commands,
                             orders them by z, merges what can share a GL call.
    canvas.h/.c              Pure composition of transform + clip + queue; the
                             seam the drawing API is written against.
    backend.h/.c             The layer-2 seam: a function-pointer table a real
                             GL backend or a recording fake plugs into, plus
                             the loop that drives it from a prepared frame.
    texture.h/.c             Pure: refcounted texture sheets, the sub-rects
                             sprites cut out of them, and pixels -> UVs.
    primitives.h/.c          Pure: rects, thick lines, circles and sprites, in
                             terms of the canvas's triangles and quads.
    recording.h/.c           Pure: a baked block of drawing, kept between
                             frames and replayed as one call per texture.
    gl_backend.h/.c          The real GL calls — the only file that issues
                             them on the drawing path.
    image.c                  Decode a PNG and upload it — the thin GL shim
                             over texture.h. Views share one upload.
    image_internal.h         What the draw path needs from inside an image.
  text/                      Glyphs, from a .ttf to a texture page.
    atlas.h/.c               Pure: shelf packing for the glyph atlas — where
                             the next glyph goes on a texture page.
    glyph_cache.h/.c         Pure: codepoint -> rasterised glyph, open
                             addressed, never evicted.
    font.h/.c                Pure: a typeface at one size — glyph metrics,
                             kerning, rasterisation and UTF-8, over
                             stb_truetype. No atlas, no GL.
    font_atlas.c             Composes font + atlas + glyph cache and owns the
                             GL pages — the only text file that calls gl*.
    font_internal.h          What the draw path needs from inside a font.
  input/                     Keyboard and controllers.
    input.h/.c               Pure input snapshot + the flat button-id space
                             (keyboard and gamepad ranges). No SDL.
    device_slots.h/.c        Pure player-slot table for controllers: keeps a
                             player on the same slot across a disconnect. No SDL.
    gamepad.h/.c             Thin SDL_GameController shim: opens/closes pads on
                             hot-plug and copies their state into the snapshot.
  audio/                     Sound, which touches neither SDL nor GL.
    audio.c                  The sound device, samples and songs — miniaudio
                             talks to the platform directly.
    audio_internal.h         The live-sound counter, for tests.
    vorbis_decoder.h/.c      Ogg Vorbis for miniaudio, over stb_vorbis —
                             miniaudio cannot read ogg on its own.
  ruby/                      The Ruby-facing glue, and the only C here that
                             includes ruby.h.
    core_ext.c               VALUE wrappers + callback trampolines, and the
                             extension's entry point.
    core_ext.h               One init function per Ruby-visible class here.
    image_ext.c              RGame::Core::Image — the Ruby binding.
    audio_ext.c              RGame::Core::Audio, Sample and Song — the
                             bindings; three classes in one file because they
                             share a wrapping shape.
    renderer_ext.c           RGame::Core::Renderer — the drawing primitives.
    font_ext.c               RGame::Core::Font — the Ruby binding.
    recording_ext.c          RGame::Core::Recording — baked, replayable draws.
  vendor/                    Third-party sources + their licences.
    <name>_impl.c            One per vendored library (stb_image, stb_truetype,
                             stb_vorbis, miniaudio): instantiates it and picks
                             its features. The only files built without
                             -Wall -Wextra; the suffix is what selects that.
  extconf.rb                 mkmf script; pkg_config("sdl2"), -lGL. It lists
                             the subsystem folders, because mkmf's own default
                             only finds sources one level up from here.
  example.rb                 Manual smoke test driven from Ruby.

ext/rgame_util/              RGame::Util — the graphics-free half, so pure-data
                             helpers can be required without pulling in SDL/GL.
  util_ext.c                 Entry point; hands RGame::Util to each class init.
  tensor.c                   RGame::Util::Tensor — flat-array 3D grid.
  color.c/.h                 Pure RGBA packing, no Ruby — Check-tested.
  color_ext.c                RGame::Util::Color — the Ruby binding over it.
  extconf.rb                 mkmf script; no pkg_config, no -lGL.

lib/rgame.rb                 `require "rgame"` — loads RGame::Util only.
lib/rgame/version.rb         RGame::VERSION, and nothing else — the gemspec
                             loads this file before anything is compiled.
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
lib/rgame/core/font.rb       The default font path, over the C-backed Font.
lib/rgame/fonts/             The default font shipped with the engine:
                             Liberation Sans 2.1.5 (SIL OFL 1.1). Data read at
                             runtime, so it lives here rather than in ext/.
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
  packaging_spec.rb          What the gem ships, asserted against the tree so a
                             new source or data file cannot be left out of it.
spec_core/                   RSpec specs for RGame::Core (`rake spec:core`).
                             Opens real windows; boots its own Xvfb.
docs/                        The feature spec the engine is being built out to.
  api/                       Reference documentation for using it from Ruby.

rgame.gemspec                Packages both halves as one gem: both extconf.rb
                             files, and a globbed file list so a new source or
                             asset ships without being listed anywhere.
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
4. **Gem** (done) — `rgame.gemspec` packages both halves, building each
   extension into `lib/rgame/` on install the way `make ext` does in a
   checkout. Not published to RubyGems.

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
