# 04 — Roadmap

The implementation plan for the design in [`03-design.md`](03-design.md),
following the order sketched in its §10 and breaking each step into landable
commits.

**All steps are now planned in detail. Steps 0–4 are implemented**, each
carrying a "Landed" note recording how the result differed from the sketch;
those notes are the useful part to read before starting the next step, because
most of them are decisions the sketch got wrong.

Steps 4–6 were deliberately left rough at first and re-planned once the layer
beneath them existed — the way both previous plans in this project worked, and
it was right again here. Step 4's re-plan overturned two assumptions step 3 had
recorded as fact (that a recording bakes the ambient transform, and that the
tile map fix needed a change to the C API); step 5 and 6's found that `solo!`
was already built and that the UI atlas the first menu needs already exists.
Writing any of them out earlier would have been writing fiction.

Each step ends green: `rake` (C tests, both Ruby suites), RuboCop on the touched
files, and both examples still running — **driven, not booted** (step 0).

---

## Dependency shape

```
0 harness ─→ 1 input ─→ 2a Player+camera ─→ 2b ownership ─→ 3 View/Layout ─→ 4 two views ─┬─→ 5 solo + pause ─┐
                 │                                              │                         │                   ├─→ 6 per-player UI
                 └── independently useful ──────────────────────┘                         └───────────────────┘
```

Step 6 wants 5a's `paused` flag — a player's walker stops while their menu is
open — but nothing else from step 5, so the two can be reordered if the UI half
turns out to be the more pressing one.

Steps 1–3 are worth landing even if split-screen is deferred indefinitely. Each
one closes a standing defect on its own account:

| Step | Defect it closes |
|---|---|
| 1 | no gamepad input above Core at all; no analog axes; no dead zone anywhere |
| 2 | a camera that cannot be reused, and one clamped to a size fixed at construction |
| 3 | a HUD that cannot measure its own region; no culling hook |

## What was measured before planning

Numbers, so nobody budgets from a guess. Taken at `b68a511`.

| | |
|---|---|
| Headless suite baseline | **587 examples, 0 failures**, 0.48s |
| Engine-layer `draw`-protocol definitions | **11**, across **8** files |
| `on_draw` in `examples/` | **4**, across **4** files |
| Spec files defining a `draw` | 2 real (`node2d_spec.rb`, `spec/support/*`) + 4 cop-spec fixtures |
| `Core`'s own `draw` methods | 5 — **none of them change**; `Recording#draw(x, y)` and friends are a different protocol |
| Engine files defining `control` | 6 |
| Engine spec files | 50 |

**The `draw(renderer, view)` sweep is far smaller than it sounds.** Eleven
definitions in `lib/rgame/engine/`, four in the examples, a handful of spec
fixtures. That is the single widest change in the plan and it is a morning's
work, not a week's. It was worth measuring precisely because "change every draw
call site" *sounds* like the expensive part of this rework and is not.

The exact eleven:

```
lib/rgame/engine/node2d.rb:145   def draw(renderer)
lib/rgame/engine/node2d.rb:219   def on_draw(renderer); end
lib/rgame/engine/node2d.rb:227   def draw_content(renderer)
lib/rgame/engine/node2d.rb:235   def draw_children(renderer)
lib/rgame/engine/component.rb:23 def draw(renderer); end
lib/rgame/engine/camera_view.rb:23           def draw_children(renderer)
lib/rgame/engine/debug_overlay.rb:58         def draw(renderer, width, height, fps)
lib/rgame/engine/scene/scene_stack.rb:51     def draw(renderer)
lib/rgame/engine/components/sprite.rb:25         def draw(renderer)
lib/rgame/engine/components/animated_sprite.rb:42 def draw(renderer)
lib/rgame/engine/components/tile_world.rb:58     def draw(renderer)
```

## The invariant every step must preserve

Beyond the standing ones (no Core in Engine, no Engine in Core, no SDL in
`spec/`), this rework has one of its own:

> **`control` and `update` run exactly once per node per tick, whatever the
> player count. Only `draw` multiplies.**

It is worth a spec of its own, added in step 3 and extended in step 4: a counting
node in the world band asserts `update` ran once and `draw` ran N times. Without
it, the regression that duplicates simulation is silent until an NPC moves at
double speed with two players.

---

## Step 0 — A driven-example harness, in the repo

**Nothing else starts until this exists.** Every step from 1 onward changes
wiring, and CLAUDE.md is explicit that the examples are the acceptance test for
wiring — *driven*, not booted. The failures this rework risks are exactly the
ones a frame counter cannot see: player 2's input reaching nothing, player 2's
viewport drawn with player 1's camera. A plain boot of a game whose menu
responded to nothing once reported "90 ticks, 90 frames" and looked healthy.

It also goes **in the repo**, at `tools/drive_example.rb`. The previous harness
lived outside it, which made it a caller no project-wide rename could reach, and
it broke after every sweep. `tools/` is already the documented home for
development tools that are not built by `make`.

### What it does

1. Boots an example under the Xvfb helper `spec_core/support/headless_display.rb`
   already provides.
2. Injects a **scripted input backend** — a per-tick script of which actions are
   held, per device — instead of the real one.
3. Bounds the tick count and exits.
4. **Counts and reports**: draw calls by kind, clip rects pushed (with their
   coordinates), translate offsets pushed, sounds played, scene pushes/pops, and
   ticks vs frames.

(3) and (4) are the point. The clip and translate report is what will make
step 4 provable rather than eyeballed.

### The one production change it needs

`RGame::Game` hardcodes `@input = RGame::Core::Input.new(self)` (`game.rb:54`).
It needs an injection seam — `Game.new(..., input: nil)` defaulting to the real
one. Small, and it is the same duck-typed seam the engine layer already relies
on everywhere else.

**Verify:** run both examples through it, and confirm the counts are non-trivial
— that example 14's start scene actually advances when the script presses
`confirm`, and that example 15's player actually moves. A harness that reports
zeros for everything passes just as easily as one that works.

**Landed.** `tools/drive_example.rb` plus one script per example in
`tools/drive/`, named after the example's directory so adding an example means
adding a script rather than editing the harness. `RGame::Game` gained the
`input:` keyword and nothing else. `rake` green: 318 C checks, 587 headless
examples, 329 Core examples.

Both acceptance criteria met. Example 14 reports
`push StartScene / pop StartScene / push PlayScene / pop PlayScene / push
GameOverScene` — the scripted `confirm` really does advance the title screen, and
the ship really does die. Example 15 reports the tilemap camera moving
`first(…, 0.0, 0.0, 640, 480)` → `last(…, 788.0, 648.0, 640, 480)`, so the player
walked.

Four things the sketch got wrong or did not anticipate:

- **The probes had to be split in three.** One recording delegator was not
  enough: the asset manager *decodes* through the audio server (`sample`,
  `song`), so a single probe counted file loads as draw calls. `Probe` is now the
  bare forwarder, with `RendererProbe` and `AudioProbe` deciding what is worth
  recording. Forwarding stays generic — a renderer that grows a primitive is
  counted with no edit here — and only the deny-list is enumerated.
- **`press` is two ticks, not one.** Edge queries compare against the previous
  poll, so an action that goes down and never comes up reads as *held* forever,
  which drives a menu differently from a press. The DSL's `press` emits down then
  up for exactly this reason.
- **Example 14 is not deterministic.** It spawns rocks from an unseeded
  `Random.new`, so draw counts vary by tens between runs and a collision may or
  may not happen. Structure (scenes, sounds, clips, ticks vs frames) is stable
  and is what to assert on. Recorded in the harness's own header and in CLAUDE.md
  rather than "fixed", since the seed is the example's choice.
- **One RuboCop exception**, with its reason, in `.rubocop.yml`:
  `Style/FrozenStringLiteralComment` is excluded for `tools/drive/**/*.rb`. Those
  files are `instance_eval`'d, never required, so a file-level magic comment in
  one is inert and adding it would be cargo cult.

**And it immediately earned its keep**: all three examples report
`clips pushed: (none)`. Inventory blocker 9 — "`renderer.clipped` has never been
called from above" — was read off the source and is now *measured*. That is the
baseline step 4 has to move.

Documented in CLAUDE.md ("The examples are the acceptance test for wiring", which
described this harness in the abstract and now names it) and as tier 3b in
`.claude/skills/verify/`.

---

## Step 1 — Input: real physical ids, real devices, real axes

Single player throughout. No `Player` object yet, no camera changes. At the end
of this step **a controller drives `examples/15_tiled_world`**, which is
impossible today.

### 1a. `RGame::Engine::InputMap`

A new value class: one entry per action, listing every physical id that triggers
it plus an optional analog source.

```ruby
InputMap.new(
  move_x:     { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT], stick: Controls::AXIS_LEFT_X },
  fire:       { buttons: [Controls::KEY_SPACE, Controls::PAD_A] },
  ui_confirm: { buttons: [Controls::KEY_RETURN, Controls::PAD_A] }
)
```

