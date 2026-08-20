# Camera and input overhaul — proposed design

The proposal for [`camera-and-input-requirement.md`](camera-and-input-requirement.md).
Inventory of what exists is in [`01-current-state.md`](01-current-state.md); the
survey behind the choices is in [`02-prior-art.md`](02-prior-art.md).

**Status: design decided, not yet implemented.** Every section that had a real
alternative says what it was and why it lost. §11 records the decisions taken so
far. One question remains open there and is marked as such: whether the world
band ever gets per-view `control`/`update` (3), deferred until the case arrives.

---

## 0. The one idea

> **The camera and the input bindings belong to the *player*, not to the scene.
> The world is updated once and drawn once per player.**

Everything else follows mechanically. The reason the current design cannot be
extended in place is not that a camera is "a component" — it is that the camera
is applied *from inside the world subtree* (`CameraView#draw_children`), which
forces the world to know how many times it is being drawn. Move the camera onto
the viewer and that goes away.

This is what all four engines surveyed do, and the one that does it least
cleanly (Godot) is the one whose users end up duplicating action names per
player — the thing the requirement explicitly rules out.

## 1. The tick, restated

The invariant the requirement asks for, spelled out:

| Phase | Runs | Over |
|---|---|---|
| `control` | **once** per tick | the whole stage, routed per player |
| `update` | **once** per tick | the whole stage |
| `draw` | **once per active view** for world content, once for everything else | see §2 |

Only `draw` multiplies. `control` and `update` stay single-pass — an NPC moves
the same whether one player or four are watching. This is the requirement's
"each node needs to update once" and it is non-negotiable; it is also what makes
the whole thing cheap, since simulation cost is independent of player count.

## 2. The stage: three draw bands

A game's tree gains a defined top-level shape. Three bands, because there are
exactly three ways a thing can relate to a viewport:

```
Stage (root)
├── world          world space, shared      → drawn ONCE PER VIEW, under that view's camera
├── Player 0 ──────┬ camera, bindings, device
│                  └ ui: Node2D             → drawn ONCE, screen space, clipped to player 0's rect
├── Player 1 ──────┬ camera, bindings, device
│                  └ ui: Node2D             → drawn ONCE, screen space, clipped to player 1's rect
└── overlay        screen space, global     → drawn ONCE, full screen (cutscene, game over, debug)
```

- **`world`** is where the shared simulation lives. It contains no camera and no
  reference to any player. This is what makes it drawable N times.
- **A player's `ui`** is their HUD, and their inventory menu when they open one.
  It is a normal `Node2D` subtree: it updates once (it is per-player, so once is
  right) and draws once, inside its own player's rect, in screen space.
- **`overlay`** is the band that "pulls both players into a single screen-wide
  scene". A cutscene or a game-over screen is a scene pushed here.

Each band can host a `SceneStack` unchanged — it is already a `Component`, so
`world.add_component(SceneStack.new)` and `overlay.add_component(SceneStack.new)`
work today with no modification. **That is the piece that makes "player 1 in
their inventory, player 2 walking" nearly free**: player 1's `ui` gets its own
`SceneStack` and pushes a menu scene onto it; nothing else in the game notices.

### Why not just let games arrange their own tree?

They still can — the bands are node types (§2.1), not a fixed schema, and
`Game` merely assembles a default one. But the default has to exist, because the
requirement's last bullet ("little to no additional setup overhead for one
player") means the single-player path must get all of this without asking. A
single-player game writes `Game.new(world: MyRoot.new)` and gets one player, one
full-screen view, one camera, the default bindings, and an empty `ui` — the
same ceremony as today's `root:`.

### 2.1 The bands are node types, and they use the seam that already exists

`Node2D#draw_children` (`node2d.rb:235`) is already the override point, and it
is already documented as "so a node can wrap the whole subtree's draw in a
transform". Three subclasses:

```ruby
# The world band. The successor to CameraView, and the only new mechanism here.
class WorldView < Node2D
  def draw(renderer)
    views.each do |view|
      renderer.clipped(view.x, view.y, view.width, view.height) do
        renderer.translated(view.x - view.camera.x, view.y - view.camera.y) do
          @children.each { it.draw(renderer, view) }
        end
      end
    end
  end
end
```

Note `view.x - view.camera.x`, not `-view.camera.x`: the clip is in screen space
and the world has to be pushed over to the viewport's origin as well as offset by
the camera. This is exactly the shape `test/test_canvas.c:414` already asserts
(`push_translate(-2000 + 400, 0)`), so the C side is proven and the Ruby side is
a transcription.

