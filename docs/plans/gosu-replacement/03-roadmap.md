# 03 — Roadmap

Detailed for phases 0–4. Phases 5–7 stay deliberately rough: they get
re-planned once the layer beneath them exists and the shape of the problem is
concrete rather than imagined. That is what happened to phase 3 — re-written
from eight bullets into nine landable steps once phase 2 was done and the GL
situation had been measured rather than assumed — and to phase 4, which stayed
one paragraph until the default-font question had been answered by reading
Gosu's sources instead of guessing at them.

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

**Recommendation: SDL_mixer for v1.** It gives ogg decode, streaming, looping
and a playing-query almost for free. The cost is one more system dependency in
the README's install lists. A hand-rolled mixer over `SDL_audio` +
`stb_vorbis` adds no dependency but is a real project on its own, and audio is
not where this rewrite's interesting problems are.

Independent of phases 3–4; schedule it wherever convenient.

Fix `SDL_Init`/`SDL_Quit` scoping here — audio wants `SDL_INIT_AUDIO`
initialised separately from video, and the current per-app `SDL_Quit`
(`core.c:77`) tears down everything.

---

## Phase 6 — Port the Ruby layer

With the C surface complete, move `lib/platform/` to `lib/rgame/core/`, class by
class, preserving every public API:

`Renderer` (ex-`GosuRenderer`) → `SpriteSheet` → `NineSlice` → `UiAtlas` →
`TileMapRenderer` → `AssetManager` (only `DEFAULT_LOADERS` changes) → `Audio`.

Then delete `lib/platform/`, drop `gosu` from the `Gemfile`, retire the
`Game/PreferGosuModuleMethod` cop, and clean the `.rubocop.yml` excludes that
point at paths this repo doesn't have.

The `Engine::` references (`DebugOverlay`, `TileMap`, `Tileset`) stay as they
are — they name the pure-Ruby engine layer that will sit on top, and the whole
point of constraint 1 is that it doesn't have to change.

The **one** thing that layer will have to change is anything built on the mouse:
the `:pointer` binding and `pointer_x`/`pointer_y` existed to serve click-based
UI hit-testing somewhere above, and that has to become keyboard/controller
navigation. Outside this plan's scope, but it is the visible cost of the
mouse decision and it is easier to plan for now than to discover here.

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
