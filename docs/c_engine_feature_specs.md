# C engine feature spec

**Purpose:** this document specifies the feature set the C layer needs in order to sit
under a 2D game engine written in Ruby. It was derived from an exhaustive inventory of
every call the engine's platform layer made into [Gosu](https://github.com/gosu/gosu),
the library this engine replaced, plus a handful of features committed to but not yet
implemented at the time (gamepad input, split-screen).

**Nearly all of it now exists**, so read it as scope and as a record of what was
decided rather than as a to-do list. Two items are marked as amended, where the
implementation deliberately went the other way; the section on things "not currently
used but worth deciding deliberately" is the part still worth consulting before adding
a subsystem.

**Design context that shaped this list:** the source engine keeps a strict separation —
game logic never touches the platform layer directly, only a small set of interfaces
(`Renderer`, `AudioServer`, `InputBackend`, a `Clock`). Every Gosu call in the whole
codebase lives behind those interfaces, which is exactly why this inventory is
complete: nothing else in the engine can be calling into Gosu. A C rewrite should
preserve that same seam — a thin binding layer implementing these primitives, with all
game/engine logic on the other side of it and ignorant of the implementation.

---

## 1. Basic / SDL functionality

Window, timer, main loop, input.

**Required (currently used):**

- Window creation with fixed width/height and a caption string.
- A main loop with per-frame callbacks: `update`, `draw`, and a `needs_redraw?`-style
  hook so a frame can be skipped when nothing changed (draw is expensive; simulation
  should be able to run without forcing a redraw every tick).
- A window-close / teardown call.
- Keyboard state: "is this key currently held" query, addressable by a stable set of
  key constants (arrows, return/confirm, space, escape, at minimum — the actual key set
  is small and fixed).
- ~~Mouse state.~~ **Dropped, deliberately.** The layer being replaced handled the
  cursor and a click button, and none of it was carried over: `RGame::Core::Input`
  has no pointer, no `:pointer` binding, and the button-id space covers keyboard
  and controllers only — the range a mouse would have occupied is left unused in
  `rgame/core.h` rather than renumbered later. The visible cost is that
  click-based UI hit-testing has to become keyboard and controller navigation,
  which the engine layer owes.
- A discrete key-press event callback (distinct from "is held" polling) — used for
  one-shot actions like toggling a debug overlay or handling Escape-to-quit.
- Monotonic millisecond timer, for computing frame delta time. Exposed as
  `App#ticks_ms`, and **not** for driving animation: nothing on a draw path reads
  a clock, because `draw` may be skipped or run once per five updates. Animation
  phase is accumulated from `dt` in `update` and passed in as a number — see
  CLAUDE.md, "`draw` renders state; time enters through `update`".
- Frame-rate readout (FPS), for a debug overlay. Not gameplay-critical.

**Required (planned, not yet implemented — design in from the start):**