`PlayerLayer` and `Overlay` are the degenerate cases: clip and translate to the
rect, no camera.

## 3. Views and layout

A **`View`** is a value: a screen rect plus (for world views) the camera to draw
it through, plus the player it belongs to.

```ruby
view.x, view.y, view.width, view.height   # screen rect
view.camera                                # nil for screen-space bands
view.player                                # the Engine::Player, or nil for the global band
view.visible?(x, y, w, h)                  # culling; see §8
```

**Rects come from a layout, never from the camera.** This is the direct fix for
blocker 3 in the inventory: `Camera#viewport_width` is fixed at construction
today and would be wrong the moment a second player joins. All four surveyed
engines put the rect on the layout/camera-instance side and none of them bakes it
in at construction.

### 3.1 `Layout` is a value; `Viewports` is the system that holds one

The question "should `Layout` be a value or a system component" conflated two
different things, and once they are separated the answer is both:

| | What it is | Where it lives |
|---|---|---|
| **`Layout`** | the rect arithmetic — given a view count and a window size, the rects | a pure value; no anchors, no lifetime, no state |
| **`Viewports`** | which players are active, which mode we are in, the window size | an `Engine::Component` on the root — a root-scoped system |

```ruby
Layout.split(2, 640, 480)   # => two rects; pure, comparable, spec-able alone
node.system(Viewports).solo!(camera)   # camera is required — see §11.7
```

**Why the arithmetic is a value.** It is layer-1 logic by the project's own
definition, so it gets written and specced before anything draws
(CLAUDE.md, "Abstraction & testability strategy"). A spec asserts on rects
directly with no node, no tree and no window.

**Why the holder is a system component.** Three concrete reasons, in order of
weight:

1. **Reachability without threading.** `docs/api/systems.md` is explicit that
   shared resources are components on an anchor node, "not threaded through
   constructors", and that there is deliberately no `GameContext` bag. A cutscene
   scene in the overlay band calling `system(Viewports).solo!` is the
   requirement's "interrupt the split-screen" in one line, with nothing passed
   into it. The value alternative reaches it as `root.context.layout`, which is
   the same mutable state through a worse door.
2. **It can tick.** A component gets `update(dt)`, so an *animated* transition
   between split and solo — a sliding divider, which is what dynamic-split-screen
   demos in other engines do — has a home. A value cannot drive itself.
3. **Scope override for free.** `node.system(klass)` checks scene scope before
   root, so a scene that must be solo (a boss arena) can carry its own without a
   new mechanism.

**And the guard for what that costs.** A system reachable from anywhere is
mutable state anyone can poke, including from `draw` — where it would now fire
once per view. So **mode changes are deferred**: `solo!` records the request and
the stage applies it at a fixed point in the tick, never mid-draw. That is the
shape `Root#go` uses in `examples/14_asteroids/main.rb` and the shape
`sweep_freed` uses, so it is an established pattern here rather than a new rule
to remember.

`Game` owns the window, so `Game` forwards `App#resize(w, h)` into `Viewports`;
the root node has no idea how big the screen is and should not learn.

### The ownership question, answered

[`README.md`](README.md) asked: does a viewport own a camera, or a camera own a
viewport? **Neither.** The player owns the camera; `Viewports` owns the rect; a
`View` is the per-frame pairing of the two. That is Unreal's and Unity's answer,
and it is the one that survives the layout changing under a fixed set of players.

## 4. Camera, rebuilt

`Engine::Camera` loses its viewport size and keeps everything else:

```ruby
Camera.new(world_width:, world_height:)
camera.center_on(x, y)                 # target point
camera.resolve(view_width, view_height) # clamp against world bounds for THIS rect
```

Clamping has to happen against the rect the camera is currently being drawn
into, because a half-width viewport clamps differently from a full-width one.
Making it a call rather than state is what stops the two going out of sync.

**Who drives the camera?** A `CameraFollow` component in the *world*, on the
node being followed, holding a reference to the player's camera object:

```ruby
player_node.add_component(CameraFollow.new(camera: players[0].camera))
```

This is worth stating because it resolves the tension in the user's framing.
"Camera as a component" fails as *ownership* — the camera cannot be owned by a
world node when there are N of them. But it is exactly right as *behaviour*: the
thing that decides where a camera points is a per-node concern and belongs in the
world. Own the camera on the player, drive it from a component.

### The tile map is the awkward case, and it is what forces `draw(renderer, view)`

