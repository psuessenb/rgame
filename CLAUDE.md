# ctest

A learning project: SDL2 + OpenGL in C, structured so the core can later be
wrapped as a Ruby C extension. The user is not an experienced C programmer —
prefer explaining unfamiliar C/SDL/GL idioms briefly when introducing them,
and favor straightforward code over clever code.

## Current phase

Pure C, no Ruby yet. Ruby bindings are a deliberate future step, not part of
the current work unless asked for.

## Structure and why it looks like this

- `include/ctest/core.h` — the *only* public API. Opaque `ctest_app` handle,
  plain C types only (no SDL/GL types in the signature). This is what a
  future Ruby extension in `ext/` will call — keeping SDL/GL details out of
  the header means `ext/ctest/ctest_ext.c` can `#include` it without also
  pulling in `SDL.h` conflicts or exposing internals.
- `src/core.c` — the actual engine (SDL window/GL context setup, update,
  render). Compiled with `-fPIC` so the resulting `.a` can be linked into a
  shared object (`.so`) later without recompiling.
- `src/main.c` — thin standalone entry point; only talks to `core.h`'s API,
  never touches SDL/GL directly. This is intentionally what a Ruby extension
  would also do, just driven from Ruby instead of a C `main()`.
- `ext/` — empty for now. Reserved for the Ruby extension (`extconf.rb` +
  glue code) — see `ext/README.md`.
- `src/internal.h` — pure-logic helpers (no SDL/GL, no I/O) factored out of
  `core.c` specifically so they're unit-testable without a display/GL
  context. `test/` links against these directly. When adding engine logic,
  prefer putting the parts that don't touch SDL/GL here so they stay
  testable — see `test/test_core.c` for the pattern.

When adding new engine features, put the implementation in `src/core.c` and
extend `include/ctest/core.h`'s public API rather than adding logic to
`main.c` — that's what keeps the future Ruby wrapper thin.

## Build

Plain Makefile (mirrors what Ruby's `mkmf`-generated Makefile will look like
later, so the mental model carries over):

```
make        # builds build/ctest
make run    # build + run
make test   # build + run the Check unit tests
make clean
```

Requirements are listed in README.md.

## Testing

Uses [Check](https://libcheck.github.io/check/), a C xUnit-style framework
(each test runs in its own forked process, so a segfault only fails that
test rather than aborting the whole suite — relevant given how easy it is
to crash while learning pointers/SDL/GL). Tests only cover pure logic in
`src/internal.h`/`internal.c`-style helpers — SDL window/GL context
creation itself isn't unit-tested (needs a real/headless display) and is
verified manually via `make run`.

## Conventions

- C17, `-Wall -Wextra`, keep it warning-clean.
- No OpenGL loader (GLAD/GLEW) yet — using legacy/compatibility-profile GL
  calls (`glBegin`/`glEnd`) since that's what's available without extra
  dependencies. If/when the project moves to core-profile modern GL, a
  loader will need to be added — flag that as a deliberate decision, not a
  drive-by change.
