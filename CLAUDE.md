# rgame

A learning project: SDL2 + OpenGL in C, structured so the core can later be
wrapped as a Ruby C extension. The user is not an experienced C programmer —
prefer explaining unfamiliar C/SDL/GL idioms briefly when introducing them,
and favor straightforward code over clever code.

## Current phase

Pure C, no Ruby yet. Ruby bindings are a deliberate future step, not part of
the current work unless asked for.

## Structure and why it looks like this

- `include/rgame/core.h` — the *only* public API. Opaque `rgame_app` handle,
  plain C types only (no SDL/GL types in the signature). This is what a
  future Ruby extension in `ext/` will call — keeping SDL/GL details out of
  the header means `ext/rgame/rgame_ext.c` can `#include` it without also
  pulling in `SDL.h` conflicts or exposing internals.
- `src/core.c` — the actual engine (SDL window/GL context setup; owns the
  main loop and drives caller-supplied `update`/`draw` callbacks). Compiled
  with `-fPIC` so the resulting `.a` can be linked into a shared object
  (`.so`) later without recompiling.
- `src/main.c` — thin standalone entry point; only talks to `core.h`'s API,
  never touches SDL/GL directly. This is intentionally what a Ruby extension
  would also do, just driven from Ruby instead of a C `main()`.
- `ext/` — empty for now. Reserved for the Ruby extension (`extconf.rb` +
  glue code) — see `ext/README.md`.
- `src/frame_loop.{c,h}` — pure-logic helpers (no SDL/GL, no I/O) factored
  out of `core.c` specifically so they're unit-testable without a display/GL
  context (currently the fixed-timestep accumulator + FPS counter). `test/`
  links against these directly. When adding engine logic, prefer putting the
  parts that don't touch SDL/GL here so they stay testable — see
  `test/test_frame_loop.c` for the pattern.
- `docs/c_engine_feature_specs.md` — the feature spec this engine is being
  built out to satisfy (2D primitives to replace Gosu under a Ruby game
  engine). Large surface area, implemented incrementally. Consult it when
  adding a new subsystem rather than guessing scope.

When adding new engine features, put the implementation in `src/core.c` and
extend `include/rgame/core.h`'s public API rather than adding logic to
`main.c` — that's what keeps the future Ruby wrapper thin.

## Abstraction & testability strategy

`docs/c_engine_feature_specs.md` is a lot of surface area. This is the
standing rule for building all of it, not just advice for one feature —
every new subsystem should be split into three deliberately separate
layers:

1. **Pure logic** — math/state transforms with no SDL, no GL, no I/O:
   transform-stack composition, clip-rect intersection, z-sort/batching,
   tile-grid slicing, glyph cache eviction, the fixed-timestep accumulator's
   catch-up/skip decisions, etc. This is most of what's actually hard to get
   right in a 2D engine, and none of it needs a window to test. Give it its
   own small module (`src/<subsystem>.c` + header) and Check tests, the same
   way `src/frame_loop.{c,h}` is covered by `test/test_frame_loop.c` today.
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

Plain Makefile (mirrors what Ruby's `mkmf`-generated Makefile will look like
later, so the mental model carries over):

```
make        # builds build/rgame
make run    # build + run
make test   # build + run the Check unit tests
make clean
```

Requirements are listed in README.md.

## Testing

Uses [Check](https://libcheck.github.io/check/), a C xUnit-style framework
(each test runs in its own forked process, so a segfault only fails that
test rather than aborting the whole suite — relevant given how easy it is
to crash while learning pointers/SDL/GL).

**Verification tiers**, matching the layers above:

- `make test` — Check suite covering layer 1 (pure logic) and layer 2 (fake
  backends: assert on recorded calls, no display involved). Fast,
  deterministic, expected to pass for every change.
- `make run` — manual verification of layer 3, the real SDL/GL/audio path.
  Subjective/visual, run by a human, not automated.
- Automated integration/smoke tier — **documented pattern, not yet built.**
  Once there's real rendering worth checking without a human watching,
  Mesa's software rasterizer (llvmpipe) under Xvfb can drive a real
  `SDL_CreateWindow`/GL context headlessly, for a small number of true
  end-to-end checks (a frame renders without a GL error, a `glReadPixels`
  spot-check on a known scene). Add this once there's enough real drawing
  to justify it, not preemptively. Note: `SDL_VIDEODRIVER=dummy` alone only
  covers window/event-pump smoke tests — it cannot create a real GL
  context, so it doesn't help for verifying actual draw calls.

## Conventions

- C17, `-Wall -Wextra`, keep it warning-clean.
- No OpenGL loader (GLAD/GLEW) yet — using legacy/compatibility-profile GL
  calls (`glBegin`/`glEnd`) since that's what's available without extra
  dependencies. If/when the project moves to core-profile modern GL, a
  loader will need to be added — flag that as a deliberate decision, not a
  drive-by change.