`TileWorld#draw` (`tile_world.rb:58`) does not draw under `translated` — it hands
the camera offset and viewport size to `renderer.tilemap`, because the C renderer
culls internally. With N views it needs to know *which* view it is in. Options:

| | Cost |
|---|---|
| **A. `draw(renderer, view)`** — recommended | Mechanical churn across every `on_draw`, every component, every example and spec. Explicit, no hidden state, and the `view` is what culling wants anyway. |
| B. Ambient `system(Viewports).current_view` | No signature churn. Introduces mutable "which pass am I in" state, which is exactly the kind of thing a node will cache and get wrong. |
| C. Put the view on the renderer | Would make `Core::Renderer` hold an Engine value and grow the shared renderer contract for an Engine concern. Rejected. |

**A — decided.** The signature change is wide but shallow, it fails loudly and
immediately when a call site is missed, and B's failure mode is a cached view
that is right for player 1 and wrong for player 2 — silent, and only in
two-player mode. Two parameters rather than one `view` carrying the renderer:
`view.renderer` would add an indirection to every draw call site to save a word
in a signature written once per node type.

A second gain that justifies the churn on its own: **a screen-space node can
finally lay itself out against its viewport** (`view.width`), where today it has
to reach `context.width` and get the whole window. That is blocker 7, and it is
unfixable without something like this parameter.

## 5. Input, rebuilt

### 5.1 Collapse the two binding tables into one

Today: game action → `Core::Input` action name → physical id (§3 of the
inventory). The middle table earns nothing, is duplicated per device class inside
`Core`, and is unreachable from a game's config screen because it lives on a
`Core` object.

Proposed: **one table, in the engine layer, per player, mapping straight to
`Util::Controls` ids.**

```ruby
RGame::Engine::InputMap.new(
  move_x:  { axis:   [Controls::KEY_LEFT, Controls::KEY_RIGHT],
             stick:  Controls::AXIS_LEFT_X },
  fire:    { buttons: [Controls::KEY_SPACE, Controls::PAD_A] },
  ui_confirm: { buttons: [Controls::KEY_RETURN, Controls::PAD_A] }
)
```

One entry per action, listing every physical id that triggers it, plus an
optional analog source. Because `Util::Controls` ids are values, the engine layer
may hold this outright and a rebinding screen can build one — which is the whole
point of having moved `Controls` to `Util` in the first place.

**`Core::Input`'s own binding tables then have no caller and should go**, leaving
it as the raw query it always wanted to be (`App#input_down?(device, id)` and
`App#input_axis(device, axis_id)` already exist and are exactly the right
surface). That is a deletion, not a rewrite — see §10.

### 5.2 One mapper per player, and it finally uses the device

`ActionMapper` becomes per-player and passes the player's device on every query,
fixing blockers 5 and 6 and unlocking the entire finished-and-unused C gamepad
stack:

```ruby
player.device = Controls.gamepad(0)   # or Controls::KEYBOARD
player.actions                        # this player's Actions snapshot, this tick
```

Each player keeps their own reused `Actions` object, so the allocation-free
property (`action_mapper.rb:19-24`, guarded by
`spec/rgame/engine/action_mapper_allocation_spec.rb`) is preserved per player
rather than lost.

Two things that have nowhere to live today and get one here:

- **Dead zones.** Nothing in the project applies one, and
  `docs/api/input.md` correctly says a resting stick reports non-zero. Per-player
  mapper is where it belongs, since it is a per-device property.
- **Device assignment on hot-plug.** `gamepad_connected(slot)` already fires; the
  player registry can claim a newly connected pad for the first player that has
  none, which is Unity's `PlayerInputManager` join behaviour and is the natural
  place for a "press a button to join" flow later.

### 5.3 Actions are global, bindings are per player

Directly from the requirement, and matching Unity's Input Action Asset. A game
declares its action vocabulary once; each player gets their own `InputMap` over
that same vocabulary. The engine reserves and guarantees a **universal set** —
`ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_confirm`, `ui_cancel` — merged
into every player's map unless the game overrides it, so the UI package (this
folder's other half) can rely on it existing for every player.

Note `Controls::DEFAULT_KEYBOARD` has no `cancel`/`back` today. It needs one, and
the UI toolkit is blocked on it.

### 5.4 "Any player" is a snapshot too

The global overlay band has no owning player, so "press any button to continue"
needs an answer. Make it the same type: an `Actions` that ORs every active
player's state. Then a cutscene's dismiss button is written exactly like a
player's, and the band difference stays in the routing rather than in the
node's code.

