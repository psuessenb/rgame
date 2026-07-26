# 02 — Target architecture

Where everything ends up, and why. The ordering to build it in is
[03](03-roadmap.md).

---

## Namespace and file layout

```
ext/rgame_core/                 RGame::Core — links SDL2 + OpenGL (+ audio)
  include/rgame/core.h          the public C API (opaque handles, no SDL/GL types)
  app.c                         window, GL context, main loop, event pump
  frame_loop.{c,h}              [pure] fixed-timestep accumulator + FPS counter
  input.{c,h}                   keyboard/mouse snapshot, key constants
  color.{c,h}                   [pure] RGBA packing
  transform.{c,h}               [pure] 2D affine transform stack
  clip.{c,h}                    [pure] clip-rect stack + intersection
  draw_queue.{c,h}              [pure] z-sorted, batched draw-call list
  backend.h                     the function-pointer seam (layer 2)
  gl_backend.c                  the real GL implementation (layer 3)
  texture.{c,h}                 PNG decode + upload; subimage views; tile grids
  font.{c,h}                    glyph atlas + measurement
  audio.{c,h}                   samples + streaming music
  core_ext.c                    the ONLY file that includes ruby.h
  extconf.rb
  example.rb

ext/rgame_util/                 RGame::Util — links nothing but Ruby (unchanged)

lib/rgame.rb                    require "rgame"      → Util only, no SDL/GL
lib/rgame/core.rb               require "rgame/core" → opt-in, pulls SDL/GL
lib/rgame/core/app.rb           C-backed
lib/rgame/core/input.rb         C-backed + Ruby binding table
lib/rgame/core/renderer.rb      Ruby, delegating to C primitives
lib/rgame/core/sprite_sheet.rb  Ruby
lib/rgame/core/nine_slice.rb    Ruby façade over C tiling
lib/rgame/core/ui_atlas.rb      Ruby
lib/rgame/core/tile_map_renderer.rb  Ruby façade over a C tile layer
lib/rgame/core/asset_manager.rb Ruby (unchanged logic)
lib/rgame/core/audio.rb         Ruby registry over C handles
```

`[pure]` marks layer-1 modules: no SDL, no GL, no I/O, covered by Check tests
in `test/`. That is most of the interesting code.

One naming snag to settle in phase 0: the directory is `rgame_core`, the public
header is `rgame/core.h`, the extension entry point is `Init_core_ext` in
`core_ext.c`, and the engine implementation is currently `core.c`. Three
different "core"s. **Rename the engine implementation to `app.c`** — it is the
app/window/loop file, `core.h` stays the name of the public API, `core_ext.c`
stays the Ruby glue. Reader confusion avoided for the price of one `git mv`.

---

## `App`/window

`RGame::Core::App` becomes subclassable, matching what `GameWindow` expects
from `Gosu::Window`:

```ruby
class GameWindow < RGame::Core::App
  def initialize(width:, height:, caption:, root:, renderer:, mapper:)
    super(width: width, height: height, caption: caption)
    ...
  end

  def update(dt); end      # called once per fixed simulation tick
  def draw; end            # called once per rendered frame
  def needs_redraw?; end   # polled before draw
  def button_down(id); end # discrete key/mouse press
  def button_up(id); end   # discrete release

  # inherited, C-backed:
  #   #run, #close, #width, #height, #caption=, #ticks_ms, #fps
end
```

The proc-passing `app.run(update, draw, needs_redraw)` form goes away. The C
trampolines call `rb_funcall(self, id_update, ...)` instead of reading procs out
of ivars. Default no-op implementations are defined in C (or in
`lib/rgame/core/app.rb`) so a subclass only overrides what it cares about.

### Who owns the fixed-timestep accumulator

There is a genuine tension here worth naming. `docs/c_engine_feature_specs.md`
§1 says *"the accumulator logic itself stays on the engine side of the
boundary"* — i.e. in Ruby, which is how `GameWindow` does it today. But
`frame_loop.c` already implements it in C, with Check tests, and it is
currently what drives `rgame_app_run`.

**Recommendation: keep the accumulator in C.** Reasons:

- It already exists, and it is the best-tested code in the project.
- It makes `update(dt)` mean "one fixed tick", which is simpler than
  `GameWindow#update`'s "figure out how many ticks are due and loop".
- `@dirty` falls out for free: if `update` was called at all, a step ran, so
  `@dirty = true` in `update` reproduces `steps.positive?` exactly.
- The spec's concern is that the *game* shouldn't see variable frame time. That
  holds either way.

`Platform::Clock` disappears as a consequence.

The one thing this loses is `GameWindow`'s "poll input once per frame, reuse
across catch-up steps". Two ways to get it back:

### Input is snapshotted per frame

**Recommended:** make the C input layer snapshot keyboard/mouse state once per
frame, at event-pump time, and have every `down?` read the snapshot. Then
calling `@mapper.poll(@backend)` inside `update` returns identical results for
every catch-up step of the same frame — the property is preserved by
construction rather than by Ruby-side caching, and `SDL_GetKeyboardState`
already works exactly this way.