- Gamepad support for up to 4 simultaneous controllers:
  - Digital buttons + dpad state (the same "is held" query as the keyboard).
  - Analog stick and trigger axes as floating-point values.
  - Hot-plug callbacks: controller-connected(index) / controller-disconnected(index),
    with indices stable across a momentary disconnect/reconnect.
  - A human-readable name string per connected controller (for "Player 2: connect a
    controller" UI).
- This exists specifically to support local split-screen / couch co-op: one input
  device (keyboard or a specific controller index) bound per player.

**Fixed-timestep loop shape** (informs the callback contract, not a Gosu feature per
se): the engine runs simulation at a fixed step (e.g. 1/60 s) via an accumulator fed by
real elapsed time, decoupled from render/vsync rate, with a cap on catch-up steps per
frame to avoid a spiral of death under a slow frame. The C layer's job is only to
supply accurate elapsed time and call `update`/`draw`.

**Amended:** the accumulator itself moved *into* C, where `frame_loop.c` implements
it with the best test coverage in the project. This line originally put it on the
engine side; that was written before `frame_loop.c` existed. Its actual concern —
that the game never sees variable frame time — is better served by the C loop
handing Ruby a guaranteed-fixed `dt`, which is what `update(dt)` now is.

Three things fall out, all simplifications: the Ruby side stops counting steps;
"has anything changed" becomes `@dirty = true` inside `update`, since a call
means a step ran; and the step size and catch-up cap become C constants
(`RGAME_TICK_SECONDS`, `RGAME_MAX_TICKS_PER_FRAME`). What the move would
otherwise cost — "poll input once per frame and reuse it across catch-up
ticks" — comes back structurally, as a per-frame input snapshot in C plus the
`frame_begin` hook.

---

## 2. Graphics functionality

Primitives, sprites, z-layering, clipping, and what multi-viewport/split-screen needs.

**Required (currently used):**

- Texture loading from PNG, with GPU upload. Nearest-neighbor ("retro"/pixel-art,
  non-interpolated) sampling is the only mode used — no filtered/smoothed sampling
  needed.
- Sub-rectangle texture views ("subimage"): cut a rectangular region out of a loaded
  texture and get back a drawable handle for just that region, without a new decode or
  upload. Used heavily for sprite sheets and 9-slice UI chrome.
- A tile-grid loader convenience: given a texture, a tile width/height, slice it into a
  grid of subimage handles in one call.
- Draw a textured quad at a position, with optional: rotation (degrees, about an
  arbitrary origin within the quad — not just its center), uniform or non-uniform
  scale, horizontal/vertical flip (equivalent to negative scale), and a tint color
  (RGBA multiply, white = no tint).
- Draw a filled, untextured rectangle with a given color.
- Draw a filled, untextured quad from four arbitrary points with a color (used to draw
  a line of arbitrary thickness as a thin rotated rectangle, since a native 1px line
  primitive isn't enough).
- Draw a filled, untextured triangle from three points with a color (used once, to
  procedurally bake a filled-circle texture at startup — see "recorded images" below).
- **Z-ordering:** every draw call takes a z value (numeric, higher = drawn later/on
  top). The renderer must sort/batch draw calls by z regardless of call order, not rely
  on painter's-algorithm call ordering. This is depended on throughout — UI draws above
  gameplay, overlays above UI, etc., all by z value rather than draw-order bookkeeping.
- **Transform stack:** push a rotation (angle + pivot point) or translation (dx, dy)
  around a block of draw calls, composing with any outer transform, then pop back to
  the previous state. Used for (a) spinning a node's whole subtree around its own
  origin, (b) the camera: shifting an entire world subtree's draw calls by
  `(-camera_x, -camera_y)` so world-space nodes never need to know the camera exists.
- **Clipping:** restrict drawing to a rectangular region (x, y, w, h) around a block of
  draw calls, composing with any outer clip. Used today for tiling a 9-slice texture's
  edges/center without overdraw; is also the primitive split-screen needs (see below).
- **Recorded images / macros:** capture a sequence of draw calls into a reusable
  texture/vertex-buffer object once, then redraw that whole captured sequence as a
  single cheap draw call thereafter. Used to bake static (non-animated) tile map layers
  into one draw instead of one draw per tile per frame, and to procedurally build a
  filled-circle texture at startup by recording a triangle fan.
- Text rendering: load a font at a point size, draw a string at a position with a
  color, and query a string's rendered width and the font's line height (for
  layout/centering by engine-side UI code that never touches font internals directly).
  Font rendering should cache at the **glyph** level, not the whole-string level — an
  engine draws many short-lived changing strings (scores, timers) and a per-glyph cache
  keeps memory bounded by the character set rather than growing per distinct string
  ever drawn.
- Color: RGBA color values, constructible from either 0-255 channel bytes or a named
  white/opaque default; used both as literal draw-call arguments and as tints.

**Required (planned, not yet implemented — the split-screen / multi-viewport case):**

- Split-screen is architecturally just: for each player's viewport, clip to that
  viewport's screen rectangle, then translate by that player's camera offset, then run
  the *same* world-draw code as single-player. No new draw primitives are needed beyond
  the transform + clip stack above — but the C API should support **multiple
  concurrent clip+transform regions composed and torn down within a single frame**
  cleanly (e.g. a proper push/pop stack, not global mutable state that only tolerates
  one active region), since split-screen exercises that repeatedly every frame.
- Camera zoom (scale factor as part of the transform stack) is not currently used
  anywhere but is a natural sibling of translate/rotate and cheap to include from the
  start rather than retrofit.

**Notably absent / intentionally not needed:**

- No shader/material system, no lighting, no post-processing, no 3D. This is a strictly
  2D, textured-quad-and-primitives renderer.
- No blend-mode variation beyond standard alpha blending is currently exercised.

---

## 3. Sound / music

- Load a short sound sample from a file (decode fully into memory) and play it
  fire-and-forget (one-shot, no loop, no handle needed afterward).
- Load a longer music track from a file (streamed, not fully decoded into memory) and
  play it looping.
- Query whether a given music track is currently playing (used to make "start this
  music" idempotent — re-requesting a track already playing must not restart it
  mid-loop).
- Stop whatever music track is currently playing.
- Formats actually loaded in practice: ogg. The loader should not assume a single
  format, but ogg is the only one that needs to work on day one.

**Not currently used but worth deciding deliberately** (Gosu exposes these; the engine
just never reached for them): per-sample/per-song volume control, stereo panning, pitch
shifting. Recommend including basic volume at least, since it's near-free to add to a
mixer and commonly wanted later (SFX ducking during dialogue, music fade).

---

## 4. Anything else

- **Fixed-arity callbacks matter.** A prior Ruby-side patch existed purely to strip a
  variadic-argument calling convention that Gosu's generated bindings imposed on every
  per-frame callback, because it allocated a throwaway array on every single call
  (update, draw, needs_redraw?, every button event) — a measurable per-frame cost for
  literally nothing. A hand-written C binding should use fixed-arity function
  signatures for every per-frame callback and hot-path query from the start, so this
  category of problem cannot occur.
- **Batched drawing matters for animated tiles specifically.** The one clearly
  identified performance sore point in the current Gosu-backed renderer is
  per-frame-changing tiles (e.g. animated water) which cannot be baked into a static
  recorded image and so fall back to one draw call per visible animated tile per frame.
  If practical, expose a batched "draw N textured quads from a packed coordinate list
  in one native call" primitive as an alternative to one-quad-at-a-time drawing — this
  turns an O(visible animated tiles) native-call-boundary cost into O(1) per layer.
  This is a nice-to-have optimization primitive, not a correctness requirement; the
  per-quad draw call is sufficient for a first working version.
- **Loaders should be cheap to call redundantly.** The asset layer above this API
  caches by path and reference-counts by "group" (e.g. "everything level 3 loaded") so
  the same file is never decoded/uploaded twice and can be released when every group
  holding it releases it. This has no bearing on the C API shape itself — the C layer
  can assume every load call is a real, uncached load — but it's worth knowing the
  layer above will call these functions in a load-once, share-by-handle pattern rather
  than reloading per use.
- **Headless testability is a hard requirement of the engine above this layer.** All
  game/engine logic must be runnable and unit-testable without a window, GPU context,
  or audio device — only the platform binding described in this document touches any
  of that. This has no direct bearing on the C API's shape, but explains why the API
  surface here is deliberately small and fully enumerated: it's the *entire* boundary
  the rest of the engine crosses to reach real hardware.

---

## 5. API surface summary

| Subsystem | Primitives needed |
|---|---|
| Window + loop | create window (w, h, caption), main loop w/ fixed-arity `update`/`draw`/`needs_redraw?`/button-event callbacks, close, query width/height |
| Input | keyboard "is held" query, discrete key-press event, gamepad state + hot-plug (no mouse — dropped) |
| Time | monotonic milliseconds, frame-rate readout |
| Textures | PNG decode + GPU upload (nearest-neighbor sampling), sub-rectangle view, tile-grid slicing, width/height query |
| Draw | textured quad (pos/rotation-about-arbitrary-pivot/scale/flip/tint), filled rect, filled quad (4 points), filled triangle, z-sort/batch across all of the above |
| Transform/clip | push/pop translate, push/pop rotate (+ pivot), push/pop clip rect, all composable and nestable — **must support several concurrent viewport transforms per frame for split-screen (planned)** |
| Record | bake a sequence of draw calls into a reusable macro/texture, redraw it as one call |
| Text | TTF load, glyph-level-cached string draw, measure string width, query line height |
| Color | RGBA construction from bytes, an opaque-white default |
| Audio | decode+play one-shot sample, decode+stream+loop track, query-playing, stop; **volume control recommended** |

---

## 6. Explicitly out of scope for v1

- 3D rendering, shaders/materials, lighting, post-processing.
- Blend modes beyond standard alpha.
- Audio panning/pitch (nice-to-have, not blocking).
- Non-ogg audio formats, non-PNG image formats (extend later if a real asset needs it).
