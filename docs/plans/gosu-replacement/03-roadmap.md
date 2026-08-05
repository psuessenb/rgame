# 03 — Roadmap

Detailed for phases 0–5. Phases 6–7 stay deliberately rough: they get
re-planned once the layer beneath them exists and the shape of the problem is
concrete rather than imagined. That is what happened to phase 3 — re-written
from eight bullets into nine landable steps once phase 2 was done and the GL
situation had been measured rather than assumed — and to phase 4, which stayed
one paragraph until the default-font question had been answered by reading
Gosu's sources instead of guessing at them — and to phase 5, which was a
recommendation for the wrong library until six other engines had been read and
both alternatives built.

**Phases 0–3 are implemented.** Each of their steps carries a "Landed" note
recording how the result differed from the sketch; those notes are the useful
part to read before starting the next step, because most of them are decisions
the sketch got wrong.

Throughout: **layer 1 (pure logic + Check tests) before layer 3 (real SDL/GL)**,
per CLAUDE.md. The recurring temptation in a graphics rewrite is to open a
window first and see something on screen; resisting that is what makes the hard
parts (z ordering, transform composition, clip intersection) testable at all.

Dependency shape, so the ordering rationale is visible:

```
0 rename ─→ 1 App ─→ 2 Input + gamepads ──┐
                └──→ 3 Renderer ─→ 4 Text ─┴→ 6 Port ─→ 7 Optimise
                └──→ 5 Audio ──────────────┘
```

Phase 5 (audio) touches nothing the renderer touches and can be slotted in
wherever it is convenient.