## 6. Routing `control` to the right player

`control(actions)` currently broadcasts one snapshot to the whole tree
(`game.rb:89`). Three ways to make it per-player:

| | |
|---|---|
| **A. Ownership inherited down the tree** — recommended | The traversal carries the player *registry*; each node resolves its owning player and passes that player's plain `Actions` to its components and hook. |
| B. Traverse `control` once per player | N× traversal cost, and every node must filter itself. Rejected: it breaks the "update once" spirit and makes every component player-aware. |
| C. No routing — components pull from a system | `node.system(Players).actions_for(@player_id)`. Keeps signatures, but every player-driven component grows the same three lines and the `control(actions)` phase loses its purpose. |

**A**, and the mechanism is one the codebase already uses: ownership is
**inherited exactly like the transform is**. `resolve_origin` (`node2d.rb:249`)
already accumulates `abs_x`/`abs_y`/`abs_z`/`abs_angle` from the parent; add
`abs_player` resolving as "my own `player`, or my parent's". Setting
`player_2_ship.player = players[1]` makes the ship *and its whole subtree* read
player 2's input.

The decisive property: **components do not change at all.**
`Components::PlayerController#control(actions)` still receives an `Actions` and
still calls `actions.axis(:move_x)`. Every existing component, every existing
spec, and the whole single-player path keep working, because an unowned node
resolves to the primary player. That is the requirement's "little to no
additional setup overhead" falling out of the design rather than being bolted on.

`PlayerLayer(player: p2)` sets ownership for its whole subtree, so a player's
menu reads their own input with nothing declared inside it.

## 7. Scene management across the bands

The user's suspicion that "the whole setup around root nodes and scene
management" needs revisiting is half right. `SceneStack` itself is fine and
should not change. What changes is that **there is no longer one stack** — there
are up to three kinds, one per band:

| Stack lives on | Holds | Example |
|---|---|---|
| `world` | levels | beach → cave |
| a player's `ui` | that player's screen | HUD → inventory → HUD |
| `overlay` | global interruptions | cutscene, game over, pause |

`Node2D#scene` resolves to the nearest boundary, so a scene-scoped system
(`CollisionWorld`, `TileWorld`) still resolves correctly inside whichever band it
lives in. `node.system(klass)` still checks scene then root. No change.

The one real question is **what an overlay scene does to the world**: a cutscene
almost certainly wants the world to stop simulating while it plays, and a
per-player inventory almost certainly does not. That is a `paused?` flag per
band, checked by the stage before calling `world.update(dt)` — and it is exactly
the case CLAUDE.md's "a pause overlay has to keep animating while the world it
covers is frozen" was written for. Two clocks, which is why elapsed time is
already a number passed to `draw` rather than a clock read.

## 8. What N draws per tick makes newly illegal

Worth its own section because it turns three existing *style* rules into
*correctness* rules, and the failures are all silent in single-player:

- **A side effect in `draw` now happens N times.** CLAUDE.md already says `draw`
  renders state; with split-screen a `draw` that mutates is a bug that appears
  only when a second player joins.
- **An allocation in `draw` is now N× worse.** `DebugOverlay`'s Δ/f meter is the
  guard, and it should be read per-view-count during this work.
- **A cache keyed on "last frame" is wrong if it is not keyed per view.**
  Anything that memoises what it drew (a baked `Recording` of the visible tile
  region, say) needs the view in its key or it thrashes between viewports every
  frame. `CachedLabel` is safe — it caches on the *value*, not on the frame.
- **Culling stops being optional.** Drawing the whole world four times is four
  times the queue. `view.visible?(x, y, w, h)` is the hook, and it is another
  reason the view wants to be a parameter (§4).

### Z bands have to be stated

The draw queue sorts by `z` across the whole frame, and each command carries its
own clip — so two viewports interleaving in the sort is harmless (disjoint
pixels, proven by `test/test_canvas.c:414`). What is *not* harmless is band order
inside one viewport: a player's HUD must be above the world, and the global
overlay above both. Component `z:` values are hand-picked render layers today
(`sprite.rb:12` is explicit that they are not `abs_z`), and `DebugOverlay` picks
`1_000_000` to win. That needs to become a documented band convention with the
bands reserving ranges, rather than each class picking a number that happens to
work.

## 9. What this costs, honestly

**Kept unchanged:** the scene graph, components, anchors, systems, signals,
`queue_free`, `SceneStack`, the entire C layer, `Util::Controls`.

