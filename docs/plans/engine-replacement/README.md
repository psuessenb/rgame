# Moving the engine layer into `RGame::Engine` — brief

The scene graph a game is written against lives in `lib/engine/` under a bare
top-level `Engine::`. It runs on `RGame::Core` today, through `RGame::Game`, and
its specs pass. What is left is the namespace, the packaging that depends on it,
and the work the layer itself still owes.

| Document | What it covers |
|---|---|
| [README](README.md) *(this file)* | Goal, what was measured, decisions taken |
| [01 — Roadmap](01-roadmap.md) | The move, step by step, then what follows it |

The Gosu replacement is done and its plan folder deleted; `git log` has the
reasoning if a decision behind the current shape is ever wanted.

---

## The goal

```
lib/engine/           →  lib/rgame/engine/
Engine::Node2D        →  RGame::Engine::Node2D
spec/engine/          →  spec/rgame/engine/
```

And the two things that follow from it: the engine layer starts shipping in the
gem, and `Game/NoCoreInEngineLayer` starts guarding `lib/` for the first time.

## What was measured before planning

Numbers, so nobody budgets from a guess.

| | |
|---|---|
| Engine sources | 48 files, all opening with exactly `module Engine` — no variants, no `::Engine` anywhere |
| Engine specs | 50 files, 3,340 lines, **580 examples green** |
| External `Engine::` references | 157 in 58 spec files, 51 in 10 example files, 5 in `lib/rgame/game.rb` |
| Constant collisions with `RGame`'s members | **none** |
| Bare `Core::` / `Util::` in engine or spec code | **none** — comments only |

**`lib/engine/` names `RGame::` exactly once, in a comment.** The layer already
keeps the rule the move has to satisfy: it reaches everything through
duck-typed seams — a `renderer` passed into `draw`, `node.root.context.assets`,
an audio server behind `AudioDirector`, an input backend behind
`ActionMapper#poll`. So this is a rename and a packaging change, **not** a
rewrite.

## The one thing that is not mechanical

**Nesting the layer under `RGame` opens a hole the cop cannot see.** Verified,
both halves:

```ruby
module RGame::Engine
  Core::Image.new(...)   # resolves to RGame::Core::Image — the rule, broken
end
```

`Game/NoCoreInEngineLayer` matches the prefix `%w[RGame Core]`, so it flags
`RGame::Core::Image` and misses the bare `Core::Image` beside it. That spelling
*cannot resolve* today, because top-level `Engine::` code has no path to
`RGame::Core` without spelling it out. Once nested, it resolves silently.

The fix is one word — add `%w[Core]` to the cop's `PREFIXES`, exactly as
`NoEngineInCoreLayer` already does with bare `Engine` — and it has to land
**with** the move rather than after it.

Two smaller findings in the same family:

- The cop's `Include` already lists `lib/rgame/engine/**/*.rb`, which matches
  nothing today. `lib/` has never actually been guarded; only `spec/` has. The
  move switches the guard on for the first time, and the layer should pass it
  immediately.
- Inside `module RGame; module Engine`, an internal `Engine::Component`
  reference still resolves. So the 48 sources need the wrapper and the
  reindentation — **not** a find-and-replace. Only the ~69 external callers do.

## Decisions taken

### `require "rgame"` loads everything that needs no window

Four entry points, each a strict superset of the last:

```ruby
require 'rgame'         # RGame::Util + RGame::Engine — no graphics libraries
require 'rgame/core'    # the window, the GPU, the sound device
require 'rgame/game'    # all of it, wired together
```

`rgame/util`, `rgame/engine` and `rgame/core` stay separately requirable —
`rgame.rb` is only a convenience that requires two of them, so **nothing is
forced through it**, specs included. That was the open question and it answers
itself: a spec that wants one layer requires that layer's file by name, the way
`spec_core/core_spec_helper.rb` requires `rgame/core` today.

Why fold Engine into the default rather than leave it opt-in: `require "rgame"`
should name a useful thing. Nobody installs this gem for `Color` alone, and
"everything that runs without a window" is a real boundary — it is the one the
headless spec suite is built on. The cost is load time for 48 pure-Ruby files.