**Listing keyboard and pad ids in the same entry is safe and self-selecting**,
because a device only answers for its own kind of input — asking a gamepad about
a keyboard scancode is `false`, never the keyboard's answer (`docs/api/input.md`,
"Devices"). That is what lets one table serve any device and removes the need for
`Core::Input`'s two parallel tables.

Ships with a default map built from `Controls::DEFAULT_*`, plus the **universal
UI set** merged into every map unless overridden: `ui_up`, `ui_down`, `ui_left`,
`ui_right`, `ui_confirm`, `ui_cancel`.

> `Controls::DEFAULT_KEYBOARD` has **no `cancel`/`back` binding** today. Add one
> here, bound to **Escape**. The UI toolkit is blocked on this.
>
> **Done ahead of step 1**: Escape used to be `Game`'s quit key, which is exactly
> the key a player expects to back out of a menu. The quit binding moved to `F2`,
> so both of `Game`'s development shortcuts are now function keys (`F1` overlay,
> `F2` quit) and Escape is free for the layer that should own it. That took a new
> `KEY_F2` in all three places an id has to exist — `Util::Controls`,
> `ext/rgame_core/include/rgame/core.h`, and a `_Static_assert` against
> `SDL_SCANCODE_F2` in `app.c` — plus `docs/api/game.md` and `docs/api/input.md`.

Placed in `Engine` rather than `Util`, alongside `Actions`, on the grounds that
`Actions` is already there and the two are read together. It holds nothing but
`Util::Controls` integers, so `Util` would also be defensible — flag it at review
rather than churn later.

### 1b. `Core::Input` loses its binding tables

It becomes the raw query it always wanted to be:

```ruby
input.down?(physical_id, device: Controls::KEYBOARD)   # was: down?(action, device:)
input.axis(axis_id, device: Controls::KEYBOARD)        # was: axis(action, device:)
```

`App#input_down?(device, id)` and `App#input_axis(device, axis_id)` already exist
and are exactly this, so `Core::Input` becomes a thin argument-order adapter.
Delete `bindings:`, `pad_bindings:`, `axis_bindings:` and `bindings_for`.

Touches: `spec_core/rgame/core/input_spec.rb` (its whole "the binding table"
describe block goes; the rebinding example moves to the engine layer as an
`InputMap` spec), and `docs/api/input.md` (the "Actions, not keys" and
"Rebinding" sections move up a layer).

**This is a deliberate public-API deletion.** Say so in the commit: the table it
removes had exactly one caller and put rebinding out of reach of the layer that
needs it.

### 1c. `ActionMapper` takes a device and reads real axes

```ruby
mapper = ActionMapper.new(input_map, device: Controls.gamepad(0), dead_zone: 0.15)
mapper.poll(backend)   # backend: down?(id, device:) / axis(id, device:)
```

- Pass `device:` on every query — the fix for the defect that no gamepad input
  reaches the engine layer at all.
- Prefer the `stick:` source when the device has one, falling back to the
  two-button `axis:` pair. A keyboard player and a pad player then produce the
  same `Actions` from the same map.
- Apply the dead zone here. It is a per-device property and there is nowhere else
  for it to live.
- **Keep the allocation-free steady state.**
  `spec/rgame/engine/action_mapper_allocation_spec.rb` guards it and must stay
  green; the reused `@held`/`@axes`/`@prev_held` hashes and the single `Actions`
  are the mechanism.

### 1d. Wire it into `Game`

One mapper still, but constructed from an `InputMap` and a device.
`Game.new(..., action_map:)` becomes `input_map:`; both examples update (4 lines
between them).

Device selection stays dumb here — a `device:` argument defaulting to the
keyboard. Auto-claiming a pad on hot-plug is step 2's registry, not this.

### Verify

Three tiers, and **note that no single automated tier can see the whole path** —
`spec/` may not name Core and `spec_core/` may not name Engine, so the join is
only visible where all three layers are present at once. That is the rule, not a
gap to be worked around.

| Tier | What it proves |
|---|---|
| `spec/` | the mapper: device routing, stick-vs-button preference, dead zone, edge detection, still allocation-free |
| `spec_core/` | the raw queries answer per device — largely covered by `gamepad_spec.rb` already |
| `tools/drive_example.rb` + `VirtualGamepad` | the join: a synthetic pad moves the player in example 15 |

`spec_core/support/virtual_gamepad.rb` fabricates a real SDL controller
in-process and can set buttons and axes, so the last row needs no hardware.

**Landed.** `rake` green (318 C checks, 620 headless, 330 Core), RuboCop clean
across all 199 files, both examples driven.

New: `RGame::Engine::InputMap` and `spec/support/fake_input_backend.rb`.
Rewritten: `ActionMapper` (per device, analog, dead zone), `Core::Input` (raw
query, binding tables deleted), `Game` (`action_map:` → `input_map:` + `device:`).

**A controller now drives `examples/15_tiled_world`.** That was step 1's stated
goal and it needed a fifth verification mode nobody had planned: `--gamepad` on
the driver. The scripted *backend* stands where `Core::Input`'s answer would
arrive, so it can prove the game reacts to an action but not that a controller
reaches the game at all. `--gamepad` fakes the **hardware** instead — the
`VirtualGamepad` the Core suite already had — so SDL, the C snapshot,
`Core::Input`, `InputMap` and `ActionMapper` all run unstubbed. Result, from
`tools/drive/15_tiled_world_pad.rb`: the tilemap camera walks
`(0, 0)` → `(752.7, 428.0)` under a synthetic pad.

The dead zone got a three-way proof, which is worth repeating for any future
tuning because it needs no eyeballing:

| Script | Camera ends at |
|---|---|
| no input at all | `(648.0, 508.0)` |
| stick at 0.12 (inside the 0.15 dead zone) | `(648.0, 508.0)` — byte-identical |
| stick at 0.30 | `(669.2, 508.0)` — moves |

Four things the sketch did not anticipate:

- **`Util::Controls` lost its three `DEFAULT_*` tables**, not just
  `Core::Input`'s. They were shaped `action => one id per device class`, which is
  precisely the split one table listing every id for an action removes. `Controls`
  is now vocabulary only, and its spec says so out loud (`constants.grep(/\ADEFAULT_/)`
  must be empty) rather than the rule going silent. CLAUDE.md's "value objects go
  in Util" worked example was built on `DEFAULT_KEYBOARD` and now builds an
  `InputMap` instead — the argument survives intact and reads better, since the
  whole table is now an engine-layer value made of Util ids.
- **`ext/rgame_core/example.rb` had to grow a two-line `held?(key, pad)` helper.**
  It is the Core-only driver, so with binding gone it must name both ids itself.
  That is not a wart: it demonstrates exactly what the layer above is for, and
  its comment says so.
- **`InputMap` validates at construction** — unknown source key, no source at
  all, empty button list, an axis that is not a pair. This replaces a guarantee
  the rework deletes: `Core::Input#down?(:teleport)` used to raise `KeyError`. A
  misspelled action at a *read* site is still silent (`Actions#held?` returns
  false), which is unchanged from before but now worth considering — see below.
- **`press` in the driver's DSL, and the `tilt` verb.** The script gained
  per-tick analog values because there was no other way to exercise the new
  analog path; both modes read them.

### 1e. `Actions` is strict *(follow-up, landed separately)*

Reading an action the snapshot never declared raises `KeyError` instead of
returning `false`. This is where `Core::Input#down?(:teleport)`'s old `KeyError`
went: that guarantee was about an unbound *physical* id and could not survive
1b, but the mistake it caught — a name nothing answers for — is real and now
caught one layer up, where the vocabulary actually lives.

The failure it replaces is silent and remote. A misspelled action reads as
"never pressed", and what a player sees is a button that does nothing, somewhere
far from the typo. Driving `examples/14_asteroids` with `:ui_confirm`
deliberately misspelled now stops on:

```
no such action :ui_confrim — declare it in the InputMap
(this snapshot has [:ui_up, :ui_down, :ui_left, :ui_right, :ui_confirm, ...])
```

The correct name is in the message, beside the wrong one. Before this it was a
title screen that never advanced.

**The hashes are the declaration.** `ActionMapper` seeds all three from its map
at construction, so through the normal path every declared action answers every
query and nothing else does. No extra state and no membership check: the lookup
that was already there simply stopped having a default.

Three things worth recording:

- **It costs nothing.** `fetch(name) { undeclared(name) }` rather than a bare
  `fetch(name)`, so the message can be useful; a literal block passed to a C
  method allocates no Proc. `action_mapper_allocation_spec.rb` asserts that
  directly, because this is the hottest read in the engine — once per action per
  node per tick.
- **`prev_held` stays lenient**, and deliberately. It is one frame behind, so on
  the first poll after an action is added it legitimately has no entry, and "was
  not held before" is the right answer rather than an error. The current-frame
  lookup is what catches the typo.
