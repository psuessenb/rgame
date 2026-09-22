# Roadmap complexity estimate

An estimate of what ten README roadmap items cost, read off the code at
`542d08c` (version 0.4.0). It covers every roadmap bullet except Tiled feature
support.

This is research, not a plan. It schedules nothing and commits to nothing. What
it gives is a size, a breaking-change risk and an ordering for each item, so the
next plan starts from the code rather than from memory. Findings tagged
*(measured)* were checked against the files; the rest is judgement.

## Summary

| # | Item | Size | Breaking-change risk | Gated by |
|---|---|---|---|---|
| 1 | Long press and button combos | M | **Medium–high** — `poll` needs `dt` | — |
| 2 | Scene manager, teleport example | S–M | Low | 9, for transitions only |
| 3 | Debug layer toggle, collision boxes | S / M | Low | — |
| 4 | Dialogue, better text | **L** | Low now, **high** if the typeface moves | text measurement |
| 5 | Push and pull objects | M | Low API, **medium behavioural** | — |
| 6 | Inventory and equipment screens | M | Low | measurement, for the good version |
| 7 | Collectables and interactables | **S** | None | — |
| 8 | Audio transitions | M | Low, all additive | — |
| 9 | Visual effects | S–M | None | — |
| 10 | Cutscenes | M | None | 4, 9 |

S is one branch. M is a few. L is a plan of its own.

## Two findings decide the order

### Nothing in the engine moves a value over time — *(measured: no match for `lerp`, `ease` or `tween` under `lib/`)*

`Timer` accumulates intervals. `Animator` steps sprite frames. Neither eases a
number from one value to another over a duration.

A fade to black, an audio fade, a typewriter reveal, a cutscene camera move and
a scene transition are one object with five consumers. That is the "extend or
generalize" pile CLAUDE.md asks a plan to fill: build one pure
`Engine::Tween` driven by `update(dt)` and items 2, 4, 8, 9 and 10 all shrink.
Build it in any other order and it gets written four times, noticed only from
the file that needs two of them.

### Text measurement gates two items, and the write-up already exists

*(Landed after this estimate: the pure typeface moved to `RGame::Util`, and
`Engine::Paragraph` and `UI::Label` break and draw translated text. What is still
open is under "Text layout past a label" in [possible-todos.md](../possible-todos.md).)*
[possible-todos.md, "Text measurement for the engine layer"](../possible-todos.md)
recorded the problem and marked its trigger satisfied. Item 4 cannot wrap a line
without it. Item 6 cannot size a slot to an item name.

That entry weighs two options: hand the engine a measuring object, or move the
pure typeface into `RGame::Util`. Which one wins changes the size of both items,
so settle it before starting either.

## The items

### 1. Long press and button combos

