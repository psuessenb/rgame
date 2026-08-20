# ext/

The project's two Ruby C extensions. They are split by **dependency**, and that
split is the rule for deciding where new code goes:

| | `rgame_core` | `rgame_util` |
|---|---|---|
| Ruby namespace | `RGame::Core` | `RGame::Util` |
| Required as | `rgame/core_ext` | `rgame/util_ext` |
| Entry point | `Init_core_ext` | `Init_util_ext` |
| Links | SDL2 + OpenGL + libm + pthread + libdl | nothing but Ruby |
| Holds | `App` (window, GL context, main loop), `Image`, `Renderer`, `Recording`, `Font`, `Audio`, `Sample`, `Song` | `Tensor`, `Color` |

Anything that depends on SDL/OpenGL — or on something that does — belongs in
`rgame_core`. Everything else belongs in `rgame_util`. The point of the
split is that `RGame::Util` can be required, and its specs run, in a process
with no graphics libraries loaded and no display available:

```
ext/rgame_core/
  extconf.rb            # mkmf script -> Makefile; pkg_config("sdl2"), -lGL
  include/rgame/core.h  # the public C API
  example.rb            # manual/visual smoke test (opens a real window)
  app/
    app.c               # engine: SDL window/GL context + main loop
    app_gl.h            # private: the GL context behind the opaque app handle
    frame_loop.c/.h     # pure fixed-timestep + FPS logic (unit-tested)
  graphics/
    transform.c/.h      # pure 2D affine transform stack (unit-tested)
    clip.c/.h           # pure rects + intersecting clip stack (unit-tested)
    draw_queue.c/.h     # pure z-sort + batching of draw commands (unit-tested)
    canvas.c/.h         # pure transform+clip+queue composition (unit-tested)
    backend.h/.c        # the GL seam: function-pointer table + submit loop
    texture.c/.h        # pure texture sheets, sub-rects and UVs (unit-tested)
    primitives.c/.h     # pure rects/lines/circles/sprites -> canvas (unit-tested)
    recording.c/.h      # pure baked draws, replayed cheaply (unit-tested)
    gl_backend.c/.h     # the real GL calls: the only gl* on the draw path
    image.c             # decode a PNG + upload it: the thin GL shim
    image_internal.h    # what the draw path needs from inside an image
  text/
    atlas.c/.h          # pure glyph-atlas shelf packing (unit-tested)
    glyph_cache.c/.h    # pure codepoint -> glyph table (unit-tested)
    font.c/.h           # pure typeface: metrics, kerning, UTF-8 (unit-tested)
    font_atlas.c        # glyph atlas pages on the GPU: the impure quarter
    font_internal.h     # what the draw path needs from inside a font
  input/
    input.c/.h          # pure button-id space + input snapshot (unit-tested)
    device_slots.c/.h   # pure controller-slot table, no SDL (unit-tested)
    gamepad.c/.h        # thin SDL_GameController shim (open/close/poll)
  audio/
    audio.c             # sound device, samples and songs (unit-tested)
    audio_internal.h    # the live-sound counter, for tests
    vorbis_decoder.c/.h # ogg for miniaudio, over stb_vorbis (unit-tested)
  ruby/                 # the only C here that includes ruby.h
    core_ext.c          # Ruby-facing glue: VALUE wrappers + trampolines
    core_ext.h          # one init function per Ruby-visible class here
    image_ext.c         # RGame::Core::Image — the Ruby binding
    font_ext.c          # RGame::Core::Font — the Ruby binding
    audio_ext.c         # RGame::Core::Audio, Sample and Song — the bindings
    renderer_ext.c      # RGame::Core::Renderer — the drawing primitives
    recording_ext.c     # RGame::Core::Recording — baked, replayable draws
  vendor/               # third-party sources + licences (stb_image,
                        #   stb_truetype, stb_vorbis, miniaudio)
    *_impl.c            # one per vendored library, built with warnings off

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

`extconf.rb` runs `mkmf` to generate a Makefile. Every `.c` becomes one loadable
`.so`, linked against SDL2 + OpenGL the same way the root `Makefile` links the
standalone binary. No prebuilt `librgame_core.a` in the middle, so there's one
build step.

mkmf's default is to compile every `.c` in the extension's own directory and
nothing deeper, so `rgame_core`'s subsystem folders are named in its
`extconf.rb` — one `SOURCE_DIRS` list feeding `$srcs` (what to compile) and
`$VPATH` (where make looks for a source named by basename). Within a listed
folder nothing has to be remembered: dropping a `.c` into `graphics/` is all it
takes to get it compiled and linked. Adding a *folder* is one entry in that
list, and forgetting it fails loudly — the file is simply never compiled, and
the first call into it is an undefined symbol at `require` time.

Two consequences of how mkmf does this are worth knowing:

- **Objects land flat**, named after the source's basename, whatever folder it
  came from. So basenames have to be unique across the tree — and that rule
  enforces itself, because mkmf aborts with `source files duplication` rather
  than silently overwriting one object with another.
- **Header dependencies need help.** mkmf emits `$(OBJS): $(HDRS)` but builds
  `HDRS` by globbing the extension's own directory only, which is now empty of
  headers. `extconf.rb` appends the real list, or editing a header would
  rebuild nothing and link objects compiled against the old struct.

The vendored translation units are the exception, and are built with warnings
off. mkmf has no per-file flag setting, so `extconf.rb` appends an explicit rule
per entry in its `VENDORED` table to the Makefile it just generated — an
explicit rule beats mkmf's generic `.c.o` one, so it applies to those files and
nothing else. The `_impl.c` suffix is what marks a file as one of them, and it
is reserved for that: the project stays `-Wall -Wextra`-clean everywhere we
wrote the code. See `rgame_core/vendor/README.md`.

Not everything in a namespace comes from its extension: `RGame::Core::Input`,
`RGame::Core::Gamepad` and `RGame::Util::Controls` are pure Ruby in `lib/`,
layered on top, and `RGame::Core::Image` is C with a few sheet-slicing methods
added in `lib/rgame/core/image.rb`. The tables above list what each *extension*
provides.

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
input.down?(controls::PAD_A, device: controls.gamepad(0))
input.axis(controls::AXIS_LEFT_X, device: controls.gamepad(0))   # => Float

# Input is the raw query: physical ids, per device. What an id *means* to a game
# is RGame::Engine::InputMap, one table per player, a layer up.

# Which controllers are plugged in — a readout for menus, not the frame path:
pads = RGame::Core::Gamepad.new(app)
pads.count                                   # => 1
pads.each_connected { |slot, name| ... }     # "Player 2: <name>"

# Images: one decode and one upload, sliced into as many views as you like.
sheet = RGame::Core::Image.new(app, "tiles.png")
sheet.width; sheet.height
sheet.subimage(16, 0, 16, 16)                             # a view, not a copy
RGame::Core::Image.load_tiles(app, "tiles.png", 16, 16)   # => [Image, ...]

# Drawing, from inside App#draw only. Nothing is immediate: the frame is
# z-sorted and batched once, after #draw returns.
renderer = RGame::Core::Renderer.new(app)
renderer.rect(10, 10, 100, 40, color: RGame::Util::Color::WHITE)
renderer.circle(200, 200, 30, color: [255, 0, 0])
renderer.line(0, 0, 100, 100, thickness: 4)
renderer.image(sheet, 400, 300, angle: 45, scale: 2)      # centred, clockwise
renderer.rotated(30, 400, 300) { renderer.rect(380, 280, 40, 40) }
renderer.clipped(0, 0, 400, 600) { renderer.background(sheet) }

# Text. The renderer has a font already; Font.new(app, size) makes another.
renderer.text("Score: 1200", 10, 10)
renderer.text_width("Score: 1200")   # => Float, and what #text actually draws

# Bake a block of drawing once, replay it for one call per texture.
ground = renderer.record { 100.times { |i| renderer.rect(i * 8, 0, 6, 6) } }
ground.draw(-camera_x, -camera_y)

# Sound. The device owns no window, so it takes no app.
audio = RGame::Core::Audio.new
audio.sample("hit.ogg").play                   # another voice each time
audio.song("theme.ogg").play(looping: true)    # streamed, one voice, stoppable

grid = RGame::Util::Tensor.new(width, height, depth, initial: nil)
grid[x, y, z] = value

colour = RGame::Util::Color.new(255, 128, 0)   # frozen, compares by value
RGame::Util::Color.coerce([255, 128, 0])       # nil / [r,g,b] / [r,g,b,a] / Color
```