- **Twelve specs needed the action set declared**, not the fifteen estimated —
  and the ones that did not are informative. `scene.control(Actions.new)` used
  purely to resolve absolute positions keeps working, because nothing in those
  trees reads an action. The twelve that broke are exactly the specs of
  components that *do* read one, and each now says what set it reads
  (`actions(turn: 1.0)` over a declared `{turn:, thrust:}`), which is better than
  what was there.

---

## Step 2 — `Player`, the registry, and the camera moving onto it

Two commits, because 2b changes a traversal and 2a does not.

### 2a. `Player` + `Players` + camera ownership

**`RGame::Engine::Player`** — id, device, `InputMap`, its own `ActionMapper` and
`Actions`, a `Camera`, and a `ui` root `Node2D` (unused until step 6).

**`RGame::Engine::Players`** — a registry, a component on the root node so it is
reachable as `node.system(Players)`. Holds the player list, `primary`, and
`poll(backend)` which polls every player's mapper once per tick. Claims a newly
connected pad for the first player without one, driven by `Game`'s existing
`gamepad_connected(slot)` hook.

**`Camera` loses its viewport size:**

```ruby
Camera.new(world_width:, world_height:)
camera.center_on(x, y)
camera.resolve(view_width, view_height)   # clamp for THIS rect
```

The clamp has to happen against the rect actually being drawn into — a half-width
viewport clamps differently from a full-width one, and that difference is
visible, not theoretical:

```
target  500 (mid-world)      cam 340.0 -> 180.0   target at 50% -> 50% across the view
target  900 (near right edge) cam 680.0 -> 360.0   target at 69% -> 84%
```

Making it a call rather than stored state is what stops the two drifting.

**`CameraFollow`** — a component in the world, on the followed node, holding the
player's camera. Replaces `BeachScene#on_update`'s hand-rolled centring
(`beach_scene.rb:44-48`), which also drops that method's inline comment about
computing the feet-box centre without allocating — keep the technique, move it.

`TileWorld` takes the camera from the player rather than the scene. Still one
camera, so nothing looks different.

**Verify:** example 15 looks and behaves exactly as before. `rake spec` green,
with `camera_spec.rb` rewritten for the new signature.

**Landed.** `rake` green (318 C checks, 683 headless, 330 Core), RuboCop clean
across 206 files. Example 15 drives **byte-identically** to the committed
baseline — `(788.0, 648.0)` and 1680 sprites, the same numbers as before the
step — which is exactly the acceptance criterion for a step that is meant to
change ownership and nothing else.

New: `Engine::Player`, `Engine::Players`, `Components::CameraFollow`, and specs
for each. Rewritten: `Camera` (`center_on` records intent, `resolve(w, h)`
clamps), `Game` (owns a `Players`, mounts it as a root-scoped system, resolves
cameras before drawing, forwards hot-plug), `TileWorld` (takes its camera from a
player and sets that camera's world bounds from the map).

**The harness caught a real bug, and it was mine.** The first version attached
`CameraFollow` inside `build_player`, which reads the player's feet box — and
`CharacterBody#collision_box` is *memoised from `node.width`/`node.height`*,
which `AnimatedSprite#on_attach` sets. Reading it one line too early baked a box
computed from a 0×0 sprite, permanently, for the **collision system** as well as
for the camera. The suite stayed green. What showed it was the drive report
moving from `(788, 648)` to `(780, 616)` — a 32px drift with byte-identical
sprite counts — and `git stash` gave the before/after in one command. This is
the failure class the harness exists for: nothing looked wrong anywhere.

Two things came out of that:

- `follow_camera` is called *after* `view.add_node(@player)`, with a comment
  saying why the order is load-bearing.
- **`CharacterBody#collision_box` now refuses an early read** rather than baking
  a wrong box, naming the size it saw and where the size comes from. That is
  beyond 2a's scope and deliberate: the failure is silent, permanent and
  action-at-a-distance, and it took thirty seconds of ordinary use to hit.

Three smaller notes:

- **`Camera` defaults to unbounded**, not to `0`. A camera with no declared
  world follows its target exactly, so a game that has not set bounds yet gets
  one that visibly works rather than one mysteriously pinned to the origin.
  `TileWorld` sets the bounds when it loads a map.
- **`TileWorld#draw` reads the view size from `context`** for now, since a camera
  no longer carries one and there is no `View` yet. Marked transitional in the
  code and in its spec; step 3 replaces it with `view.width`.
- **`Game#action_mapper` is gone**, replaced by `Game#players`. It had no callers
  outside its own docs, and a compatibility shim for a gem that has never shipped
  is clutter.

Not in this step, by design: `control` still broadcasts the primary player's
`Actions` to the whole tree. Ownership routing is 2b.

### 2b. Ownership routing for `control`

`Node2D` gains an owner attribute, **inherited down the tree exactly like the
transform**, resolved in `resolve_origin` alongside `abs_x`/`abs_y`/`abs_z`:

```ruby
@abs_controller = @controller || (@parent && @parent.abs_controller)
```

Named `controller` rather than `player` so that a game's own `Player` node does
not read `@player.player` from outside — see [`03-design.md`](03-design.md) §11.1.

`Node2D#control(players)` then resolves the owning player and passes that
player's plain `Actions` to its components and to `on_control`. **No component
changes.** `Components::PlayerController#control(actions)` still receives an
`Actions`; an unowned node resolves to the primary player, so the entire
single-player path is untouched.

**Verify:** the whole existing suite is the test — the examples that all assume
a broadcast `Actions` must stay green, because an unowned node still gets one.
Add examples for a node with an explicit owner and for inheritance through a
subtree.

**Landed.** `rake` green (318 C checks, 701 headless, 330 Core), RuboCop clean
across 208 files, all three drives byte-identical to the 2a baseline. Exactly one
pre-existing example needed changing (`node2d_spec.rb`'s ordering example, to
stub the new method on its double) — the 683 that assume a broadcast snapshot
stayed green untouched, which was the claim.

**The mechanism is one method on two types**, which is what kept the blast
radius at one example. An input *source* answers `actions_for(owner)`:
`Players` returns that player's snapshot (or the primary's for nil), and
`Actions` returns **itself** — a snapshot is a degenerate source, one answer for
everyone. So `node.control(actions)` still means what it always meant, and
`node.control(players)` routes. No type checks, no branch on the hot path.

**Ownership is inherited like the transform.** `resolve_origin` resolves
`abs_input_owner` alongside `abs_x`/`abs_y`, so it costs one assignment per phase
and is available in `update` and `draw` too — which a per-player HUD will want.
`spec/rgame/engine/node2d_control_allocation_spec.rb` asserts the whole
traversal still allocates nothing, since routing added a call per node per tick.

Three things the sketch did not anticipate:

- **The attribute cannot be called `player`.** The sketch said `controller`, and
  §11.1 of the design said `player` with `controller` as an option. Both are
  wrong. `attr_accessor :player` reads `@player` — which is exactly what
  `examples/15_tiled_world` calls its hero node — so it silently claimed that
  ivar and the input system was handed a `Node2D`. `controller` is taken too:
  `Actor#controller` is the thing that produces movement intent. It is
  **`input_owner`**, which collides with neither and says what it decides. Found
  by driving the example, not by the suite: every spec passed with the collision
  in place, because no spec subclasses Node2D and stores a hero in `@player`.
- **`SceneStack` had to be taught to forward the source.** Scenes live off the
  child list, so the traversal cannot reach them — and a *component* is handed
  one player's resolved snapshot, which is right for a component but flattens a
  whole scene onto whoever owns the host. It pulls `node.system(Players)` in
  `on_attach` and passes that down, falling back to the snapshot when no
  registry is mounted. Without this, 2b would have been inert in practice: every
  bit of game content lives inside a scene.
- **That is a general rule, now written down** in `Component`, beside
  `sweep_freed`: a container component holding a subtree needs the source, and
  gets it by system lookup rather than by a new hook.

Documented in `docs/api/scene_graph.md` ("Who a node answers to").

---

## Step 3 — `View`, `Layout`, `Viewports`, and `draw(renderer, view)`

Still **one full-screen view**, so the acceptance test is that nothing looks
different. This is the step that introduces the machinery; step 4 is the step
that uses it.

### 3a. The values and the system

- **`View`** — `x`, `y`, `width`, `height`, `camera` (nil for screen-space
  bands), `player`, `visible?(x, y, w, h)`.
- **`Layout`** — pure rect arithmetic. `Layout.split(count, w, h) => [rects]`,
  `Layout.full(w, h)`. Specced alone, with no node and no window.
- **`Viewports`** — the root-scoped system holding the active players, the
  current mode and the window size. `solo!(camera)` / `split!` **record a
  request**; the stage applies it at a fixed point in the tick, never mid-draw
  (`03-design.md` §3.1). `Game` forwards `App#resize(w, h)` into it.

