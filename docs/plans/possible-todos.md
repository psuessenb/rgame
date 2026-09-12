# Possible todos

Work that has a reason to exist but no reason to happen yet. Nothing here is
scheduled, and nothing here is a promise — this file exists so that ideas with
real thought behind them are not lost to a deleted plan or a finished
conversation.

Each entry says what the thing is, why it is not being done now, and what would
make it worth doing. **An entry with no trigger is a wish, not a todo**; if the
answer to "what would make this worth starting" is "nothing in particular", the
entry should be deleted rather than kept.

---

## A low-resolution render target, and the GL loader it needs

**What.** Render a frame into an offscreen buffer at the game's own resolution,
then scale that buffer onto the window — Godot's `viewport` stretch mode, as
against the `canvas_items` one.

**What exists instead.** `RGame::Game.new(scale_mode:)` and
`RGame::Engine::Presentation` scale the *coordinates*: everything still
rasterises at the window's real resolution, and the transform maps a logical
size onto it. That covers most of what a game wants, `:integer` included, and it
needed no C at all.

The difference shows up in one place. Coordinate scaling rasterises text and
shapes at full resolution, which is what you want for anything that is not pixel
art — but a *sprite* drawn at 2x is still sampled from its original texels, so
the crispness depends on the filter and the factor rather than on having been
rasterised at 320x240 in the first place. A render target gives the genuine
low-resolution look, and hands the frame over as a texture, which is also what
any post-processing effect would need.

**Why not now.** It is the project's first call above OpenGL 1.1, and that is a
threshold rather than a line of code. Every `gl*` call in `ext/rgame_core/` today
is GL 1.1 — checked, all 24 of them — which is exactly what "no GL loader" has
bought so far. Windows' `opengl32.dll` exports only GL 1.1, so `glGenFramebuffers`
and friends must be fetched through `SDL_GL_GetProcAddress`. A naive
implementation compiles, links and runs perfectly on Linux and fails on Windows,
which is the failure class the `windows-portability` skill exists for.

**What it would take.**

- A keyhole loader: six entry points (`glGenFramebuffers`, `glBindFramebuffer`,
  `glFramebufferTexture2D`, `glCheckFramebufferStatus`, `glDeleteFramebuffers`,
  and `glGenerateMipmap` if wanted) resolved once into a struct. Roughly thirty
  lines, and not GLAD.
- An availability check with a clear failure. We never request a context
  version, so we take SDL's default; a missing FBO must say so rather than draw
  a blank screen.
- Two entries on `backend.h`'s table — bind target, unbind target — which
  `test/support/recording_backend.c` implements too, so "bound, drew, unbound,
  blitted once" stays assertable with no display.
- The Y flip. An FBO-rendered texture is upside down against our
  `glOrtho(0, w, h, 0, …)` top-left origin, so the final blit needs flipped
  texture coordinates. This one is famous for costing an afternoon.

Two things are already in place and do not need designing:
`rgame_texture_sheet_create` takes a raw GL texture name and does not care where
it came from, so an FBO's colour attachment becomes an ordinary sheet the whole
existing sprite path can draw; and the policy half — which scale, which
offsets — is `Presentation`, which is pure and already specced.

**Trigger.** A game that wants a genuine low-resolution look and finds
coordinate scaling not good enough, or the first want for a post-processing
effect.

### Two smaller things in the same area

- **`:overscan`.** `Presentation` has four modes; SDL has a fifth, which fills
  the window on the *smaller* axis and lets the larger overflow. It is two lines
  — `max` where `fit_uniform` takes `min` — and was left out because no example
  asks for it. Adding an unused mode is a claim nothing checks.
- **A minimum window size.** `:integer` never scales below 1x, so a window
  smaller than the logical size crops instead of shrinking. `SDL_SetWindowMinimumSize`
  would design the case out entirely rather than documenting it. It needs C, and
  the case only arises if a player drags a window below the game's design size.

---

## Move the hot paths into C

Only after profiling, and only where there is a measured reason. Carried over
from the roadmap that planned the C engine; the entries have been checked
against what the code does now.

- **`NineSlice`'s tiling loops.** Still Ruby: `draw` walks each band with nested
  `while` loops, five tiled regions per call per frame. Every menu item on screen
  is one of these.
- **`TileMapRenderer`'s per-tile draw loop.** Half of this is already gone, and
  it is the outcome the roadmap hoped for: static tiles are baked into a
  `Recording` on first draw and replayed as one call per texture. What still
  loops per tile is the *animated* ones, which are collected once at construction
  precisely because finding them again each frame would cost more than drawing
  them. A map with a handful of animated tiles is already cheap; one with
  thousands is the case that would justify moving this.
- **`Renderer`'s per-draw id lookups.** Now one hash fetch on a registry that
  caches the resolved asset, so this is a much smaller item than when it was
  written. Left here only because it is the third thing to look at if a profile
  ever points this way.

**Why not now.** Each is a straightforward move once the pure geometry is
separable, and doing any of them early trades readability for a speedup nobody
has measured.

**Trigger.** A profile. Not a suspicion.

---

## The drive harness owns the save directory

**What.** `tools/drive_test_project.rb` gives every run a fresh temporary
`RGAME_SAVE_DIR` unless one is passed.

**What exists instead.** The drive scripts for `save_load`, `save_load_ids` and
`menu_navigation` say in a comment to set it, and the verify skill says so for
comparisons. Without it a run writes into the real data directory and the next
run reads that file, so two runs of unchanged code report differently.

**Why not now.** Found in the middle of the component-architecture sweep, which
had no reason to touch the harness.

**Trigger.** The next driven comparison across examples — or the first time a
report differs for this reason, whichever is sooner. It is a remembered rule, the
kind "Design out misuse" in CLAUDE.md says to remove.

---

## Edge margins derived from the node's size

**What.** `ScreenWrap` and `DespawnOffscreen` derive their `margin` from how big
the node is, rather than taking it by hand.

**What exists instead.** Every caller sets `margin` to a radius or more itself.
Asteroids' rock uses its largest tier's radius for all four tiers.

**Why not now.** It needs a footprint convention first, and there is none:
`node.width`/`height` do not say where the box sits. `Sprite` culls a box centred
on the origin and `AnimatedSprite` one cornered at it, each deciding for itself,
and the wrapped and despawned nodes draw centred.

**Trigger.** A caller whose hand-set margin is visibly wrong, or a second place
that needs a node's footprint and has to pick a convention.
