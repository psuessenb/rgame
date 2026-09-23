# RGame

RGame is a small 2D game engine for Ruby, written in Ruby and C. It's built with testability and performance in mind, and aims to be an engine where you can write your whole game code in Ruby, test it as usual with RSpec (or Minitest, or another test framework) and still have acceptable performance.

## Why does this exist and should you use it?

RGame is not a universal game engine yet and is currently aimed at games with the following criteria:

* top-down 2D
* tiled maps and sprites for characters
* controlled with a controller or keyboard alone (or multiple controllers, it supports local multiplayer and split-screen)
* dialogue-, puzzle- or quest-based. There is no combat system in this engine, although you can of course build one
* pixel-art as art-style is possible, but not scaled perfectly when playing in fullscreen at the moment

RGame is the product of both my lazyness and me looking for something that did not exist. Coming from Ruby on Rails, I wanted to write games while not learning a new language. There are Ruby game engines, but none offered me what I wanted: The option to write modern, standard Ruby and proper specs for the game logic. The closest I found was [Gosu](https://github.com/gosu/gosu), which is just a media layer. This project initially started as a "high level engine on top of Gosu", but eventually the mismatch of my design philosophy with Gosu drove me into rewriting this layer myself.

RGame puts a lot of emphazis on testing and being testable: It separates the layers that talk to SDL2/OpenGL from the high level engine concepts, so the whole game logic is testable headless.

It also tries to marry the beauty of Ruby with the hard performance requirements of games: Math-heavy use-cases are backed by C code instead of Ruby classes, and the engine codes allocates nothing on a per-frame basis to trigger as little garbadge collection runs as possible.

Should you _use_ it, though? If you're looking for something mature, free, and more battle-tested: Take a look at [Godot](https://godotengine.org/) instead. If you're looking for something mature and battle-tested _in Ruby land_, take a look at [dragonruby](https://dragonruby.org/) instead (it's not free, but it's probably worth the price).

If you're just starting with game development and planning on making the next big indie hit - might as well pick this one as the engine for the game you never finish!

In all seriousness, though: This is a hobby project of mine, and while it might develop into something actually useful, at the time of writing it's a playground. If you search for something I searched and found nothing - **try RGame**! If you want to learn how to write games or just need a small prototype, and you really like Ruby - **try RGame**! If all you know is Rails, but you want to make a game that doesn't run in a browser and don't care about shipping it - **try RGame!**

I would be really happy if someone else actually uses it, but at this point I can't really recommend it for anything else than small projects and/or learning the ropes of game development.

## Getting started

Installing the gem puts an `rgame` command on your PATH, which you can use to setup a project:

```
gem install rgame
rgame new tictactoe

cd tictactoe
bundle install
bundle exec rspec     # the game logic, headless — no window needed
ruby main.rb          # the game itself
```

It's just a small skeleton — a game class, a root node, a spec and the usual configuration — but it is laid out the way the engine wants to be used: one file loads SDL, everything else stays graphics-free and therefore testable with no display. [The `rgame` command](docs/api/cli.md) explains the layout and the reasoning. This is also sets you up with a Rubocop configuration already geared towards RGame and game development in general.

**On a common desktop that first line needs nothing else** — no compiler, no SDL2, no header files. `gem install rgame` fetches a gem whose two C extensions are already built, with SDL2 linked into them:

- macOS 11 or later on Apple Silicon
- x86-64 Linux with glibc 2.29 or later
- 64-bit Windows, on a RubyInstaller Ruby

All three need Ruby 4.0. Anywhere else — an Intel Mac, a Raspberry Pi, Ruby 4.1 — `gem install` falls back to the gem that ships the C and compiles it on your machine. That one needs [a compiler and SDL2](#building-from-source).

## Hello world

The simplest "game" you can write, all in one file:

```ruby
require 'rgame/game'

class Scene < RGame::Engine::Node2D
  def _draw(renderer, _view)
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

## Examples

`examples/` holds one small program per concept, each a single file you can run with `ruby examples/<name>/main.rb`. [The examples page](docs/api/examples.md) describes them in more detail. They're also full of code comments so you have an easier time learning the concepts.

| Example | Shows |
|---|---|
| [walk](docs/api/examples.md#walk) | A player-controlled sprite — a node, three components, input as actions |
| [sprite](docs/api/examples.md#sprite) | One frame drawn at a node, with no animation behind it |
| [velocity](docs/api/examples.md#velocity) | Movement with nobody driving: a velocity, integrated |
| [scroll_map](docs/api/examples.md#scroll_map) | A Tiled map larger than the window, scrolled by a camera |
| [collision](docs/api/examples.md#collision) | Two shapes touching, and who gets told about it |
| [collectables](docs/api/examples.md#collectables) | Coins taken by touch, and a chest opened with a press |
| [collision_tiles](docs/api/examples.md#collision_tiles) | Walking into a wall of solid tiles, and sliding along it |
| [jump_topdown](docs/api/examples.md#jump_topdown) | A hop in a top-down view, where the sprite rises and the feet stay on the ground |
| [push_pull](docs/api/examples.md#push_pull) | Crates pushed by walking into them, and pulled with a held button |
| [block_puzzle](docs/api/examples.md#block_puzzle) | Blocks shoved a cell at a time onto their squares |
| [signals](docs/api/examples.md#signals) | A node announcing something happened, to nobody in particular |
| [timer](docs/api/examples.md#timer) | Things that happen on a clock, with nothing pressed |
| [pooling](docs/api/examples.md#pooling) | Spawning a lot of things without allocating them |
| [game_menu](docs/api/examples.md#game_menu) | A menu over a world that keeps running |
| [menu_navigation](docs/api/examples.md#menu_navigation) | Several screens, and settings that persist |
| [radial_menu](docs/api/examples.md#radial_menu) | A wheel of icons, chosen by the direction of the stick |
| [quick_wheel](docs/api/examples.md#quick_wheel) | A wheel held open by a button and chosen by letting go |
| [skill_bar](docs/api/examples.md#skill_bar) | A row of tools, stepped through or fired by hotkeys |
| [sound](docs/api/examples.md#sound) | A sound effect fired by a button, and the seam it travels |
| [music](docs/api/examples.md#music) | A looping track, started and stopped |
| [split_screen](docs/api/examples.md#split_screen) | Two players in one world, drawn once per viewport |
| [input_glyphs](docs/api/examples.md#input_glyphs) | Prompts that match the device in your hands |
| [input_holds](docs/api/examples.md#input_holds) | One button tapped and held, and a chord that silences it |
| [fullscreen](docs/api/examples.md#fullscreen) | Fullscreen, switched at any time, and the scale modes |
| [save_load](docs/api/examples.md#save_load) | Writing game state to disk and putting it back |
| [save_load_ids](docs/api/examples.md#save_load_ids) | A save that has to name things, and why a reference forces ids |
| [localization](docs/api/examples.md#localization) | The same screen in two languages, switched and remembered |
| [intro](docs/api/examples.md#intro) | A story broken into lines and pages that differ per language, typed out a character at a time |
| [pathfinding](docs/api/examples.md#pathfinding) | Setting a target for an actor and let if find its way there |
| [dialogue](docs/api/examples.md#dialogue) | A branching conversation in a dialogue box, and nothing else |
| [quests_and_dialogue](docs/api/examples.md#quests_and_dialogue) | A village where talking moves a quest on, and one save keeps both |

## Building from source

**This section is for two readers: anyone on a platform the binary gems miss, and anyone working on RGame itself.** Installing on one of the three platforms above needs none of it.

Compiling the C engine needs a compiler and the system libraries it links against. A source install of the gem needs the compiler, `pkg-config`, SDL2 and OpenGL from the list below. The rest is for running rgame's own suites.

### C engine

- A C compiler — `gcc` or `clang`
- `make`
- `pkg-config`
- SDL2 development headers (`sdl2` pkg-config package)
- OpenGL development headers/libs (provided by Mesa on Linux)
- [Check](https://libcheck.github.io/check/) (`check` pkg-config package) — C unit test framework, only needed for `make test`

PNG decoding, text and audio need no system libraries: `stb_image.h`,
`stb_vorbis.c` and `miniaudio.h` are vendored in `ext/rgame_core/vendor/`, and
`stb_truetype.h` in `ext/rgame_util/vendor/` (all public domain / MIT). The
default font ships in `lib/rgame/fonts/` (SIL OFL 1.1). miniaudio finds ALSA or
PulseAudio at runtime, so there is nothing to install for sound either. The
README in each `vendor/` directory covers the details.

`tools/` holds development tools that are not part of the engine and are not
built by `make` — currently one, which generates the audio suite's `.ogg`
fixture and needs `libvorbisenc` to run.

### Ruby side

- **Ruby 4.0.5**, pinned in `.ruby-version`.
- **Ruby development headers.** Version-manager builds (mise, rbenv, rvm, asdf) include them. On a distro-packaged Ruby, install `ruby-dev`
  (Debian/Ubuntu). These are what `extconf.rb` compiles against.
- **Bundler**, then `bundle install` for the dev/test gems (RSpec, RuboCop).

Nothing else. The engine's one runtime gem is `rexml`, which Bundler installs with it, and the `Gemfile` holds only development gems.

All three platforms below are built and tested on every push by
[CI](.github/workflows/ci.yml) - with that people have usually at home, so Apple Silicon and not Apple Intel, etc.

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
                     # project's own cops from lib/rgame/rubocop/.
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

Both extensions and the Ruby layer ship as one gem, built from `rgame.gemspec` and published at [rubygems.org/gems/rgame](https://rubygems.org/gems/rgame):

```
gem install rgame               # from RubyGems; compiles nothing on a covered platform
```

Or from a checkout, which builds the source gem locally:

```
rake build                      # package into pkg/rgame-<version>.gem
gem install pkg/rgame-*.gem     # compiles both extensions on this machine
```

**RubyGems holds two kinds of gem for each version.** The source gem carries the
C and compiles on install. Three platform gems carry `core_ext` and `util_ext`
already built, with SDL2 linked statically into `core_ext`; they ship no `.c`,
no `extconf.rb` and declare no extensions, so they compile nothing. `gem
install` picks by platform and Ruby version on its own.

CI builds and publishes all four. `tools/platform_gem.rake` builds a platform
gem, `tools/check_platform_gem.rb` checks it against nine rules before it may be
published, and the `smoke` job installs it on a runner with no SDL2 and plays
the examples out of it.

Installing the source gem runs each `extconf.rb` and installs the resulting
`.so` into the gem's own `lib/rgame/`, which is the same layout `make ext`
produces in a checkout — so `require "rgame"` and `require "rgame/core"` behave
identically whichever gem you got, including the guarantee that the first of
those loads no graphics libraries. Its system dependencies are the ones the C
engine needs (SDL2, OpenGL, pkg-config, a compiler); `extconf.rb` aborts with
the package to install if one is missing, rather than failing later at the link
step.

What ships is a glob over `lib/`, `ext/` and `docs/api/`, not a hand-written
list: a new C source or a runtime asset dropped into either tree is packaged
without being registered anywhere. `spec/packaging_spec.rb` holds that up from
the other side — it asserts every source, header and data file is in the gem and
that no build artifact, spec directory or plan is, so the parts of this that
would otherwise be a checklist fail the suite instead.

The version is `RGame::VERSION` in [lib/rgame/version.rb](lib/rgame/version.rb).

## Project structure

The C lives under `ext/rgame_core/` rather than a top-level `src/`, because`gem install` runs each `extconf.rb` and an extension can only build sources inside its own directory — so one copy of the code serves both the standalone binary and the gem. The Ruby half is split the same way it is namespaced:
`lib/rgame/util/`, `lib/rgame/core/` and `lib/rgame/engine/`.

A file-by-file map of the whole repository is in
[docs/project_structure.md](docs/project_structure.md).

## Roadmap

There is no real roadmap for this project, but there are a few features on my mind which I want to include in the next release(s):

- support more of Tiled's features. Orthogonal maps will stay the only one supported for a while, though. - **IN PROGRESS**
- allow better input-to-action-mapping for complexer inputs like long presses or button combinations - **DONE**
- a better scene manager that means less boilerplate in each game with scene transitions. With it an example for teleports/room-transitions
- allow toggeling the debug layer and connect it better to systems like collision (show collision boxes on toggle)
- a dialogue system and better text representation - **DONE**
- an examples (and if needed, new components) for pushing and pulling objects in the game world
- an example (and if needed, new components) for inventory and equipment screens
- an example (and if needed, new components) for collectable and interactable nodes like coins and treasure chests
- audio transitions - fades, pauses, etc.
- visual effects like lightning, sparkles, fade-to-black
- better engine support for cutscenes

## AI clause

This project is not vibe-coded, but AI tools were used heavily while
writing code. If you dislike AI generated code, this project is not for
you.