### 3b. The signature sweep

The eleven definitions listed above, the four example `on_draw`s, and the spec
fixtures. `DebugOverlay#draw(renderer, width, height, fps)` collapses to
`draw(renderer, view)` — it already wants a rect and currently gets the window
by hand from `Game`.

Two things to catch while sweeping:

- **`draw_children` and `draw_content` are not in the hot-path cop's method
  list** (`rubocop/cop/game/hot_path.rb:16` — `%i[update control draw on_update
  on_draw on_control]`). `WorldView#draw_children` will run once per view per
  frame, which is the hottest path in the whole design and is currently
  unguarded. Add both names, or tag them `# hot-path`.
- The cops key on method *names*, so adding a parameter is invisible to them —
  no cop changes are needed for the sweep itself.

### 3c. The band node types

`WorldView`, `PlayerLayer`, `Overlay` — the three subclasses in
[`03-design.md`](03-design.md) §2.1. `CameraView` is deleted and its spec
becomes `world_view_spec.rb`.

`Game` assembles the default stage: a world band holding whatever the game passes
as its root, one player, an empty overlay. `Game.new(root:)` becomes
`Game.new(world:)`, and the single-player call site gains nothing else.

### 3d. `TileWorld` draws through the view

```ruby
def draw(renderer, view)
  renderer.tilemap(@tilemap_id, view.camera.x, view.camera.y, view.width, view.height, elapsed: @elapsed)
  ...
end
```

The clearest single illustration of why the view is a parameter: this component
cannot work from a stored camera once there is more than one.

**Verify:** both examples pixel-identical to before — `spec_core`'s
`RenderedFrame` helper reads the framebuffer back, so this is assertable rather
than eyeballed. Plus the once-per-tick invariant spec described above.

**Landed.** `rake` green (318 C checks, 753 headless, 330 Core), RuboCop clean
across 215 files, all three examples driving identically to the 2b baseline.

**`renderer.clipped` is now called from above, for the first time in the
project's history.** Inventory blocker 9 was the one thing here that had never
been exercised, and the drive report moved from `clips pushed: (none)` to
`240 × [0, 0, 640, 480]`. It worked first time, which is what the C-side
`test_canvas.c` coverage was for.

New: `View`, `Layout`, `Viewports`, `WorldView`, `spec/support/view_helper.rb`,
and specs for each. Deleted: `CameraView` and its spec. Swept:
`draw(renderer)` → `draw(renderer, view)` across the engine layer, the examples
and the spec suite.

**The stage is not a node.** The sketch had `Game` assembling a Stage with the
game's root inside a world band, and `Game.new(root:)` becoming `world:`. That is
wrong, and the reason is `Node2D#root`: inserting anything above the game's root
node moves the anchor, so `node.system(HighScores)` — a root-scoped system
`examples/14_asteroids` mounts on its own root — would resolve against the Stage
and find nothing. Every game with a root-scoped system would break silently.

What actually works is smaller and better: **`WorldView` marks where world space
begins, and everything outside one is screen space.** `Game` draws the tree once
with the whole window as its view, and a `WorldView` anywhere in it loops the
viewports internally. So the bands are node types the game places (which is what
§2.1 of the design said all along), `root:` keeps its name and its meaning, and
nothing is imposed above the game's own tree. The "three bands" stay a
conceptual model rather than a schema.

Four other things worth recording:

- **The tilemap does not multiply yet, and step 4 has to fix it.** `TileWorld`
  sits on the scene node, outside any `WorldView`, so it draws once per frame
  rather than once per viewport. That is correct for one view and is the first
  thing the second view breaks, because Core's tilemap draws in **screen**
  space — `TileMapRenderer#draw` replays its baked recording at `-camera`, so
  inside the band's translate it would offset twice.

  > **Corrected while planning step 4.** This note went on to say the fix needs
  > "Core to grow a world-space tilemap draw", implying a C change, and that the
  > lazy bake could not happen inside the band. Both are wrong.
  > `tile_map_renderer.rb` is pure Ruby, and a recording bakes on a *separate
  > canvas* begun at identity, so the ambient transform is not captured —
  > measured, see step 4's "What was measured before planning". The fix is a
  > change of meaning to three arguments in one Ruby file.
- **`DebugOverlay` lays out against its view**, not the window, so it already
  behaves correctly in a region. Its signature is `draw(renderer, view, fps)` —
  `fps` stays an argument because nothing on a draw path reads a clock.
- **`draw_children` and `draw_content` joined the hot-path cop's list.** A
  `WorldView` runs them once per node *per player*, which makes them the hottest
  methods in the engine, and they were the only part of the draw path the
  allocation guards could not see.
- **A cop I nearly disabled was right.** `Style/ExplicitBlockArgument` wanted
  `Layout.each_rect` to capture `&block` rather than re-yield, and I assumed
  capturing a block allocates a Proc and would break the allocation spec. It
  does not — Ruby elides the Proc for a block that is only forwarded. Tested
  before writing the justification, which is the only reason the wrong
  justification did not get written down.

Documented in `docs/api/scene_graph.md` — the camera section is rewritten around
`WorldView`, and there is a new "Viewports and views" section covering `View`,
`Layout` and `solo!`.

---

## Step 4 — Two views

Re-planned after step 3, which is what the roadmap said would happen: the
obstacle step 3 left behind turned out to be smaller than it looked, and two
assumptions in the sketch were wrong.

**Six commits, in this order.** The harness comes first for the same reason it
did in step 0 — nothing after it is verifiable otherwise — and the tile map
comes before the second player because it is the one thing that is *broken* at
two views rather than merely absent.

4c grew a second half after the plan was first written: **how a device comes to
occupy a seat.** The sketch left `claim_gamepad`'s seat-on-connect in place as
the only behaviour, which drops a pad plugged in by a solo player, splits the
screen when a spare pad wakes up, and cannot be turned off for a cutscene. The
default was wrong rather than merely unfinished, so the fix belongs where the
second player first exists rather than after it.

### What was measured before planning

Two questions decided the shape of this step, and both were answered by running
code rather than reading it.

**Does a recording bake the transform that was active when it started?** This
decides whether the tile map can live inside a `WorldView` at all, because
`TileMapRenderer` bakes lazily on its first draw — which, inside the band, would
happen under a camera transform. Step 3's note assumed it did and recorded that
Core would need a new world-space tilemap call.

**It does not.** `rgame_app_begin_record` calls `rgame_canvas_begin_frame` on a
**separate `record_canvas`**, so the bake starts from an identity transform
stack; only transforms pushed *inside* the block are captured. Verified by
drawing through a real window: a quad recorded inside `translated(20, 0)` and
replayed inside `translated(20, 0)` lands at x=24, not x=44.

```
at (4,4)   = [26, 26, 38, 255]    background
at (24,4)  = [255, 0, 0, 255]     only the replay translate applied
at (44,4)  = [26, 26, 38, 255]    the ambient transform was NOT baked
```

**Is `TileMapRenderer` C?** No — `lib/rgame/core/tile_map_renderer.rb` is pure
Ruby, and the camera reaches GL only through `Recording#draw` and
`renderer.image_at`. So the whole of 4a is a Ruby change in one file plus its
callers. Step 3's note said this needed "Core to grow a world-space tilemap
draw", which is true but meant Core-the-layer, not C.

Together those turn the known blocker from "extend the C API" into "change what
three arguments mean".

---

### 4a. The tile map moves into the world band

The blocker step 3 left. `TileWorld` draws once per *frame* because it sits on
the scene node, outside any `WorldView`; the second view is what breaks it.

The camera arguments to `TileMapRenderer#draw` mean two different things at once
today, and separating them is the whole fix:

| Use | What it should become |
|---|---|
| `@static_below.draw(-camera_x, -camera_y)` — where to put the replay | **gone**: replay at `(0, 0)`, in world coordinates |
| `(col * tile_width) - camera_x` — where to put an animated tile | **gone**: draw at `col * tile_width`, in world coordinates |
| `col_start`/`col_end` — which tiles are worth drawing | **kept**: this is the cull rect, and it is genuinely the camera's |

So the arguments stay, the arity stays, and their meaning narrows to "the
rectangle of the world to cull to". Placement becomes the transform stack's job,
exactly like every other drawable.

1. **`lib/rgame/core/tile_map_renderer.rb`** — replay at `(0, 0)`, animated
   tiles at world coordinates, cull unchanged. Rename the parameters so the new
   meaning is on the page (`cull_x`, `cull_y`, `cull_width`, `cull_height`).
2. **`Renderer#tilemap` / `#tilemap_overlay`** — same signature, updated doc
   comment saying the map draws in world space and the caller supplies the
   transform.
3. **The renderer contract** — `spec/support/shared_examples/a_renderer.rb` and
   `spec/support/fake_renderer.rb`. Arity is unchanged, so this is a wording and
   assertion change, not a new method. `spec_core/rgame/core/tile_map_renderer_spec.rb`
   asserts positions and is where the change actually bites.