Two things are **extensions**, not ports, and are scheduled early on purpose
because both change the shape of code written before them (see
[the brief](README.md#gamepads-and-split-screen-are-in-scope--this-is-an-extension-not-just-a-port)):
**gamepad support is part of phase 2**, and **split-screen is a stated
requirement on phase 3's transform/clip design** even though no Ruby scene uses
it yet.

One thing is deliberately **removed**: mouse input is not ported at all
([why](README.md#mouse-input-is-not-carried-over)). Phases 1 and 2 below simply
never mention it, which is the point.

---

## Phase 0 — Rename `Platform` → `Core`

Mechanical, no behaviour change, done first so nothing later has to be written
twice. Land it as one commit.

1. `git mv ext/rgame_platform ext/rgame_core`
2. `git mv ext/rgame_core/platform_ext.c ext/rgame_core/core_ext.c`;
   `Init_platform_ext` → `Init_core_ext`
3. `git mv ext/rgame_core/core.c ext/rgame_core/app.c` — see the three-way
   "core" name collision in [02](02-architecture.md#namespace-and-file-layout).
   `include/rgame/core.h` keeps its name.
4. `create_makefile("rgame/platform_ext")` → `create_makefile("rgame/core_ext")`
5. `rb_define_module_under(mRGame, "Platform")` → `"Core"`
6. `lib/rgame/platform.rb` → `lib/rgame/core.rb`; `lib/rgame/platform/app.rb` →
   `lib/rgame/core/app.rb`
7. Makefile: `EXT_PLATFORM_DIR`/`ext-platform`/`platform_ext.so` →
   `EXT_CORE_DIR`/`ext-core`/`core_ext.so`. Keep `ext-util` untouched.
8. `example.rb`, `src/main.c` include paths and the `RGame::Platform::App`
   reference
9. Prose: `README.md`, `ext/README.md`, `CLAUDE.md` (the whole "Platform / Util
   split" section, including the zero-graphics check command)

**Verify:** `make && make test && make ext && bundle exec rspec`, plus the
zero-graphics check with the new name:

```
ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
# => []
```

and `ruby ext/rgame_core/example.rb` still opens a window.

---

## Phase 1 — `App` becomes `GameWindow`-shaped

The prerequisite for everything: until `App` is subclassable with the right
callbacks, no ported class has anywhere to live.

### 1.1 Extend the C API (`include/rgame/core.h`)

```c
/* window queries + control */
int  rgame_app_width(const rgame_app *app);
int  rgame_app_height(const rgame_app *app);
void rgame_app_set_title(rgame_app *app, const char *title);
void rgame_app_close(rgame_app *app);   /* stops the loop; safe from a callback */

/* new fixed-arity callbacks (fixed arity is a hard rule — feature spec §4) */
typedef void (*rgame_frame_begin_fn)(void *userdata);
typedef void (*rgame_button_fn)(void *userdata, int button_id);
typedef void (*rgame_resize_fn)(void *userdata, int width, int height);
```

The growing callback count argues for grouping them into a
`rgame_app_callbacks` struct passed once to `rgame_app_run`, rather than seven
positional parameters. Do that now while there are only a handful — phase 2
adds two more for controller hot-plug.

The accumulator stays where it is. `rgame_app_run` keeps driving
`frame_loop.c` and keeps calling `update` once per fixed tick; there is nothing
to move, and `frame_loop.{c,h}` and its Check tests are untouched by this whole
phase. See [the brief](README.md#the-fixed-timestep-accumulator-lives-in-c).

### 1.2 Fix `app.c`

- **Remove the hardcoded Escape-quit** (`core.c:87` today). Escape-to-quit is
  game policy; it moves to a Ruby `button_down` override, which is where
  `GameWindow` has it. `SDL_QUIT` (window close button) stays in C — that one
  really is the platform's.
- Emit `button_down`/`button_up` from `SDL_KEYDOWN`/`SDL_KEYUP`. Ignore key
  repeats (`event.key.repeat`) — a discrete press must fire once. No mouse
  events; `SDL_MOUSE*` is not handled.
- Call `frame_begin` once per frame, before the tick batch.
- Keep `glViewport` on resize, but also emit the resize callback.

### 1.3 Rewrite the Ruby glue (`core_ext.c`)

- `App.new(width:, height:, caption:)` — keyword arguments, matching
  `GameWindow.new`. (Today's `App.new(w, h, title)` is positional.)
- Trampolines call `rb_funcall(self, id_update, 1, DBL2NUM(dt))` instead of
  reading procs from ivars. `self` is already passed as `userdata`.
- **Run every trampoline under `rb_protect`.** On a caught exception: stash it,
  call `rgame_app_close`, let `rgame_app_run` return normally, then re-raise
  from `#run`. This closes the known limitation documented at
  `platform_ext.c:100-106` — which explicitly deferred the fix "until the
  callbacks actually do real work", i.e. until now.
- Define no-op defaults for `update`/`draw`/`needs_redraw?` (returns true)/
  `button_down`/`button_up`/`frame_begin`/`resize`, so a subclass overrides only
  what it needs.
- Expose `#close`, `#width`, `#height`, `#caption=`, keep `#ticks_ms`, `#fps`.

### 1.4 Delete `Clock`

Nothing calls it once the accumulator stays in C. `App#ticks_ms` covers the
animation-phase use.

### 1.5 Keep the two drivers in step

`src/main.c` and `ext/rgame_core/example.rb` are parallel drivers of the same
API and both need the callback-struct change. `example.rb` becomes a subclass:

```ruby
class Example < RGame::Core::App
  def initialize = super(width: 800, height: 600, caption: 'rgame via Ruby')
  def draw = @frames = (@frames || 0) + 1
  def button_down(id) = close if id == RGame::Core::Input::KEY_ESCAPE
end
```

(the `KEY_ESCAPE` constant arrives in phase 2; until then, close on window
close only.)

**Verify:** `make test` still green (`frame_loop.c` is untouched); `make run`
and `ruby ext/rgame_core/example.rb` both open a window and quit cleanly;
a callback that raises produces a Ruby backtrace and a closed window rather than
a hang or a leak.

---

## Phase 2 — Input, keyboard and controllers

Self-contained, and it unblocks writing a real `example.rb` that responds to
input. Bigger than a straight port, because this is where the layer gets
extended: **gamepads are part of this phase, not a follow-up**, and **mouse
support is dropped**.

Doing controllers here rather than later is the whole point. The device
dimension has to be in `down?`'s signature from the first call site, or every
caller gets touched twice.

### 2.1 `device_slots.{c,h}` — pure, and first

Before any SDL: the player-slot table. A fixed 4-slot array, each slot holding
the joystick GUID that last filled it. On connect, a pad reclaims the slot
matching its GUID, else takes the lowest free one; on disconnect the slot
empties but keeps the GUID. That is what makes the feature spec's "indices
stable across a momentary disconnect/reconnect" true, and SDL gives none of it
for free — its joystick indices renumber on every device change.

Pure integer/byte bookkeeping, no SDL, so it is layer 1 with Check tests:

- reconnecting the same pad reclaims its previous slot
- a *different* pad takes a free slot rather than stealing a remembered one
- slots fill lowest-first
- a fifth pad is rejected without disturbing the four

Writing this before touching `SDL_GameController` is far easier than verifying
it by plugging controllers in and out by hand.

### 2.2 `input.{c,h}` — the button-id space and the keyboard snapshot

- Snapshot `SDL_GetKeyboardState` once per frame at event-pump time. Reading a
  snapshot rather than live state is what gives `GameWindow`'s "poll once, reuse
  across catch-up steps" property for free — see
  [02](02-architecture.md#input-is-snapshotted-per-frame).
- One flat button-id space in ranges, so later devices never renumber what
  exists: `0x0000–0x0FFF` keyboard scancodes, `0x1000–0x10FF` controller
  buttons and dpad. (The range mouse buttons would have occupied stays unused.)
- `int rgame_input_down(const rgame_app*, int device, int button_id)`.

**Already in place from phase 1.** The keyboard half of that id space exists:
`button_down`/`button_up` deliver SDL scancodes today, and `core.h` defines
`RGAME_KEY_ESCAPE` / `RGAME_KEY_F1`, each backed by a `_Static_assert` in
`app.c` against the SDL constant it mirrors. That was forced rather than
planned — `src/main.c` includes only `core.h`, so it cannot name a key without
the header defining it. Phase 2 therefore *extends* that set and adds the
`0x1000+` controller range; it does not introduce the scheme. Copy the
`_Static_assert` pattern for every new key id.

### 2.3 `gamepad.{c,h}` — the thin real shim

`SDL_INIT_GAMECONTROLLER`, `SDL_GameControllerOpen`/`Close` driven by
`SDL_CONTROLLERDEVICEADDED`/`REMOVED` through the slot table from 2.1, plus
`GetButton` / `GetAxis` snapshotted per frame alongside the keyboard, and a name
string per slot for "Player 2: connect a controller" UI.

Two new fixed-arity callbacks on the app: `gamepad_connected(slot)` /
`gamepad_disconnected(slot)`.

Deliberately dumb — all the decisions live in 2.1.

### 2.4 `RGame::Core::Input` (C) + `lib/rgame/core/input.rb`

C exposes the constants (`KEY_LEFT`, `KEY_RETURN`, `KEY_SPACE`, `KEY_ESCAPE`,
`KEY_F1`, `PAD_A`, `PAD_DPAD_LEFT`, …) and the raw queries. Ruby keeps the
binding table, because it is *configuration* — which physical input means
`:fire` — and reads far better as a Ruby hash than as a C table:

```ruby
KEYBOARD = { left: KEY_LEFT, right: KEY_RIGHT, up: KEY_UP, down: KEY_DOWN,
             confirm: KEY_RETURN, fire: KEY_SPACE }.freeze
PAD      = { left: PAD_DPAD_LEFT, ..., confirm: PAD_A, fire: PAD_A }.freeze

def down?(physical_id, device: 0) = ...
def axis(physical_id, device: 0) = ...   # Float, -1.0..1.0
```

`device:` defaults to 0, so every existing single-player call site
(`input.down?(:fire)`) keeps working unchanged — which is what constraint 1
asks for. `GosuInput.new(window)` takes the window; keep that constructor shape.

**Gone:** `pointer_x`, `pointer_y`, and the `:pointer` → `MS_LEFT` binding.

### 2.5 `RGame::Core::Gamepad`

`connected?(slot)`, `name(slot)`, `count`. Small; mostly a readout for UI.

**Verify:** Check tests for the slot table (2.1) and the binding/button-id
mapping; `example.rb` moves a rectangle with the arrow keys *or* a controller
stick, prints connect/disconnect events, and quits on Escape via `button_down`.
Unplugging and replugging a pad mid-run keeps it on the same slot.

---

## Phase 3 — The render foundation

The bulk of the work, and the part where a wrong foundation is expensive to
undo. Nine steps, each meant to land on its own with the suites green.

Ground rules for the whole phase:

- **Pure before impure.** Steps 3.1–3.4 contain no GL at all. The hard parts of
  a 2D renderer — z ordering, transform composition, clip intersection,
  batching — are arithmetic, and every one of them is Check-tested before a
  single `gl*` call is written.
- **No per-frame allocation in steady state.** Every buffer here grows by
  doubling and is *reset*, not freed, at end of frame. A renderer that mallocs
  per frame is a GC-pause equivalent, and it is the one thing this design
  cannot retrofit later.
- **Mutation-check each new Check suite** under the full sanitizer flags before
  calling a step done — see `.claude/skills/verify/SKILL.md`. Two of the four
  suites written so far had a test that passed for the wrong reason.

### Measured facts this plan rests on

Probed on this machine, under Xvfb + Mesa llvmpipe — i.e. exactly what
`rake spec:core` sees, not what a GPU box would give:

| | |
|---|---|
| `GL_VERSION` | **4.5 (Compatibility Profile)**, Mesa 23.2.1 |
| `GL_MAX_TEXTURE_SIZE` | 16384 |
| FBO (`ARB_` and `EXT_framebuffer_object`) | present, and a colour-attached FBO reports `GL_FRAMEBUFFER_COMPLETE` |
| VBO, NPOT textures | present |
| GL 1.1 client-side vertex arrays | compile warning-clean against `SDL2/SDL_opengl.h`, no loader |
| FBO/VBO entry points | **do not compile** against `SDL_opengl.h` alone — implicit-declaration warnings |

Two consequences:

1. **The client-side vertex-array plan needs no loader and no new dependency.**
   `glVertexPointer`/`glTexCoordPointer`/`glColorPointer`/`glDrawArrays` are GL
   1.1 and declared already. That settles the layer-3 approach.
2. **Anything past GL 1.1 needs one extra line**: `#define GL_GLEXT_PROTOTYPES 1`
   before `<SDL2/SDL_opengl.h>`, which was verified to compile warning-clean
   *and* work at runtime under llvmpipe. Mesa also happens to export those
   symbols so they link directly — but that is a Linux/Mesa accident, not a
   portable fact (Windows' `opengl32.dll` exports only GL 1.1). **Only step
   3.9 needs this**; if the project ever targets Windows, that step is where a
   loader or `SDL_GL_GetProcAddress` table has to appear.

`stb_image` is not packaged on this machine and gets **vendored** as a single
header (public domain / MIT). See 3.7 for the one wrinkle that creates.

---

### 3.1 `Util::Color` — the value every draw call takes

Pure Ruby-visible value in `ext/rgame_util/color.c`, not Core: a colour is a
value, and the engine layer must be able to hold one (CLAUDE.md, "Value
objects go in Util; only handle-owners go in Core").

```ruby
c = RGame::Util::Color.rgba(255, 128, 0, 200)
c = RGame::Util::Color.new(0xFFC80080)     # packed 0xRRGGBBAA
RGame::Util::Color::WHITE
c.r; c.g; c.b; c.a                         # => Integer 0..255
c.packed                                   # => Integer, what the C layer stores
c == other                                 # value equality
```

Also the tri-modal coercion `GosuRenderer#resolve_color` promises, since every
draw method accepts it: `nil` → white, `[r,g,b]`/`[r,g,b,a]` → a Color, a Color
→ itself. Put that in one place (`Color.coerce`) rather than in each primitive.

- **Pure C**: `color.{c,h}` packing/unpacking, Check-tested.
- **Tests**: `spec/rgame/util/color_spec.rb` (fast suite — no SDL) for the Ruby
  API; Check for the packing arithmetic.
- **Watch**: the packed byte order must match what the vertex format feeds GL
  (`GL_UNSIGNED_BYTE` × 4, RGBA). Assert it once, in C, rather than discovering
  it as blue-tinted sprites.

### 3.2 `transform.{c,h}` — the 2D affine stack (pure)

```c
typedef struct { float a, b, c, d, tx, ty; } rgame_transform;  /* 2x3 affine */

void rgame_transform_stack_init(rgame_transform_stack *s);   /* top = identity */
int  rgame_transform_push_translate(rgame_transform_stack *s, float dx, float dy);
int  rgame_transform_push_rotate(rgame_transform_stack *s, float degrees,
                                 float pivot_x, float pivot_y);
int  rgame_transform_push_scale(rgame_transform_stack *s, float sx, float sy);
void rgame_transform_pop(rgame_transform_stack *s);
void rgame_transform_apply(const rgame_transform_stack *s,
                           float x, float y, float *out_x, float *out_y);
```

Each push composes with the current top and pushes the result, so `apply` is
one matrix-multiply regardless of nesting depth. Push returns 0 if the stack is
full — a depth limit is fine (say 32) and better than unbounded growth.

- **Tests** (`test/test_transform.c`): identity leaves a point alone; translate
  then rotate composes in the right order (a known point to a known place); pop
  restores exactly; rotate about a pivot leaves the pivot fixed; degrees not
  radians (Gosu's convention, and the ported `Renderer#rotated` passes degrees);
  overflowing the stack is reported, not silently wrong.
- **Settled**: rotation direction. Measured against Gosu by rendering
  `Gosu.rotate` off-screen and reading back the inked pixel: a positive angle
  turns **clockwise on screen** — a point right of the pivot lands below it.
  That is the textbook matrix with no sign flip, because screen y points down.
  `test_transform.c` pins it with coordinates rather than matrix entries, and
  the implementation was cross-checked against Gosu at 30/90/150/250/-45
  degrees.

### 3.3 `clip.{c,h}` — the intersecting clip stack (pure)

```c
typedef struct { int x, y, w, h; } rgame_rect;

void rgame_clip_stack_init(rgame_clip_stack *s, int width, int height);
int  rgame_clip_push(rgame_clip_stack *s, rgame_rect r);  /* intersects with top */
void rgame_clip_pop(rgame_clip_stack *s);
rgame_rect rgame_clip_current(const rgame_clip_stack *s);
int  rgame_clip_is_empty(const rgame_clip_stack *s);
```

- **Tests** (`test/test_clip.c`): a pushed rect intersects rather than replaces;
  nested pushes intersect cumulatively; disjoint rects give an empty clip and
  `is_empty` says so; pop restores; the base rect is the window, so an
  unclipped draw is still bounded.
- **Watch**: empty must be a first-class answer (`w` or `h` ≤ 0), because the
  queue uses it to drop commands early.
- **Measured**: Gosu's `clip_to` **is transformed** by the surrounding
  transform stack — a clip at x 0..20 inside `translate(50, 0)` clips x 50..70,
  confirmed by reading pixels back from a real window. So `clip.{c,h}` works in
  *screen* space and the canvas (3.5) transforms the caller's rect before
  pushing it. Under translate and scale that stays exact; under rotation a
  scissor rect cannot represent the result, so the canvas will take the
  axis-aligned bounding box — conservative, and untested against Gosu because
  nothing in the engine rotates a clip.

### 3.4 `draw_queue.{c,h}` — z-sort and batching (pure)

**The single most important module in the rewrite.** Gosu's contract is that
every draw call carries a `z` and the renderer sorts by it regardless of call
order; `glEnable(GL_DEPTH_TEST)` does *not* provide that, because depth-testing
and alpha blending are mutually exclusive — a depth-tested translucent quad
rejects the fragments behind it instead of blending. Every UI panel in this
engine is translucent chrome over gameplay.

Concrete shape:

```c
typedef struct { float x, y, u, v; unsigned int rgba; } rgame_vertex;  /* 20 bytes */

typedef struct {
    double z;             /* Gosu-compatible Float */
    unsigned int order;   /* insertion index — the stable-sort tiebreak */
    unsigned int texture; /* GL name; 0 = untextured */
    rgame_rect clip;      /* travels WITH the command, see below */
    unsigned int first_vertex, vertex_count;
} rgame_draw_command;
```

Vertices live in one growable array; commands index into it. That handles
triangles (3) and quads (6, as two triangles) uniformly, keeps the sorted
records small, and means the flush is a linear walk.

```c
void rgame_draw_queue_reset(rgame_draw_queue *q);          /* per frame; keeps capacity */
rgame_vertex *rgame_draw_queue_alloc(rgame_draw_queue *q, unsigned count,
                                     double z, unsigned texture, rgame_rect clip);
void rgame_draw_queue_flush(rgame_draw_queue *q, const rgame_draw_backend *backend);
```

`alloc` returns a writable span so the caller fills vertices in place — no
temporary array, no copy.

Three rules the tests must pin:

1. **Sort ascending by `z`.**
2. **Stable within a `z`** — ties break by insertion order. Gosu behaves this
   way, and without it same-z sprites flicker between frames as the sort
   reshuffles them.
3. **The clip rect is part of the command and part of the batch key.** Sorting
   reorders commands across viewports, so a clip left as ambient state would
   scissor the wrong quads. This is a split-screen requirement landing on the
   very first renderer module — and the thing a single-viewport implementation
   gets wrong in a way that needs a rebuild to fix.

Batching: after sorting, consecutive commands sharing `(texture, clip)` merge
into one `draw_batch` call.

- **Tests** (`test/test_draw_queue.c`): ascending z; equal z keeps insertion
  order; three same-texture same-clip commands become one batch; a texture
  change splits a batch; a *clip* change splits a batch; an empty clip drops the
  command entirely; reset keeps capacity so a second frame allocates nothing
  (assert on a capacity counter, not on malloc).

### 3.5 `canvas.{c,h}` — composition, still pure

The piece that ties 3.2–3.4 together, and the one the rest of the engine talks
to. Owns a transform stack, a clip stack and a draw queue; transforms vertices
**at append time** so the queue can reorder freely.

```c
void rgame_canvas_begin_frame(rgame_canvas *c, int width, int height);
void rgame_canvas_push_translate(rgame_canvas *c, float dx, float dy);
void rgame_canvas_push_rotate(rgame_canvas *c, float deg, float px, float py);
void rgame_canvas_push_clip(rgame_canvas *c, rgame_rect r);
void rgame_canvas_pop(rgame_canvas *c);                     /* one pop for any push */
void rgame_canvas_quad(rgame_canvas *c, const float *xy8, unsigned rgba, double z);
void rgame_canvas_triangle(rgame_canvas *c, const float *xy6, unsigned rgba, double z);
void rgame_canvas_textured_quad(rgame_canvas *c, unsigned texture,
                                const float *xy8, const float *uv8,
                                unsigned rgba, double z);
void rgame_canvas_end_frame(rgame_canvas *c, const rgame_draw_backend *backend);
```

One `pop` for every kind of push keeps the Ruby side's block form honest and
means a caller can never pop the wrong stack.

- **Tests** (`test/test_canvas.c`): a quad drawn inside `push_translate` lands
  translated; nested transforms compose; pop unwinds; a quad drawn inside a clip
  carries that clip into its command; **the split-screen shape end-to-end** —
  two viewports, each `push_clip` + `push_translate`, the same world draw in
  both, asserting the recorded batches have the right clips and offsets.

### 3.6 `backend.h` + a recording fake — the layer-2 seam

Added exactly here, per CLAUDE.md: the point at which real GL calls first
appear, not speculatively before.

```c
typedef struct {
    void (*begin_frame)(void *ctx, int width, int height);
    void (*set_clip)(void *ctx, rgame_rect clip);
    void (*draw_batch)(void *ctx, unsigned texture,
                       const rgame_vertex *verts, unsigned count);
    void (*end_frame)(void *ctx);
    void *ctx;
} rgame_draw_backend;
```

`test/support/recording_backend.{c,h}` appends every call to an array so Check
tests can assert "these batches, in this order, with these vertices" with no
display involved.

**Correction to the original plan**: 3.4 and 3.5 are *not* written against the
fake. Both hand back their prepared batches directly and are tested with no
backend at all, which keeps the dependency one-directional — `draw_queue` and
`canvas` do not include `backend.h`. What the seam is actually for is the
submit loop, `rgame_draw_submit`: the small amount of logic between a prepared
frame and the GPU, including issuing a scissor only when the clip changes. That
last part is a state-change optimisation invisible to any pixel test, since the
picture is identical either way — a call recorder is the only thing that can
see it.

### 3.7 `texture.{c,h}` + `Core::Image` — decode, upload, views

The rect arithmetic is pure and Check-tested; only decode+upload touches GL.

```ruby
img = RGame::Core::Image.new('hero.png')       # nearest-neighbour, always
img.width; img.height
sub = img.subimage(x, y, w, h)                 # a VIEW: same GL texture, new UVs
tiles = RGame::Core::Image.load_tiles('sheet.png', 16, 16)   # => [Image, ...]
```

A subimage is a view — same texture name, a sub-rect of UV space, no re-decode
and no second upload. `subimage` on a subimage composes rects. `retro: true` is
not a parameter: nearest is the only mode the feature spec needs, so it is the
only mode there is.

- **Pure part** (`test/test_texture.c`): pixel rect → UV rect; a subimage of a
  subimage composes; `load_tiles` slices a grid in the right order (row-major);
  an out-of-bounds sub-rect is rejected rather than producing garbage UVs.
- **Impure part**: `stbi_load` + `glTexImage2D` + `GL_NEAREST`. Covered in
  `spec_core/` by loading a small fixture PNG and asserting `width`/`height`.
- **Wrinkle — vendoring `stb_image.h`.** mkmf compiles every `.c` in the ext
  directory, so the implementation TU (`#define STB_IMAGE_IMPLEMENTATION`) will
  be compiled with the project's `-Wall -Wextra`, and third-party headers rarely
  survive that. Plan: put it in `ext/rgame_core/vendor/`, wrap it in one small
  `stb_image_impl.c`, and give that file relaxed warnings in `extconf.rb`.
  Keeping the project warning-clean is a stated convention; carving out exactly
  one vendored TU is the honest way to hold it. Record the licence.

**Landed.** What shipped differs from the sketch above in five ways worth
carrying into 3.8:

- **`Image.new(app, path)` takes the app**, rather than implying "the window
  that happens to be open". A texture lives in one GL context, so an image is an
  image *of* an app — which is also what makes two windows work, and what lets
  the Ruby object keep its app reachable. `load_tiles(app, path, w, h)` likewise.
- **The refcount is in the pure layer.** `texture.{c,h}` owns a refcounted
  `rgame_texture_sheet` and cheap `rgame_texture` views over it, so "the upload
  dies exactly when the last sprite using it does" is Check-tested with no GPU.
  `rgame_texture_sheet_release` hands the GL name *back* rather than deleting
  it; image.c does the one-line deletion. 22 tests, mutation-checked under
  ASan+UBSan (one survivor, a redundant negative-index guard, kept with a
  comment saying so).
- **The app handle is refcounted too.** Ruby can sweep an app and its images in
  one pass in an unspecified order, so `rgame_app_gl_retain`/`_release` (private,
  `app_gl.h`) keep the *struct* alive while an image points at it. The window and
  context still close the moment `rgame_app_destroy` runs; an image left over
  then skips its `glDeleteTextures`, correctly — a destroyed GL context has
  already freed its textures.
- **Out-of-range slicing raises**, it does not return nil: `ArgumentError` for a
  subimage that does not fit, `IndexError` for a tile index. A nil travels too
  far before failing.
- **`Image.debug_live_textures`** exposes the sheet counter to specs. A leaked
  GPU texture is otherwise invisible until video memory runs out.

`load_tiles`, `tiles` and `each_tile` are pure Ruby in `lib/rgame/core/image.rb`
over the C `tile_count`/`tile`. Documentation is `docs/api/images.md`.

Not covered yet, deliberately: whether the *pixels* land the right way up. That
needs `glReadPixels` after a real draw, so it belongs with 3.8's spot checks —
the UV convention (`v` increases downwards, row 0 at `v = 0`) is pinned in
`test_texture.c` and asserted against the upload order in image.c's comments,
but nothing has yet drawn a texture to prove the two agree.

### 3.8 Primitives and the Ruby `Core::Renderer`

Now that the machinery exists, the drawing API is thin. Ruby-side
`lib/rgame/core/renderer.rb` over the C canvas:

| Method | Notes |
|---|---|
| `rect(x, y, w, h, z:, color:)` | one quad |
| `quad(x1..y4, z:, color:)` | four arbitrary points |
| `triangle(x1..y3, z:, color:)` | three points |
| `line(x1, y1, x2, y2, thickness:, z:, color:)` | a quad; keep the `-0.0` note from `gosu_renderer.rb:149-157` if it stays in Ruby |
| `image(id, cx, cy, angle:, scale:, z:)` | centred, rotated, scaled. Gosu's `draw_rot` was measured to use the same angle convention as `Gosu.rotate` — 0 is unrotated, positive is clockwise — so this is the transform stack, with no second convention to translate |
| `background(id, z:)` | at the origin |
| `sprite(id, row, col, x, y, flip_x:, z:)` | via `SpriteSheet` |
| `rotated(deg, px, py) { }` / `translated(dx, dy) { }` / `clipped(x, y, w, h) { }` | push/pop around a block |
| `debug_box(x, y, w, h)` | tinted rect |

`clipped` is the one method the rewrite *adds* to the Ruby API, and all
split-screen needs from Ruby's side.

**This is where the renderer interface contract gets written** — the piece
deliberately left unbuilt until there was a renderer to write it against.
`spec/support/shared_examples/a_renderer.rb` states the method list and its
argument shapes; the recording fake in `spec/` and the real `Core::Renderer` in
`spec_core/` are both run against it. Per CLAUDE.md, a method added to the real
renderer is not done until the shared contract and the fake have it too.

Keep the zero-angle/zero-offset fast paths from `gosu_renderer.rb:77,:91` — and
the `yield`-without-block-capture trick, which exists to avoid allocating a Proc
per rotated draw.

**Landed.** Deviations from the sketch above, and what they mean for 3.9:

- **Two new C modules, not one.** `primitives.{c,h}` (pure: rect, thick line,
  circle fan, sprite quad — 20 Check tests, all 22 mutations caught) and
  `gl_backend.{c,h}` (layer 3: `glOrtho` with y flipped so the origin is
  top-left, `glDrawArrays` over interleaved client arrays, `glScissor` with its
  bottom-up flip, blending on and depth testing **off**). `app.c` now owns a
  canvas and brackets the draw callback with begin/end/submit, so a game never
  opens or closes a frame itself.
- **`sprite` and `background(id)` are not built**, as the note below this
  section recommends: they need a `SpriteSheet` and an asset registry, which are
  phase 6. `image` and `background` take an `Image` object instead, so both are
  usable today and neither is a stub that phase 6 has to un-drift.
- **`circle` is a fan**, and the whole fan is one batch — the cached
  unit-circle texture (and the `Gosu.render` support it needed) is not
  replaced, it is simply unnecessary. `scaled { }` was added alongside
  `rotated`/`translated`/`clipped`; the trio had an odd gap without it.
- **The `-0.0` note retires.** It described a CRuby flonum concern — a computed
  negative zero heap-allocating on an axis-aligned line — and the line's corner
  arithmetic is now in C, where it costs nothing. The corner *order* still
  matters and is pinned by a test, since listing the four points in Z order
  gives an hourglass.
- **Drawing outside `draw` raises**, and so does drawing an image that belongs
  to another App. The second one was found by the pixel tests: a texture lives
  in one GL context, so a cross-app draw sampled nothing and painted a plain
  white quad with no error anywhere.

The contract is written and both implementations run against it —
`spec/support/shared_examples/a_renderer.rb`, the fake in `spec/`, the real one
in `spec_core/`. `spec_core/support/rendered_frame.rb` is the new pixel tier: it
runs a frame, reads the back buffer through `glReadPixels` (via fiddle) at the
start of the next one, and checks placement, y direction, z order, blending, the
scissor flip and sprite orientation. That also closes the gap 3.7 left open —
images are now proven to draw the right way up.

Documentation is `docs/api/drawing.md`; `src/main.c` and `example.rb` both draw
a scene now, so `make run` is a real layer-3 check rather than a blank window.

### 3.9 `record` — retained batches

`Gosu.record` is what makes the tile map affordable: bake the static layers once
and redraw them as one call. With a batching queue this is nearly free — capture
the commands a block produces, keep the vertex array, replay it later offset by
the current transform.

```ruby
baked = renderer.record { ...many draws... }
baked.draw(x, y, z)
```

- **Tests**: pure (a recorded block produces the same batches on replay, offset
  correctly); plus a `spec_core/` check that replaying is one `draw_batch`, not
  N.
- **Note**: Gosu's recorded images draw white-only (no tint), which
  `tile_map_renderer.rb:11` documents working around. Ours has no reason to
  inherit that limitation.

**Landed, and phase 3 with it.** How it came out:

- **`recording.{c,h}`** (pure, 21 Check tests, all 20 mutations caught) stores
  the *prepared* frame — the already-sorted, already-grouped vertex array — so
  the sorting and batching is the work being saved rather than repeated.
  `rgame_canvas_replay` appends one command per baked batch.
- **Clips are not captured**, and pushing one inside a bake raises rather than
  being dropped. A clip rectangle is decided at rasterisation, so one recorded
  at a given place on screen is wrong everywhere else the recording is replayed.
  `clipped { baked.draw(...) }` is the thing the caller meant anyway.
- **The offset is applied before the current transform**, which is what makes a
  baked layer scroll under a camera. Replaying at `z` puts every batch at that
  z, and equal-z insertion order keeps the painter order baked into it.
- **Tinting works**, as the note above hoped: each recorded colour is multiplied
  by the replay's, so a whole baked layer can be faded at once.
- **A recording holds the Images baked into it** (`recording_ext.c`). A baked
  batch stores a GL texture *number*, so a collected Image would leave it
  drawing whatever the driver put there next — silently. The renderer collects
  the images drawn during a bake and hands them to the finished Recording.

The pixel tier found a second real bug, unrelated to recordings but caught by
them: freeing an image made its own window's GL context current and **left it
current**, so the rest of that frame was submitted into the wrong context and
came out blank. A garbage collector picks the moment, so it would have been an
occasional mystery. `rgame_app_gl_make_current` now takes a save to restore, and
`spec_core` pins it with a GC mid-frame.

### Deferred out of phase 3: render-to-texture

`Gosu.render` (FBO → texture) has exactly one caller in the current engine: the
cached unit-circle used by `Renderer#circle`. With a real batching renderer, a
per-call triangle fan is cheap enough that the cached texture may be pure
overhead — so **`circle` becomes a fan, and FBOs wait until something actually
needs them**. This is also the only step that would need the
`GL_GLEXT_PROTOTYPES` line and a portability decision, so deferring it keeps
phase 3 entirely inside GL 1.1.

Revisit if text (phase 4) wants to bake a glyph atlas via GL rather than
uploading a CPU-rasterised one. It should not — stb_truetype rasterises to
memory, and uploading that is an ordinary `glTexImage2D`.

### Verification tiers for this phase

The headless integration tier CLAUDE.md used to describe as "not yet built" now
exists as `spec_core/` (Xvfb + llvmpipe, booted by the suite itself). Phase 3 is
what makes it worth using for rendering:

- **`make test`** — everything in 3.1–3.6, 3.9's pure half. The bulk.
- **`rake spec`** — `Util::Color`; the renderer contract against the fake.
- **`rake spec:core`** — real texture upload; the renderer contract against the
  real renderer; **`glReadPixels` spot checks**: draw a red quad at a known
  place and assert the pixel is red; draw a blue quad at higher z over it and
  assert the pixel is blue; clip a quad away and assert the pixel is unchanged.
  Three of those catch more layer-3 mistakes than any amount of staring.
- **`ruby ext/rgame_core/example.rb`** — the human check that it looks right.

### What phase 3 does *not* deliver

Text (phase 4), audio (phase 5), and the ported Ruby classes — `SpriteSheet`,
`NineSlice`, `UiAtlas`, `TileMapRenderer`, `AssetManager` (phase 6). 3.8's
`sprite` and `background` need a `SpriteSheet` and an image registry to be
useful; either stub them against a trivial registry in 3.8 and port properly in
phase 6, or leave those two rows until then. Prefer leaving them: a stub that
looks like the real thing is how phase 6 acquires silent drift.

---

## Phase 4 — Text

`stb_truetype` rasterising into a glyph atlas, `RGame::Core::Font`, and
`Renderer#text`. The shape is the same as phase 3: most of it is arithmetic that
needs no GPU, and the part that does is four GL calls wide.

The default-font question that used to block this is
[settled](README.md#the-default-font-is-vendored-not-looked-up): the gem ships
Liberation Sans 2.x and there is no font-name lookup. That is what makes 4.1
mostly a packaging step.

### Decisions to take before writing any of it

Recorded here so they are not re-argued in the middle of 4.4.

- **Cache per glyph, never per string.** Feature spec §2 is explicit, and
  `gosu_renderer.rb:113-117` says why: a game draws many short-lived changing
  strings (scores, timers), so a per-glyph cache stays bounded by the character
  set while a per-string cache grows forever.
- **No eviction.** A game's glyph set is small (a few hundred) and stable, so
  the bound the cache needs already exists. Pages are added on demand and never
  reclaimed until the font is dropped. This overrides CLAUDE.md's speculative
  mention of "glyph cache eviction" as a thing to test — there is nothing to
  evict. A `debug_live_font_pages` counter makes the growth observable, the way
  `debug_live_textures` does for images.
- **One `Font` is one typeface at one pixel height**, as in Gosu. Two sizes are
  two Fonts with two atlases. Sharing one atlas across sizes would need a key
  wider than a codepoint for no benefit anyone has asked for.
- **A Font belongs to an app**, like an Image, because its atlas pages are GL
  textures. Same ownership rules, same cross-app refusal.
- **Rasterise at the requested pixel height, 1:1.** Gosu renders glyphs at 2x
  and draws them scaled down (`Font.cpp:14`, `FONT_RENDER_SCALE`) so that scaled
  text stays smooth. Skipped for now: our text is drawn at its native size, and
  the supersample costs 4x the atlas for a case nothing in the port needs.
  Revisit if UI text ever gets drawn inside `scaled`.
- **Atlas pages are 512x512, single-channel `GL_ALPHA`, with a 1px gutter.**
  An alpha texture under the fixed-function default (`GL_MODULATE`) gives
  `rgb = vertex colour, a = vertex alpha * coverage`, which is exactly coloured
  text, at a quarter the memory of RGBA. The gutter is because the atlas samples
  with `GL_LINEAR` (text is not pixel art, and stb antialiases), so a glyph
  packed flush against its neighbour bleeds into it. Note for the day the
  project moves to core-profile GL: `GL_ALPHA` goes away there and becomes
  `GL_RED` plus a shader swizzle.
- **Kerning is applied**, via `stbtt_GetCodepointKernAdvance`. It is one call
  per pair, it is pure, and without it "AV" reads wrong.
- **`(x, y)` is the top-left of the line box**, matching what `Gosu::Font#draw_text`
  does and therefore what `GosuRenderer#text` callers already assume. The
  baseline sits at `y + ascent`.
- **Out of scope, explicitly**: markup (`<b>`, `<c=ff0000>`), bold/italic flags,
  multi-line layout, text input, bidi and shaping. A string is one line of
  left-to-right glyphs; a caller that wants two lines splits it and uses
  `#height`, which is what `#height` is for.

---

### 4.1 Vendor the font and `stb_truetype`

Two vendored things with two different homes, and the difference matters:

| | Where | Why |
|---|---|---|
| `stb_truetype.h` | `ext/rgame_core/vendor/` | compiled in, like `stb_image.h` |
| `LiberationSans-Regular.ttf` + `OFL.txt` | `lib/rgame/fonts/` | **data read at runtime**, so it belongs where a gem installs data, not in an ext directory that only exists to be compiled |

- `stb_truetype_impl.c` alongside `stb_image_impl.c`, same one-TU-per-header
  pattern. Both need warnings off, so generalise the carve-out rather than
  copying it: a `stb_%_impl.$(OBJEXT)` pattern rule in `extconf.rb`'s appended
  block and in the root `Makefile`. Two hand-written copies of the same rule is
  how the second one rots.
- `ext/rgame_core/vendor/README.md` gets an entry for `stb_truetype.h` and a
  pointer to where the font lives and why it is not here.
- **Handled**: the font ending up in the gem needs no action. `rgame.gemspec`
  globs `lib/**/*`, so dropping the `.ttf` and its `OFL.txt` into
  `lib/rgame/fonts/` packages them, and `spec/packaging_spec.rb` asserts that
  every non-Ruby file under `lib/` is in the gem — the check exists precisely
  because a missing default font fails at the first `Font.new`, on someone
  else's machine. Put them in `lib/rgame/fonts/` and the suite covers it.

### 4.2 `atlas.{c,h}` — where a glyph goes (pure)

A shelf packer. Glyphs arrive one at a time and are mostly the same height, so
shelves are the right amount of cleverness: fill a row left to right, start a
new row when it runs out, report "full" when the page does.

```c
typedef struct {
    int width, height;
    int shelf_y;      /* top of the row being filled */
    int shelf_height; /* tallest glyph on it so far */
    int cursor_x;     /* next free x on that row */
} rgame_atlas;

void rgame_atlas_init(rgame_atlas *atlas, int width, int height);
/* Reserves w x h (plus the gutter) and writes where it went. 0 if the page is
 * full — the caller then opens another page. */
int rgame_atlas_place(rgame_atlas *atlas, int w, int h, rgame_rect *out);
```

- **Tests** (`test/test_atlas.c`): the first glyph lands at the origin; a second
  sits to its right with exactly one pixel between them; a row that fills opens
  a new shelf below the tallest glyph of the previous one; a page that fills
  refuses rather than overlapping; a glyph taller or wider than the whole page
  is refused rather than looping forever; a zero-sized glyph (the space
  character rasterises to nothing) is handled without consuming a slot.
- **Watch**: the gutter belongs *inside* `place`, not at the call site. A caller
  that has to remember to add one is a caller that eventually does not, and
  bilinear bleed between two glyphs looks like a rendering bug, not a packing
  one.

**Landed.** `rgame_atlas_place` returns 1 and an *empty* rectangle for a glyph
with no pixels, rather than refusing it — the space character rasterises to
nothing, and handling that here means the font layer has no special case to
remember. `rgame_atlas_init` clamps a negative size to zero, because the page
size is read back by the layer that allocates the texture behind it.

14 tests to start, all 16 mutations run against them, and three survived. All
three were test gaps rather than dead code, and the tests that closed them are
the interesting ones:

- the page-height off-by-one only shows on a shelf that starts part way down,
  which the "full page" case did not produce;
- the over-tall guard is redundant for *correctness* (the page check catches it
  anyway) but not for behaviour — without it a glyph that is both too tall and
  too wide opens a fresh shelf before failing, displacing the next glyph that
  would have fitted the current row;
- the negative-size clamp is invisible through `place` and observable only by
  reading `atlas.width` back, which is exactly what 4.5 will do.

### 4.3 `glyph_cache.{c,h}` — what is already rasterised (pure)

```c
typedef struct {
    int codepoint;
    int page;             /* which atlas page it landed on */
    rgame_rect rect;      /* where, in that page's pixels */
    float advance;        /* how far the pen moves, already scaled */
    float bearing_x;      /* pen -> left edge of the bitmap */
    float bearing_y;      /* line top -> top edge of the bitmap */
} rgame_glyph;

int rgame_glyph_cache_find(const rgame_glyph_cache *cache, int codepoint,
                           rgame_glyph *out);
int rgame_glyph_cache_insert(rgame_glyph_cache *cache, const rgame_glyph *glyph);
unsigned int rgame_glyph_cache_count(const rgame_glyph_cache *cache);
```

Open addressing on a fixed-capacity table keyed by codepoint, grown by
doubling — no allocation per glyph, and no pointer chasing on the draw path.

- **Tests** (`test/test_glyph_cache.c`): a miss reports a miss and leaves `out`
  alone; insert then find round-trips every field; two codepoints that collide
  in the table both survive; re-inserting the same codepoint replaces rather
  than duplicating; the count tracks distinct codepoints, not calls — draw
  "aaaa" and it is 1; the table grows without losing entries.
- **Watch**: key on the codepoint, not on the byte. The whole point of the cache
  is that `ä` and `€` behave like `a`.

**Landed.** Open addressing over one flat array, codepoint 0 as the empty
marker (it is NUL, never a glyph, and inserting it is refused rather than
silently hiding an entry), grown at three-quarters full *before* the insert —
the probe walk has no exit other than an empty slot, so the table must never be
allowed to fill. No tombstones, because nothing is ever deleted.

12 tests, 20 mutations, two survivors, and both were worth the trip:

- **A miss on a *populated* cache** was untested. The empty-cache miss returns
  before the table is touched, so it said nothing about the path where `find`
  probes to an occupied-then-empty slot; a `find` that copied the slot out
  before checking the key would hand back a neighbouring glyph and the caller
  would draw it. Now tested.
- **Replacing the hash with the identity function survives, and should.**
  Linear probing resolves collisions whatever the hash does, so a worse one is
  slower, not wrong — there is no assertion to write short of counting probes.
  Writing that survivor up exposed a factual error in the comment justifying the
  multiply (it claimed Latin-1 accents are "a multiple of 16 apart"; they are
  contiguous, and identity would spread them fine). The comment now says the
  honest thing: it is one multiply of insurance against the *next* game's key
  distribution, not a correctness requirement.

One test took three attempts, and the sequence is the useful part:

1. It computed the hash itself to find a colliding pair — which would stop
   colliding, and go on passing, the day the hash changed.
2. Replaced with "crowd the table and collisions follow by pigeonhole", using
   an arithmetic progression of keys. That premise is simply false: 47 keys in
   64 slots need not collide, and a multiplicative hash with an odd multiplier
   maps an arithmetic progression to *distinct* slots — measured, zero
   collisions. The rewrite exercised no probe walk at all, and a mutation that
   the first version had caught (`& capacity` instead of `& (capacity - 1)`)
   started surviving. Only re-running the mutations after the rewrite found it.
3. Now keyed on a realistic character set — letters, digits, punctuation,
   accents — which collides ten times over in a fresh table. The broken wrap is
   caught again, as an infinite probe loop.

Worth remembering beyond this module: a test rewritten for good reasons can be
weaker than what it replaced, and nothing says so except running the mutations
again.

### 4.4 `font.{c,h}` — the typeface (pure, and testable *because* the font is vendored)

Wraps `stb_truetype`. No GL, no atlas, no cache — just "what does this glyph
measure and what does it look like". Called `rgame_typeface` so that the public
`rgame_font` (4.5) can be the composed, app-bound thing.

```c
typedef struct rgame_typeface rgame_typeface;

rgame_typeface *rgame_typeface_open(const unsigned char *ttf, size_t length,
                                    int pixel_height);
void rgame_typeface_close(rgame_typeface *typeface);

int   rgame_typeface_height(const rgame_typeface *typeface);  /* line height, px */
float rgame_typeface_ascent(const rgame_typeface *typeface);

/* Metrics and bitmap size for one glyph, without rasterising it. */
int rgame_typeface_glyph(const rgame_typeface *typeface, int codepoint,
                         rgame_glyph *out, int *bitmap_w, int *bitmap_h);

/* Rasterises into a caller-provided 8-bit coverage buffer. */
void rgame_typeface_render(const rgame_typeface *typeface, int codepoint,
                           unsigned char *out, int stride, int width, int height);

/* Advance from `previous` to `codepoint`, kerning included. 0 for the first. */
float rgame_typeface_kern(const rgame_typeface *typeface, int previous, int codepoint);

/* One UTF-8 codepoint. Returns 0 at the end or on a malformed sequence. */
int rgame_utf8_next(const char *text, size_t length, size_t *offset, int *codepoint);
```

The stb calls behind these are `stbtt_InitFont`, `stbtt_ScaleForPixelHeight`,
`stbtt_GetFontVMetrics`, `stbtt_GetCodepointHMetrics`,
`stbtt_GetCodepointKernAdvance`, `stbtt_GetCodepointBitmapBox` and
`stbtt_MakeCodepointBitmap` — all deterministic, which is what makes the tests
below assertions rather than approximations.

- **Tests** (`test/test_font.c`), against the shipped Liberation Sans — a real
  TTF the suite can rely on, which is a side benefit of vendoring it:
  - line height and ascent are positive, and ascent < height
  - `i` advances less than `W`; both advance more than zero
  - a space has an advance but rasterises to an empty box
  - kerning is applied and is negative for `AV`
  - a codepoint the font lacks resolves to glyph 0 and still returns *some*
    advance, rather than a zero-width nothing that silently swallows characters
  - `ä` (2 bytes), `€` (3) and an emoji (4) decode to the right codepoints
  - a truncated UTF-8 sequence stops rather than reading past the end — this is
    the one place in the engine that walks attacker-shaped data, since a string
    can come from anywhere
  - the same string measured twice gives the same answer (no accumulated
    rounding between calls)
- **Watch**: **`text_width` and the draw path must walk the same function.** If
  measurement and drawing disagree by a rounding rule, every centred label in
  the game drifts by a pixel or two and nothing points at why. One
  `advance`-summing loop, used by both.

**Landed.** The face is `rgame_typeface` so that the composed, app-bound thing
can be `rgame_font` in 4.5. Three decisions worth carrying forward:

- **It copies the font bytes.** stb keeps pointers into the data for the life of
  the face, so borrowing would make "keep the buffer alive" a rule a caller has
  to remember. A few hundred kilobytes per open size is the cheaper answer, and
  4.5 can free its file buffer immediately.
- **`rgame_text_cursor` is the one walk**, used by measuring and (in 4.6) by
  drawing. The plan asked for "one advance-summing loop used by both"; making it
  a cursor makes the sharing structural rather than a promise, and
  `rgame_typeface_measure` is literally that cursor run to the end.
- **Malformed UTF-8 yields U+FFFD and advances one byte**, rather than stopping
  as the sketch above said. One bad byte in a data file should cost one visible
  replacement box, not the rest of the label — and always advancing means a
  caller's loop terminates however bad the input is.

31 tests, 33 mutations, seven survivors on the first run. Four were gaps, and
three of those were the same shape — **a suite that only compares numbers to
each other cannot tell you the numbers are in the right unit**:

- Every advance could have stayed in font units, a thousand times too big, and
  every relative assertion (`i` < `W`, kerned < unkerned, the sum matches) would
  still have passed. Now bounded against the pixel height.
- `bearing_x` was never read by a test. It goes both ways — `i` is inset from
  its pen, `j` hangs back over the previous letter — so both signs are asserted.
- The cursor could have reported each pen position *after* adding the advance,
  shifting every string right by one character, and "the pen moves forward" plus
  "the total is the width" would both still have held. Now the first glyph is
  pinned at zero.
- A two-byte lead followed by an ordinary letter swallowed the letter without
  the continuation check; `\xC3z` decoded as one plausible accented character
  and the `z` vanished.

The other three survive on purpose and say so in the code: stb tolerates a
zero-sized rasterisation box (the guard stays for negatives), the shipped font
has no kern pair involving codepoint 0 (the guard stays because that is a fact
about one font, not about kerning), and `lead & 0x1F` is genuinely equivalent to
`& 0x0F` for a three-byte lead, since `1110xxxx` always has the fifth bit clear.

### 4.5 `font_atlas.c` + `Core::Font` — the impure quarter

The one file in the text stack that touches GL: it owns the atlas pages
(`glGenTextures` + `glTexImage2D` of an empty `GL_ALPHA` page, `glTexSubImage2D`
per glyph), and composes typeface + atlas + cache into the public handle.

```c
typedef struct rgame_font rgame_font;   /* opaque in core.h */

rgame_font *rgame_font_load(rgame_app *app, const char *path, int pixel_height,
                            char *err, size_t err_size);
void  rgame_font_destroy(rgame_font *font);
int   rgame_font_height(const rgame_font *font);
float rgame_font_measure(rgame_font *font, const char *utf8, size_t length);
```

`rgame_font_glyph(font, codepoint, out)` is the internal one that matters: cache
hit returns immediately; a miss rasterises, places, uploads and inserts. Misses
happen *during* a frame, which is fine — uploads are immediate and drawing is
deferred, so the page is complete by the time the frame is submitted.

Ruby side, `font_ext.c` + `lib/rgame/core/font.rb`:

```ruby
font = RGame::Core::Font.new(app, 18)                       # the shipped font
font = RGame::Core::Font.new(app, 18, path: 'assets/pixel.ttf')
font.height        # => 18
font.text_width('Score: 1200')   # => Float
```

- **Reuse, do not reinvent**: the app-retain/GL-context-save discipline from
  3.7–3.9 applies unchanged. A Font marks its app, `rgame_app_gl_make_current`
  is called *with a save* around every upload, and a Font from another app is
  refused rather than drawn blank.
- **Tests**: `spec_core/rgame/core/font_spec.rb` — a font loads at a size and
  reports it; a missing path raises `Font::LoadError` naming the file; the
  default needs no path; `text_width` grows with the string and is zero for an
  empty one; `debug_live_font_pages` returns to its baseline after GC.
- **Watch**: `Font.new` must work *outside* a frame (a game builds its fonts in
  `initialize`), which means the load path makes its own context current rather
  than assuming one. Measuring must work outside a frame too — it touches no
  GL at all, only metrics.

**Landed.** `font_atlas.c` is the whole impure quarter: it reads the file,
composes typeface + atlas + glyph cache, and owns the pages. Three things came
out differently from the sketch:

- **A font allocates no page until something is drawn.** A layout pass that only
  measures costs no video memory, which falls out of creating pages lazily and
  is worth keeping.
- **`rgame_font_glyph` reports the page texture and size** alongside the glyph,
  because the caller needs all three to turn a page rectangle into texture
  coordinates. That is what `font_internal.h` exposes, mirroring
  `image_internal.h`.
- **`Font.new(app, size, path:)` is a Ruby-side `self.new`** that forwards a
  positional path to the C initialize. Where a gem installs its data is a
  packaging question; the C layer has no opinion and no default.

The GL-context save/restore discipline from 3.7–3.9 applied unchanged, and so
did the app retain — both uploads and page deletion go through it.

### 4.6 `Renderer#text` — and the contract

```ruby
renderer.text(string, x, y, z: 10, color: nil, font: nil)
renderer.text_width(string, font: nil)
renderer.text_height(font: nil)
```

`z: 10` and the method names come straight from `gosu_renderer.rb:120-127`;
constraint 1 says they survive. `font:` defaults to the renderer's own, which is
the shipped font at `FONT_SIZE` (18) — created lazily on first use, because
creating it needs a GL context that does not exist when `Renderer.new` runs.
`Renderer.new(app, font: my_font)` overrides it.

Drawing walks the string once, emitting one textured quad per glyph from the
atlas page. Every glyph of one font shares one page until the page fills, so a
string is one batch — the same property the sprite path already has, for the
same reason.

- **Tests**: the shared contract in `spec/support/shared_examples/a_renderer.rb`
  grows `text`, `text_width` and `text_height`, and the recording fake grows
  them too — per CLAUDE.md, a method added to the real renderer is not done
  until the contract and the fake have it. Then `spec_core` reads pixels:
  - text at a known position puts ink there and none well outside it
  - an empty string draws nothing at all
  - `color:` tints the glyphs
  - **the inked extent matches `text_width`** — render a string, scan for the
    leftmost and rightmost inked columns, and compare. This is the assertion
    that catches measure and draw disagreeing, which is the failure mode with
    the longest fuse.
  - a string with `ä` and `€` draws ink, so the vendored font's coverage is
    checked by the suite rather than by the earlier cmap analysis alone
- **Watch**: `text` on the hot path must not allocate per call. Ruby hands the
  string to C as bytes; the codepoint walk and the glyph lookups happen there.
  No `each_char`, no `codepoints` array.

**Landed, and phase 4 with it.**

`rgame_prim_glyph` was added to primitives.c rather than reusing
`rgame_prim_image`: a glyph's source is a rectangle of a shared page, not a
texture view, and wrapping every page in a refcounted `rgame_texture` to reuse
one function would be the tail wagging the dog. It is pure and has its own
tests, including the same normalise-against-the-page mistake `rgame_texture_uv`
guards against.

The contract's `render` hook now yields a font as well as an image, for the same
reason it yields an image: both own GL objects belonging to one context, so the
real renderer's version has to build them from the capture's own app. Ruby
blocks drop extra yielded arguments, so no existing example needed touching.

The pixel checks include the one the plan called for by name — **render a
string, scan for its inked columns, compare to `text_width`**. It found nothing
wrong with the code and one thing wrong with the test: the capture frame was
narrower than the sample string, so the "inked extent" was measuring the window
edge. Widened.

`Renderer#font` is built lazily on first use rather than in the constructor,
because creating a font needs a GL context and a renderer is often built before
there is one.

### Verification tiers for this phase

- **`make test`** — 4.2, 4.3, 4.4. Most of the phase, and all of the parts that
  are easy to get subtly wrong.
- **`rake spec`** — the renderer contract against the fake.
- **`rake spec:core`** — font loading, and the pixel checks above.
- **`make run` / `example.rb`** — both drivers get a line of text, including one
  with accented characters, so a human sees kerning and coverage.

### What phase 4 does not deliver

Markup, bold and italic, multi-line layout, text input, shaping and bidi, and
any script outside the shipped font's coverage. `SpriteSheet`, `NineSlice` and
the rest of the Ruby layer are still phase 6 — a widget that centres a label
will exist then, and `text_width` is the thing it will need.

---

## Phase 5 — Audio

`Core::Sample`, `Core::Song`: load, play one-shot, play looping, `playing?`,
stop, and volume (feature spec §3 recommends volume as near-free at mixer
level; add it now rather than retrofit).

**Settled: vendor miniaudio, with stb_vorbis for ogg.** Not SDL_mixer, which
this section used to recommend — see
["Audio is vendored too, and it is not SDL_mixer"](README.md#audio-is-vendored-too-and-it-is-not-sdl_mixer)
for the survey of what other engines do and the measurements behind the change.
The short version: SDL_mixer is a system dependency that pulls 8 MB and a MIDI
soundfont on Debian, no comparable engine uses it, and the two dependency-free
finalists were both prototyped. miniaudio won because OpenAL/MojoAL hands back
streaming and voice management — exactly the "real project on its own" this
paragraph used to be worried about.

The prototype that settled it is not committed, but everything it established
is written into 5.2 and 5.5 below — including the two things that would
otherwise cost a day each: miniaudio cannot read ogg without a backend we write,
and the whole stack can be tested with no sound card.

Independent of phases 3–4; schedule it wherever convenient.

### Decisions to take before writing any of it

- **Audio is not app-bound, and this is the one subsystem that touches neither
  SDL nor GL.** miniaudio talks to ALSA/PulseAudio/CoreAudio/WASAPI directly,
  loading them at runtime. So a `Sample` has no GL context to belong to and no
  window to outlive: it takes an `Audio`, not an `App`, and none of the
  retain/context-save discipline from 3.7–3.9 applies.

  This also **retires the note that used to be here** about fixing
  `SDL_Init`/`SDL_Quit` scoping for `SDL_INIT_AUDIO`. There is no
  `SDL_INIT_AUDIO`: the engine never asks SDL for audio at all. (The scoping
  itself was already fixed in phase 3.7, by refcounting the app handle.)

- **One `Audio` owns one device.** Not a process-wide global the way Gosu does
  it. A game makes one; making two is allowed and gives two devices, the same
  way two `App`s give two windows.

- **`Sample` is decoded, `Song` is streamed.** That is Gosu's split and it maps
  exactly onto miniaudio's `MA_SOUND_FLAG_STREAM`: a short effect played fifty
  times a second should be decoded once and kept, and a three-minute track
  should not become 40 MB of PCM.

- **"One song at a time" is Ruby's policy, not C's.** `Gosu::Song.current_song`
  is a global the port has to reproduce, but it is bookkeeping, not device
  management. `Core::Song` stays a plain handle with `play`/`stop`/`playing?`;
  the registry that stops the previous song is phase 6's `Audio` class. Keeps
  the C layer free of a global it would otherwise have to own.

- **ogg and wav, nothing else.** mp3 and flac are compiled out
  (`MA_NO_MP3`, `MA_NO_FLAC`), along with encoding and the waveform generators —
  measured at **215 KB** of object code saved, and every format left in is
  another parser reachable from a game's asset files.

- **Volume everywhere it is free**: per `Sample#play`, per `Song`, and a master
  on `Audio`. Feature spec §3 asks for it and retrofitting it later would touch
  every signature.

### 5.1 Vendor miniaudio and stb_vorbis, and make a test fixture

Mechanically the same step as 4.1, and it should reuse its machinery: both go in
`ext/rgame_core/vendor/`, each gets a one-line implementation TU, and both names
join `VENDOR_OBJS` in the root `Makefile` and `VENDORED_STB` in `extconf.rb` —
which is exactly the "add a name to two lists" that 4.1's generalised carve-out
was built for. `stb_vorbis.c` is a `.c` rather than a `.h`, so check the pattern
rule copes or adjust it once.

Compile flags for the vendored TU, all measured:

```
-DMA_NO_FLAC -DMA_NO_MP3 -DMA_NO_ENCODING -DMA_NO_GENERATION
-DMA_ENABLE_ONLY_SPECIFIC_BACKENDS -DMA_ENABLE_ALSA -DMA_ENABLE_PULSEAUDIO -DMA_ENABLE_NULL
```

`MA_ENABLE_NULL` is not optional — see the test strategy below. Link needs
`-lpthread` and `-ldl` on Linux/BSD; nothing at all on Windows and macOS.

**The fixture is the awkward part.** The image specs generate PNGs in Ruby with
`zlib`, and the font tests use the font the engine ships. Neither trick works
here: there is no Ogg Vorbis encoder in Ruby's stdlib, and stb_vorbis only
decodes. `libvorbisenc` *is* available as a dev package (verified), so the
answer is a one-off generator committed as a tool, not as a dependency:

- a small C program under `tools/` that links `libvorbisenc` and writes a
  couple of seconds of a known waveform to `spec_core/fixtures/tone.ogg`
- the generated file is committed; the tool is not built by `make`
- a README line saying how to regenerate it, the way `vendor/README.md` records
  how to update the stb headers

A WAV fixture needs no such thing — `dr_wav` is in miniaudio and a WAV can be
written from Ruby in twenty lines, like `PngFixture`.

**Landed.** Three things came out differently from the sketch:

- **The carve-out pattern had to widen from `stb_%_impl.c` to `%_impl.c`.**
  miniaudio is not an stb library and stb_vorbis ships as a `.c`, so neither
  matched. The suffix is now documented as *reserved* for vendored code, since
  it is what turns the warning flags off — a convention with teeth, because a
  file of ours named `*_impl.c` would silently lose its warnings.
- **Feature macros went into `miniaudio_impl.c`, not the build flags.** They
  decide what the engine can *do* — which formats, which sound systems — and in
  build flags they would have to be repeated in the root Makefile and in
  `extconf.rb`, where the day they disagreed the binary and the gem would
  support different formats.
- **`-lpthread`/`-ldl` are probed, not assumed.** `have_library` guards them, so
  the link does not break on Windows and macOS, where miniaudio needs neither.

Measured after trimming mp3, flac, encoding and the generators: miniaudio
contributes **768 KB** to a stripped `core_ext.so` (972 KB total), better than
the 983 KB the decision predicted. The unstripped `.so` is 2.2 MB, almost all of
it debug info from Ruby's own `CFLAGS`.

The fixture works: `tools/make_ogg_fixture.c` writes 0.25 s of stereo — 440 Hz
left, 880 Hz right, deliberately asymmetric so a decoder that drops or swaps a
channel is visible — and the vendored stb_vorbis reads it back as 2 channels,
44100 Hz, 11025 frames with both channels non-silent.

### 5.2 `vorbis_decoder.{c,h}` — teaching miniaudio to read ogg

miniaudio does **not** decode Ogg Vorbis. It does wav, mp3 and flac; vorbis
needs a custom decoding backend, and miniaudio's own reference implementation
uses *system* libvorbis, which would hand back the dependency this whole
decision was about. So the backend is ours, over vendored stb_vorbis.

This is prototyped and working — roughly 150 lines. What the prototype
established, and what would otherwise cost a day of confusion:

- **Both `onInitFile` and `onInit` are needed.** `ma_decoder_init_file` uses the
  first; `ma_engine` — which is where voices and streaming live — reads through
  miniaudio's VFS and calls the second, with read/seek/tell callbacks. A backend
  with only `onInitFile` loads through `ma_decoder` and fails through the engine,
  with `MA_INVALID_FILE` and no hint as to why.
- **stb_vorbis has no callback-based open.** It offers filename, memory, and a
  pushdata API. So `onInit` reads the *compressed* file into memory and uses
  `stb_vorbis_open_memory` — a few MB per track, against the ~40 MB a full PCM
  decode of a three-minute song would cost. Those bytes must outlive the
  `stb_vorbis` handle, so the data source owns them and frees them in `uninit`.
- The data-source vtable needs `onRead`, `onSeek`, `onGetDataFormat`,
  `onGetCursor` and `onGetLength`. Format is `ma_format_f32` via
  `stb_vorbis_get_samples_float_interleaved`.

- **Tests** (`test/test_vorbis_decoder.c`): the fixture decodes to the expected
  channel count, sample rate and frame count; reading returns PCM and then
  reports the end; seeking to the start and re-reading gives the same first
  frames; a truncated or garbage file is refused rather than crashing; a file
  that is not there is refused. Run under the sanitizers like everything else —
  this is the one part of the audio stack parsing untrusted bytes.

**Landed.** ~230 lines and 14 tests, all passing under the sanitizers. Both
prototype findings held up exactly: the engine really does need `onInit` as well
as `onInitFile`, and stb_vorbis really has no callback-based open, so the
callback path buffers the compressed file.

One structural thing the prototype got wrong and this did not: stb_vorbis
**does** honour `STB_VORBIS_HEADER_ONLY`, so it splits into a declarations-only
include and one implementation TU exactly like the other vendored libraries. The
prototype had included the whole `.c` from a header and hit duplicate symbols.

21 mutations, and the survivors are the interesting part — five of them, all
kept deliberately and all now commented in the code:

- **`onRead`'s return code is advisory.** Mutating it to *always* report success,
  or *always* report the end, both survive: miniaudio decides end-of-stream from
  `frames_read` and never looks. Proven by the mutation itself — an assertion
  that the decoder finishes with `MA_AT_END` passes even when the source never
  says so.
- **`onInitFile` is optional.** Without it miniaudio opens the file itself and
  calls `onInit`. It stays because that fallback buffers the whole compressed
  file, and opening by name lets stb_vorbis read from disk.
- **The zero-length guard and the close-before-free ordering** are both belt and
  braces — stb_vorbis refuses an empty buffer on its own, and its `close` never
  looks at the input buffer again. Kept; the comments say why.

The one survivor that was a real gap: a data source can **lie about its format**
and nothing notices, because when the output format matches the input miniaudio
converts nothing and the bytes pass through whatever they are. The test that
catches it asks the decoder for a *specific* output format, forcing a
conversion, and then checks the samples are inside the range a float sample is
defined over. Worth remembering wherever a format is declared separately from
the data it describes.

### 5.3 `audio.{c,h}` — the device, and the two handles

```c
typedef struct rgame_audio rgame_audio;   /* one device + engine */
typedef struct rgame_sound rgame_sound;   /* one Sample or Song */

rgame_audio *rgame_audio_create(char *err, size_t err_size);
void  rgame_audio_destroy(rgame_audio *audio);
void  rgame_audio_set_volume(rgame_audio *audio, float volume);

/* Decoded up front and playable many times over, overlapping. */
rgame_sound *rgame_sound_load(rgame_audio *audio, const char *path, char *err, size_t n);
/* Streamed from disk, for music. */
rgame_sound *rgame_sound_stream(rgame_audio *audio, const char *path, char *err, size_t n);
void rgame_sound_destroy(rgame_sound *sound);

void rgame_sound_play(rgame_sound *sound, float volume, int looping);
void rgame_sound_stop(rgame_sound *sound);
int  rgame_sound_playing(const rgame_sound *sound);
```

One wrinkle worth deciding here rather than discovering: a **decoded** sample
played twice while the first is still sounding needs two voices, and a
`ma_sound` is one voice. miniaudio's answer is `ma_engine_play_sound`, which
spawns a fire-and-forget voice from the resource manager and cleans it up
itself — verified in the prototype with eight overlapping one-shots. So
`rgame_sound_play` on a loaded sample goes through the engine's
fire-and-forget path, while a streamed song owns a persistent `ma_sound` it can
be asked about and told to stop. That asymmetry is the reason the two are
loaded by different functions even though they share a handle type.

**Landed.** 30 tests. The API came out as sketched apart from three things:

- **`rgame_sample_play` takes no volume.** A fire-and-forget voice hands back no
  handle to set anything on, so per-*play* volume is not free after all. Volume
  is per sample instead, via a mixer group every voice of that sample plays
  into, and it reaches voices already sounding. Nothing in the port used
  per-play volume anyway.
- **`rgame_song_looping` was added**, because it is the only way to check the
  looping flag is honoured without playing a song past its own end, which the
  offline test device cannot do (below).
- **A sample holds a never-played `ma_sound`** rather than calling
  `ma_resource_manager_register_file`. Its job is to fail loudly at load and to
  keep the decoded copy alive; see the miniaudio bug below for why the direct
  call is avoided.

**Two real bugs, both found by tooling rather than by reading.**

*A use-after-free in miniaudio 0.11.25.* Any failed load through the resource
manager frees the data buffer node and then reads a field of it a few lines
later (`miniaudio.h:70918` and `:70926`) — so every rejected file was undefined
behaviour. AddressSanitizer caught it on the first run of the "a file that is
not a sound is refused" test. The fix is not to patch the vendored copy, which
the next update would silently undo, but to never hand the resource manager a
file that has not already been checked: `file_is_playable` opens it with a
plain `ma_decoder` first, using the same decoders the real load will.

*A short-read bug in our own vorbis backend.* `stb_vorbis` decodes a packet at a
time and routinely returns fewer frames than asked for, in the middle of a
perfectly healthy file. Passing those partial counts straight up made
miniaudio's streaming path mark the stream finished after the first page —
which presented as "looping music does not loop". `onRead` now fills the buffer
before returning. Worth remembering as a general shape: *a short read means the
end of the data to almost everything that reads*.

**The offline listening tier** — `rgame_audio_create_offline` plus
`rgame_audio_read`, in `audio_internal.h` — is the one thing here the plan did
not anticipate, and it earned its place immediately. miniaudio can run an engine
with no device and hand the mixed output back, which is the audio equivalent of
reading the framebuffer. It catches what no transition test can: that sound
actually comes out, that a volume reaches the output, that stopping silences it.
Three mutations survived everything else and died to it.

Its limit is worth knowing: a *streamed* sound refills its buffers on a thread
that keeps up easily against a real device and starves against a tight pumping
loop — measured, a three-second track goes quiet after exactly two one-second
pages. So nothing offline asks a song to outlive what it has buffered.

Four mutations survive deliberately, each commented at the code: the group stop
before teardown (uninit does it anyway), the playability check on songs
(streaming fails cleanly without it, but "some loads validate and others do not"
is worse than a redundant call), streamed-versus-decoded for songs (identical
for a short fixture; it protects a number nobody measures until a player's
machine swaps), and the rewind in `play` — observable only by playing a song
nearly to its end, which is exactly what the offline device cannot do.

### 5.4 `Core::Audio`, `Core::Sample`, `Core::Song`

```ruby
audio  = RGame::Core::Audio.new
audio.volume = 0.8

hit    = RGame::Core::Sample.new(audio, 'assets/hit.ogg')
hit.play(volume: 0.5)

music  = RGame::Core::Song.new(audio, 'assets/theme.ogg')
music.play(looping: true)
music.playing?
music.stop
```

`Sample` and `Song` are one C class each over `rgame_sound`, differing only in
which loader they call — the same shape as `Image` and its views. `LoadError`
per class, named after the file, like `Image::LoadError` and `Font::LoadError`.

A `Sample`/`Song` marks its `Audio` so the device outlives it. No GL context
save/restore, no app retain: there is no context.

- **Tests**: `spec_core/rgame/core/audio_spec.rb`. Loading a missing or
  malformed file raises; a loaded sample plays without a device present; a song
  reports `playing?` true after `play` and false after `stop`; volume out of
  range is clamped or refused (decide, then test it); `debug_live_sounds`
  returns to baseline after GC, like `Image.debug_live_textures`.

**Landed.** 33 examples in `spec_core/rgame/core/audio_spec.rb`. Four things
differ from the sketch:

- **`hit.play(volume:)` is `hit.volume = 0.5; hit.play`**, following 5.3 — the
  C layer has no per-play volume to expose.
- **Three classes in one `audio_ext.c`**, against the one-class-per-file rule
  the rest of the extension follows. They share a single wrapping shape (a
  handle plus a marked `Audio`), and splitting them would triplicate the
  TypedData boilerplate to separate ninety lines that are read together. Same
  reasoning for `lib/rgame/core/audio.rb`, so the two halves stay parallel.
- **`Song#play(looping:)` is Ruby over a C `play_looping(bool)`.** Keywords are
  a Ruby idea; the C method takes the positional flag, and the wrapper is the
  only thing in the file that needs to exist.
- **Volume above 1.0 is allowed, below 0.0 is clamped** — the decision the plan
  asked for, and it was already made in 5.3's `clamp_volume`. Amplification is
  a real fix for a quiet asset; a negative volume phase-inverts the samples,
  which is *louder*, so silence is the only sensible reading of it.

`Audio.new` takes no app. Nothing about sound is tied to a window, so there is
no GL context to save and restore and no app to retain — the one place this
subsystem is simpler than the drawing side rather than harder.

**The GC-order example bites.** "Keeps its device alive" holds no reference to
the `Audio` it made the sound from, collects, then plays. With `.dmark = NULL`
in place of `sound_ref_mark` it segfaults inside `ma_sound_start`, which is
what it is there to catch — a sound is a voice inside the device's mixer, and
without the mark the collector is free to take the mixer first.

**`example.rb` now takes a sound file** (`ruby ext/rgame_core/example.rb
theme.ogg`): Space plays it as a sample, Return toggles it as looping music.
This is the only place a *real* device is driven — everything automated runs
against a null or offline one — and it is what makes 5.3's "rewind on play"
checkable at all. No default asset, deliberately: a sound file is a thing you
bring. `src/main.c` stays silent; the C driver would need one too.

**A name is now taken.** The inventory in this plan maps `Platform::GosuAudio`
to `RGame::Core::Audio`, but `Audio` is the device. Resolved in phase 6: the
play-by-id registry does not become a class of its own, it folds into this one —
see 6's decisions.

### 5.5 The audio contract, the fake, and where the tests run

The engine layer reaches audio the same way it reaches drawing — by method name
on an object handed to it — so audio gets the same treatment as the renderer:
`spec/support/shared_examples/an_audio_server.rb`, a `FakeAudio` in `spec/`, and
both run against it. Per CLAUDE.md a method added to the real one is not done
until the contract and the fake have it too.

**The test strategy is unusually good here, and it is worth knowing why.**
miniaudio ships a **null backend** — a device that consumes frames on a timer
and produces silence. Verified: with `ma_backend_null` forced, loading,
overlapping one-shots, streaming, looping, `playing?` and `stop` all behave
correctly. So:

- the real audio stack can be exercised **with no sound card**, which makes it
  layer 2 in CLAUDE.md's scheme — a fake backend, exactly like
  `recording_backend.c` for drawing, except that this one comes with the library
- `make test` can therefore cover real loading and playback, not just
  arithmetic, and CI needs no audio device
- `rake spec:core` gets the Ruby-visible surface, again with no device

One caveat to design around: with the null backend a sound "plays" against a
simulated clock, so a test that waits for a short sample to *finish* is timing
dependent. Assert on the transitions the caller controls — play makes it
playing, stop makes it stopped — and not on natural completion.

**Landed, and phase 5 with it.** The contract is
`spec/support/shared_examples/an_audio_server.rb`, 18 examples, with
`with_audio { |audio, sound_path| ... }` as the host hook — a device plus a path
it will load, since loading is the one thing the two implementations genuinely
differ on. `FakeAudio` (plus `FakeSample` and `FakeSong`) is in
`spec/support/fake_audio.rb`, and both sides run against it:
`spec/support/fake_audio_spec.rb` and `spec_core/rgame/core/audio_spec.rb`.
`core_spec_helper.rb` requires the contract across the boundary, the second and
last thing that does.

Two things the sketch did not have:

- **`Audio#sample(path)` and `Audio#song(path)`** were added to the real class.
  `Sample.new(audio, path)` cannot be a contract method — a stand-in device
  cannot offer someone else's constructor — so the interface needed a form that
  starts from the device. Both remain; the constructors are how a C-backed class
  is made, and `audio.sample` is the one to prefer.
- **The fake logs centrally.** Every sample and song reports back to the
  `FakeAudio` that made it, so `audio.played?('hit.ogg')` works without a spec
  holding on to the individual sounds. That is the difference from
  `FakeRenderer`, where there is only one object to call.

**What the contract deliberately omits** is a sound *finishing*. Playback runs
against a clock in both implementations, so "is it still playing a moment later"
has no stable answer; only the transitions a caller controls are stated. The
audio equivalent of `renderer_spec.rb`'s framebuffer read is `test/test_audio.c`
against the offline device, one layer down.

Docs: `docs/api/audio.md`, every example in it executed against the built
extension. The three READMEs and CLAUDE.md record the new files, the two
deviations (three classes per file, and audio's exception to one-class-per-file)
and the second contract.

### What phase 5 does not deliver

Positional or 3D audio (miniaudio has it; nothing in the feature spec asks for
it), effects and filters, fade in/out, mp3 and flac, and the play-by-id registry
— that last one is `GosuAudio`'s job and lands in phase 6 along with the rest of
the Ruby layer.

---

## Phase 6 — Port the Ruby layer

Eleven files, 844 lines. Three of them are already superseded by work that
landed in phases 1–2, one has no port target at all, and seven get rewritten
against `RGame::Core`.

**No spec loads `lib/platform/` and no spec ever will.** It has been a reference
document since phase 0, not running code, and the gemspec excludes it. So "port"
means *rewrite against Core, with the specs these classes never had* — the specs
are the deliverable at least as much as the code is.

**But the layer above is no longer invisible, and that changes how phase 6 is
verified.** `lib/engine/` (3,083 lines, 57 files), `lib/son_gosu_game.rb`, two
runnable games under `examples/`, and `docs/engine/` are all in the tree now.
Constraint 1 stopped being a promise nothing could check:

> **`examples/14_asteroids` and `examples/15_tiled_world` running on
> `RGame::Core` is the definition of done.** Step 6.8 is that, and it is the
> step the rest of the phase exists to reach.

### What the engine layer actually requires

Checked rather than assumed, and the result is better than the plan expected.

**`lib/engine/` names `Gosu` and `Platform::` in comments only** — not one
constant reference in code. It reaches everything through duck-typed seams: a
`renderer` handed to `draw`, `node.root.context.assets` for assets, and an audio
server behind `Engine::AudioDirector`. The layering constraint 1 asks for was
honoured by that layer itself, not merely promised to it, so **it needs no
change to be ported to.**

Three lines in the whole tree name the platform in code, and all three are game
boot: `lib/son_gosu_game.rb` (the `AssetManager` / `GosuRenderer` / `GameWindow`
trio) and `examples/14_asteroids/main.rb:76,82`.
`examples/15_tiled_world/main.rb` names it zero times and should come through
the port untouched — a useful control.

**Nothing calls `SpriteSheet.load`, `UiAtlas.load` or `TileMapRenderer.load`.**
What the code uses are the `AssetManager` instance accessors —
`assets.image/sound/song/sheet/tilemap` — which reach those class methods only
inside loader lambdas. The standalone `.load` conveniences are internal, which
is what keeps the `app` parameter out of the public surface entirely (see the
decisions below).

**The mouse is the one genuine break**, and it is smaller than feared. Setting
aside `lib/engine/ui/`, which is outdated and being replaced on its own account,
it is six lines: `ActionMapper#poll` calls `backend.pointer_x`/`pointer_y`
**unconditionally**, so polling does not run *at all* against a `Core::Input`
that has neither, plus `Actions#pointer_x`/`#pointer_y` and the `Clickable`
component. Fixing it is engine-layer work; it and everything else found while
reading that layer are collected in `docs/plans/engine-replacement/`.

### What each file becomes

| Today | Lines | Becomes | |
|---|---|---|---|
| `gosu_renderer.rb` | 214 | `Core::Renderer` | primitives landed in phase 3; **6.7** folds in the id registry |
| `asset_manager.rb` | 121 | `Core::AssetManager` | **6.6** — logic unchanged, only the loaders differ |
| `tile_map_renderer.rb` | 111 | `Core::TileMapRenderer` | **6.5** |
| `nine_slice.rb` | 81 | `Core::NineSlice` | **6.3** |
| `game_window.rb` | 70 | — | **no port target**; see below |
| `sprite_sheet.rb` | 57 | `Core::SpriteSheet` | **6.2** |
| `ui_atlas.rb` | 50 | `Core::UiAtlas` | **6.4** |
| `gosu_patches.rb` | 47 | — | deleted: fixed-arity callbacks by construction |
| `gosu_audio.rb` | 40 | `Core::Audio` | **6.7** folds in the id registry |
| `gosu_input.rb` | 34 | `Core::Input` + `Util::Controls` | done in phase 2; the mouse half dropped |
| `clock.rb` | 19 | — | deleted: the C loop measures elapsed time |

**`GameWindow`'s port target is not in `RGame::Core` — it is `SonGosuGame`.**
Its two halves went in opposite directions. The accumulator, the catch-up cap,
`@dirty` and `needs_redraw?` became `frame_loop.c` and `Core::App` in phase 1.
What is left — constructing an `Engine::DebugOverlay`, holding `root` and
`mapper`, calling `root.control(actions)` then `root.update(dt)` then
`root.sweep_freed` — is game wiring, not engine code.

`lib/son_gosu_game.rb` is where it goes, and that class is already almost it: a
facade that assembles a mapper, an asset manager, a renderer and a window, then
`start`s. Under Core it stops holding a window and *becomes* one —
`class SonGosuGame < RGame::Core::App` — building its renderer inside
`initialize` after `super`, the way `ext/rgame_core/example.rb` does, and
`start` becoming `run`. Two classes collapse into one. Step 6.8.

### Decisions to take before writing any of it

- **The two registries fold into `Core::Renderer` and `Core::Audio`. They do not
  become new classes.**

  This settles two things at once. It is the answer to
  [open question 3](README.md#open-questions) — "whether `Renderer` stays one
  class" — which was deferred until the primitives existed. They exist, and they
  took the by-object shape (`renderer.image(image, …)`), so a by-id layer is
  needed on top either way. And it dissolves the name collision 5.4 flagged:
  the inventory maps `GosuAudio` → `RGame::Core::Audio`, but `Audio` is now the
  device.

  Two façade classes would need two names for a role that already has one. The
  engine layer is handed exactly one object it calls `renderer` and one it calls
  `audio`; `Core::Renderer` and `Core::Audio` are those objects. Both are
  already pure-Ruby classes over C methods, so the registry has somewhere
  natural to live.

  The cost is real and worth stating: a `Renderer` used only with `Image`
  objects carries four empty hashes it never reads, and both shared contracts
  and both fakes grow. 02-architecture's per-class table already sanctioned
  this shape ("**Ruby** façade over C primitives… revisit if the per-draw hash
  lookup shows up in a profile"), and phase 7 is where that revisit happens.

- **Drawing by id is not a Gosu-era convenience — it is what the layering
  requires.** CLAUDE.md's rule is that the engine layer may hold `Util` values
  and may not hold `Core` handles at all. A `Symbol` is a value; an `Image` is a
  handle. So `:hero` is the *only* thing a node can hold, and the id→asset table
  has to sit on the Core side of the boundary. What looked like indirection
  inherited from the old layer is the boundary itself.

- **Everything ported is pure Ruby under `lib/rgame/core/`.** These are the
  first files there that are not "one Ruby file per C-backed class". The rule
  becomes: `lib/rgame/core/` holds the Ruby half of `RGame::Core`, whether that
  half is a wrapper around a C class or a whole class in Ruby; what makes it
  `Core` is that it holds handles, not that it has C behind it. CLAUDE.md's
  structure section needs that amendment in 6.9.

- **Each ported class is handed a renderer and stores none.** `NineSlice#draw`
  and `TileMapRenderer#draw` take one as their first argument, the same
  discipline the engine layer follows. This is not symmetry for its own sake:
  it is what lets `FakeRenderer` drive them, so nine-slice band geometry and
  tile culling are asserted as *exact recorded calls* — "the top edge tiled
  three times at these five rects" — with no window and no pixels. That is a
  far sharper test than a screenshot, and it is available only if the renderer
  arrives as an argument.

- **The fakes cross the spec-directory line, alongside the contracts.** These
  classes live under `RGame::Core`, so loading one loads the extension and their
  specs cannot live in `spec/`. They go in `spec_core/` — but they should still
  be driven by `FakeRenderer`, which lives in `spec/support/`.
  `core_spec_helper.rb` already crosses for the shared examples; it gains the
  fakes too. CLAUDE.md's rule becomes: **the contracts and the fakes built
  against them cross; no `_spec.rb` ever does.** Safe because a fake that has
  drifted is already a failing example on the other side.

- **The `App` owns the asset manager, so a game never constructs one.** This is
  the answer to the only awkward consequence of Core's design, and it deserves
  the reasoning written out.

  A `Core::Image` belongs to one GL context and says so: `Image.new(app, path)`.
  `Gosu::Image.new(path)` did not, because Gosu has exactly one window backing a
  process-wide `Graphics` singleton — the context requirement is identical, Gosu
  just had a global to answer it from. Left alone, that parameter is viral:
  everything that loads an image needs an `app` to hand it.

  It is viral through the *plumbing* only, and the plumbing has one entry point.
  `AssetManager` is the sole loader — nothing else in the tree loads from a path
  — so the app has to reach exactly one object. Give it to the `App`:

  ```ruby
  class MyGame < RGame::Core::App
    def initialize
      super(width: 640, height: 480, caption: 'demo', media_root: MEDIA)
      @renderer = RGame::Core::Renderer.new(self, assets: assets)
    end
  end

  app.assets   # => AssetManager, rooted at media_root, built on first use
  app.audio    # => Audio, the device, opened on first use
  ```

  Both are lazy. An app that draws only primitives builds no asset manager; one
  that never plays a sound never opens a device — which is also the right moment
  to open it, since `assets.sound(path)` is the first thing that needs one.
  `media_root:` becomes a fourth, optional keyword on the C `initialize`
  (`rb_get_kwargs` with one optional key), defaulting to `'media'`.

  What this buys, checked against the real callers:

  | Call | Change |
  |---|---|
  | `assets.image/sound/song/sheet/ui_atlas/tilemap/read(path, group)` | **none** |
  | `assets.preload` / `release` / `clear` | **none** |
  | `SpriteSheet.new(image, atlas)`, `UiAtlas.new(image, data)`, `NineSlice.new(image, …)` | **none** — they never loaded anything |
  | `SpriteSheet.load` / `UiAtlas.load` / `TileMapRenderer.load` | gain an `app`, but nothing calls them; they are reached from loader lambdas that close over it |
  | `AssetManager.new(root:)` | a game stops writing it at all |

  So the parameter exists in exactly one place a game never types. The
  alternatives considered and rejected: a process-wide *current app*, which
  brings back the global the two-window design deliberately does not have;
  shared GL contexts via `SDL_GL_SHARE_WITH_CURRENT_CONTEXT`, which was measured
  to work and would delete the cross-app checks, but is a change to `app.c` in
  service of a multi-window capability nothing asks for; and a singleton `App`,
  which would break `spec_core`'s window-per-example structure. None of them is
  needed once the app has one place to be.

- **The ordering rule is not new, only visible.** `app.assets` means the window
  exists before anything loads. That was already true under Gosu, which needed a
  window before `Gosu::Image.new` and enforced it with a runtime failure —
  `examples/14_asteroids/main.rb:75` says so in a comment. The one place it
  bites is `SonGosuGame`, which today builds the asset manager and renderer
  *before* the window; 6.8 reorders it, and it is being rewritten anyway.

- **`retro: true` disappears.** Every `Gosu::Image.new(path, retro: true)` in
  the old layer becomes `Core::Image.new(app, path)`: `image.c` uploads with
  `GL_NEAREST` unconditionally, so the flag has no counterpart and no default to
  get wrong. Pixel art was the only mode the old layer ever asked for.

- **`Recording` tints, so `TileMapRenderer`'s caveat goes.** Its class comment
  warns "recorded images draw only in white (no tint) — fine here, we don't
  tint". `Recording#draw` takes `color:` and multiplies it through. Delete the
  caveat rather than carrying it over.

- **Out of scope, deliberately:** moving any of this into C. 02-architecture's
  table marks `NineSlice`'s tiling and `TileMapRenderer`'s animated-tile loop as
  future C, and phase 7 is where that happens *after a measurement*. Phase 6
  writes all of it in Ruby, and the `FakeRenderer` specs written here are what
  will hold phase 7 honest — a C rewrite that produces the same recorded calls
  is a rewrite that cannot have changed behaviour.

### 6.1 `Renderer#image_at` — the top-left scaled draw

The one capability gap the port runs into. Core has two image draws:

```ruby
renderer.image(image, cx, cy, angle: 0, scale: 1)  # centred, uniform scale
renderer.background(image, x = 0, y = 0)           # top-left, no scale
```

Three of the ported classes need a third: top-left anchored with *independent*
x and y scales. `SpriteSheet#draw` flips a frame horizontally
(`frame.draw(x + w, y, z, -1, 1)` in Gosu — a negative x-scale), and `NineSlice`
draws its corners and tiles at an integer pixel scale. Neither is expressible
today.

```ruby
# Top-left at (x, y), scaled independently per axis. A negative scale mirrors
# about that axis, which is how a sprite faces the other way.
renderer.image_at(image, x, y, scale_x: 1, scale_y: 1, z: IMAGE_Z, color: nil)
```

`background` stays, delegating with both scales at 1 — "draw this at the origin"
is a real thing to want and reads better than `image_at(image, 0, 0)`. It is
already in the contract, the fake, `docs/api/drawing.md` and `example.rb`, so
removing it is churn for nothing.

The alternative is no new primitive: `renderer.scaled(-1, 1) { … }` around each
draw. It works, and for `NineSlice` it is arguably *better* — a whole band can
be drawn inside one `scaled(s, s)` push, in source-pixel coordinates. But per
sprite it is two extra C calls plus a division on the hottest path in the
engine, to avoid twenty lines of C that mirror `rgame_prim_image_rot` almost
exactly. Write the primitive.

Layer 1 first, as always:
`rgame_prim_image_scaled(canvas, view, x, y, scale_x, scale_y, color, z)` in
`ext/rgame_core/graphics/primitives.c`, then the `draw_image_scaled` method in
`ruby/renderer_ext.c`, then the Ruby keyword wrapper.

- **Tests**: `test/test_primitives.c` — a negative scale must mirror the quad
  about `x`, *not* move it (the failure mode is a sprite that faces the right
  way and stands one width to the left, which reads as a positioning bug). A
  scale of 1 must produce byte-identical vertices to `rgame_prim_image`, so the
  two paths cannot drift.
- Then `spec/support/shared_examples/a_renderer.rb`, `FakeRenderer`, and a
  framebuffer example in `spec_core/rgame/core/renderer_spec.rb` that reads back
  a mirrored 2×1 image and checks the pixels swapped.
- **Verify**: `make test`, `rake spec`, `rake spec:core`.

**Landed.** `rgame_prim_image_scaled` in `graphics/primitives.c`,
`rgame_app_draw_image_scaled` in the public header, `draw_image_scaled` in
`ruby/renderer_ext.c`, `Renderer#image_at` in `lib/rgame/core/renderer.rb`. Six
Check tests (318 total), two contract examples, three framebuffer examples.

Three notes:

- **The mirror is in the texture coordinates, not the geometry.** `textured_rect`
  grew `flip_x`/`flip_y` flags that swap the `u` of the two top corners and of
  the two bottom ones; `image_scaled` passes the *sign* of each scale as the
  flag and the *magnitude* as the size. Handing in a negative width would have
  produced the same picture in the wrong place, which is exactly the convention
  this step rejected.
- **`rgame_prim_image` is now `image_scaled` at 1, 1.** The "byte-identical
  vertices" test the plan asked for is therefore a tautology today — kept
  anyway, and commented as to why: the shared implementation is free to change
  back, and "the backdrop moved half a pixel" is not something anyone would
  come looking for in this file.
- **Both tiers were mutation-checked.** Ignoring the sign entirely, and
  switching to the Gosu convention (negative width, mirror about the anchor),
  each fail 3 Check tests and 2 of the 3 pixel examples. The pixel example that
  survives the second mutation is the pure scaling one, which is correct — it
  says nothing about signs.

### 6.2 `Core::SpriteSheet`

```ruby
sheet = RGame::Core::SpriteSheet.load(app, 'media/hero.json')
sheet.frame_width   # => 16
sheet.animations    # => the raw table, for the engine's AnimationSet
sheet.draw(renderer, row, col, x, y, flip_x: false, z: 0)
```

A near-mechanical rewrite. The grid arithmetic (cells larger than frames,
`origin_x`/`origin_y` offsets within a cell) is unchanged, `image.subimage` is
`Core::Image#subimage` with the same signature, and `Gosu::Image.new(path,
retro: true)` becomes `Core::Image.new(app, path)`.

The one behavioural line is the flip, which becomes `image_at`:

```ruby
def draw(renderer, row, col, x, y, flip_x: false, z: 0)
  renderer.image_at(@frames[row][col], x, y, scale_x: flip_x ? -1 : 1, z: z)
end
```

Note what is *not* there: the `x + @frame_width` the Gosu version needed. 6.1
mirrors inside the rectangle rather than about the anchor, so the branch and the
compensating add both go away.

- **Tests**: `spec_core/rgame/core/sprite_sheet_spec.rb`, driven by
  `FakeRenderer` with a stub image that answers `subimage`, `width` and
  `height`. Which cell a `(row, col)` maps to; that a frame smaller than its
  cell is taken from the right offset; that `flip_x` mirrors *and* shifts by
  exactly one frame width, so the sprite occupies the same rectangle either way.
  A separate handful of examples with a real `Core::Image` covers `.load`:
  the descriptor is parsed, the image is resolved relative to the descriptor,
  and a missing file raises.
- **Verify**: `rake spec:core`, RuboCop.

### 6.3 `Core::NineSlice`

```ruby
slice = RGame::Core::NineSlice.new(image, x:, y:, w:, h:, border:, scale: 1)
slice.draw(renderer, dx, dy, dw, dh, z: 0, color: nil)
```

The nine sub-images are still cut once at construction, so `draw` allocates
nothing. Three substitutions:

- `Gosu.clip_to(bx, by, bw, bh) { … }` → `renderer.clipped(bx, by, bw, bh) { … }`
- `img.draw(x, y, z, s, s, color)` → `renderer.image_at(img, x, y, scale_x: s, scale_y: s, z: z, color: color)`
- `color: Gosu::Color::WHITE` → `color: nil`, Core's "no tint" default

The band clamping (`inner_w = 0 if inner_w.negative?`) matters and is easy to
lose: a widget drawn narrower than its own borders must draw *no* centre rather
than a negative-width one.

- **Tests**: `spec_core/rgame/core/nine_slice_spec.rb`, entirely against
  `FakeRenderer`. This is the class that gains most from recorded calls — the
  assertion is the exact list of rects. Cover: the four corners land at the four
  corners at `scale`; each edge band tiles the right number of times and is
  clipped to its band, so the trailing tile is cropped; a widget smaller than
  its borders draws corners only; the tint reaches every call. `FakeRenderer`
  records transform depth, so "the tiles were drawn *inside* the clip" is
  checkable, which is the bug this class would otherwise ship silently.
- **Verify**: `rake spec:core`, RuboCop.

### 6.4 `Core::UiAtlas`

```ruby
atlas = RGame::Core::UiAtlas.load(app, 'media/ui.json')
atlas.nine_slices    # => { button_idle: <NineSlice>, … }
```

Pure descriptor parsing, load-time only, and the smallest step in the phase.
`Gosu::Image.new` → `Core::Image.new(app, path)` in `.load`; everything else —
the uniform-integer-or-hash `border`, the per-entry `scale` override — is
unchanged.

- **Tests**: `spec_core/rgame/core/ui_atlas_spec.rb`. Border given as an integer
  expands to four sides; given as a hash with string keys it is symbolised; a
  per-entry `scale` beats the sheet default; an atlas with no `nine_slices` key
  yields an empty hash rather than raising. A stub image is enough for all of
  them.
- **Verify**: `rake spec:core`, RuboCop.

### 6.5 `Core::TileMapRenderer`

```ruby
tiles = RGame::Core::TileMapRenderer.load(app, 'media/level1.tmx')
tiles.draw(renderer, camera_x, camera_y, viewport_width, viewport_height)
tiles.draw_overlay(renderer, camera_x, camera_y, viewport_width, viewport_height, z: 20)
```

This one still names `Engine::TileMap` and `Engine::Tileset` in `.load`, and
those still do not exist here. **It ports anyway**, because everything after
`.load` treats the map duck-typed — `@map.gid(li, col, row)`,
`@map.above_layer?(li)`, `@tileset.frame_local_id(local, ms)`. A spec supplies a
fake map, exactly the way a spec supplies a fake renderer, and the whole class
is covered without the engine layer existing. Only `.load` is left uncovered,
and it is four lines of file plumbing.

Four substitutions:

- `Gosu::Image.load_tiles(path, tw, th, retro: true)` → `Core::Image.load_tiles(app, path, tw, th)`
- `Gosu.record(w, h) { … }` → `renderer.record { … }`. Core infers the recording's
  extent from what was drawn instead of being told it up front; since tiles are
  baked from `(0, 0)`, `recording.draw(-camera_x, -camera_y)` places them
  identically.
- `Gosu.milliseconds` → `@app.ticks_ms`, for animated-tile frame selection. From
  the app this class already holds, **not** through `renderer.app`: adding `app`
  to the renderer contract would hand the engine layer a route to a `Core::App`
  through an object it is allowed to call by name, which is exactly the hole the
  layering exists to close. A spec passes a stub app answering `ticks_ms`, which
  also makes the animation clock controllable.
- `@tiles[local].draw(x, y, z)` → `renderer.image_at(tile, x, y, z: z)`

The lazy bake (`@static_below ||= bake_layers { … }`) stays lazy and stays
inside `draw`, for the same reason as before: recording needs a live context,
and `Renderer#record` may only be called inside a frame.

- **Tests**: `spec_core/rgame/core/tile_map_renderer_spec.rb`, with a fake map
  and `FakeRenderer`. The below/above split sends the right layers to the right
  band; static tiles are baked exactly once and replayed thereafter (assert the
  second `draw` adds no `record` call — a rebake per frame is the expensive bug
  this class exists to avoid, and it is invisible except as a frame-rate drop);
  animated tiles are culled to the viewport, inclusive at the near edge and
  exclusive at the far one; the animation frame follows the clock.
- **Verify**: `rake spec:core`, RuboCop.

### 6.6 `Core::AssetManager`

```ruby
app.assets.image('space.png')
app.assets.preload(:level1, image: ['lvl1/bg.png'], sound: ['lvl1/hit.ogg'])
app.assets.release(:level1)
```

The cache, the group ownership sets, the reference counting and the composite
building are **unchanged, line for line**. Two things around them change.

`DEFAULT_LOADERS` stops being a constant, because every loader needs the app or
the device:

```ruby
def default_loaders(app)
  {
    image: ->(path) { Image.new(app, path) },
    sound: ->(path) { app.audio.sample(path) },
    song: ->(path) { app.audio.song(path) },
    tilemap: ->(path) { TileMapRenderer.load(app, path) },
    read: ->(path) { File.read(path) }
  }.freeze
end
```

Reaching `app.audio` *inside* the proc rather than capturing it at construction
is what keeps the device lazy: loading an image opens no sound device, and the
first `assets.sound(path)` opens one.

And `AssetManager.new` becomes internal — `App#assets` is the only caller, so
the signature is whatever suits it (`new(root:, app:, loaders: nil)`). Games
stop naming the class.

Keep the injectability. The old comment explains it as "so the cache/grouping
logic is testable without Gosu", and `docs/engine/asset_manager.md` records that
`spec/platform/asset_manager_spec.rb` did exactly that. It holds verbatim with
Core in Gosu's place, and it is why this class's real logic can be specced
against `->(path) { path }` loaders with no files and no GL at all.

- **Tests**: `spec_core/rgame/core/asset_manager_spec.rb`, almost all of it with
  recording loaders. The same path twice loads once; a hit under a second group
  tags it with both; `release` drops only what no group still holds; a
  `PERMANENT` (ungrouped) asset survives every `release` and only `clear` takes
  it; a failed load leaves no owner behind, so a retry is a clean retry; a
  sheet's PNG shares a cache key with a standalone `image` of the same file.
  A couple of examples with the real loaders confirm the wiring, and one that
  `App#assets` is lazy, memoised, and does not open an audio device until a
  sound is asked for.
- **Verify**: `rake spec:core`, RuboCop.

### 6.7 The registries: `Renderer` and `Audio` grow their id tables

The last of `gosu_renderer.rb` and all of `gosu_audio.rb`.

**Resolution through the asset manager is the primary path; registration is the
override.** `docs/engine/asset_manager.md` is explicit about this and it is easy
to get backwards — a draw id is normally a *root-relative path*, which the
renderer resolves through `assets` and then memoises so a per-frame draw neither
re-resolves nor allocates a lookup key:

```ruby
renderer.sprite('example 09/player.json', row, col, x, y)   # nothing registered
```

`register_*` pre-binds an id to a chosen object, and exists for the two cases a
path cannot cover: an id that is not a file (nine-slice ids are *atlas element*
names), and an object the game built itself.

```ruby
renderer.register_image(:space, app.assets.image('space.png'))
renderer.register_nine_slice(:panel, atlas.nine_slices[:panel])
renderer.register_ui_atlas(atlas)          # every element in one call
renderer.register_sheet(:hero, app.assets.sheet('hero.json'))
renderer.register_tilemap(:level1, tiles)

renderer.sprite(:hero, row, col, x, y, flip_x: false, z: 0)
renderer.nine_slice(:panel, x, y, width, height, z: 0, tint: nil)
renderer.tilemap(:level1, camera_x, camera_y, viewport_width, viewport_height)
renderer.tilemap_overlay(:level1, camera_x, camera_y, vw, vh, z: 20)
```

Two things to carry over exactly:

- **The lookup order and its error.** `sheet_for(id)` prefers an explicit
  registration, otherwise asks the `AssetManager` by symbol or path, then
  memoises. The `KeyError` when neither can supply it names both the type and
  the id, and is worth keeping word for word — it is the error a game hits most.
- **`register_image` and friends take an already-loaded object.** Loading is the
  `AssetManager`'s job. The registry only records.

`Core::Renderer` currently takes an `App`; it gains `assets: nil`, defaulting to
that app's own manager so the common case wires itself. Its `initialize` is C
and has fixed arity, so the keyword arrives the way `Font`'s `path:` does — a
Ruby `self.new` that unpacks it before calling `super`.

On the audio side:

```ruby
audio.register_sound(:hit, assets.sound('hit.ogg'))
audio.register_music(:theme, assets.song('theme.ogg'))
audio.play_sound(:hit)
audio.play_music(:theme)   # idempotent: already playing is a no-op
audio.stop_music
```

One deliberate behaviour change. `stop_music` was
`Gosu::Song.current_song&.stop` — a process-wide global. Core has no such
global, by the decision in phase 5 that "one song at a time is Ruby's policy".
So the registry tracks the song it started and stops that one. A game that
starts a `Song` by hand, outside the registry, is not affected by `stop_music`,
which is both more predictable and the only thing implementable without
reintroducing the global.

- **Tests**: both shared contracts grow, and both fakes with them —
  `a_renderer.rb` gains the register/draw-by-id pair, `an_audio_server.rb` gains
  the sound registry including the idempotent `play_music` and the
  stop-what-I-started rule. Per CLAUDE.md a method on the real one is not done
  until the contract and the fake have it. Then in `spec_core`: an unregistered
  id with no `AssetManager` raises `KeyError` naming both; an id resolved
  through an `AssetManager` is resolved once and memoised; `register_ui_atlas`
  registers every element.
- **Verify**: `make test`, `rake spec`, `rake spec:core`, RuboCop.

### 6.8 Port the game shell, and run the two examples

The step everything above exists to reach, and the first time any of it is
proved rather than asserted.

`SonGosuGame` stops holding a window and becomes one:

```ruby
class SonGosuGame < RGame::Core::App
  attr_reader :action_mapper, :renderer

  def initialize(root:, width: WIDTH, height: HEIGHT, caption: 'SonGosu Game',
                 media_root: 'media', action_map: {})
    super(width: width, height: height, caption: caption, media_root: media_root)
    @action_mapper = Engine::ActionMapper.new(action_map)
    @renderer = RGame::Core::Renderer.new(self)
    @root = root
    @overlay = Engine::DebugOverlay.new
    @dirty = true
  end
end
```

`GameWindow`'s body moves in with it, minus the accumulator: `frame_begin` polls
the mapper once per frame, `update(dt)` runs one tick
(`control` → `update` → `sweep_freed`), `needs_redraw?` is
`@dirty || @overlay.visible?`, `draw` draws the root then the overlay, and
`button_down` handles Escape and F1. `start` becomes `run`, with the
`root.context = self` and `root.enter_tree` wiring kept ahead of it.

Note what the merge deletes: the `renderer:` and `mapper:` constructor
parameters, because the object that needed passing them is now the object that
owns them.

Then the two games, in this order — the second is the control:

- **`examples/14_asteroids`** — drop its own `AssetManager` (it builds one while
  `game.assets` already exists, so today there are two caches) and its
  `Platform::GosuAudio`, using `game.assets` and `game.audio`. Three lines
  change; everything from `register_image` down is untouched.
- **`examples/15_tiled_world`** — names the platform zero times. It must run
  with **no edit at all**, and if it needs one, that is a finding about the port
  rather than about the example. It is also the only thing that exercises
  `TileMapRenderer`, `AnimatedSprite` and the camera end to end.

Neither runs until the mouse is dealt with: `ActionMapper#poll` calls
`backend.pointer_x`/`pointer_y` unconditionally. Delete those two lines and
`Actions`' pointer accessors — the smallest change that makes the engine layer
run, and the rest of the mouse cleanup belongs to
`docs/plans/engine-replacement/`.

- **Tests**: none new. This step is manual and visual by nature — it is CLAUDE.md's
  layer-3 tier, the same one `make run` occupies. What it verifies is the thing
  no headless spec can: that the pieces compose into a game.
- **Verify**: both examples run, play, and quit cleanly; sprites animate, the
  tile map scrolls with canopies over the actors, sounds fire, music loops. Then
  the full sweep, since this step touches `App` and `Renderer`.

### 6.9 Delete `lib/platform/`, and the cleanup that follows

Only now, when everything above is green *and both examples run* — the old files
are the reference the port is read against, and deleting them early throws that
away for no gain.

- `rm -r lib/platform/`.
- Drop `gem 'gosu'` from the `Gemfile`, `bundle install`, commit the lockfile.
- Retire `Game/PreferGosuModuleMethod`: delete
  `rubocop/cop/game/prefer_gosu_module_method.rb`, its `require` line in
  `.rubocop.yml`, and its row in the comment block there and in CLAUDE.md's cop
  table (five cops become four). It has no spec of its own, so nothing else
  goes. The principle it enforced is now structural: the C bindings have fixed
  arity and there is no compat shim to prefer against.
- Remove the `lib/platform/` exclusion from `rgame.gemspec` and the matching
  expectation in `spec/packaging_spec.rb` — both are commented as going with it.
  The other packaging expectations must keep passing untouched, which is what
  proves the newly added `lib/rgame/core/*.rb` files ship.
- **Replace it with an exclusion for the engine layer, for now.** `spec.files`
  is a glob over `lib/`, so the arrival of `lib/engine/`, `lib/engine.rb`,
  `lib/boot.rb` and `lib/son_gosu_game.rb` silently added **60 files** to the
  gem, one of which (`son_gosu_game.rb:4`) does `require 'gosu'` against a gem
  that is not a dependency. `spec/packaging_spec.rb` stays green because it
  derives its expectations from the same tree in both directions — the glob is
  doing exactly what it was designed to do, which is why the fix is an
  exclusion plus an asserted expectation, not a change to the glob. Both come
  back out when the layer becomes `lib/rgame/engine/` and *should* ship; that is
  noted in `docs/plans/engine-replacement/`.
- Drop the "only if you keep gosu in the Gemfile" apt and brew lines from
  `README.md`, and the paragraph explaining why gosu is pinned. `lib/boot.rb`
  and `lib/son_gosu_game.rb` stop requiring it.
- `.rubocop.yml`: drop the stale `spec/integration/**/*` exclude, which points
  at a directory this repo does not have. Keep the `lib/rgame/engine/**/*.rb`
  ones — that path is the engine layer's, and the cop that reads it is the guard
  for work still to come.
- **Amend `docs/c_engine_feature_specs.md`.** Two places where it now
  contradicts decisions this plan took and recorded: §1 says the fixed-timestep
  accumulator "stays on the engine side of the boundary" (it is in
  `frame_loop.c`), and §1 and §5 list mouse state as required (it was
  deliberately dropped). Both have been outstanding since phases 1 and 2; this
  is the last chance to close them before the plan folder is deleted.
- Documentation, per CLAUDE.md's rule that plans do not outlive their work:
  a new `docs/api/assets.md` covering `AssetManager`, `SpriteSheet`, `NineSlice`,
  `UiAtlas` and `TileMapRenderer`; the by-id sections added to
  `docs/api/drawing.md` and `docs/api/audio.md`; the new files in CLAUDE.md,
  `README.md` and `ext/README.md`; and CLAUDE.md's structure section amended for
  the two rules this phase changed — pure-Ruby classes under `lib/rgame/core/`,
  and the fakes crossing into `spec_core/`.

- **Verify** (the full sweep, and the one that matters most in this phase):
  `make test`, `rake spec`, `rake spec:core`, `bundle exec rubocop`, zero build
  warnings, and

  ```
  ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
  # => []
  ```

  plus one that is specific to this step:

  ```
  grep -ril gosu lib ext spec spec_core examples rubocop Gemfile .rubocop.yml
  ```

  returns nothing except `lib/engine/`'s comments and `son_gosu_game.rb`'s name,
  both of which belong to the next plan. Only `docs/` may still say the word,
  and there only to explain what the engine replaced. That is the actual end
  condition of this one.

### 6.10 Fold the plan back and delete it

With `lib/platform/` gone, this folder has served its purpose. Whatever is still
true moves into the real documentation — the decisions in
[the brief](README.md) that explain *why* the engine looks the way it does
(vendored font, vendored audio, no mouse, accumulator in C) belong in CLAUDE.md
or `docs/api/`, not in a plan. Then delete
`docs/plans/gosu-replacement/`; git history keeps it.

The landed notes are the exception worth reading before deleting: several record
a deliberate deviation or a surviving mutation whose reasoning exists nowhere
else. Anything in that category goes into a comment at the code it describes,
which is where it should have been all along.

### What phase 6 does not deliver

Any of it in C — that is phase 7, and only where a measurement asks for it.

And the engine layer itself. `lib/engine/` runs against Core at the end of phase
6, which is all this plan ever promised, but it is still `Engine::` rather than
`RGame::Engine`, still carries a `Tensor` that duplicates the C one, still has a
UI package built on a mouse that no longer exists, and does not yet do the
split-screen the transform and clip stacks were designed for. Moving it is the
next effort, planned separately in `docs/plans/engine-replacement/` — which
already holds everything phase 6 turned up while reading it, so nothing has to
be rediscovered.

---

## Phase 7 — Move the hot paths into C

Only after profiling, and only where there's a measured reason:

- `NineSlice`'s five clipped tiling loops per call per frame.
- `TileMapRenderer`'s per-visible-animated-tile draw loop — feature spec §4's
  explicitly named sore point. With phase 3b's batching this may already be
  fast enough, which would be the nicest possible outcome.
- `Renderer`'s per-draw id→asset hash lookups, if they show up at all.

Deliberately last. Each of these is a straightforward move once the pure
geometry is separable, and doing any of them early trades readability for a
speedup nobody has measured.
