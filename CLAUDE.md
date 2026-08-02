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
`mark` function, and `ext/rgame_core/core_ext.c` explains TypedData and
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

Both halves exist. The C engine (window + fixed-timestep loop, no draw
primitives yet) is wrapped by `ext/rgame_core/core_ext.c`, and there's
a Ruby half under `lib/` backed by a second, graphics-free extension in
`ext/rgame_util/`. No `.gemspec` yet — everything runs from a checkout.

Work is still mostly C-side: the engine's drawing surface is the gap. When
adding a feature, the default is to build it in C under `ext/rgame_core/`
and only extend the Ruby wrapper once the C API for it is settled.

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
copy of the code feeds both the standalone binary and the gem. New engine
sources go in `ext/rgame_core/`.

- `ext/rgame_core/include/rgame/core.h` — the *only* public API. Opaque
  `rgame_app` handle, plain C types only (no SDL/GL types in the signature).
  This is what the Ruby extension calls — keeping SDL/GL details out of the
  header means `ext/rgame_core/core_ext.c` can `#include` it without
  also pulling in `SDL.h` conflicts or exposing internals. It sits under its own
  `include/` subdirectory so `#include "rgame/core.h"` works while mkmf's
  "compile every `.c` here" default still picks up only the sources.
- `ext/rgame_core/app.c` — the actual engine (SDL window/GL context setup; owns
  the main loop and drives caller-supplied `update`/`draw` callbacks).
  Compiled with `-fPIC` so the resulting `.a` can be linked into a shared
  object (`.so`) without recompiling.
- `ext/rgame_core/frame_loop.{c,h}` — pure-logic helpers (no SDL/GL, no I/O)
  factored out of `core.c` specifically so they're unit-testable without a
  display/GL context (currently the fixed-timestep accumulator + FPS
  counter). `test/` links against these directly. When adding engine logic,
  prefer putting the parts that don't touch SDL/GL here so they stay
  testable — see `test/test_frame_loop.c` for the pattern.
- `ext/rgame_core/device_slots.{c,h}` — the same shape, for controllers: a
  pure player-slot table that keeps a player on one slot across a
  disconnect/reconnect. No SDL, covered by `test/test_device_slots.c`.
- `ext/rgame_core/input.{c,h}` — the input snapshot and the flat button-id
  space, again pure: `app.c` copies SDL's keyboard state into it once per
  frame, and every query reads that copy. Covered by `test/test_input.c`.
- `ext/rgame_core/gamepad.{c,h}` — the controller shim, and the one place
  `SDL_GameController` appears. Deliberately thin: which player a pad belongs
  to is `device_slots`, what a button id means is `input`, and both are pure.
  Its own correctness is checked end-to-end with an SDL *virtual* controller
  under Xvfb — no hardware needed, see `.claude/skills/verify/`.
- `ext/rgame_core/core_ext.c` + `extconf.rb` — the Ruby glue for the
  engine (`RGame::Core::App`); see `ext/README.md`.
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

The gem step is still ahead: a top-level `.gemspec` listing *both*
`extconf.rb` files, installing both `.so`s into `lib/rgame/` the way
`make ext` already does.

When adding new engine features, put the implementation in
`ext/rgame_core/app.c` and extend
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
   tile-grid slicing, glyph cache eviction, the fixed-timestep accumulator's
   catch-up/skip decisions, etc. This is most of what's actually hard to get
   right in a 2D engine, and none of it needs a window to test. Give it its
   own small module (`ext/rgame_core/<subsystem>.c` + header) and Check
   tests, the same way `ext/rgame_core/frame_loop.{c,h}` and
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
rake              # make test, then both suites
``` Ruby is
4.0.5, pinned in `.ruby-version` and installed via mise. Requirements are
listed in README.md.

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
  `RGame::Util` and `RGame::Engine`. Fast, deterministic, no display, no SDL
  in the process at all. Requires `make ext-util` first. Expected to pass for
  every change.
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