4. **`TileWorld` stops drawing.** It keeps what makes it a *system* — the map,
   collision, world bounds, and the animation clock — and loses `draw` and its
   `@camera`. A system that also drew was always a little odd; this is a good
   excuse.
5. **New `RGame::Engine::TileMapLayer < Node2D`**, placed *inside* the
   `WorldView`. It reads `system(TileWorld)` for the map id and the elapsed
   clock, and `view.camera` for the cull rect. Both z bands are drawn from it.
6. **`examples/15_tiled_world`** places it.

**Verify:** example 15 drives byte-identically with one view — the tile map is
the one thing whose numbers would move. Then, with two views, `tilemap` appears
twice per frame with two different cull rects.

**One thing to check while here**, because the probe above did not cover it: the
first draw bakes a recording *inside the band's clip*. Clips are refused
**while** recording, and this pushes none, so it should be fine — but confirm it
rather than assume, with the same throwaway probe recipe.

**Landed.** `rake` green (318 C checks, 761 headless, 333 Core), RuboCop clean
across 217 files, all three examples driving identically.

The flagged check passed: baking inside an active clip neither raises nor
captures the clip — a recording made under `clipped(0, 0, 32, 64)` replays
correctly under `clipped(32, 0, 32, 64)`.

What landed, against the plan: `TileMapRenderer` draws in world coordinates and
its rectangle is now a cull rect (`cull_x`… throughout); `Renderer#tilemap` and
the renderer contract say so; `TileWorld` lost `draw` and `camera:` and gained
`cameras:`, `#bound`, `#tilemap_id` and `#elapsed`; `RGame::Engine::TileMapLayer`
draws the map inside the world band; `examples/15_tiled_world` mounts it.

**Two things worth recording:**

- **`spec_core/rgame/core/tile_map_renderer_spec.rb` caught the change exactly,
  and its failures sorted themselves into two piles.** Two were real behaviour
  assertions that had to be rewritten (the replay offset, and where an animated
  tile lands). Three were the *helper* — `drawn_cells` recovered a tile's column
  by adding the camera back to its drawn position, which is only meaningful
  while the output is camera-relative. Culling itself never changed. Worth
  knowing that the split was 2 real to 3 incidental before reading the diff as
  alarming.
- **A pixel tier was missing and now exists.** Every assertion in that spec is
  about recorded calls, which is right for "which tile, in which band, at which
  coordinate" — but it cannot say whether a map drawn in world coordinates then
  lands where the caller's transform puts it, and that is exactly what this step
  changed. Three examples now draw through a real window, including **one bake
  replayed under two transforms in a single frame**: split-screen in miniature,
  and the property that makes it affordable. That test would have failed against
  the old code for the right reason.

### 4b. The harness drives two players

Before anything two-player is written, since nothing after this is verifiable
otherwise — the lesson of step 0, and of the `@player` collision in 2b that only
a driven example caught.

`ScriptedInput` answers `down?(id, device:)` and ignores the device; `Script`
holds one timeline. Both become per device:

```ruby
idle 20
on controls::KEYBOARD        { hold controls::KEY_RIGHT, 60 }
on controls.gamepad(0)       { hold controls::PAD_DPAD_LEFT, 60 }
```

Keep the bare (device-less) form meaning "the keyboard", so every existing
script still runs unchanged.

Also worth adding while here: the report should say **how many distinct
translates each clip contained**, since "two clips, two different cameras" is the
assertion this whole step exists to make and it is currently two separate lines
to read.

**Landed.** `rake` green (318 C checks, 761 headless, 333 Core), RuboCop clean
across 217 files, all four scripts driving identically to 4a.

Tracks are **independent and absolute** — every device's timeline starts at
tick 0 — which was the design decision worth making deliberately. The
alternative, a shared cursor that `on` blocks advance, reads shorter but makes
"do these two players act at the same time or in turn?" a question you answer by
tracking state across blocks. Repeating a leading `idle` is the price of reading
one player's whole timeline top to bottom.

Verified directly rather than by inference, since nothing two-player exists yet
to drive:

```
tick | kbd RIGHT | pad DPAD_LEFT | pad LEFT_X | kbd sees PAD_LEFT
   2 |      true |          true |        0.0 | false
   5 |     false |         false |       0.75 | false
```

Both tracks act at ticks 2–4 *concurrently*, the stick tilts later on its own
track, the keyboard device sees none of the pad's buttons, and everything rests
past the end of a track.

`ScriptedGamepad` now plays the track for the slot it seats itself in, so
`tools/drive/15_tiled_world_pad.rb` names its device like any other. The report
prints clips with what moved inside each:

```
clips pushed
  240 × [0, 0, 640, 480] — 221 distinct translate(s) inside
```

**One thing measured that changes how 4e is verified.** A run came in at 239
tilemap draws where every other run gives 240 — not the RNG (example 15 is
seeded) but the fixed-timestep loop: a slow frame runs several catch-up ticks, so
the budget can be spent and `close` called before that frame draws. Three
subsequent runs gave 240. So draw counts wobble by one for timing reasons as well
as by tens for RNG reasons, and 4e's "the counts drop" has to be read as an order
of magnitude rather than an exact figure. Recorded in the harness's own header.

### 4c. A second player, and how one joins

Two halves: seats, and how a device comes to occupy one. The second half was
missing from the sketch, and the default it left in place was wrong.

#### The join policy

**Seating on connect is wrong.** It is what `Players#claim_gamepad` does today —
`Game#gamepad_connected` fills the first empty seat immediately — and it fails
all three of the questions worth asking:

| | Connect-to-join does | Should do |
|---|---|---|
| Solo player on the keyboard plugs in a pad | **nothing**: no seat is free, so the pad is silently dropped | player one starts using the pad |
| A spare pad wakes up mid-game | splits the screen, unprompted | nothing until someone uses it |
| Cutscene, menu, mid-round | no way to refuse | joining can be closed |

A connect is a statement about *hardware*. Seating a player creates a camera, a
viewport and a screen split, and that should follow a statement of *intent*.
Every engine that ships couch co-op does it this way; Unity's
`PlayerInputManager` is the clearest (see [`02-prior-art.md`](02-prior-art.md)).

So `Players` grows two knobs:

```ruby
players.on_unassigned_input = :join   # :join | :takeover | :ignore
players.accepting_joins = false       # temporary, for a cutscene or a menu
```

- **`:join`** — a press on an unassigned device seats the next free player.
  Couch co-op. The default when a game asks for more than one seat.
- **`:takeover`** — a press on an unassigned device becomes the *primary*
  player's device. Single-player, where switching from keyboard to pad is not a
  second player arriving. The default when there is one seat.
- **`:ignore`** — the game assigns devices itself.

And the decisions behind them, recorded because each has a plausible opposite:

- **The trigger is a `ui_confirm` press, never an axis.** One action rather than
  "any input", because joining creates a player and splits the screen, and a
  stick resting slightly off-centre must never do that. `ui_confirm` is in the
  universal set, so every map already has it, and a game that wants "press
  Start" rebinds it like anything else. Edge, not held.
- **Seats are pre-created and the count is the cap.** `players: 4` means four
  seats, of which the unfilled ones are inactive and draw no viewport. One
  concept doing the work of both "how many players" and "the maximum", rather
  than a separate `max_players` that could disagree with the list.
- **The keyboard is scanned only under `:takeover`.** It is always "connected",
  so under `:join` an idle keyboard would sit there waiting to seat somebody the
  moment they pressed Return — which is right for some games and a surprise in
  most. A game that wants a keyboard player says so explicitly.
- **Connect and disconnect are still tracked**, just not acted on: `Players`
  needs to know which slots exist in order to scan them. So
  `Game#gamepad_connected` records the slot rather than seating it, and
  `claim_gamepad` becomes internal to the join path.
- **Under `:takeover`, losing the device falls back to the keyboard.** Today
  `release_gamepad` empties the seat, which for a solo player means the game
  stops responding to anything. Under `:join` an empty seat is correct — the
  player left. Under `:takeover` there is no second player to be, so the primary
  goes back to the keyboard.

#### Where the scan lives

`Players#poll(backend)` already runs once per tick with the backend in hand, so
the scan goes there: for each connected-but-unseated device, is `ui_confirm`
newly down. That needs an `InputMap` to read ids from — the one a joining player
would get — so `Players` takes a template map, which `Game` already has.

**No change to the input backend contract.** The scan needs `down?(id, device:)`,
which it has, and the list of live slots, which arrives through the hot-plug
hooks the engine is already given. That was worth checking: the alternative —
asking the backend to enumerate devices — would have widened a contract that two
implementations have to keep in step.

Cost is a handful of button lookups per unassigned device per tick, and zero
when every seat is full.

#### Seats and the example

