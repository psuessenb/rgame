# Moving the engine layer into `RGame::Engine` — findings, not yet a plan

**Status: notes only.** This folder exists so that what was learned while
planning the Gosu replacement is not lost between now and when this work
actually starts. There is no roadmap here and there should not be one yet — the
prerequisite is `docs/plans/gosu-replacement/` phase 6, which ends with
`lib/engine/` *running* on `RGame::Core` while still living where it does.

Everything below was found by reading the code, and each claim names the file it
came from so it can be re-checked rather than trusted. Nothing here is a
decision.

---

## What this is about

`lib/engine/` — 3,083 lines across 57 files, plus `lib/son_gosu_game.rb`, two
games under `examples/` and reference documentation under `docs/engine/`. It is
the scene graph a game is actually written against: `Node2D`, components,
signals, scenes, systems, UI, tile maps, pathing, pooling, i18n.

CLAUDE.md already describes where it is going and under what rule:

> `RGame::Engine` lives in `lib/rgame/engine/` and is the layer a game is
> actually written against. It may hold `RGame::Util` types, may not name
> `RGame::Core` at all, and reaches Core only through objects handed to it,
> duck-typed.

Two things already enforce that for code that does not exist yet: the
`Game/NoCoreInEngineLayer` cop (which includes `lib/rgame/engine/**/*.rb`), and
the headless `spec/` suite, which never loads Core so a stray reference is a
`NameError`.

## The good news, measured

**`lib/engine/` names `Gosu` and `Platform::` in comments only.** Not one
constant reference in code, across all 57 files. It reaches everything through
duck-typed seams:

| Seam | Where |
|---|---|
| `renderer` passed into `draw` | `node2d.rb:144`, `component.rb:22`, every UI and component `draw` |
| `node.root.context.assets` | `components/animated_sprite.rb:29` |
| an audio server behind `AudioDirector` | `audio_director.rb`, fed by `AudioBus` events |
| an input backend behind `ActionMapper#poll(backend)` | `input/action_mapper.rb:28` |

So the layering rule this move has to satisfy is one the layer already keeps.
The move is mostly a rename, a namespace and a spec suite — **not** a rewrite.
That is worth knowing before anyone budgets for it.

## What is actually blocking

### 1. The mouse — six lines, and one of them stops everything

