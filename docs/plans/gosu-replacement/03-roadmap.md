# 03 — Roadmap

Detailed for phases 0–2, which are the next things to actually do. Rough after
that on purpose: the later phases will be re-planned once the render foundation
exists and the shape of the problem is concrete rather than imagined.

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

The bulk of the work. Detail here is deliberately thinner; it gets re-planned
once phase 2 lands. Sub-order matters more than sub-detail:

- **3a `color.{c,h}` + `Util::Color`.** Trivial, unblocks every other
  signature. `Color.rgba(r,g,b,a)`, `Color::WHITE`, and the tri-modal
  `nil`/`Array`/`Color` acceptance `GosuRenderer#resolve_color` promises.
  Built in `ext/rgame_util/`, not `ext/rgame_core/`: a colour is a value, and
  the engine layer must be able to hold one as an attribute.
- **3b `draw_queue.{c,h}` — z-sort + batching.** Pure C, zero GL, full Check
  coverage. This is the piece the whole engine's correctness rests on and the
  reason `glEnable(GL_DEPTH_TEST)` has to go; see
  [02](02-architecture.md#the-draw-queue). Build it before anything is drawn.
  The clip rect must travel *with* each command into the queue and form part of
  the batch key — sorting reorders commands across viewports, so a clip left as
  ambient state would scissor the wrong quads. That is a split-screen
  requirement landing on the very first renderer module.
- **3c `transform.{c,h}` + `clip.{c,h}`.** Pure C, Check-tested. Push/pop
  translate, rotate-about-pivot, scale, and intersecting clip rects. **Real
  stacks, because split-screen is in scope** — several clip+transform regions
  composed and torn down within one frame, cleanly and repeatably, not one
  global "current region" that only works while a single viewport is active.
  See [02](02-architecture.md#split-screen-is-a-requirement-on-this-design-not-a-later-feature).
  Check tests should include the split-screen shape directly: two viewports,
  two camera offsets, one world draw each, asserting on the recorded batches.
- **3d `backend.h` + a recording fake.** Layer 2, added exactly here — the point
  at which real GL calls first appear.
- **3e `gl_backend.c`.** Layer 3, thin. Client-side vertex arrays
  (`glVertexPointer` + `glDrawArrays`), no loader — the decision and its
  rationale are in [02](02-architecture.md#the-gl-shim).
- **3f `texture.{c,h}` + `Core::Image`.** `stb_image` decode, `GL_NEAREST`
  upload, subimage-as-UV-view, `load_tiles`. The rect arithmetic is pure and
  tested; only decode+upload is not.
- **3g Primitives.** Textured quad (position, rotate about arbitrary pivot,
  non-uniform scale, flip, tint), filled rect, filled quad from four points,
  filled triangle.
- **3h Record + render-to-texture.** `Core.record` (retained batch) and
  `Core.render` (FBO → texture). Unblocks the tile-map static bake and the
  circle texture.

After 3g, most of `GosuRenderer` is portable: `rect`, `line`, `sprite`,
`image`, `background`, `rotated`, `translated`, `debug_box` — plus `clipped`,
the one method the rewrite *adds* to the Ruby API, which is all split-screen
needs from Ruby's side. After 3h, `circle` — though with a real batching
renderer, a per-call triangle fan may be cheap enough to drop the cached-texture
trick entirely, which would be a genuine simplification.

This is also the point where the **headless integration tier** CLAUDE.md
describes but hasn't built (Xvfb + Mesa llvmpipe, `glReadPixels` spot checks)
becomes worth standing up: there is finally real rendering to check without a
human watching.

---

## Phase 4 — Text

`stb_truetype` + a glyph atlas. `Core::Font` with `#draw_text`, `#text_width`,
`#height`. Pure/testable parts: atlas packing, glyph cache lookup and eviction,
string width from advances.

Blocked on the default-font question in
[the brief](README.md#open-questions) — `Gosu::Font.new(18)` needed no path,
and preserving `GosuRenderer#initialize`'s signature means the new `Font` needs
some default too.

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