- `Game.new(..., players: 2)` builds them: player 0 on the keyboard as now,
  players 1+ as **empty seats** (`device: nil`), and picks `:join` as the
  default policy because more than one seat was asked for.
- `examples/15_tiled_world` gains a second walker: its own node, its own
  `CameraFollow` with that player's camera, and `input_owner` set to them.
  It only exists once its player is active, so a one-controller session is a
  single full-screen view and a game.

**Verify:** drive it with a keyboard track and a pad track. The report should
show one clip while the second seat is empty, then **two** clips with the
layout's two rects once the pad presses confirm — each with its own camera
track, which is what 4b's per-clip translate count was added to show. World
traversal happens twice per frame while `update` still runs once, which
`world_view_spec.rb` already asserts in the small.

Worth scripting all three policies as spec examples rather than only the happy
path: a pad that connects and stays silent seats nobody, a press while
`accepting_joins` is false seats nobody, and a press under `:takeover` moves the
primary player rather than seating a second.

**Landed.** `rake` green (318 C checks, 774 headless, 333 Core), RuboCop clean
across 218 files. **Split-screen works**, and the report says so in one place:

```
clips pushed
  21 × [0, 0, 640, 480]    — 11 distinct translate(s) inside
  219 × [0, 0, 640, 240]   — 161 distinct translate(s) inside
  219 × [0, 240, 640, 240] — 41 distinct translate(s) inside
```

Twenty-one full-screen frames while the second seat was empty, then two
half-height viewports each carrying its own camera track. The tile map is drawn
459 times — 21 + 219 × 2 — which is exactly once per viewport per frame, and the
number 4a existed to make true. Driven solo, the same example is byte-identical
to its one-seat run: one clip, one camera, the same 240 tilemap draws.

Everything the plan called for landed as planned. Three things it did not
anticipate:

- **A scripted backend fakes what a device *says*, not that it exists.** Joining
  needs the engine to know a controller is there, and that knowledge arrives
  through SDL's hot-plug hooks — which no scripted run fires. So a scripted pad
  was pressing buttons into a slot nothing was watching, and nobody ever joined.
  The harness now announces its script's gamepad slots once, as SDL would a
  frame in. Worth knowing generally: standing in for the input *backend* is not
  the same as standing in for the input *hardware*, and `--gamepad` mode exists
  because some things need the latter.
- **`Players#actions_for` had a local named `seat`**, which the new `#seat`
  method shadowed. Harmless — the local wins — but renamed to `owner`, because a
  reader should not have to work that out.
- **`Player#input_map` earned its keep.** It was added in 2a as a convenience
  reader and nothing called it; the join scan reads `ui_confirm` through the map
  of whoever *would* receive the device, which is what makes "press to join"
  follow a rebound `ui_confirm` for free — and it meant `Players` needed no
  template map passed in.

Documented in `docs/api/input.md` ("Players, seats and joining") and
`docs/api/game.md`.

### 4d. Z bands become a stated convention

Today `DebugOverlay` picks `1_000_000` by hand and every other z is a
hand-chosen render layer (`sprite.rb:12` is explicit that it is not `abs_z`).
Cross-viewport interleaving in the sort is harmless — disjoint pixels, each
command carrying its own clip — but band order *within* one viewport is not.

A small `RGame::Engine::Z` with named bases (world, HUD, overlay, debug),
`DebugOverlay` using it instead of its literal, and a paragraph in
`docs/api/drawing.md`. Deliberately constants rather than machinery: nothing can
enforce this, so the value is in it being written down in one place.

**Landed.** `rake` green (318 C checks, 781 headless, 333 Core), RuboCop clean
across 220 files, both examples driving unchanged.

`RGame::Engine::Z` with `WORLD`/`HUD`/`OVERLAY`/`DEBUG` at 0 / 100_000 /
200_000 / 1_000_000. `DebugOverlay::Z` is now `Z::DEBUG` rather than a literal,
and the examples name bands instead of guessing: the asteroids score is
`Z::HUD`, its title and results text `Z::OVERLAY`.

Three things worth recording:

- **The inventory turned up a real wart.** `Renderer::SHAPE_Z` is **50** and
  `TEXT_Z` is **10**, so a shape drawn with no `z:` sits *above* text drawn with
  no `z:` — meaning a HUD built out of defaults ends up under world shapes. That
  is pre-existing and not worth changing (the defaults are documented and games
  rely on a debug box landing on top), but it is exactly the confusion the bands
  exist to end, so it is called out in `Z`'s own comment and in
  `docs/api/drawing.md`.
- **`TileWorld::OVERLAY_Z` became `CANOPY_Z`.** With `Z::OVERLAY` now naming the
  global screen band, having "overlay" also mean "the tiles above the actors" in
  the same layer was a collision worth spending a rename on — and `CANOPY_Z` is
  the better name anyway, since the docs already describe that band as canopies
  and roofs.
- **The one check that would be most valuable cannot be written.** Asserting
  that the renderer's own defaults fall inside the world band is a genuine
  cross-layer invariant — if someone bumped `SHAPE_Z` to 200_000 the bands would
  silently break — but `Z` is Engine and `Renderer::SHAPE_Z` is Core, so
  `spec/` may not name one and `spec_core/` may not name the other. The layering
  rule forbids the check rather than the check being forgotten. Stated in the
  docs with the actual headroom instead: four orders of magnitude between the
  largest default and `Z::HUD`.