The invariant this is often confused with is untouched. It is about **Core**,
not Engine: `require "rgame"` must load no SDL and no OpenGL, and Engine links
nothing.

Two consequences worth having:

- `spec/spec_helper.rb` becomes one `require "rgame"`, and the suite *is* the
  invariant check — see below.
- `spec_core/core_spec_helper.rb` requires `rgame/core`, which pulls neither
  `rgame.rb` nor Engine. So `RGame::Engine` is an undefined constant in the Core
  suite, giving that suite the same **runtime** guard the headless suite has
  against naming Core. Today only the cop covers that direction.

### The no-graphics invariant becomes a spec

It has never been one. It is checked by hand, as a shell one-liner, and it is
the single property the whole two-suite split rests on:

```
ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
```

`spec/` requires exactly what that line requires, so the check belongs in it.
`/proc/self/maps` is Linux-only, so it skips elsewhere — the same honesty the
platform-support section already applies to Xvfb and XTEST.

### `lib/boot.rb` becomes `lib/rgame/boot.rb`, and `RGame::Game` requires it

It is a YJIT switch, not engine code, which is why it sat awkwardly inside the
engine-layer packaging exclusion. Moving it under `rgame/` lets it ship, and
having `RGame::Game` require it puts the decision at the entry point rather than
asking every example to remember it. The examples drop their `require 'boot'`.

### `docs/engine/` is merged into `docs/api/` as its own step

Eight files, 1,328 lines, and `asset_manager.md` still describes
`Platform::AssetManager` returning `Gosu::Image` — actively wrong, not merely
misplaced. Too big to ride along with the move.

### The `Tensor` swap happens after the move, as its own step

`Engine::Tensor` and `RGame::Util::Tensor` have **identical public method
sets** — checked, not assumed — so it is a drop-in. It gets simpler after the
move, too: inside `RGame::Engine`, `Util::Tensor` resolves with no
qualification. One caller, `tile_map.rb`.

## What the layer still owes, after the move

These are the reasons this is a *replacement* and not only a rename. None of
them blocks the move; all are in the roadmap's second half.

### The UI package is gone, and its replacement is undecided

`ui/menu.rb`, `ui/button.rb`, `ui/selector.rb`, `ui/control.rb` and
`components/clickable.rb` were built on mouse hit-testing and have been deleted
along with the mouse. Keyboard and controller navigation is the replacement,
which was the known cost of dropping the pointer.

Knock-on: nothing exercises `renderer.nine_slice` or `Core::UiAtlas` end to end
any more. Whatever replaces the UI package is what will first prove that path.

### Split-screen does not exist yet

The transform and clip stacks were built for it — per viewport, `clipped` then
`translated`, running the same world-draw code, which is why they are proper
push/pop stacks rather than one global mutable region. `CameraView` and `Camera`
are the pieces that grow it, and `renderer.clipped` is the one Core drawing
method nothing above ever calls. The plumbing is ready and untested from above.

This is the part that is not 1:1: it changes what a camera *is*, from a single
draw-time offset to one of several viewports.

### `TileWorld` still needs its animation clock

Core no longer reads one — see CLAUDE.md, "`draw` renders state; time enters
through `update`" — so the component accumulates `dt` and passes `elapsed:`
down, the two lines `AnimatedSprite` already has. Until then a caller passes the
elapsed time by hand and animated tiles stand still.

### `AudioDirector` should run against the audio contract

It turns `:play_sound` / `:play_music` events into calls on an injected audio
server, and `spec/support/shared_examples/an_audio_server.rb` is exactly the
interface it calls. Running the director against the same `FakeAudio` the
contract checks is a free win.

### `DebugOverlay` reports per-frame allocations — of what?

That number was worth watching because the old binding layer allocated on every
callback. It no longer does: the trampolines have fixed arity, and
`ruby/core_ext.c` says why. Worth asking what the overlay should measure now.

## Cross-references

- `docs/engine/` — the layer's own documentation. `scene_graph.md`,
  `components.md` and `systems.md` describe the architecture this move
  preserves; read those first.
- CLAUDE.md, "The three layers, and who may talk to whom" — the rule the move
  has to satisfy, and the two cops that enforce it.