The Gosu-replacement brief dropped mouse input deliberately
([why](../gosu-replacement/README.md#mouse-input-is-not-carried-over)).
`RGame::Core::Input` has no `pointer_x`/`pointer_y` and no `:pointer` binding.

The hard blocker is `input/action_mapper.rb:41-42`:

```ruby
@pointer[:x] = backend.pointer_x
@pointer[:y] = backend.pointer_y
```

Unconditional, so `poll` raises `NoMethodError` against a `Core::Input` — the
engine layer does not run *at all* until this goes. Phase 6.8 deletes these two
lines as the minimum to get the examples up; the rest is this plan's:

- `input/actions.rb:16,20,43,44` — the `pointer:` constructor keyword and the
  `pointer_x`/`pointer_y` readers.
- `components/clickable.rb:31` — a component that is mouse-only by definition.
  Probably deleted rather than ported.
- `lib/engine/ui/` — see below.

### 2. The UI package is outdated and mouse-built

`ui/menu.rb`, `ui/button.rb`, `ui/selector.rb`, `ui/control.rb` all hit-test
against `actions.pointer_x`/`pointer_y` (`menu.rb:59-64`, `button.rb:72`,
`selector.rb:39-41`). It is being replaced on its own account, so it is **not a
reference for the port** — do not treat its current API as something to
preserve. Keyboard and controller navigation is the replacement, which was the
known cost of the mouse decision.

Note the knock-on: nothing in the copied examples registers a UI atlas, so
`renderer.nine_slice` and `Core::UiAtlas` have no end-to-end exercise. Whatever
replaces the UI package is what will first prove that path.

### 3. `Engine::Tensor` duplicates `RGame::Util::Tensor`

`lib/engine/tensor.rb` is a pure-Ruby 3-D grid. `RGame::Util::Tensor` is the
same thing in C, and is *why* `ext/rgame_util/` exists. One caller:
`tile_map.rb:109`, packing per-layer gids.

A straight swap, and the first concrete instance of the rule "the engine layer
may hold `Util` types". Worth doing early — it is small, it validates the
boundary, and it deletes a file. Check `Engine::Matrix` (`lib/engine/matrix.rb`)
for the same question at the 2-D end.

### 4. `TileMap` needs a `load`, and Core is blocked on it

The smallest concrete piece of work in this folder, and the only one another
plan is waiting for. `Platform::TileMapRenderer.load` is the one place the
platform layer names `Engine::` from code:

```ruby
map = Engine::TileMap.parse(File.read(tmx_path))
map.tileset = Engine::Tileset.parse(File.read(tsx_path), firstgid: map.firstgid)
image_path = File.join(File.dirname(tsx_path), map.tileset.image_source)
```

Ported as-is that puts `RGame::Core` in the position of knowing `RGame::Engine`
exists, which `Game/NoEngineInCoreLayer` now forbids. The five lines are pure
file-and-XML work with no graphics in them, so they belong here rather than
below: **`Engine::TileMap.load(tmx_path)`**, returning the parsed map with its
tileset attached, plus the resolved image path.

Gosu-replacement 6.5 is written against that, and cannot land without it. It
also settles the shape Core wants: the renderer is *handed* a map and a set of
tiles and loads nothing itself, so the map protocol it calls by name —
`layer_count`, `above_layer?`, `gid`, `tile_width`, `pixel_width`, `tileset` —
becomes a shared example both `Engine::TileMap` and a spec fake run against.

### 5. Split-screen does not exist yet

The transform and clip stacks were designed for it
([02-architecture](../gosu-replacement/02-architecture.md#split-screen-is-a-requirement-on-this-design-not-a-later-feature)):
per viewport, `clipped` then `translated`, running the same world-draw code.
`CameraView` (`camera_view.rb:22`) and `Camera` are the pieces that would grow
it, and `renderer.clipped` is the one Core method the copied examples never
call — so the plumbing is ready and untested from above.

This is the "not 1:1, there will be changes" part: it changes what a camera *is*
from a single draw-time offset to one of several viewports.

## Things to decide when this becomes a plan

Recorded as questions, not answered.

- **Namespace and path.** `Engine::` → `RGame::Engine::`, `lib/engine/` →
  `lib/rgame/engine/`. Mechanical, but it is 57 files and every `examples/`
  reference, so it wants to be one commit that does nothing else.
- **What `SonGosuGame` becomes.** Phase 6 turns it into an
  `RGame::Core::App` subclass, which means it holds Core and therefore cannot
  move into `RGame::Engine`. Is it a game's own file (each game writes one), a
  documented template, or something in `RGame::Core` with a scene-graph-shaped
  hole? The name goes either way.
- **Where `docs/engine/` lands.** It is real reference documentation, currently
  describing the Gosu-era API (`docs/engine/asset_manager.md` documents
  `Platform::AssetManager` returning `Gosu::Image`). It should end up merged
  into `docs/api/` rather than living beside it, but it is eight files and
  1,328 lines, so that is a task rather than a footnote.
- **Packaging.** `rgame.gemspec`'s `spec.files` is a glob over `lib/`, so
  `lib/engine/`, `lib/engine.rb`, `lib/boot.rb` and `lib/son_gosu_game.rb`
  currently ship — 60 files, one of which requires `gosu`, which is not a gem
  dependency. Gosu-replacement 6.9 excludes them as a stopgap. When the layer
  moves to `lib/rgame/engine/` it *should* ship, so that exclusion and its
  packaging-spec expectation come back out here — the same lifecycle
  `lib/platform/`'s exclusion had.
- **Specs.** `lib/engine/` arrives with none in this repo, and
  `docs/engine/asset_manager.md` references a `spec/platform/asset_manager_spec.rb`
  that did not come with it. The headless `spec/` suite is exactly the right
  home — the whole point of the layer is that it specs with no window — so this
  is the same shape phase 6 had: the specs are the deliverable as much as the
  move is.
- **`Engine::AudioDirector` and `AudioBus`.** The engine emits
  `:play_sound`/`:play_music` events and a director turns them into calls on an
  audio server. `RGame::Core::Audio` grows exactly that interface in phase 6.7,
  and `spec/support/shared_examples/an_audio_server.rb` is the contract —
  so the director should be run against the same fake the contract checks. That
  is a free win and probably the first spec written here.
- **`DebugOverlay`.** Reads `Gosu.fps` via its `draw(renderer, w, h, fps)`
  signature, so it is already decoupled; `App#fps` supplies it. But it also
  reports per-frame allocations, and the reason that number was worth watching —
  Gosu's splat-allocating callback wrappers — no longer exists. Worth asking
  what it should measure now.

## Cross-references

- `docs/plans/gosu-replacement/` — the prerequisite. Its phase 6 ends with
  `lib/engine/` running unmodified on Core; delete that folder only after
  folding its still-true decisions into the real documentation.
- `docs/engine/` — the engine layer's own documentation, written against the
  Gosu-era platform. Read `scene_graph.md`, `components.md` and `systems.md`
  first; they describe the architecture this plan is preserving.
- CLAUDE.md, "The three layers, and who may talk to whom" — the rule this move
  has to satisfy, and the two mechanisms that enforce it.
