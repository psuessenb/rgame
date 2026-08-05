# rgame

A learning project: SDL2 + OpenGL in C, wrapped as Ruby C extensions. The user
is not an experienced C programmer — prefer explaining unfamiliar C/SDL/GL
idioms briefly when introducing them, and favor straightforward code over
clever code.

## Code comments, documentation and code style

Add top-level comments to modules, classes and C files describing what they are
and do. Public methods of Ruby classes — and their C-layer equivalents, the
functions exposed via `rb_define_method` — get an explaining comment when
they're non-trivial and the name doesn't already tell the whole story. Apart
from that, keep comments to a minimum.

Prefer code that speaks for itself through variable and method names over
lengthy comments. Use comments to document gotchas (for instance when the
obvious implementation didn't work for an unforeseen reason), tricky parts of
the code, or cases where clarity through naming isn't an option.

**Exception — the teaching layer.** C, SDL, OpenGL and Ruby-C-API idioms get
explained when first introduced, even at length. This is a learning project
(see the top of this file) and those explanations are load-bearing:
`ext/rgame_util/tensor.c` spends its header explaining why the GC needs a
`mark` function, and `ext/rgame_core/ruby/core_ext.c` explains TypedData and
the alloc/initialize split. Existing implementation files run roughly 35–80%
comment lines by design — treat them as the target density and don't thin them
out. "Minimal" applies to comments that restate what the code already says, not
to ones that teach an unfamiliar mechanism.

Write documentation alongside code. Reference documentation lives under
`docs/`; the top-level `README.md` and `ext/README.md` stay where they are and
cover setup and orientation. Documentation describes the state of the code, not
the road that got it there — it must not reference prompts, previous
implementations that are now gone, or throwaway example code. Code examples in
documentation must stand on their own: complete enough to read without outside
context, and valid against the current code. Rule of thumb: the documentation
is written for a reader who has *only* the current code and took no part in
writing it, and it should help them understand and use that code.

The exception is everything under `docs/plans`. Documentation there serves an
implementation or refactoring effort, so it can and should reference previous
iterations of the code, raise open questions, and record decisions taken in
prompts. Plans are working documents: when the work lands, fold whatever is
still true into the real documentation and delete the plan — git history keeps
it. A plan that outlives its refactor is just a stale description of code that
no longer exists.

## Design out misuse: the right thing must be the easy thing

Aim for a design that admits little or no misuse. When something *must* happen
for the engine to work, making it happen is the engine's job — never a rule the
calling code is asked to remember.

Two examples of the shape this takes:

- **Give the user a blank hook, keep the machinery separate.** A node exposes
  an empty `on_draw` to override, while `draw` does the bookkeeping and calls
  it. That is better than one `draw` the user overrides and must remember to
  `super` from — because forgetting `super` is silent, and the failure shows up
  somewhere else entirely.
- **The engine makes its own required calls.** A node that can be rotated
  applies that rotation inside its own `draw`; it does not depend on the author
  remembering to wrap their drawing in `renderer.rotated`.

The same principle governs project structure, not just class design, and that
is the test to apply when adding any convention: *if following the rule depends
on someone remembering, the design is wrong.* Concretely — the headless spec
suite lives in its own directory with its own runner, rather than in a shared
one with an `exclude_pattern` that must not be forgotten. A convention that
fails loudly beats one that has to be observed.

## RuboCop

Run RuboCop over the Ruby files you touched, as a finishing step:

```
bundle exec rubocop path/to/changed_file.rb
```

**Scope it to the files you changed.** There is a backlog of pre-existing
offenses elsewhere in the project; leave those alone unless clearing them is
the actual task, so unrelated churn stays out of the diff.

`-a` (safe autocorrect) is fine unprompted. `-A` (unsafe autocorrect) can change
semantics, so only with a deliberate look at what it did.

Attempt to fix offenses, but watch for rules that don't fit this codebase. A lot
of RuboCop is written with web applications in mind and this is a game engine,
so some rules make the code worse. In that case add an exception rather than
write worse code:

- a justified one-off → inline `# rubocop:disable Cop/Name -- reason`
- a codebase-wide rule → an entry in `.rubocop.yml`

**Either way, say why.** `.rubocop.yml` already models this: its `Metrics/*`
block explains that a game engine's `update`/`draw` methods run long and its
coordinate variables are idiomatically short. An exception without a reason is
indistinguishable from having given up.

### The custom cops are house rules — don't disable them

`rubocop/cop/game/` holds five project-specific cops (plus a shared `HotPath`
mixin), loaded by `.rubocop.yml`:

| Cop | Enforces |
|---|---|
| `Game/NoInterpolationInHotPath` | no string interpolation in per-frame methods |
| `Game/NoNeedlessAllocation` | no throwaway Array/Range literals on a per-frame path |
| `Game/PreferGosuModuleMethod` | call `Gosu.<m>`, not the allocating `Window#<m>` compat shim |
| `Game/UseAbsoluteCoords` | in `draw`/`update`/`contains?` use the resolved `@abs_*`, never parent-relative `@x`/`@y` |
| `Game/NoCoreInEngineLayer` | no `RGame::Core` reference in `lib/rgame/engine/` or `spec/` — the engine layer must stay headless |

These exist because a steady 60fps frame that allocates is a GC pause waiting to
happen, and the cost is invisible without a guard. Unlike stock cops, these are
the ones that *do* fit here — fix the code, not the cop.
(`Game/PreferGosuModuleMethod` retires along with Gosu itself; see
`docs/plans/gosu-replacement/`.)

## Current phase

Both halves exist. The C engine — window, fixed-timestep loop, input, images, a
z-sorted batching renderer, text, and audio — is wrapped by
`ext/rgame_core/ruby/`, and there's a Ruby half under `lib/` backed by a
second, graphics-free extension in `ext/rgame_util/`.
`rgame.gemspec` packages both, so the project installs as a gem as well as
running from a checkout — though nothing is published yet.

The gap now is the whole `RGame::Engine` layer: the scene graph a game is
actually written against does not exist yet. What remains after that is porting
`lib/platform/` off Gosu and deleting it. When adding a feature, the default is
still to build it in C under `ext/rgame_core/` and only extend the Ruby wrapper
once the C API for it is settled — unless it is engine-layer work, which is pure
Ruby by definition.

## The Core / Util split

**This is the first question to answer about any new code: does it depend on
SDL, OpenGL, or on something that does?**

- **Yes** → `RGame::Core`, built from `ext/rgame_core/`, required as
  `rgame/core_ext`, loaded via `require "rgame/core"`.
- **No** → `RGame::Util`, built from `ext/rgame_util/`, required as
  `rgame/util_ext`, loaded via `require "rgame"`.

Everything Ruby-visible is under the `RGame` module — no other top-level
constant. Both `Init_` functions call `rb_define_module("RGame")`, which is
idempotent, so load order between the two extensions doesn't matter.

The split is load-bearing, not cosmetic. `require "rgame"` loads
`RGame::Util` with **zero graphics libraries in the process**, which is what
lets pure-logic code and its specs run with no display and no SDL present.
So `lib/rgame.rb` must never require `rgame/core`, directly or
transitively — that would silently destroy the property for every consumer.
It's checkable, and worth re-checking after touching `lib/`:

```
ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
# => []
```

If a subsystem has both a pure part and an SDL-driven part, split it across
the two rather than putting the whole thing in Core — that's the same
layering rule as below, applied at the extension boundary.

### Value objects go in Util; only handle-owners go in Core

The sharper form of the same question, and the one to apply when a type could
plausibly sit on either side:

> **Anything that is a shareable *value* belongs in `Util`. Only something that
> owns a GPU or OS *handle* belongs in `Core`.**

A colour, a vector, a rect, a grid are values: cheap, comparable, no resources.
A window, a texture, a font, an audio device own something the OS gave us and
must give back. `Tensor` is a value and lives in Util; `App` owns a window and
lives in Core.

`RGame::Util::Controls` is the worked example. It is nothing but integers — the
ids for keys, pad buttons, axes and device slots, plus the default binding
tables. Those started in Core, because the C engine defines them and asserts
them against SDL's own scancodes. But an id is a value, and a game's control
config has to be able to name one:

```ruby
controls = RGame::Util::Controls
bindings = controls::DEFAULT_KEYBOARD.merge(fire: controls::KEY_J)
```

In Core that is impossible for engine-layer code, which may not name Core at
all. In Util it is ordinary. The C `#define`s stay where they are — `src/main.c`
includes only `rgame/core.h` and needs them — so the numbers exist twice, and
`spec/rgame/util/controls_spec.rb` parses the header and compares every one.
Duplication with a guard beat putting a value out of reach.

This is not tidiness — it is what makes the engine layer below usable. Engine
code may hold Util types as attributes but may **not** hold Core types at all,
so putting a value type in Core would put it permanently out of reach of the
scene graph that wants to store it.

## The three layers, and who may talk to whom

```
RGame::Engine   scene tree, signals, sprites, tile maps, pathfinding — pure
                game concepts, no SDL, fully spec-able headless
      |  may hold Util types as attributes
      |  may CALL methods on Core objects it is handed, by name
      |  may NOT name, require or hold a Core class
      v
RGame::Core     App, Input, Renderer, ... — owns windows, GPU and OS handles
RGame::Util     Tensor, and every other shareable value type
```

`RGame::Engine` lives in `lib/rgame/engine/` and is the layer a game is
actually written against. Its hard rule:

- **It may hold `RGame::Util` types.** A node may have a `Tensor` attribute.
- **It may not name `RGame::Core` at all** — no `require`, no constant
  reference, no attribute. Not even in its specs.
- **It reaches Core only through objects handed to it**, duck-typed. A node's
  `draw` receives a `renderer` and calls methods on it that it knows by name.
  It never stores that renderer, and never asks what class it is.

That is what keeps the whole engine layer, and any game built on it,
spec-able with no window, no GPU and no clock — specs drive `update(dt)`
directly and can run a simulated hour in milliseconds.

Two things enforce it rather than merely asking for it:

- Engine specs never load `rgame/core`, so `RGame::Core` is simply an
  undefined constant during those runs — a stray reference raises `NameError`
  instead of quietly working.
- `Game/NoCoreInEngineLayer` (see the RuboCop section) flags any `RGame::Core`
  reference under `lib/rgame/engine/` or `spec/`, which also catches the
  branches a test run never reaches.

Because the engine may only call a renderer by name, that method list is a real
interface with more than one implementation — the live `RGame::Core::Renderer`
and every recording fake a spec substitutes. Both must be checked against the
same shared example group, or the fake drifts and a fully green headless suite
stops predicting whether the game runs. See "Testing" below.

## Structure and why it looks like this

**All engine C lives in `ext/rgame_core/`**, not a top-level `src/`. This is
because the project is headed for a single gem containing both the C and the
Ruby half: `gem install` runs each `extconf.rb`, and an extension can
only build sources within its own directory. Keeping the C there means one
copy of the code feeds both the standalone binary and the gem.

Inside it, sources are grouped by subsystem — `app/`, `graphics/`, `text/`,
`input/`, `audio/` — plus `ruby/` for the Ruby-facing glue and `vendor/` for
third-party code. **A new engine source goes in the folder for its subsystem**,
and includes name the folder they come from: `graphics/canvas.c` says
`#include "graphics/clip.h"`, so a dependency that crosses a subsystem boundary
is visible in the source rather than hidden in an include path.

mkmf compiles every `.c` in an extension's own directory and nothing deeper, so
`extconf.rb` lists these folders in `SOURCE_DIRS`, feeding `$srcs` (what to
compile) and `$VPATH` (where make looks for a source named by basename). Two
things follow. Objects are named after the source's *basename*, so basenames
must be unique across the whole tree — mkmf aborts with `source files
duplication` rather than clobbering one with another, so that rule holds itself
up. And a **new folder** has to be added to `SOURCE_DIRS`; forgetting fails
loudly, as an undefined symbol the first time something calls into it. Adding a
file to a folder already listed needs nothing.

- `ext/rgame_core/include/rgame/core.h` — the *only* public API. Opaque
  `rgame_app` handle, plain C types only (no SDL/GL types in the signature).
  This is what the Ruby extension calls — keeping SDL/GL details out of the
  header means `ext/rgame_core/ruby/core_ext.c` can `#include` it without
  also pulling in `SDL.h` conflicts or exposing internals. It sits under its own
  `include/` subdirectory, which is on the include path but not in
  `SOURCE_DIRS` — a header directory, never a source one.
- `ext/rgame_core/app/app.c` — the actual engine (SDL window/GL context setup;
  owns the main loop and drives caller-supplied `update`/`draw` callbacks).
  Compiled with `-fPIC` so the resulting `.a` can be linked into a shared
  object (`.so`) without recompiling.
- `ext/rgame_core/app/frame_loop.{c,h}` — pure-logic helpers (no SDL/GL, no I/O)
  factored out of `core.c` specifically so they're unit-testable without a
  display/GL context (currently the fixed-timestep accumulator + FPS
  counter). `test/` links against these directly. When adding engine logic,
  prefer putting the parts that don't touch SDL/GL here so they stay
  testable — see `test/test_frame_loop.c` for the pattern.
- `ext/rgame_core/input/device_slots.{c,h}` — the same shape, for controllers: a
  pure player-slot table that keeps a player on one slot across a
  disconnect/reconnect. No SDL, covered by `test/test_device_slots.c`.
- `ext/rgame_core/input/input.{c,h}` — the input snapshot and the flat button-id
  space, again pure: `app.c` copies SDL's keyboard state into it once per
  frame, and every query reads that copy. Covered by `test/test_input.c`.
- `ext/rgame_core/graphics/transform.{c,h}` — the 2D affine transform stack that
  rotation, scale and the camera all run through. Pure; covered by
  `test/test_transform.c`, which asserts on coordinates rather than matrix
  entries because a matrix assertion passes just as happily with the rotation
  going the wrong way.
- `ext/rgame_core/graphics/clip.{c,h}` — rectangles and the intersecting clip
  stack, in screen space. Pure; covered by `test/test_clip.c`. A push always
  *narrows*, so a child can never draw outside the region its parent allowed,
  and "empty" is a canonical value because the draw queue uses it to drop
  commands.
- `ext/rgame_core/graphics/canvas.{c,h}` — composes the transform stack, the
  clip stack and the draw queue, and is the seam the drawing API is written
  against. Pure; covered by `test/test_canvas.c`, including the split-screen
  shape end to end. It transforms vertices on the way *in*, which is what lets
  the queue reorder them freely afterwards.
- `ext/rgame_core/graphics/backend.{c,h}` — the layer-2 seam where arithmetic
  stops and real GL calls begin: a function-pointer table, plus
  `rgame_draw_submit`, which walks a prepared frame and issues a scissor only
  when the clip actually changes. `test/support/recording_backend.{c,h}` is the
  fake that stands in for GL, and is what makes "the right calls in the right
  order" checkable with no display — a state-change optimisation is invisible
  to a pixel test.
- `ext/rgame_core/graphics/draw_queue.{c,h}` — z-ordering and batching, and the
  reason the depth buffer is not used: depth testing and alpha blending are
  mutually exclusive, so translucent UI over gameplay needs a CPU sort. Pure;
  covered by `test/test_draw_queue.c`. Its buffers are reset rather than freed
  each frame, and a test asserts capacities do not grow on a second identical
  frame — a renderer that allocates per frame is a stutter nothing else would
  notice.
- `ext/rgame_core/graphics/texture.{c,h}` — what part of an uploaded image a
  sprite covers, and who owns the upload: a refcounted sheet plus cheap views
  into it, so slicing a sprite sheet costs no second decode. Pure — including
  the refcount, because "free the GPU texture exactly when the last sprite
  using it goes" is bookkeeping that needs no GPU to get wrong. Covered by
  `test/test_texture.c`; `rgame_texture_live_sheets` is the counter that makes
  a leaked texture visible from a spec.
- `ext/rgame_core/graphics/image.c` — layer 3 for images: read the file,
  `stbi_load`, `glTexImage2D`, `GL_NEAREST`. Kept dumb on purpose; the
  interesting parts are in `texture.c` above. Covered end to end by
  `spec_core/rgame/core/image_spec.rb`.
- `ext/rgame_core/vendor/` — the vendored PNG decoder, TrueType rasteriser,
  Ogg Vorbis decoder and audio device library, and beside each the single
  translation unit (`<name>_impl.c`) that instantiates it and picks its
  features. **The only files in the project compiled without `-Wall -Wextra`**,
  and the `_impl.c` suffix is what selects that, from one list in both
  `extconf.rb` and the root `Makefile`. Feature macros live in the `_impl.c`
  rather than in build flags, so the standalone binary and the gem cannot end up
  supporting different formats. The default font is *not* here: it is runtime
  data and lives in `lib/rgame/fonts/`. See `ext/rgame_core/vendor/README.md`.
- `tools/` — development tools, outside the engine and not built by `make`.
  `make_ogg_fixture.c` generates the audio suite's `.ogg` and needs
  `libvorbisenc` to *run*; the engine links no vorbis library at all.
- `ext/rgame_core/graphics/primitives.{c,h}` — the shapes a game asks for
  (rect, thick line, circle, sprite) in terms of the two the canvas knows.
  Pure; covered by `test/test_primitives.c`. A rotated sprite goes through the
  canvas's own transform stack rather than its own sin/cos, so which way a
  positive angle turns is decided in exactly one place.
- `ext/rgame_core/text/atlas.{c,h}` — where the next glyph goes on a texture page:
  a shelf packer, pure, covered by `test/test_atlas.c`. The one-pixel gutter
  between glyphs is reserved *inside* `place` rather than by each caller,
  because a caller that has to remember eventually does not and the result
  looks like a rendering bug rather than a packing one.
- `ext/rgame_core/text/glyph_cache.{c,h}` — which glyphs have already been
  rasterised and where they went: an open-addressed table keyed by codepoint,
  pure, covered by `test/test_glyph_cache.c`. Nothing is ever evicted, which is
  the point — caching per *glyph* rather than per string bounds the whole thing
  by the character set the game draws, so there is no policy to get wrong and
  no tombstones to skip.
- `ext/rgame_core/text/font.{c,h}` — a typeface at one pixel size: glyph metrics,
  rasterisation and UTF-8, over `stb_truetype`. Pure — no atlas, no GL — and
  covered by `test/test_font.c` against the font the engine *ships*, so the
  assertions are real advances rather than fixtures. Measuring a string and
  drawing it share one `rgame_text_cursor`: two loops that both "sum the
  advances" drift, and every centred label in the game drifts with them.
- `ext/rgame_core/audio/audio.c` — the sound device and the two kinds of sound.
  Touches neither SDL nor GL: miniaudio talks to ALSA/PulseAudio/CoreAudio
  directly, so a sound belongs to an `rgame_audio` rather than to an app, and
  none of the window-lifetime rules apply. A `sample` is decoded and gets a
  fresh voice per play; a `song` is streamed and has one voice that can be
  stopped and asked about — two types so that `playing?` cannot be asked of a
  fire-and-forget effect. Layer 3, but properly tested (`test/test_audio.c`),
  because miniaudio falls back to a **null device** when no sound system opens:
  the same tests run against PulseAudio on a desktop and against silence in CI.
- `ext/rgame_core/audio/vorbis_decoder.{c,h}` — a miniaudio decoding backend over
  stb_vorbis, because miniaudio reads wav/mp3/flac but **not** Ogg Vorbis, and
  its own reference vorbis backend uses system libvorbis. It needs *both*
  entry points: `onInitFile` for `ma_decoder`, and `onInit` for `ma_engine`,
  which reads through miniaudio's VFS. Covered by
  `test/test_vorbis_decoder.c` against a committed `.ogg`, malformed inputs
  included — it is the only part of the audio stack parsing untrusted bytes.
- `ext/rgame_core/text/font_atlas.c` — the impure quarter of text: it composes
  `font` + `atlas` + `glyph_cache`, owns the atlas pages as `GL_ALPHA` textures,
  and is the only file in the text stack that calls `gl*`. Layer 3, kept thin;
  covered end to end by `spec_core/rgame/core/font_spec.rb`.
- `lib/rgame/fonts/` — the default font (Liberation Sans, SIL OFL 1.1), shipped
  rather than looked up in a system font database. It is runtime data, so it
  lives where a gem installs data rather than in `ext/`. Shipping it is also
  what lets `test/test_font.c` assert real advances instead of fixtures; see
  `docs/plans/gosu-replacement/README.md` for why not to copy Gosu here.
- `ext/rgame_core/graphics/recording.{c,h}` — a block of drawing baked once and
  replayed as one call per texture, which is what makes a tile map affordable.
  Pure; covered by `test/test_recording.c`. It stores no clip on purpose:
  clipping happens at rasterisation, so a rect captured in one place is wrong
  everywhere else the recording is drawn, and pushing one inside a bake is
  refused rather than silently dropped.
- `ext/rgame_core/graphics/gl_backend.{c,h}` — layer 3 for drawing: the real
  `glOrtho`/`glDrawArrays`/`glScissor` calls behind `backend.h`'s table, and
  the only file on the draw path that calls `gl*`. Verified by looking at
  pixels (`rake spec:core`, `make run`), not by unit tests — the call sequence
  itself is already checked against the recording backend.
- `ext/rgame_core/input/gamepad.{c,h}` — the controller shim, and the one place
  `SDL_GameController` appears. Deliberately thin: which player a pad belongs
  to is `device_slots`, what a button id means is `input`, and both are pure.
  Its own correctness is checked end-to-end with an SDL *virtual* controller
  under Xvfb — no hardware needed, see `.claude/skills/verify/`.
- `ext/rgame_core/ruby/` + `extconf.rb` — the Ruby glue and the extension's
  entry point; see `ext/README.md`. This is the only C in the extension that
  includes `ruby.h`: everything above it is engine code that knows nothing
  about Ruby. `core_ext.c` holds `RGame::Core::App`, and every *other*
  Ruby-visible class gets its own file with one init function declared in
  `core_ext.h` (`image_ext.c` is the first), the
  same shape as `ext/rgame_util/util_ext.h` — so adding a class means adding a
  file rather than growing an unrelated one. `audio_ext.c` is the one deliberate
  exception: `Audio`, `Sample` and `Song` share a wrapping shape and are read
  together, so splitting them would triplicate TypedData boilerplate to separate
  ninety lines. `lib/rgame/core/audio.rb` mirrors that, so the two halves stay
  parallel.
- `src/main.c` — thin standalone entry point; only talks to `core.h`'s API,
  never touches SDL/GL directly. This is intentionally what the Ruby
  extension also does, just driven from Ruby instead of a C `main()`. It
  stays *outside* `ext/` so mkmf doesn't compile its `main()` into the
  extension.
- `ext/rgame_util/` — the graphics-free extension (`RGame::Util`). Its
  `extconf.rb` has no `pkg_config` and no `-lGL`, which is what enforces the
  split above. `util_ext.c` is the entry point and does nothing but hand the
  module to each class's init, so adding a class means adding a file rather
  than editing an unrelated one. `Tensor` and `Color` live here, and so does
  any future pure-data/pure-logic code Ruby needs to call. Note `color.{c,h}`
  is pure and has no `ruby.h`, so the Check suite covers it directly — the
  same layer-1 split the engine side uses.
- Both extensions build to a `.so` that `make ext` copies into `lib/rgame/`
  (`core_ext.so`, `util_ext.so`) — the path where `require
  "rgame/core_ext"` / `require "rgame/util_ext"` find them, mirroring how
  rake-compiler installs a compiled ext into `lib/<gem>/`. Naming both under
  `rgame/` in `create_makefile` also leaves the bare name `rgame` to
  `lib/rgame.rb`; don't take it for an extension.
- `lib/` — the pure-Ruby half, currently just namespace loaders:
  `lib/rgame.rb` → `lib/rgame/util.rb` → `lib/rgame/util/tensor.rb`, and
  separately `lib/rgame/core.rb` → `lib/rgame/core/app.rb`,
  `lib/rgame/core/input.rb` and `lib/rgame/core/gamepad.rb`. Each
  leaf is a `require` of the compiled extension plus a comment saying what
  the class is and what moved to C. Keep that pattern — one Ruby file per
  C-backed class — so the load path stays readable and there's an obvious
  place to add pure-Ruby methods to a C-backed class later.
- `spec/` — RSpec specs for the Ruby half (`bundle exec rspec`). Note
  `spec/spec_helper.rb` requires only `lib/rgame`, deliberately: if any core
  file ever reaches for Gosu, the specs fail to load. Preserve that property.
- `docs/c_engine_feature_specs.md` — the feature spec this engine is being
  built out to satisfy (2D primitives to replace Gosu under a Ruby game
  engine). Large surface area, implemented incrementally. Consult it when
  adding a new subsystem rather than guessing scope.

- `rgame.gemspec` — packages both halves as one gem: both `extconf.rb` files in
  `spec.extensions`, so `gem install` compiles each and drops its `.so` into
  `lib/rgame/` exactly where `make ext` puts it. See "Packaging" below.

When adding new engine features, put the implementation in
`ext/rgame_core/app/app.c` and extend
`ext/rgame_core/include/rgame/core.h`'s public API rather than adding
logic to `main.c` — that's what keeps the Ruby wrapper thin. `src/main.c` and
`ext/rgame_core/example.rb` are parallel drivers of the same API; when the
API changes, they generally both need the change.

## Abstraction & testability strategy

`docs/c_engine_feature_specs.md` is a lot of surface area. This is the
standing rule for building all of it, not just advice for one feature —
every new subsystem should be split into three deliberately separate
layers:

1. **Pure logic** — math/state transforms with no SDL, no GL, no I/O:
   transform-stack composition, clip-rect intersection, z-sort/batching,
   tile-grid slicing, glyph atlas packing, the fixed-timestep accumulator's
   catch-up/skip decisions, etc. This is most of what's actually hard to get
   right in a 2D engine, and none of it needs a window to test. Give it its
   own small module (`ext/rgame_core/<area>/<name>.c` + header) and Check
   tests, the same way `ext/rgame_core/app/frame_loop.{c,h}` and
   `device_slots.{c,h}` are covered by `test/test_frame_loop.c` and
   `test/test_device_slots.c` today. Each test file exposes a Check `Suite`
   declared in `test/suites.h`; `test/test_main.c` runs them all as one binary,
   so a new module adds a file and two lines rather than another `main()`. If the logic is also useful from Ruby on its
   own, `ext/rgame_util/` is where it belongs instead — same reasoning, one
   level up.
2. **Fake/recording backend** — once a subsystem's logic drives real SDL/GL/
   audio calls, put a small function-pointer table ("backend" struct)
   between the pure logic and the real implementation, so tests can link a
   fake backend that just records calls (e.g. `draw_textured_quad(x, y,
   ...)` appended to an array) instead of hitting SDL/GL. This is what makes
   it possible to verify "the right primitive calls happened in the right
   order" — for a human or an agent — with no display involved at all. Add
   this seam *when* a subsystem starts producing real SDL/GL calls, not
   speculatively ahead of that.
3. **Thin real shim** — the actual `SDL_*`/`gl*`/audio-device calls. Keep
   these as dumb as possible: take already-computed values from layer 1 and
   issue the corresponding call. Being this thin means there's little logic
   left in it to get wrong, which is what justifies not unit-testing it
   directly — see the verification tiers below.

Default order when implementing a spec item: write layer 1 and its Check
tests first, before touching SDL/GL at all.

## Build

Plain Makefile for the C (written to mirror what `mkmf` emits, so the mental
model carries over), with targets that shell out to the mkmf-generated
Makefiles for the extensions:

```
make              # builds build/rgame (standalone C binary)
make run          # build + run
make test         # build + run the Check unit tests
make ext          # build both extensions
make ext-core # ext/rgame_core -> lib/rgame/core_ext.so
make ext-util     # ext/rgame_util     -> lib/rgame/util_ext.so
make clean        # includes ext-clean
```

`make ext-util` is a prerequisite for `rake spec` — `lib/` requires the
compiled `rgame/util_ext`, so those specs can't even load without it.
`make ext-core` is a prerequisite for `rake spec:core`.

Ruby-side tasks come from the `Rakefile`:

```
rake spec         # headless: RGame::Util + RGame::Engine, no SDL in the process
rake spec:core    # RGame::Core; opens real windows, boots its own Xvfb
rake build        # package the gem into pkg/ (from bundler/gem_tasks)
rake              # make test, then both suites
``` Ruby is
4.0.5, pinned in `.ruby-version` and installed via mise. Requirements are
listed in README.md.

## Packaging

`rgame.gemspec` ships both halves as one gem. Both `extconf.rb` files are in
`spec.extensions`, so `gem install` compiles each one and lands its `.so` in
`lib/rgame/` — the same place `make ext` puts it, which is why nothing about
the load path changes between a checkout and an installed gem.

**`spec.files` is a glob over whole directories, never a list.** Anything the
installed gem compiles from or reads at runtime — a new `.c`, a font, any data
file — must ship, and the failure mode when it doesn't is invisible locally: the
checkout still has the file, so it only breaks on someone else's machine, at
`require` time or at the first call that reads it. Dropping a file under `lib/`
or `ext/` is therefore enough to get it packaged, by design. Do not replace the
glob with an enumeration, and do not keep a "remember to add it to the gemspec"
checklist — that is exactly the remembered rule "Design out misuse" rejects.

`spec/packaging_spec.rb` is what makes that safe rather than merely intended. It
re-derives what must ship from the directory tree and asserts it against the
gemspec's own derivation, in both directions: every C source and header, every
`extconf.rb`, everything under `lib/` including non-Ruby data, the vendored
sources and their licences — and, the other way, that no build artifact, spec
directory or plan is in the gem. If the two derivations ever disagree, one of
them is wrong and the suite says which file.

Two exclusions are deliberate and both are asserted:

- **build artifacts** (`lib/rgame/*.so` and friends) — that is *this* machine's
  binary, and shipping it would shadow the one `gem install` compiles.
- **`lib/platform/`** — the Gosu-backed code from the game this engine came out
  of, still in use in the checkout. It could not work in the gem anyway: gosu is
  not a dependency. When it goes, the exclusion in `rgame.gemspec` and the
  matching expectation in the packaging spec go with it.

The version lives in `lib/rgame/version.rb` and nothing else may go in that
file: the gemspec loads it directly, long before either extension is compiled,
so a require reaching for `rgame/util_ext` there would break `gem build`.

## Testing

Uses [Check](https://libcheck.github.io/check/), a C xUnit-style framework
(each test runs in its own forked process, so a segfault only fails that
test rather than aborting the whole suite — relevant given how easy it is
to crash while learning pointers/SDL/GL).

**Verification tiers**, matching the layers above:

- `make test` — Check suite covering layer 1 (pure logic) and layer 2 (fake
  backends: assert on recorded calls, no display involved). Fast,
  deterministic, expected to pass for every change.
- `rake spec` — the **headless** RSpec suite in `spec/`, covering
  `RGame::Util`, `RGame::Engine` and what the gem packages
  (`spec/packaging_spec.rb`; see "Packaging"). Fast, deterministic, no display,
  no SDL in the process at all. Requires `make ext-util` first. Expected to pass
  for every change.
- `rake spec:core` — the RSpec suite in `spec_core/`, covering
  `RGame::Core`'s Ruby-visible surface: the App lifecycle, `Input`'s binding
  table, hot-plug. Requires `make ext-core`, and boots its own Xvfb, so it
  needs no display of its own either. Slower — it opens real windows.
- `make run` / `ruby ext/rgame_core/example.rb` — manual verification of
  layer 3 from C and from Ruby respectively. Subjective/visual, run by a
  human, not automated.

`rake` with no argument runs everything: `make test`, `rake spec`,
`rake spec:core`.

### Why the Ruby specs are two suites, in two directories

They are two *processes*, and that is the entire point. RSpec loads everything
under its root into one process, so a single `require "rgame/core"` anywhere
would define `RGame::Core` for every other example in the run — and the
engine layer's guarantee (that it cannot even name Core) would silently
evaporate. An `exclude_pattern` would technically work and is exactly the kind
of rule someone forgets; separate directories with separate runners cannot be
forgotten. See "Design out misuse" above.

So:

| | `spec/` | `spec_core/` |
|---|---|---|
| Runner | `rake spec` | `rake spec:core` |
| Covers | `RGame::Util`, `RGame::Engine` | `RGame::Core` |
| Loads | `require "rgame"` only | `require "rgame/core"` |
| SDL in process | **never** | yes |
| Display | none | its own Xvfb |
| Needs | `make ext-util` | `make ext-core` |

`RGame::Core` used to be untested here because Gosu sat in that position and
was covered by its own gem. Replacing Gosu made it ours to test, which is why
`spec_core/` exists at all.

### Fakes must be checked against the same contract as the real thing

The engine layer only ever calls a renderer (or audio server, or input
backend) by method name, so every such interface has at least two
implementations: the real `RGame::Core` one and the recording fake that
headless specs substitute. If the fake drifts from the real one, `rake spec`
stays green while the game no longer runs — the classic failure of this
pattern, and the one thing the split cannot catch by itself.

So each of those interfaces gets a **shared example group** in
`spec/support/`, and both implementations are run against it: the fake from
`spec/`, the real one from `spec_core/`. A method added to the real renderer
is not done until the shared contract and the fake have it too.

There are two of these today, both built the same way:

| | Renderer | Audio |
|---|---|---|
| Contract | `spec/support/shared_examples/a_renderer.rb` | `spec/support/shared_examples/an_audio_server.rb` |
| Fake | `spec/support/fake_renderer.rb`, run against it by `fake_renderer_spec.rb` | `spec/support/fake_audio.rb`, run against it by `fake_audio_spec.rb` |
| Real | `RGame::Core::Renderer`, run against it by `spec_core/rgame/core/renderer_spec.rb` | `RGame::Core::Audio`, run against it by `spec_core/rgame/core/audio_spec.rb` |
| Host hook | `render { \|renderer, image, font\| ... }` | `with_audio { \|audio, sound_path\| ... }` |

`spec_core/core_spec_helper.rb` requires the contracts across the directory
boundary. That is the *only* thing that crosses: no `spec/` example file is
loaded there, and nothing in `spec/` ever names Core.

A contract states the method list and its argument shapes; it cannot state
pixels or samples, because the fake produces neither. That is why
`renderer_spec.rb` also reads the framebuffer back, and why the audio output
tier is `test/test_audio.c` reading an offline device — the two halves together
are the guarantee.

The audio contract also shows what a contract must *leave out*: whether a sound
has finished. Playback runs against a clock in both implementations, so
"is it still playing a moment later" has no stable answer, and only the
transitions a caller controls are stated.

### A fake must refuse what the real thing refuses

The rule above is about methods that exist. This one is about the calls that
must **fail**, and it is the half that is easy to miss — a fake is written by
listing what a caller does, and a caller does not ordinarily pass `nil`.

> **A fake that only ever says yes tests nothing about the paths that exist
> because the real one says no.**

The failure is specific and nasty: a guard is written in the real code *because*
the real thing raises, a spec is written against the fake, the spec passes
whether or not the guard is there, and the mutation that deletes the guard
survives. That is exactly how it was found — a `NineSlice` guard against
zero-size sub-images looked untested because `StubImage#subimage` accepted what
`Image#subimage` rejects.

So, whenever a fake is written or a real method grows a `raise`:

1. **Compare them by running them.** Call the same bad input on both and diff
   the exception classes. Reading the code finds the refusals you remembered to
   write; running it finds the ones you did not. Doing this over the renderer
   and audio surfaces turned up **ten** differences, one of which was a
   *segfault* in the real code (`renderer.text(nil, …)` reached `RSTRING_PTR`
   without a type check).
2. **Put the refusal in the contract, not just in the fake.** A patched fake
   drifts again; a contract example runs against both. `spec/support/shared_examples/`
   has an "arguments it refuses" section for exactly this.
3. **Match on argument-shape refusals; document the rest.** A fake can check
   that a coordinate is a number and a label is a String — the real ones cross
   into C through `NUM2DBL` and `StringValue`, which raise `TypeError`. It
   cannot check that a file exists or that an image belongs to this app. Where
   it cannot, say so at the code and name the tier that does cover it. Two
   worked examples: `FakeRenderer#image_arg` refuses only `nil`, because a fake
   never looks at an image; `FakeRecording` documents that it does not refuse
   `.new` the way the real `Recording` does, because no scene ever calls it.
4. **Validate without converting.** The real binding converts (`NUM2DBL`); the
   fake should check and then record what the caller actually passed, so
   assertions read as written. Where a coercion is pure Ruby — colours go
   through `RGame::Util::Color.coerce` — the fake calls *the same function*,
   which is better than matching its behaviour.

`spec_core/support/stub_image.rb` is the smallest example of all of this: it
refuses exactly what `RGame::Core::Image#subimage` refuses, with the same
message, and says in its own comment why that matters.

### Platform support

The automated tiers are Linux-first today. `make test` is portable; the
headless `rake spec` suite is portable (it is pure Ruby with no display); the
parts that are not are in `rake spec:core`:

- **Xvfb is X11, so Linux/BSD only.** It is also only *needed* there: macOS and
  Windows CI runners have a real window server, so Core specs can open windows
  directly without it. The spec helper picks a display strategy per platform.
- **Synthetic keyboard input via XTEST is X11 only.** The macOS equivalent is
  Quartz `CGEvent` (and needs accessibility permission); on Windows it is
  `SendInput`. Until one of those is written, keyboard-driven Core specs skip
  themselves off Linux rather than fail.
- **Virtual gamepads are already portable** — `SDL_JoystickAttachVirtual` is
  SDL-level, not OS-level, so those specs work anywhere SDL does.

## Conventions

- C17, `-Wall -Wextra`, keep it warning-clean. The extensions compile with
  `-std=gnu17` instead — Ruby's headers lean on GNU extensions, and gnu17 is a
  superset, so the same sources still satisfy C17.
- No OpenGL loader (GLAD/GLEW) yet — using legacy/compatibility-profile GL
  calls (`glBegin`/`glEnd`) since that's what's available without extra
  dependencies. If/when the project moves to core-profile modern GL, a
  loader will need to be added — flag that as a deliberate decision, not a
  drive-by change.
- Ruby: `# frozen_string_literal: true` at the top of every file, single
  quotes, RuboCop (+ `-performance`, `-rspec`) via the `Gemfile`. Configured in
  `.rubocop.yml`, which also loads the project's own cops from
  `rubocop/cop/game/` — see the RuboCop section above.
- `gosu` is in the `Gemfile` but intentionally unused — it's the library being
  replaced (`docs/c_engine_feature_specs.md`), kept as the reference point. No
  file under `lib/`, `spec/`, or `ext/` may require it.