**Rewritten:**

| File | Change |
|---|---|
| `engine/camera.rb` | drop viewport size; `resolve(w, h)` |
| `engine/camera_view.rb` | replaced by `WorldView` + `PlayerLayer` + `Overlay` |
| `engine/input/action_mapper.rb` | per player, per device, real physical ids, axes, dead zone |
| `engine/input/actions.rb` | unchanged interface; one instance per player |
| `engine/components/tile_world.rb` | draws through the passed `view` |
| `game.rb` | assembles the stage, owns the player registry and layout, drives the bands |
| `core/input.rb` | binding tables deleted; raw query only |

**New:** `Player`, `View`, `Layout` (value), `Viewports` (root-scoped system),
`InputMap`, `Players` (registry), `CameraFollow`.

**Wide but shallow:** `draw(renderer)` → `draw(renderer, view)` everywhere.

**The justification for the size of it** is that four of the seven blockers
(1, 2, 5, 6) are not fixable in place — they are consequences of *where* the
camera and the input snapshot live, and moving them is the change. The other
three (3, 4, 7) are small and would be pointless on their own. What is *not*
justified by the requirement, and should be resisted: touching the scene graph
traversal, the component model, or anything in C.

## 10. Suggested order of work

Each step should leave `rake` green and the examples running.

1. **Input first, single-player.** One `InputMap` with real `Controls` ids, one
   per-player `ActionMapper` that passes `device:`, delete `Core::Input`'s
   tables. Verifiable immediately: **plug in a controller and drive
   `examples/15_tiled_world` with it** — something that is impossible today and
   is the cheapest possible proof the whole per-device C stack works from Ruby.
2. **`Player` + the registry**, still one player, still full-screen. Camera
   moves onto the player; `CameraFollow` replaces the scene's `on_update`.
3. **`View` + `Layout`, one full-screen view.** Introduce `draw(renderer, view)`
   and the band node types. Still visually identical.
4. **Two views.** Split the layout, drive `examples/15_tiled_world` with two
   players. This is the first time `renderer.clipped` is called from above at all
   (inventory blocker 9) — expect to find things.
5. **`solo!` / collapse**, and a global overlay scene. The collapsed view needs a
   camera from the game (§11.7), so this step builds the first cinematic camera
   as well as the mode switch.
6. **Per-player `ui` band**, which is where this meets the UI toolkit half of
   this folder — the per-player menu is the first real customer for both.

Steps 1–3 are worth doing even if split-screen is deferred: each fixes a standing
defect (no gamepad above Core, no analog axes, no dead zone, a camera that cannot
be reused, a HUD that cannot measure its own region).

### How to verify it

Per CLAUDE.md's tiers, and one thing it warns about specifically: **booting an
example is not verification** — a scripted-input harness that counts draws is,
because the exact failure this design risks (player 2's input going nowhere,
player 2's viewport drawing player 1's camera) looks perfectly healthy from a
frame counter. The recording `FakeRenderer` already records `clipped` and
`translated` (`spec/support/fake_renderer.rb:225`), so a headless spec can assert
"two clips, two different translates, one world traversal per clip" with no
window at all. That should exist before step 4, not after.

## 11. Open questions

1. ~~**Naming.**~~ **Decided: `RGame::Engine::Player`.** The objection was that it
   collides with the player *character* class a game defines. It does not:
   constant lookup is lexical scope, then the ancestors of the cref, and lexical
   nesting does *not* put `RGame::Engine` into `Node2D.ancestors` — so a game
   class inheriting `RGame::Engine::Node2D` has no path to `Engine::Player` at
   all, and bare `Player` in game code resolves to the game's own. Engine code
   finds its own lexically. Neither can reach the other's by accident, and a
   missing `RGame::Engine::Player` raises `NameError` rather than falling back to
   the top-level constant (that fallback was removed in Ruby 2.5).

   One caveat to document: `include RGame::Engine` into `Object` (a shortcut to
   write `Node2D.new` unqualified) makes bare `Player` mean the game's
   everywhere. Nothing in the repo does this — examples fully qualify — so it is
   a note in the docs, not a defect.

   Residual: the *attribute* wants a different name. `node.player = players[1]`
   gives a game's `Player` node a `#player` returning an `Engine::Player`, read
   from outside as `@player.player`. Prefer `node.controller` / `node.seat` /
   `node.input_owner` for the attribute and keep `Player` for the class.
