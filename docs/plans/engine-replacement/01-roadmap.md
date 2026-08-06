# 01 — Roadmap

Steps 1–6 are the move and everything that has to change with it. Steps 7
onward are what the layer owes on its own account, and can be reordered or
dropped as priorities change.

Each step ends green: `rake` (C tests, both Ruby suites), RuboCop, and both
examples still running. The examples are the acceptance test for anything that
touches wiring, exactly as they were for the Gosu replacement — a driven run,
not just a boot. See step 2's note on how.

---

## 1. `lib/boot.rb` → `lib/rgame/boot.rb`

Small, independent, and worth doing first so the move does not have to think
about it.

- `git mv lib/boot.rb lib/rgame/boot.rb`.
- `RGame::Game` requires it, so enabling YJIT is the entry point's decision
  made in one place rather than a line every game remembers.
- Both `examples/*/main.rb` drop their `require 'boot'` and keep the
  `$LOAD_PATH.unshift`, which is what makes `require 'rgame/game'` resolve from
  a checkout.
- It comes out of the packaging exclusion in step 5, along with everything else.

**Verify**: both examples run.

---

## 2. The move itself

**Three commits, each doing one thing.** The middle one reindents 48 files and
is unreviewable line by line; keeping it free of anything else is what makes
that acceptable.

### 2a. `git mv` only

```
lib/engine/      →  lib/rgame/engine/
lib/engine.rb    →  lib/rgame/engine.rb
spec/engine/     →  spec/rgame/engine/
```

No content changes at all, so renames are detected and `git log --follow`
keeps working afterwards. The tree does not load in this state; that is fine
for one commit.

`spec/rgame/engine/` rather than `spec/engine/` to match `spec/rgame/util/` and
`RSpec/SpecFilePathFormat`, which already carries the `RGame: rgame` transform.

### 2b. Wrap the sources, and close the cop's blind spot

- Wrap each of the 48 sources in `module RGame` and reindent. All of them open
  with exactly `module Engine`, so this is uniform. Internal `Engine::Foo`
  references keep resolving — leave them.
- `lib/rgame/engine.rb`'s `require_relative` paths still work unchanged
  (`engine/matrix` → `rgame/engine/matrix` relative to the file).
- **Add `%w[Core]` to `Game/NoCoreInEngineLayer::PREFIXES`.** This is the one
  non-mechanical part of the whole move; the brief explains why. Mirror
  `NoEngineInCoreLayer`, which already lists both spellings, and add the two
  cop-spec examples to match: a bare `Core::Image` is an offence, and a
  constant that merely ends in `Core` is not.
- The cop's `Include` starts matching for the first time. The layer should pass
  it immediately — it names `RGame::` only in a comment — but that is a claim to
  check, not to assume.

### 2c. Update the external callers

~69 files, all mechanical: `Engine::` → `RGame::Engine::`.

| | |
|---|---|
| `spec/` | 157 occurrences, 58 files |
| `examples/` | 51 occurrences, 10 files |
| `lib/rgame/game.rb` | 5 occurrences |

**Do not add `Engine = RGame::Engine` at the top level.** That bare constant is
precisely what the gem exclusion exists to prevent, and adding it would make
step 5 a lie.

While here: the stub backends in `spec/rgame/engine/action_mapper_spec.rb` and
`action_mapper_allocation_spec.rb` still define `pointer_x`/`pointer_y`. Nothing
calls them — they are leftovers that describe an input backend which no longer
has a pointer.

**Verify**: `rake`, RuboCop, and both examples *driven* rather than booted — a
harness that swaps in a scripted input backend, bounds the tick count and
reports what the game asked for. Booting alone reported "90 ticks, 90 frames"
for a game whose menu did not respond; only driving it found that.

---

## 3. Entry points

```ruby
require 'rgame'         # RGame::Util + RGame::Engine — no graphics libraries
require 'rgame/core'    # the window, the GPU, the sound device
require 'rgame/game'    # all of it, wired
```

- `lib/rgame.rb` requires `rgame/util` and `rgame/engine`.
- `lib/rgame/engine.rb` stays separately requirable, as `rgame/core` is.
- `spec/spec_helper.rb` collapses to one `require "rgame"`.
- `spec_core/core_spec_helper.rb` is unchanged and now gains a property: it
  requires `rgame/core`, which pulls neither `rgame.rb` nor Engine, so
  `RGame::Engine` is undefined there. Say so in its comment — it is the runtime
  mirror of what `spec/` has always had, and it is new.
