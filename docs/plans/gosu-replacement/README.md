# Replacing Gosu — plan index

This folder is the working plan for replacing `lib/platform/` + Gosu with a
C layer under `RGame::Core` (plus whatever is better left in Ruby).

Read in order:

| Document | What it covers |
|---|---|
| [00 — Brief and decisions](README.md) *(this file)* | Goal, hard constraints, decisions already taken, open questions |
| [01 — Inventory](01-inventory.md) | What `lib/platform/` actually is today, every Gosu call it makes, and what each class needs from a C layer |
| [02 — Target architecture](02-architecture.md) | The shape of `RGame::Core`: module layout, the layers inside the renderer, and the C-vs-Ruby split per class |
| [03 — Roadmap](03-roadmap.md) | Phased implementation order. Detailed for phases 0–2, deliberately rough after that |

Nothing in here has been implemented yet. This is a documentation-only pass.

---

## The goal

`lib/platform/` is a small Ruby layer over Gosu. It is the **entire** boundary
between the game engine and real hardware — window, GPU, audio device, input.
The plan is to replace `Gosu + lib/platform/` with a C layer (`RGame::Core`),
keeping in Ruby only the parts where Ruby genuinely reads better and costs
nothing.

`docs/c_engine_feature_specs.md` is the feature spec derived from that same
boundary. It is the *what*; this folder is the *how* and the *in what order*.

## Hard constraints

1. **The public API of the `Platform::*` classes is preserved.** A pure-Ruby
   engine layer will sit on top of these (it is not in this repo yet, see
   below), and it must not have to change. Method names, argument shapes,
   keyword arguments and return values stay as they are. Only the *class
   names* and the *implementation* move.

2. **Class renames are fine and expected.** `Platform::GosuInput` →
   `RGame::Core::Input`, `Platform::GosuRenderer` → `RGame::Core::Renderer`,
   `Platform::GameWindow` → `RGame::Core::App`, and so on. The `Gosu` prefix
   was only ever there to name the backend.

3. **Everything Ruby-visible from the new C layer lands under `RGame::Core`.**

4. **`require "rgame"` must still load zero graphics libraries.** This is the
   existing Platform/Util rule in CLAUDE.md and it survives the rewrite intact
   — see "Naming" below for how `Core` fits into it. The check stays:

   ```
   ruby -Ilib -e 'require "rgame"; puts File.read("/proc/self/maps").scan(/libSDL2|libGL\./).uniq.inspect'
   # => []
   ```

5. **The layering discipline in CLAUDE.md applies to all of it**: pure logic
   first (Check-tested, no SDL/GL), then a recording fake backend, then a thin
   real SDL/GL shim. Most of what is hard in a 2D renderer — z-sorting,
   transform composition, clip intersection, glyph cache eviction, tile
   culling — is pure arithmetic and needs no window to test.

## Decisions already taken

These come out of the framing of the work and are not up for re-litigation
inside the plan; they are recorded here so the reasoning is not lost.

### `RGame::Core` replaces `RGame::Platform`

`Core` is the new name for the SDL/GL-linked half. It is a rename, not a third
namespace:

| | before | after |
|---|---|---|
| Ruby namespace | `RGame::Platform` | `RGame::Core` |
| Extension dir | `ext/rgame_platform/` | `ext/rgame_core/` |
| Required as | `rgame/platform_ext` | `rgame/core_ext` |
| Opt-in require | `require "rgame/platform"` | `require "rgame/core"` |

`RGame::Util` is untouched and keeps its job: everything with no SDL/GL
dependency, loaded by the default `require "rgame"`. The split is what makes
constraint 4 hold, so it must not be collapsed.

One consequence worth stating plainly, because it will come up repeatedly:
**a pure-logic C module that `RGame::Core` needs cannot live in
`RGame::Util`.** They are two separate `.so` files. Sharing a C type across
them (say, a `Color` struct that Core unwraps from a Util-owned object) means
exported symbols and a shared header between two independently-built
extensions — real complexity for little gain. So the rule becomes:

> Pure-logic C that only `Core` uses lives in `ext/rgame_core/` as an
> internal module with its own Check tests. It is still layer 1 and still
> fully testable headlessly; it just isn't Ruby-visible from `Util`.
> `ext/rgame_util/` is for pure logic that **Ruby** calls on its own.

`Color` is the concrete case: it is pure arithmetic, but it is part of the draw
vocabulary and every draw call takes one, so it belongs in `Core`.

### `App` absorbs `GameWindow`'s shape, not the other way round

`RGame::Platform::App` today is a *callback sink*:

```ruby
app.run(update_proc, draw_proc, needs_redraw_proc)
```

`Platform::GameWindow` is a *subclass* of `Gosu::Window` that overrides
`update` / `draw` / `needs_redraw?` / `button_down`. The engine layer above is
written against the second shape. So `App` changes to be subclassable and the
proc-passing form goes away. Details in [02](02-architecture.md#appwindow).

### `gosu_patches.rb` disappears entirely

It exists solely to strip a `|*args|` splat out of Gosu's generated per-frame
callback wrappers. A hand-written C binding uses fixed-arity function pointers
from the start (`core.h` already does), so the problem cannot occur. This is
called out in the feature spec §4 as a design requirement, and it is already
satisfied.

The RuboCop cop `Game/PreferGosuModuleMethod` becomes obsolete at the same time
and should be retired with it. The *principle* it enforced — no allocating
shim on a per-frame path — is preserved structurally rather than by lint.

## What is NOT in this repo (and matters)

`lib/platform/` references an `Engine::` namespace that does not exist here:

- `Engine::DebugOverlay` — `GameWindow` constructs one and toggles it on F1.
- `Engine::TileMap` / `Engine::Tileset` — `TileMapRenderer.load` parses TMX/TSX
  through them.
- `Engine::AudioDirector` — named in a comment; drives `GosuAudio` by events.
- The `mapper` (an input map) and `root` (a scene-graph node) passed into
  `GameWindow#initialize`.

That is the pure-Ruby engine layer the constraint-1 API promise is made to. It
is not visible, so **the safest reading of any ambiguous API detail is "keep it
byte-identical"**. Where a change is genuinely required (see the input-polling
note in [02](02-architecture.md#input-is-snapshotted-per-frame)), it is flagged
explicitly rather than made quietly.

## Open questions

Recorded here rather than guessed at. None of them block phase 0–2.

1. **Default font.** `Gosu::Font.new(18)` with no path picks a system default
   font. A from-scratch text layer has no such thing. Options: require an
   explicit TTF path (API change, breaks constraint 1 for `Renderer#initialize`
   only), embed a small TTF in the extension, or probe fontconfig. See
   [03, phase 4](03-roadmap.md#phase-4--text).
2. **Audio dependency.** SDL_mixer gets ogg + looping + `playing?` almost for
   free but adds a system dependency; a hand-rolled mixer over `SDL_audio` +
   `stb_vorbis` adds none but is real work. Recommendation in
   [03, phase 5](03-roadmap.md#phase-5--audio).
3. **Whether `Renderer` stays one class.** Today `GosuRenderer` mixes an
   asset-id registry (Ruby-ish bookkeeping) with draw primitives (C-ish hot
   path). The plan keeps it as one Ruby class delegating to C, but a later
   split into `Core::Renderer` (C primitives) + a Ruby registry façade is
   plausible. Deferred until the primitives exist.