2. ~~**`draw(renderer, view)` vs `draw(view)`**~~ **Decided: two parameters,
   `draw(renderer, view)`.** `view.renderer` would put an indirection on every
   single draw call site for the benefit of a signature that is written once per
   node type. The common case — a node that draws and ignores the view — stays
   `renderer.text(...)`, and `view` is simply unused.

3. **Does the world band get *per-view* `control`/`update` at all?** *Open,
   deliberately deferred* — decide when the case actually arrives. The proposal
   says no. A "player 2 pressed pause" interaction still has to reach the world
   somehow, most likely by the world reading the player registry explicitly
   rather than by a second traversal. Revisit at step 5 of §10.

4. ~~**Where does UI focus live**~~ **Decided: one focus per player, owned by that
   player's `ui` band.** Focus is per player for the same reason input is: two
   people navigating two menus at once is the normal case, not an edge case, and
   a single global focus makes it impossible. This is Unity's
   `MultiplayerEventSystem` answer (see [`02-prior-art.md`](02-prior-art.md)).

   It also fixes the routing for free: the `ui` band already sets player
   ownership for its whole subtree (§6), so a focused control reads *its own*
   player's `ui_up`/`ui_confirm` with nothing declared inside it. The UI toolkit
   (this folder's other half) inherits this rather than deciding it.

5. ~~**Should `Layout` be a value or a system component?**~~ **Decided: both,
   split along the seam — see §3.1.** The question conflated two things. The rect
   arithmetic is pure and is a value; the mutable "which mode, which players"
   state is a root-scoped system component.

6. ~~**Keyboard sharing.**~~ **Decided: try one `InputMap` per player over the
   same device id, and revisit if it breaks.** Two players sharing a keyboard
   (Unity supports it explicitly, and we want it to test two-player without two
   pads) should fall out of the design as it stands: the map is per player and
   the device is just an integer, so two players both on `Controls::KEYBOARD`
   with disjoint key bindings is not a special case at all.

   What to watch for, since this is a bet rather than a proof: **edge detection
   is per player**, so two players reading the same physical key would both see
   the press — correct for a shared "any player confirms" action, wrong if
   anything ever needs a key to be *claimed* by one player. If that turns up,
   the fix is exclusivity at the map level, not a redesign.

7. ~~**What happens to a player's camera during `solo!`?**~~ **Decided: the solo
   view is driven by a camera the game supplies — `solo!(camera)`, with the
   camera required, not defaulted.**

   The question was really two, and one was already settled: *do player cameras
   keep moving while solo* falls out of the world band's `paused?` flag (§7).
   `CameraFollow` lives in the world, so a paused world freezes every camera as a
   consequence. Freezing cameras on a different schedule from their world would
   show a static view of moving actors, so "frozen" is not a separate option.

   What remained was which camera drives the collapsed view, and the answer is
   an explicit one:

   - **Explicit and symmetric.** Promoting the primary player's camera instead
     would silently give player 2 player 1's view, and privileges a player for no
     reason the game stated.
   - **Deciding what is on screen is what a cutscene *is*.** Passing a camera is
     the feature, not ceremony around it.
   - **Player cameras are untouched**, so split → solo → split is lossless.
   - **It composes.** A cinematic camera is an ordinary `Camera`; point it with a
     `CameraFollow` on a cutscene actor, a path follower, or a game-written
     component that frames every player at once (the "dynamic merge" of LEGO-style
     co-op). That last case is a game policy, not an engine one — and it needs
     zoom, which `Camera` does not have and which would mean wiring
     `renderer.scaled` into the world pass. Requiring a supplied camera keeps that
     out of the engine and still lets a game do it.

   **The consequence to accept:** the cases that do not care about framing must
   still supply a camera. For a game-over or results screen the better answer is
   usually **not to collapse at all** — keep the split and draw the panel
   full-screen in the overlay band. Collapsing is for when the *world* should be
   seen through one camera, which is cutscenes and merges, not UI.

   **Gotcha for whoever implements the transition:** the clamp changes the
   framing, not just the offset. Re-clamping a follow camera from a 320px-wide
   viewport to a 640px one moves the followed target across the screen whenever
   the world edge is in play — measured against the current `Camera#center_on`,
   a target mid-world holds at 50% across the view, but one near the right edge
   goes from 69% to 84% and one near the left edge from 31% to 16%. That is
   correct (more world is visible) but it is not seamless, and it is visible
   precisely when §3.1's animated split→solo transition is showing it. A supplied
   cinematic camera sidesteps it entirely, which is a further point for this
   decision.