`ActionMapper#poll` takes a backend and no `dt`
([action_mapper.rb:41](../../../lib/rgame/engine/input/action_mapper.rb#L41)), and
`Actions` holds three hashes with edge queries and no notion of time
*(measured)*. Hold duration therefore needs a fourth hash and `dt` threaded
through `Players#poll` → `Player#poll` → `ActionMapper#poll` from
[game.rb:165](../../../lib/rgame/game.rb#L165). That breaks the signature across the
spec fakes and the drive harness, and it is cheapest now, while the callers are
few.

Combos need a second binding kind — all of these down, against
[`any_down?`](../../../lib/rgame/engine/input/action_mapper.rb#L63)'s any of these —
plus a rule that lets a combo suppress the actions it is built from. `InputMap`
validates entries against `SOURCES` and raises on an unknown key, so a new
source breaks no existing map.

One cheaper path avoids the signature break. A hold trigger in
[`ActionTrigger`](../../../lib/rgame/engine/components/action_trigger.rb)'s shape sees
both `control(actions)` and `update(dt)`, and that class already rate-limits.
It puts hold time outside the action vocabulary and expresses no combo at all,
so take it as a decision rather than a drift.

### 2. Scene manager

The boilerplate is small and visible.
[asteroids/main.rb:24-53](../../../test_projects/asteroids/main.rb#L24-L53) holds
`@pending`, a `go`, a `build_scene` case and a deferred apply, with a comment
saying why the deferral has to be there. Folding that into a component beside
the 87-line
[`SceneStack`](../../../lib/rgame/engine/scene/scene_stack.rb) adds a registry of
named scenes and a deferred switch, and breaks nothing.

Transitions are where the item stops being small. Fading one scene into another
means holding both alive across several ticks, which wants the tween above.

The teleport example carries its own design question: moving a node from one
scene to the next. `push` and `pop` do not answer it today.

### 3. Debug layer

Two halves, two sizes.

Exposing the toggle is nearly free.
[`DebugOverlay`](../../../lib/rgame/engine/debug_overlay.rb) already lives in the
engine layer, and `Game` owns one and binds F1 to it at
[game.rb:230](../../../lib/rgame/game.rb#L230).

Connecting it to collision is the work. The flag has to reach colliders deep in
the tree, and those find systems through `node.system(...)`, so the shape is a
root-scoped debug system and an overlay that reads it. That makes `DebugOverlay`
a `Component`, or puts one beside it.

Drawing costs nothing new. `renderer.debug_box` exists at
[renderer.rb:328](../../../lib/rgame/core/renderer.rb#L328), and the `a_renderer`
contract and `FakeRenderer` both carry it *(measured)*. A collider drawing its
own box at its own offsets satisfies `Game/DrawInLocalSpace`.

One gap to scope out or to hang on `TileWorld`: `TileBlockers` and
`BoundsBlockers` stop a step without owning a node, so neither has anywhere to
draw from.

### 4. Dialogue and better text

*(Landed after this estimate: `Engine::StateMachine`, `Components::Facts`,
`Engine::Dialogue`, a reveal on `UI::Label` and `UI::DialogueBox`, with
`examples/dialogue` and `examples/quests_and_dialogue`. See
[docs/api/dialogue.md](../../api/dialogue.md). The reveal builds its prefixes
once per page, as below. It needed no tween.)*

The largest item, and the only one that is a plan rather than a branch.

Wrapping at draw time works — the UI buttons measure that way already
([text_button.rb:54](../../../lib/rgame/engine/ui/text_button.rb#L54)) — but naive
wrapping builds substrings every frame, which Δ/f and `Game/NoNeedlessAllocation`
exist to refuse. So it needs wrapped lines cached against the string, the width
and `I18n.generation`. [`Engine::Text`](../../../lib/rgame/engine/text.rb) is that
shape already, and a cache built this way survives the typeface moving to Util
later. Typewriter reveal hits the same trap, a prefix per frame, and takes the
same fix.

The machinery above it is ordinary engine Ruby: a queue of beats, advance on
`ui_confirm`, branching choices through `UI::Menu`.

### 5. Push and pull

The one item that changes a system rather than adding a component.

[`CollisionSystem#move`](../../../lib/rgame/engine/collision_system.rb#L65) only stops
a step. Pushing means moving the blocker by what is left of the step and
resolving again — recursively for a crate against a crate, and against the
pushed thing's own blockers, so that a crate against a wall stops whoever pushes
it.

The seam suits it. A source answers `resolve_x`, `resolve_y`, `blocker` and
`moved`, and a blocker answers `#node` and `#layer`, so the pusher can reach
what it pushed. A `pushes:` declaration on `Mover` parallels `blocked_by:`
exactly, which is the shape to aim at.

The API risk is low while it stays additive. The behavioural risk is not: resolve
order is what gives every existing mover its feel. The driven examples and test
projects are what catch a change in it.

### 6. Inventory and equipment screens

A plain list inventory is example-sized today.
[tiled_world/inventory.rb](../../../test_projects/tiled_world/inventory.rb) is 45
lines and works *(measured)*.

What a real one needs is the list under "What this is not" in
[ui.md](../../api/ui.md): no grid, no nesting, no scrolling. The grid layout is
easy, since `Layout.each_cell`
([layout.rb:67](../../../lib/rgame/engine/layout.rb#L67)) is the arithmetic. Moving
focus through it is a new navigation, because `UI::Stepping` walks one axis.
Equipment slots beside a bag is *nesting*: focus passing between two menus, which
nothing owns today.

Layouts and navigations are duck-typed on `arrange`, `bounds` and `axis`, so new
ones slot in. A break would come from changing who owns focus in `UI::Menu`.

### 7. Collectables and interactables

The cheapest item, and genuinely an example.

Everything it needs exists: colliders with layers and the `on_hit` and
`on_separated` edges, `queue_free`, `Pool`, `AudioBus.play_sound`, and
`Engine::Text` for the counter.
[`CollisionWorld#nearest(x, y, r, layer:)`](../../../lib/rgame/engine/components/collision_world.rb#L114)
is already "which chest am I standing next to".

One component may be worth adding — nearest in range, a prompt, an activate
signal. Hold it against `Components::Targeting` first. It answers a close enough
question about a different thing.

### 8. Audio transitions

The C is small and the ceremony is not.

A song is one `ma_sound`, so miniaudio's fades come for free. Pause and resume
do not: [`rgame_song_play`](../../../ext/rgame_core/audio/audio.c#L524) seeks to zero
on every play, deliberately, so resuming is a new entry point rather than a
wrapper *(measured)*.

Every method added lands in four places — `Core::Audio`, the `an_audio_server`
contract, `FakeAudio`, and both suites — and every new audio *fact* grows
[`AudioBus`](../../../lib/rgame/engine/audio_bus.rb)'s signals and
[`AudioDirector`](../../../lib/rgame/engine/audio_director.rb#L37)'s connects.

Settle one fork before starting. Fading on miniaudio's own clock sounds smoother
and does not stutter when the game does. Fading in `AudioDirector` per `update`
is headless-testable and matches "time enters through `update`". The contract
says nothing about timing on purpose, which points at the second.

### 9. Visual effects

Fade to black is nearly free. `Color` carries alpha, blending is on, and the
`:overlay` band sits above both the world and the HUD, so the effect is a
view-sized rect with a rising alpha. Sparkles are `Pool` plus `Velocity` plus a
lifetime, which is `examples/pooling` with different art. Lightning is
`renderer.line(thickness:)`
([renderer.rb:153](../../../lib/rgame/core/renderer.rb#L153)).

The part worth designing is the shared tween.

One caveat on ambition: additive blending and per-particle colour ramps would
reach into the GL backend, and no blend mode is exposed today. Stay inside the
current primitives and the whole item is engine-layer Ruby.

### 10. Cutscenes

More than half exists, and was built for this.
[`Node2D#paused`](../../../lib/rgame/engine/node2d.rb#L228) freezes a subtree while an
overlay above it keeps animating.
[`Viewports#solo!`](../../../lib/rgame/engine/viewports.rb#L91) collapses the split.
`Players#accepting_joins` shuts the door. `PathFollow` walks a scripted path.
[tiled_world/cutscene.rb](../../../test_projects/tiled_world/cutscene.rb) is a working
94-line cutscene *(measured)* — read it as the picture of what this replaces.

What is missing is the script: beats with waits, each ending on a duration or a
signal. That is a small sequencer node, plus the tween.

A cutscene is mostly dialogue with fades between the beats, so it belongs last.

## Suggested order

```
tween ─┬─→ 2 scene manager ──→ 10 cutscenes
       ├─→ 8 audio fades          ↑
       └─→ 9 effects ─────────────┤
                                  │
measurement ─→ 4 dialogue ────────┘
            └─→ 6 inventory

7 collectables    3 debug    1 input    5 push/pull    (independent)
```

Build the tween first. Take 7 and the toggle half of 3 next, since neither waits
on anything. Settle the measurement question. Take 1 while its `poll(dt)` break
is still cheap. Then 2, 5, 6, 8, the rest of 9, then 4, then 10.

## What this does not cover

- Tiled feature support, the one roadmap bullet left out.
- Anything already in [possible-todos.md](../possible-todos.md), except text
  measurement, which two of these items wait on.
- Sizes for the C work behind a render target or a GL loader. No item here needs
  one unless particle effects grow blend modes.