- `RGame::Game`'s two requires become `rgame/core` and `rgame/engine`.

**Verify**: the invariant, by hand, one last time before step 4 automates it.

---

## 4. The no-graphics invariant becomes a spec

`spec/rgame/no_graphics_spec.rb`: after `require "rgame"` — which
`spec_helper.rb` has already done — the process must have no SDL and no OpenGL
mapped.

```ruby
File.read('/proc/self/maps').scan(/libSDL2|libGL\./).uniq
```

Linux-only, so skip elsewhere rather than fail, the way the Core suite already
skips XTEST off Linux. Add the skip predicate next to `HeadlessDisplay`'s, or
inline — it is one `File.exist?('/proc/self/maps')`.

This is the property the entire two-suite split rests on and it has never been
executable. Worth checking it actually fails: add a `require "rgame/core"` to
the example temporarily and watch it go red.

---

## 5. Packaging: the engine ships

- Delete the `not_shipped` pattern from `rgame.gemspec` and the `held_back`
  expectation from `spec/packaging_spec.rb` — the same lifecycle
  `lib/platform/`'s exclusion had, and both are commented as going together.
- The packaging spec's other expectations must keep passing untouched. That is
  what proves the moved files ship.
- Check the gem builds and that `lib/rgame/engine/**` is in `spec.files`.

**Verify**: `rake build`, then assert the file list rather than eyeballing it.

---

## 6. `Engine::Tensor` → `RGame::Util::Tensor`

A drop-in: the two have identical public method sets. One caller,
`tile_map.rb`, and inside `RGame::Engine` it can say `Util::Tensor` with no
qualification.

- Delete `lib/rgame/engine/tensor.rb` and `spec/rgame/engine/tensor_spec.rb`;
  `spec/rgame/util/tensor_spec.rb` already covers the survivor.
- The first real instance of "the engine layer may hold `Util` types", which is
  worth a sentence in CLAUDE.md's three-layer section as a worked example.
- Check `Engine::Matrix` for the same question at the 2-D end. There is no C
  `Util::Matrix` today, so the answer may be "nothing to do" — but ask.

---

## 7. `docs/engine/` merges into `docs/api/`

Eight files, 1,328 lines. `asset_manager.md` describes `Platform::AssetManager`
returning `Gosu::Image`; that class has not existed for two phases, and
`docs/api/assets.md` covers its replacement. The rest — `scene_graph.md`,
`components.md`, `systems.md`, `signals.md`, `utils.md`, `internals.md` — is
good documentation in the wrong place, describing a layer that will by then be
`RGame::Engine`.

Per-file: fold, replace, or delete. Nothing should describe an API that is gone.

---

## 8. What the layer owes

In no fixed order; see the brief for the detail behind each.

- **A UI package**, built on keyboard and controller navigation. Its absence
  also leaves `renderer.nine_slice` and `Core::UiAtlas` with no end-to-end
  exercise, so whatever replaces it proves that path too.
- **Split-screen** — `CameraView` and `Camera` growing from one draw-time
  offset to several viewports. The Core plumbing (`clipped` + `translated`) has
  been ready since phase 3 and nothing above has ever called it.
- **`TileWorld`'s animation clock** — accumulate `dt` in `update`, pass
  `elapsed:` down. Two lines; without them animated tiles stand still.
- **`AudioDirector` against the audio contract** — it calls exactly the
  interface `an_audio_server.rb` states, so run it against the same `FakeAudio`.
- **`DebugOverlay`'s allocation counter** — decide what it should measure now
  that the binding layer no longer allocates per callback.

---

## 9. Fold this plan back and delete it

Same rule as its predecessor: when the work lands, whatever is still true moves
into CLAUDE.md, `docs/api/` or a comment at the code it describes, and the
folder goes. `git log` keeps the rest.

Watch particularly for anything a landed note records that exists nowhere else —
a deliberate deviation, a surviving mutation, a decision whose reasoning is not
obvious from the code. Those belong at the code, and the last plan needed four
such rescues.