`spec/rgame/engine/z_spec.rb` asserts what *can* be asserted — the bands are
ordered, they are far enough apart to be useful rather than merely ordered, and
the two engine-side users (`DebugOverlay`, the tile map's bands) sit where the
vocabulary says.

### 4e. Culling

`view.visible?` exists and has no callers. `Sprite` and `AnimatedSprite` are
where it pays: with two views the world is walked twice, and an actor off the
top of the screen is drawn twice for nothing.

**Last, and separable, because it is the one change here that can produce a
visual regression** — a sprite culled a frame too eagerly pops. Rotation and
scale both grow a sprite's footprint beyond `node.width`/`height`, so the test
is generous by a margin rather than exact.

**Verify:** the drive report's draw counts drop while the scene transitions and
camera tracks stay identical. That is a real before/after number, which is why
this step is worth doing here rather than "some time later".

**Landed.** `rake` green (318 C checks, 791 headless, 333 Core), RuboCop clean
across 222 files.

**Sprite draws in the two-player run: 3651 → 2503, a 31% cut**, with the tile
map counts, the scene transitions and all three clip rects and their camera
tracks byte-identical. That is the number this step existed to produce, and it
is only that large because the world is walked twice: each player's walker
spends much of the run outside the *other* player's half of the screen.

`RGame::Engine::Culling` is mixed into `Sprite` and `AnimatedSprite` — the two
components that know both where they put a footprint and how big it is. Two
rules keep it conservative, because culling one frame early is a sprite popping
in at the screen edge, which is worse than the draw it saved:

- **No size means no culling.** `examples/14_asteroids` never sets
  `node.width`/`height` on its entities, so they read as 0×0 and would otherwise
  be culled instantly. That example is unchanged by this step, which is the
  right outcome — it is screen-space and screen-wrapped.
- **A rotated node is measured generously**, by a margin of `width + height`.
  That is always at least the diagonal and costs no square root on a path that
  runs once per drawable per viewport.

Two things worth recording:

- **`abs_x`/`abs_y`/`abs_z`/`abs_angle` were nil until the first phase ran**, and
  culling reads `abs_angle`, so a component drawn in a unit spec crashed on
  `nil.zero?`. They are now seeded to 0 at construction — the same answer
  `resolve_origin` gives an unparented node, so nothing changes for a driven
  tree while a whole class of `NoMethodError` disappears. Two examples asserted
  the nil and were rewritten to state the new contract. This had already bitten
  three times during step 3 and 4 in specs where the fix was "drive from the
  root"; here the spec was legitimately a unit spec and the sharp edge was the
  code's.
- **The allocation guard cannot measure the drawing branch.** `FakeRenderer`
  records every call it receives, so it allocates by design and swamps what is
  being measured. The example measures a node that *is* culled, where nothing
  but the test itself runs — which is the branch that matters when culling pays
  anyway. Noted at the example, since the obvious reading of a failure there
  would be "culling allocates".

### What N draws per tick makes newly illegal

The audit from [`03-design.md`](03-design.md) §8, due here because this is the
step where it stops being hypothetical:

- **A side effect in `draw` now happens twice.** Grep the engine layer and the
  examples for assignment inside a draw path.
- **An allocation in `draw` costs twice.** `DebugOverlay`'s Δ/f is the
  instrument, and the drive harness can report it.
- **A cache keyed on "last frame" rather than on the view thrashes.**
  `CachedLabel` is safe (it caches on the *value*). `TileMapRenderer`'s baked
  recording is safe once 4a lands, because it is baked in world space and so is
  view-independent — which is worth stating, since it is the one cache in the
  engine that a per-view key would have ruined.

## Step 5 — Collapsing the split, and freezing the world

Re-planned after step 4. The sketch bundled two features as one; they are
orthogonal and want separate commits.

### What is already there, and what is not

- **`solo!` is built and specced.** `Viewports#solo!(camera)` / `#split!`,
  deferred to the next tick, one full-screen view while solo, player cameras
  untouched. Landed in step 3. **Nothing calls it** — no example, no engine
  class, and no camera exists for it to look through.
- **Nothing pauses anything.** There is no flag, no hook, and no way to stop one
  subtree ticking while another keeps going. `grep -rn "paus" lib/` finds four
  comments and no code.

So step 5 is one small new mechanism (pause), the first caller for one that
exists (solo), and an example that puts them together.

They are orthogonal on purpose, and the plan keeps them apart because games mix
them differently: an in-game menu pauses without collapsing, a "both players
converged" merge collapses without pausing, a cutscene does both.

### 5a. `Node2D#paused`

A paused node skips `control` and `update` — for itself and, because a subtree
is only reached through its parent, for everything under it. `draw` still runs.

```ruby
world_view.paused = true    # the world freezes; the overlay above it does not
```

**On `Node2D` rather than on `WorldView`.** "Pause the world" is then
`world_view.paused = true` with no new concept, and the same flag pauses *any*
subtree — which step 6 needs for a different reason: a player whose menu is open
should stop driving their walker, and pausing that one node is the whole fix.
It is also the classic scene-graph feature (Godot's `process_mode`), so it is
not a shape anyone has to learn.

Decisions worth recording:

- **`draw` is not skipped.** Pausing is about time, not visibility — a frozen
  world is exactly what a cutscene overlay covers.
- **There is no `abs_paused`.** Unlike `input_owner`, pausing needs no
  inherited resolution: a paused node never descends, so its subtree is skipped
  by construction. One boolean test at the top of two methods, and nothing on
  the draw path.
- **`resolve_origin` still runs at draw**, so a paused node under a moving
  ancestor is still drawn in the right place. That falls out of `draw` already
  resolving, and is worth checking rather than assuming.
- **The animation clock stops with it.** `TileWorld#update` is what accumulates
  `elapsed`, so a paused world's water freezes — which is exactly what
  CLAUDE.md's "stop calling `update` and the water freezes" describes, arriving
  for free.

**Verify:** a spec that a paused subtree stops updating, keeps drawing, and
resumes; and that an unpaused sibling keeps ticking. Plus the allocation guard,
since this is two branches on the hot path.

### 5b. The first cinematic camera

`solo!` requires a camera ([`03-design.md`](03-design.md) §11.7) and no game has
ever built one, so this is where the shape of "a camera nobody owns" gets
settled.

It is an ordinary `Camera`. The only real question is bounds: `TileWorld#bound`
clamps it to the map like a player's, which is right for a cutscene inside the
world; leaving it unbounded lets it frame something past the map edge. The
example should say which it picked and why.

Pointing it is the same machinery as everything else — `center_on` from the
scene, or a `CameraFollow` on a cutscene actor.

### 5c. The example

`examples/15_tiled_world` gains a cutscene, because it is the only example with
a world, a camera and two players.

- An action opens it. Both players are frozen, the split collapses to one view
  through a camera centred between them, and a full-screen panel draws at
  `Z::OVERLAY`. The same action closes it.
- **`players.accepting_joins = false` while it runs** — the first real use of
  4c's flag, and exactly the case it was added for.
- Freezing is `world_view.paused = true`; the overlay is outside the world view,
  so it keeps ticking and can animate.

> **The examples are short of keys.** `Util::Controls` names `RETURN`, `ESCAPE`,
> `SPACE`, `F1`, `F2` and the four arrows, and `ui_confirm` and `ui_cancel`
> already spoken for. Adding one is a `#define`, a `_Static_assert` against the
> SDL scancode, and a constant — the shape `KEY_F2` took before step 1. Decide
> the binding when writing the example rather than now.

**Verify:** drive it. The report should show the clip list going two → one → two
as the cutscene opens and closes, and **the world viewport's distinct translate
count stopping while it is open** — a frozen world produces no new camera
positions, which 4b's per-clip translate count makes readable without any new
instrumentation.

**Landed.** `rake` green (318 C checks, 806 headless, 333 Core), RuboCop clean
across 225 files. Driving the cutscene script:

```
draw calls
      62  nine_slice         first(:panel, 90, 180, 460, 120)
clips pushed
  83 × [0, 0, 640, 480] — 12 distinct translate(s) inside
  157 × [0, 0, 640, 240] — 101 distinct translate(s) inside
  157 × [0, 240, 640, 240] — 46 distinct translate(s) inside
```

Two half-height viewports while the players walk, one screen-wide viewport for
the 62 frames the cutscene is open, and the full-screen line carrying **twelve**
distinct camera positions — eleven from before the second player joined, and
exactly one for the whole cutscene, because the world is frozen. That is the
freeze visible in data rather than by eye.

`nine_slice` also appears for the first time in any example, which closes the
coverage hole [`README.md`](README.md) §1 records: nothing had exercised
`renderer.nine_slice` or `Core::UiAtlas` end to end since the old UI package was
deleted.

Landed as planned: `Node2D#paused` (skips `control` and `update`, still draws,
no `abs_paused` needed), a cinematic camera bounded by the map, and a `Cutscene`
node outside the `WorldView` that collapses the split, freezes the world and
closes joining together.

### The input vocabulary, expanded first

Step 5 needed a key `Util::Controls` did not have, and the whole set was thin —
nine keys and fifteen pad buttons. It now names **81 keys and 21 pad buttons**,
generated from SDL's own headers rather than typed:

- Letters, digits, punctuation, the function row, the navigation cluster,
  arrows and modifiers — what a Western keyboard can be relied on to have.
- Deliberately absent: the numpad (most laptops have none), the GUI key
  (Windows on a PC, Command on a Mac), the print-screen cluster, and anything
  layout-dependent.
- Every pad button SDL knows, including the six only some hardware has
  (`MISC1`, the four paddles, `TOUCHPAD`), which read as never pressed on a pad
  without them.

**All 102 are verified in both directions and neither guard was written for the
occasion.** `app.c` and `gamepad.c` carry a `_Static_assert` per id against the
SDL constant, so a wrong number fails the C build; `spec/rgame/util/controls_spec.rb`
parses the header and compares every Ruby constant to it. Writing them by hand
would have been 306 chances to typo; generating all three from one table and
letting the existing guards check the result was the only sane way to do it.

### An axis could not carry a d-pad, and that had been hiding

**`InputMap`'s `axis:` took exactly one `[negative, positive]` pair.** The
default `move_x` spent it on the arrow keys, so **a controller could not drive
movement at all** — the d-pad had nowhere to bind. `buttons:` has always taken a
list; an axis needed the same and did not have it.

`axis:` now accepts a list of pairs, largest deflection wins, and the defaults
bind arrows, WASD and the d-pad together. A device with only one of them reads
0.0 for the rest, so the extra pairs cost nothing.

**This means earlier evidence in this roadmap was thinner than it read.**
`tools/drive/15_tiled_world_2p.rb` holds `PAD_DPAD_LEFT` and `PAD_DPAD_DOWN`,
and those holds were **inert** — player two moved only during the script's
`tilt AXIS_LEFT_X` segment. The split itself was never in doubt (two clips, two
rects, two independent camera tracks, and the 41 distinct translates reported in
4c were real analog movement), but the d-pad half of that script was proving
nothing. With the fix the same script reports **161** distinct translates for
player two rather than 41. Found only because the cutscene script leant on the
d-pad and the report said "1 distinct translate(s) inside".

---

## Step 6 — A player's own screen, and the first menu

Where split-screen meets the UI half of this folder. The acceptance scenario for
the whole rework: **one player browsing an inventory while the other walks.**

### What is already there

More than the sketch assumed. `media/ui/ui_atlas.json` exists and describes
exactly the pieces a keyboard-navigated menu needs:

```
panel  button_idle  button_focus  button_pressed  button_disabled
```

`button_focus` is in there because this engine was always going to navigate by
focus rather than hover. And the whole path to draw it is built and unexercised:
`assets.ui_atlas(path)` → `renderer.register_ui_atlas(atlas)` →
`renderer.nine_slice(id, x, y, w, h, z:, tint:)`. Closing that coverage gap is
[`README.md`](README.md) §1's stated reason to build a small real menu.

What does not exist: any node that draws into one player's region, and any
notion of focus.

### 6a. `Viewports#screen_for(player)`

A reused `View` carrying that player's rect with **no camera** — the
screen-space counterpart of the world view they already get, and symmetric with
`#screen` (the whole window). Reused, not built per frame, like every other View.

**Landed.** `rake` green (318 C checks, 819 headless, 333 Core), RuboCop clean
across 225 files. `Viewports#screen_for(player)` returns the same rectangle that
player's world view is drawn into, from a second pool of Views, so a HUD laid out
at (10, 10) lands ten pixels inside the region the world beneath it occupies.

One decision the sketch did not cover: **what it returns when a player has
nowhere to draw.** Two cases, one answer — `nil`. An empty seat has no viewport.
And while the split is **collapsed**, nobody owns a half of the screen: a
cutscene is everybody looking at one thing, so per-player UI has no place to be,
and a game that wants something on screen through it draws in the global overlay
band. Returning nil rather than a zero-sized rectangle is deliberate: one check
at the one caller that needs it beats every caller relying on an empty clip
happening to draw nothing.

### 6b. `PlayerLayer`

A node whose subtree is that player's own screen: drawn **once**, clipped to
their rect, translated to its corner, with `screen_for(player)` as its view.

```ruby
overlay = root.add_node(PlayerLayer.new(player: players[1]))
overlay.add_node(inventory)
```

- **Coordinates are view-local.** A HUD element at (10, 10) is ten pixels from
  *its own* viewport's corner, not the window's — which is what lets one HUD
  class serve either player unchanged.
- **It sets `input_owner`**, so its whole subtree reads that player. Combined
  with 6c below, that is what makes focus per player with no focus-specific
  machinery at all.
- **An inactive player's layer draws nothing**, so an empty seat costs nothing
  and needs no guard at the call site.
- It closes the gap named in `Z`'s comment: `Z::HUD` currently names a z band
  whose structural counterpart has not been built. This is that counterpart.

**Landed.** `rake` green (318 C checks, 832 headless, 333 Core), RuboCop clean
across 227 files, examples unchanged.

`PlayerLayer#draw` clips to `screen_for(player)`, translates by its offset, and
hands its subtree that region. `player` is not stored: it *is* `input_owner`,
because two fields would be two things to keep in step.

**The coordinate question the sketch glossed over.** "Coordinates are view-local"
and "a `View` carries `x`/`y`" are in tension: a child that lays out with
`view.x + 10` inside a translated region is offset twice. Both conventions
were arguable, and the transform decided it — children already position
themselves through `abs_x`/`abs_y` relative to their parent, so translating the
layer is what makes the node transform mean anything. Laying out against
absolute screen coordinates instead would have made a node's own position
useless inside a HUD.

So the rule is: **lay out against the view's size, not its position.**
`view.width - margin` for the far edge; `view.x`/`view.y` are where the region
sits on the window and belong to the clip. `DebugOverlay` was written with
`view.x + view.width - PAD` back when the only view was the whole window, where
`x` is zero — harmless then, the wrong idiom to copy now, and changed to
`view.width - PAD`, which is also what makes it correct if it is ever put inside
a region.

### 6c. Focus, and a menu that is not a widget library

[`README.md`](README.md) §1: *"Focus. With no pointer there is no hover, so
something owns which control is focused and how up/down/left/right move it. That
is the whole design; everything else follows."*

A `Menu` node holding item children: it owns the focused index, moves it on
`ui_up`/`ui_down`, and activates on `ui_confirm`. An item draws
`button_focus` or `button_idle` behind its label.

**Focus is per player for free.** A `Menu` inside a `PlayerLayer` inherits that
player as its `input_owner`, so the `actions` its `on_control` receives are
already that player's — two menus open at once are independent without either
knowing the other exists. That is [`03-design.md`](03-design.md) §11.4 falling
out of the ownership work done in 2b rather than needing anything new, and it is
worth checking early that it really does.

**Deliberately not a widget library.** `Menu` plus an item, vertical, absolute
positions. README §1 leaves layout open and says outright that a small real menu
beats a widget library nobody uses; the deleted package is not a reference and
its API should not be preserved.

**Landed.** `rake` green (318 C checks, 859 headless, 333 Core), RuboCop clean
across 231 files, examples unchanged.

`RGame::Engine::UI::Menu` and `UI::MenuItem`, in a `UI` namespace because that is
where a toolkit would go. A menu owns the focused index, moves it on
`ui_up`/`ui_down` with wrapping, and activates on `ui_confirm`; an item draws one
of four atlas elements from its state and emits `on_activated`.

**The claim held: focus is per player for free.** A menu inside a `PlayerLayer`
inherits that player as its `input_owner`, so the `actions` its `on_control`
receives are already theirs. Two menus, two players, one traversal, and neither
menu contains the word "player" — `menu_spec.rb` drives exactly that and only
the pad player's menu moves. That is 2b's ownership routing paying for itself a
step later, and it is the reason this step is small.

Three things beyond the sketch, each because the shipped art asked for it:

- **Disabled items.** The atlas ships `button_disabled`, so items have an
  `enabled` flag: focus skips them, `activate` refuses them, and a menu whose
  first item is disabled opens with focus on the second. Skipping during
  navigation is the classic thing that is annoying to retrofit.
- **A pressed state**, from `button_pressed` — the focused item shows it while
  `ui_confirm` is held. There is no hover to show, because there is no pointer;
  this is what a control has instead.
- **The style is replaceable.** Hard-coding `:button_idle` would have obliged
  every game to name its atlas the way the shipped one does. `MenuItem::STYLE`
  is a hash a menu can be built with.

**One spec bug worth recording, caught by strict `Actions`.** The first version
of the menu spec's helper declared only the actions it was pressing, and
`Actions` raised for `:ui_up` the moment the menu read it. The second version
declared all three but built a fresh snapshot per call, so `prev_held` was always
empty and *every* frame read as a press — which the "fires once for a press that
is held" example caught. The helper now shifts two hashes behind one reused
`Actions`, which is what `ActionMapper` does, and is the only way `pressed?`
means anything. Both mistakes are ones a game would make.

### 6d. The example

`examples/15_tiled_world` gains a per-player inventory:

- An action opens that player's menu inside their `PlayerLayer`.
- **Their walker is paused while it is open** — 5a's flag, applied to one node,
  which is why pause is per-node rather than a property of the world view. The
  other player keeps walking, and the world keeps ticking for both.
- Closing it unpauses.

**Verify:** drive it with a keyboard track and a pad track, opening one player's
menu mid-run. The report should show both viewports still drawing the world,
`nine_slice` calls appearing for the first time in any example, and — the point
of the whole exercise — **one player's camera track continuing to grow while the
other's stops**.

**Landed.** `rake` green (318 C checks, 859 headless, 333 Core), RuboCop clean
across 233 files. **The acceptance scenario for the whole rework runs**: one
player browsing a menu while the other walks.

```
clips pushed
  438 × [0, 0, 640, 240]   — 212 distinct translate(s) inside
  438 × [0, 240, 640, 240] — 42 distinct translate(s) inside
```

Player one walks throughout and their camera tracks 212 positions; player two
walks for forty ticks, opens their inventory, and stops at 42 — while both
viewports keep drawing the world, and the world keeps running for both.

**Proved by experiment rather than by reading the number.** Commenting out the
one line that pauses the walker gives **84** instead of 42: player two walks
forty ticks before opening the menu and would walk another forty during it, and
the pause is exactly what stops the second forty. Player one's 212 is identical
either way, so the pause is scoped to one node and does not touch the shared
simulation. That is what 5a's flag being a property of a *node* rather than of
the world buys, and this is the case that justifies it.

`Inventory` mentions no viewport, no camera and no player. It sits inside a
`PlayerLayer` and inherits all three: it draws in that player's half, lays out
from that half's corner, and reads that player's controller. That was the design
claim from the very first plan document and it is now a file you can read.

Two notes:

- **A closed menu is paused *and* not drawn.** Pausing alone stops it ticking
  and leaves it on screen, so `Inventory` overrides `draw_children` too. Worth
  saying because "paused" reading as "invisible" is the obvious wrong guess, and
  the split is deliberate: a frozen world under a cutscene has to stay visible.
- **A player's rectangle is now clipped twice a frame** — once by the WorldView
  for their camera, once by their PlayerLayer for their screen. The report
  aggregates by rectangle, so the counts double and the distinct translates
  inside a rect are both passes' offsets together. Noted in the harness header,
  since the first reading of `438 × ...` against a 240-tick run is confusion.

### What this leaves for later

A real UI package is still not built, and this step should not pretend
otherwise. What it delivers is the seam a package would be built on — a region
per player, focus, and activation — plus one worked menu proving the atlas path.
Layout, nesting, scrolling lists and text input are all untouched, and
[`README.md`](README.md) §1 remains the brief for them.

## When it lands

Per CLAUDE.md: fold what is still true into `docs/api/` — `input.md` (the binding
table moves a layer up), `scene_graph.md` (the camera section, `draw(renderer,
view)`, the bands), `drawing.md` (the split-screen shape, now with a caller),
`systems.md` (`Players` and `Viewports` as root-scoped systems) — and **delete
this folder**. A plan that outlives its refactor is a stale description of code
that no longer exists.
