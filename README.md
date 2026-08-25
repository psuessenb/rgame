# RGame

RGame is a small 2D game engine for Ruby, written in Ruby and C. It's build on top of SDL2, OpenGL and miniaudio. It's built with testability and performance in mind, and aims to be an engine where you can write your whole game code in Ruby, test it as usual with RSpec (or Minitest, or another test framework) and still have acceptable performance.

While still a work in progress, RGame aims to be more than a SDL/OpenGL
binding - it ships with high level features like a scene graph, sprites,
collision systems, debugging tools and an UI toolkit.

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

## Requirements

At the moment this gem ships only source-code and no precompiled binaries, which unfortunately means you need to compile a bunch of C code on your locale machine.

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

All three platforms below are built and tested on every push by
[CI](.github/workflows/ci.yml).

### Debian / Ubuntu

```
sudo apt install build-essential pkg-config libsdl2-dev libgl1-mesa-dev check
```

`rake spec:core` opens real windows and starts its own Xvfb, which needs a few
more packages — the display itself, the `xwininfo` it polls to know the display
is up, a software rasteriser (Xvfb has no GPU, and `SDL_GL_CreateContext` fails
without one) and the XTEST runtime for synthetic keystrokes:

```
sudo apt install xvfb x11-utils libgl1-mesa-dri libxtst6
```

### macOS (Homebrew)

```
brew install sdl2 pkg-config check
```

OpenGL ships with the Xcode Command Line Tools (`xcode-select --install`) — the
full Xcode is not needed, and neither is anything else: `rake spec:core` uses
the native window server, so there is no Xvfb equivalent to set up. Note
Homebrew's `sdl2` formula now installs **sdl2-compat**, which is SDL2's API
implemented on top of SDL3; the engine works through it unchanged.

### Windows

Use a **RubyInstaller-built** Ruby (mise, vfox and rbenv-style managers all
fetch those), which is what supplies `ridk`. The combined DevKit installer is
not required — a standalone MSYS2 that `ridk` can find works just as well, and
`C:\msys64` is one of the places it looks:

```
winget install --id MSYS2.MSYS2 -e
ridk exec pacman -Syu --noconfirm      # core update; may need a second pass
```

Then the libraries. Note `make` is an **msys** package with no prefix while
everything else is **ucrt64**-prefixed — that split is the whole Windows story:

```
ridk exec pacman -S --needed \
  mingw-w64-ucrt-x86_64-SDL2 \
  mingw-w64-ucrt-x86_64-check \
  mingw-w64-ucrt-x86_64-pkgconf \
  mingw-w64-ucrt-x86_64-gcc \
  make
```

**MSYS2 is several environments in one install, and picking the wrong one fails
in a way that looks like missing packages.** UCRT64 builds native Windows
binaries, which is what RubyInstaller's Ruby can load; the plain `msys`
environment builds against a Cygwin-like runtime, which it cannot. Work from
the "MSYS2 UCRT64" shell or run `ridk enable ucrt64` first, and verify before
trusting anything:

```
which gcc                   # must be /ucrt64/bin/gcc, NOT /usr/bin/gcc
pkg-config --cflags sdl2    # must print a ucrt64 include path
```

One more Windows fact worth knowing up front: **Check has no usable fork
there**, so the first segfault kills the whole test binary and the output stops
mid-suite. Use a debugger rather than reading the log — `CK_FORK=no gdb --args
./build/test_rgame`, and `CK_RUN_SUITE=<name>` to run one suite.

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

Both extensions and the Ruby layer ship as one gem, built from `rgame.gemspec`
and published at [rubygems.org/gems/rgame](https://rubygems.org/gems/rgame):

```
gem install rgame               # from RubyGems; compiles both extensions here
```

Or from a checkout, which is the same gem built locally:

```
rake build                      # package into pkg/rgame-<version>.gem
gem install pkg/rgame-*.gem     # compiles both extensions on this machine
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

## Project structure

The C lives under `ext/rgame_core/` rather than a top-level `src/`, because
`gem install` runs each `extconf.rb` and an extension can only build sources
inside its own directory — so one copy of the code serves both the standalone
binary and the gem. The Ruby half is split the same way it is namespaced:
`lib/rgame/util/`, `lib/rgame/core/` and `lib/rgame/engine/`.

A file-by-file map of the whole repository is in
[docs/project_structure.md](docs/project_structure.md).

## Roadmap

All three layers exist and the engine is usable end to end: the games under
[examples/](examples/) are written against exactly what is documented.

**Done**

1. **C engine** — an SDL2 window and a fixed-timestep loop, keyboard and
   gamepad input with hot-plug, a z-sorted batching renderer with transforms,
   clipping and baked recordings, text from a shipped TrueType font, and audio.
   Linux, macOS and Windows are all supported and all gated by CI.
2. **Ruby C extensions** — both halves. `RGame::Core` binds
   `include/rgame/core.h` (the app, the renderer, images, fonts, recordings,
   sound); `RGame::Util` is the graphics-free one, so values can be required
   without pulling SDL and OpenGL into the process.
3. **Pure-Ruby half** — `RGame::Engine`, the layer a game is actually written
   in: the scene graph, components, signals, tile maps, collision,
   pathfinding, and split-screen players with a camera and a binding table
   each. `RGame::Game` wires it to `RGame::Core` and is the only class allowed
   to name both.
4. **Gem** — `rgame.gemspec` packages both halves, compiling each extension
   into `lib/rgame/` on install the way `make ext` does in a checkout.
   [Published to RubyGems](https://rubygems.org/gems/rgame), so
   `gem install rgame` works.

**Next**

- **A UI package worth the name.** What exists covers a region per player,
  focus and activation — enough for keyboard-and-controller menus. Layout,
  nesting, scrolling lists and text entry are all still open; see
  ["What this is not"](docs/api/ui.md#what-this-is-not).
- **Precompiled binary gems**, so installing needs no compiler. The compiling
  is the easy part — CI already does it on three platforms — and the real
  blocker is that the binary still needs SDL2 at runtime. The options are
  written up in
  [docs/plans/precompiled-binary-gems.md](docs/plans/precompiled-binary-gems.md).
- **Hot paths into C, where profiling says so** — the nine-slice tiling loops
  and the animated-tile draw loop are the candidates. Deliberately last: each
  is a straightforward move once the geometry is separable, and doing it early
  would trade readability for a speedup nobody has measured.

Also known and deliberately deferred: the drawing path uses legacy
compatibility-profile OpenGL (`glBegin`/`glEnd`), which needs no loader library.
Moving to core-profile GL is a decision to take on purpose, not a drive-by
change.

## AI clause

This project is not vibe-coded, but AI tools were used heavily while
writing code. If you dislike AI generated code, this project is not for
you.