**Also add**, because it is nearly free and exactly matches the existing code
shape: an optional `#frame_begin` hook called once per frame *before* the tick
batch. That is the natural home for `actions = @mapper.poll(@backend)`, and it
keeps the poll at once-per-frame instead of once-per-tick.

This is the one place where the ported `GameWindow` will not be a
line-for-line translation, so it is flagged rather than done quietly.

### Events

`core.h` gains fixed-arity event callbacks:

```c
typedef void (*rgame_button_fn)(void *userdata, int button_id);
typedef void (*rgame_resize_fn)(void *userdata, int width, int height);
```

and `rgame_app_close(rgame_app *)`, `rgame_app_width/height`,
`rgame_app_set_title`. The Escape-quit hardcoded in `rgame_app_poll_events`
comes out — Ruby's `button_down` decides that.

Fixed arity throughout, per feature spec §4. Not negotiable, and cheap to just
keep doing.

### Exception safety

Phase 1 is where the deferred `rb_protect` work in `platform_ext.c` stops being
deferrable. Once a Ruby callback does real work it will eventually raise, and a
raise currently longjmps through `rgame_app_run`'s C frame, leaking the SDL
window until GC. Each trampoline runs its callback under `rb_protect`, stores
the exception, tells the loop to stop, and `#run` re-raises after
`rgame_app_run` returns cleanly. This mirrors what Gosu's `protected_*`
wrappers were doing — including the part `gosu_patches.rb` faithfully preserved.

---

## The renderer

This is the substantial part. Built in four stacked pieces, three of which
never touch OpenGL.

### The draw queue

**The single most important design point in the rewrite.** Gosu's contract is:
every draw call carries a `z`, and the renderer sorts all calls by `z`
regardless of call order. The engine depends on this everywhere — UI above
gameplay, overlays above UI — and does no draw-order bookkeeping of its own.

The current `glEnable(GL_DEPTH_TEST)` does *not* provide this. Depth testing
and alpha blending are incompatible: a depth-tested translucent quad rejects
the fragments behind it rather than blending with them, so anything drawn later
at a lower z simply vanishes. Every UI panel in this engine is translucent
chrome over gameplay.

So: `draw_queue.{c,h}` accumulates draw commands during a frame and flushes
them at frame end:

- Append a command: `{ z, texture_id, 4 vertices (x, y, u, v, rgba) }`.
- **Stable** sort by `z` at flush. Stability matters — Gosu breaks z ties by
  call order, and so must this, or same-z sprites will flicker between frames.
- Batch adjacent commands that share a texture and a clip rect into one
  `glDrawArrays`.

This is 100% pure arithmetic on plain structs. It gets Check tests before a
single GL call is written: "commands come out z-ascending", "equal z keeps
insertion order", "three consecutive same-texture quads collapse to one batch",
"a clip change splits a batch". Feature spec §4's batching ask —
"draw N textured quads from a packed list in one native call" — is not a
separate feature; it is what this structure does by default.

### Transform and clip stacks

`transform.{c,h}`: a stack of 2D affine matrices (6 floats). Push
translate/rotate-about-pivot/scale, each composing with the current top; pop
restores. Vertices are transformed by the current top *at append time*, so the
transform never has to be replayed at flush and z-sorting can freely reorder
commands. Pure; Check-tested (compose translate∘rotate and check a known point,
pop restores exactly, identity push is a no-op).

`clip.{c,h}`: a stack of rects, each pushed rect intersected with the current
top, empty-intersection short-circuiting to "draw nothing". Pure;
Check-testable in about ten lines.

Together these cover the feature spec's split-screen requirement — "several
concurrent clip+transform regions composed and torn down within a single frame"
is just push/pop used twice — and they are what `NineSlice`'s tiling, the
camera, and `Renderer#rotated`/`#translated` all sit on.

### The backend seam

Per CLAUDE.md's layer 2, added *when* the first real GL calls appear and not
before: a `rgame_draw_backend` struct of function pointers —
`upload_texture`, `draw_batch`, `set_clip`, `begin_frame`, `end_frame`. Tests
link a recording fake that appends each call to an array; assertions read
"these batches, in this order, with these vertices". That is how "the right
primitive calls happened in the right order" gets verified with no display
anywhere in sight.

### The GL shim

Thin by construction: take an already-built vertex array from the queue and
issue the call.

**Decision to make deliberately (CLAUDE.md asks for exactly this):** the
project currently uses legacy immediate mode (`glBegin`/`glEnd`) with no
loader. Immediate mode cannot batch — it is one call per vertex. The
recommendation is **client-side vertex arrays**: `glVertexPointer` /
`glTexCoordPointer` / `glColorPointer` + `glDrawArrays`. These are GL 1.1
compatibility-profile functions, available with no loader (no GLAD/GLEW), and
they give real per-batch draws. Moving to core-profile modern GL with VBOs and
shaders is a bigger step that needs a loader and is not required by anything in
the feature spec (no shaders, no materials, no lighting, no 3D). Deferred, and
flagged as a decision rather than drifted into.

