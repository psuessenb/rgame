# 04 — Roadmap

The implementation plan for the design in [`03-design.md`](03-design.md),
following the order sketched in its §10 and breaking each step into landable
commits.

**Detailed for steps 0–3. Steps 4–6 stay deliberately rough**, and get
re-planned once the layer beneath them exists. That is how the two previous
plans in this project worked, and it was right both times — the Gosu
replacement's phase 3 was rewritten from eight bullets into nine landable steps
only after phase 2 made the GL situation measurable rather than imagined. The
same is true here: step 3 introduces `draw(renderer, view)` and step 4 is the
first code that ever calls `renderer.clipped` from above. What either of those
turns up will change steps 5 and 6, so writing them out now would be writing
fiction.

Each step ends green: `rake` (C tests, both Ruby suites), RuboCop on the touched
files, and both examples still running — **driven, not booted** (step 0).

---

## Dependency shape

```
0 harness ─→ 1 input ─→ 2a Player+camera ─→ 2b ownership ─→ 3 View/Layout ─→ 4 two views ─→ 5 solo ─→ 6 per-player UI
                 │                                              │
                 └── independently useful ──────────────────────┘
```

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

**Verify:** the whole existing suite is the test — 587 examples that all assume
a broadcast `Actions` must stay green, because an unowned node still gets one.
Add examples for a node with an explicit owner and for inheritance through a
subtree.

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

---

## Step 4 — Two views *(rough)*

The first code in the project's history to call `renderer.clipped` from above.
Expect this step to find things; the plumbing is proven in C
(`test/test_canvas.c:414`) and completely unexercised from Ruby.

Sketch:

- `Layout.split` for two, a second `Player`, `Viewports` reporting two views.
- **Z bands become a documented convention** — world content, per-player screen
  space, global screen space, each reserving a range. Today `DebugOverlay` picks
  `1_000_000` by hand and `Sprite`'s `z:` is a hand-chosen render layer
  explicitly independent of `abs_z` (`sprite.rb:12`). Cross-viewport interleaving
  in the sort is harmless — disjoint pixels, each command carrying its own clip —
  but band order *within* one viewport is not.
- Culling through `view.visible?`, which now earns its keep.
- Drive example 15 with two players, one on the keyboard and one on a virtual
  pad, and assert on the harness's clip/translate report: two clips, two
  *different* translates, one world traversal per clip.

Also due here: the "what N draws makes newly illegal" audit
([`03-design.md`](03-design.md) §8) — a side effect in `draw` now runs twice, an
allocation costs twice, and a cache keyed on "last frame" rather than on the view
thrashes. `DebugOverlay`'s Δ/f meter is the instrument.

## Step 5 — `solo!` and the overlay band *(rough)*

The collapsed view needs a camera from the game — `solo!(camera)`, required, not
defaulted ([`03-design.md`](03-design.md) §11.7) — so this step builds the first
cinematic camera as well as the mode switch. Also the per-band `paused?` flag,
which is what freezes the world under a cutscene while the overlay keeps
animating.

Open question 3 (does the world band ever get per-view `control`/`update`) is
scheduled to be answered here, when the case is concrete.

## Step 6 — The per-player `ui` band *(rough)*

Where this meets the UI toolkit half of this folder. The per-player menu is the
first real customer for both, and per [`03-design.md`](03-design.md) §11.4 focus
is per player, owned by that player's `ui` band. One player browsing an inventory
while the other walks is the acceptance scenario for the whole rework.

It is also what finally exercises `renderer.nine_slice` and `Core::UiAtlas` end
to end — see [`README.md`](README.md) §1.

---

## When it lands

Per CLAUDE.md: fold what is still true into `docs/api/` — `input.md` (the binding
table moves a layer up), `scene_graph.md` (the camera section, `draw(renderer,
view)`, the bands), `drawing.md` (the split-screen shape, now with a caller),
`systems.md` (`Players` and `Viewports` as root-scoped systems) — and **delete
this folder**. A plan that outlives its refactor is a stale description of code
that no longer exists.