### Textures

`texture.{c,h}`. PNG decode via `stb_image.h` (single-header, public domain, no
new system dependency), upload with `GL_NEAREST` filtering — the feature spec
says nearest is the *only* sampling mode needed, so there is no filtered path
to build.

A "subimage" is a **view**: the same GL texture id plus a UV sub-rect. No
re-decode, no re-upload, and `Image#subimage` on a subimage composes rects.
`load_tiles` slices a grid of such views in one call. All of that rect
arithmetic is pure and Check-tested; only the decode+upload touches GL.

### Text

`font.{c,h}`. `stb_truetype.h` (same rationale as `stb_image`) rasterising into
a glyph atlas texture. Cache **per glyph**, not per string — feature spec §2 is
explicit, and the reason is in `gosu_renderer.rb:113-117`: an engine draws many
short-lived changing strings (scores, timers), so a per-glyph cache stays
bounded by the character set while a per-string cache grows forever.

Pure and testable: glyph-atlas packing, cache lookup/eviction, string width
from summed advances, line height from font metrics. Only rasterisation and
upload are impure. Note the open question about a default font in
[the brief](README.md#open-questions).

### Record / render-to-texture

Two distinct Gosu features, both needed:

- `Gosu.record(w, h) { }` → a **retained batch**: capture the queue commands
  produced by the block, keep the vertex array, replay it later as one draw
  (offset by the current transform). Used to bake static tile-map layers.
- `Gosu.render(w, h) { }` → **render to texture** via an FBO, returning a real
  texture. Used to bake the unit-circle image once at startup.

With a batching renderer, `record` is nearly free to implement — it is the
draw queue with a different flush target. `render` needs an FBO, which is the
one place the GL version floor might rise (FBOs are GL 3.0 / `EXT_framebuffer_object`);
worth checking against the target GL version when it lands.

Note that `NineSlice` pushes a clip **inside** what `TileMapRenderer` records,
so the record design must handle a clip stack inside a recording. Gosu's
recorded images also draw white-only (no tint) — a limitation this rewrite has
no reason to reproduce, and `tile_map_renderer.rb:11` documents having worked
around it.

---

## Audio

`RGame::Core::Sample` and `RGame::Core::Song` as C handles; the play-by-id
registry stays in Ruby as `RGame::Core::Audio` (ex-`GosuAudio`), unchanged
except for what it wraps.

Fully independent of the renderer — it can be built at any point after phase 1,
including in parallel.

`stop_music` currently reaches for a Gosu global (`Gosu::Song.current_song`).
Simpler here: let the Ruby `Audio` class remember the handle it started. That
drops a global from the C API for free.

---

## The C-vs-Ruby split, class by class

The rule is: **C for per-frame work and for anything that needs a GL/SDL
handle; Ruby for load-time bookkeeping and configuration.** Where a class is
both, the Ruby half stays as a thin façade over a C hot path.

| Today | Becomes | Where | Why |
|---|---|---|---|
| `GameWindow` | `Core::App` | **C**, subclassed in Ruby | Owns the loop, the window, the event pump |
| `Clock` | — | **deleted** | The C loop already measures elapsed time |
| `gosu_patches.rb` | — | **deleted** | Fixed-arity callbacks by construction |
| `GosuInput` | `Core::Input` | **C** mechanism + **Ruby** binding table | `down?`/`pointer_x` are per-frame; `BINDINGS` is config and reads better in Ruby |
| `GosuRenderer` | `Core::Renderer` | **Ruby** façade over C primitives | The id registry is bookkeeping; primitives are C. Revisit if the per-draw hash lookup shows up in a profile |
| `SpriteSheet` | `Core::SpriteSheet` | **Ruby** | JSON parse at load time; `#draw` is an array index plus one C call |
| `NineSlice` | `Core::NineSlice` | **Ruby** façade, **C** tiling | Five clipped tiling loops per call per frame — the clearest C win in the Ruby layer |
| `UiAtlas` | `Core::UiAtlas` | **Ruby** | Pure config parsing, load time only |
| `TileMapRenderer` | `Core::TileMapRenderer` | **Ruby** façade, **C** tile layer | Per-visible-animated-tile loop every frame; feature spec §4's named sore point. TMX/TSX parsing stays Ruby |
| `AssetManager` | `Core::AssetManager` | **Ruby**, logic unchanged | Load-time caching and refcounting; nothing to gain in C |
| `GosuAudio` | `Core::Audio` | **Ruby** registry over **C** handles | A hash lookup and a play call |
| — | `Core::Color` | **C** | Every draw call takes one; pack to a uint32 |
| — | `Core::Image` | **C** | GL texture handle |
| — | `Core::Font` | **C** | Glyph atlas |

Two of these are "keep in Ruby *for now*" rather than settled: `Renderer`'s
registry lookups and `SpriteSheet#draw` are both a hash/array lookup on a
per-draw path. Both are easy to move later and neither should be moved
speculatively.
