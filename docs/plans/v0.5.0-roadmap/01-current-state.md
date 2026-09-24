# What these nine features build on

Read off the code at `9abd338`. Findings tagged *(measured)* were checked
against the files or run; the rest is judgement. The numbers are referred to
from the other three documents.

This replaces the complexity estimate written at `542d08c`, which planned ten
items. Three of them have landed since — `Engine::Tween`, text measurement and
dialogue — and the estimate's own corrections are folded in below.

## What already exists, by item

### F1

**Input has no notion of time at all.** *(measured)*

[`ActionMapper#poll`](../../../lib/rgame/engine/input/action_mapper.rb) takes a
backend and nothing else, and
[`Actions`](../../../lib/rgame/engine/input/actions.rb) holds three hashes:
`held`, `prev_held` and `axes`. Every query is an edge or a level. Nothing in
`lib/` times a held button, and no example asks how long one has been down.

`poll` has **3 call sites in `lib/`** — `Game#update`, `Players#poll`,
`Player#poll` — and **70 in `spec/`**. Threading `dt` through is mechanical and
touches one line each.

[`InputMap`](../../../lib/rgame/engine/input/input_map.rb) validates every entry
against `SOURCES` and raises on an unknown key, so a new kind of source cannot
break a map that does not use it. Each `Binding` is built once, at
construction, and polling walks plain attribute reads.

Two things already read like a hold and are not one.
[`Components::ActionTrigger`](../../../lib/rgame/engine/components/action_trigger.rb)
auto-repeats while an action is held, on a per-action cooldown. `UI::Menu`'s
`trigger:` opens a menu while an action is held and activates on release. Both
read `held?` and count their own seconds; neither asks how long the button has
been down.

### F2

**`Players::Everyone` folds every player's input, and would fold a hold too.**

[`Everyone`](../../../lib/rgame/engine/players/everyone.rb) rebuilds a union
snapshot each tick: `held?` is any player's, `axis` is the largest magnitude.
Anything added to `Actions` has to be folded here as well, and `poll` is
already asserted to allocate nothing.

### F3

**Two roots hand-write the same deferred scene switch.** *(measured)*

[`test_projects/asteroids/main.rb`](../../../test_projects/asteroids/main.rb)
and [`examples/menu_navigation/main.rb`](../../../examples/menu_navigation/main.rb)
each hold a `@pending`, a `go`/`show` that records a request, and an `_update`
that applies it. Both carry a comment explaining that switching during
`control` would take apart the tree being walked.

[`SceneStack`](../../../lib/rgame/engine/scene/scene_stack.rb) is 87 lines. It
pushes, pops and replaces at once, holds the stack off the host's child list,
draws every scene and updates only the top one. It has no registry of scenes
and no notion of a switch that is pending.

The drive harness prepends `push` and `pop` to report scenes entered. ~~So a
deferred switch must still go through those two methods to stay visible in a
driven run.~~ **Changed in the re-plan of steps 9–12:** a deferred `push` only
records a request, and a named one hands the harness a Symbol. The harness hooks
the step that lands a switch instead.

### F4

**A node that moves between scenes re-registers itself.** *(measured)*

`Node2D#remove_node` calls `exit_tree`, which detaches every component;
`add_node` calls `enter_tree`, which attaches them again. A `BoxCollider`
unregisters from the old scene's `CollisionWorld` and registers with the new
one, and a `Mover` resolves its blockers against the new scene's systems. So
carrying a hero through a door needs no new machinery — only somewhere to put
it down.

`Node2D#system` looks in the node's scene first and then the root. A node kept
outside the scenes would find no `TileWorld` at all, which rules out a hero
that lives above them.

### F5

**The debug overlay is pure, and nothing else draws debug.** *(measured)*

[`DebugOverlay`](../../../lib/rgame/engine/debug_overlay.rb) is 111 lines in the
engine layer. It is not a node and not a component: `Game` owns one, binds F1 to
it, and draws it after the tree with the screen view. It draws in the `:debug`
band and allocates nothing.

`renderer.debug_box` exists at
[renderer.rb:338](../../../lib/rgame/core/renderer.rb#L338) and is in both the
`a renderer` contract and `FakeRenderer`. **It has no caller outside the
specs.** `renderer.circle` and `renderer.line(thickness:)` are there for the
other two shapes.

Colliders have an unused `_draw`. A collider's box is already in world space
(`aabb_x` is `node.world_x + box.offset_x`), and drawing it from the collider's
own `_draw` satisfies `Game/DrawInLocalSpace`, because a component draws in its
node's local space.

`TileBlockers` and `BoundsBlockers` own no node and have nowhere to draw from.
[`WorldView`](../../../lib/rgame/engine/world_view.rb) does: it is the node that
marks world space, it draws once per viewport, and it can reach the scene's
`TileWorld`. **5 examples and one test project mount one** *(measured)*.

### F6

**Three interaction patterns are already written by hand.** *(measured)*

[`examples/quests_and_dialogue/main.rb`](../../../examples/quests_and_dialogue/main.rb)
holds all three:

- **Nearest in range, on a press.** `@collision.nearest(@hero.x, @hero.y, 56, layer: :npc)`
  on `ui_confirm`, which is how the smith is spoken to.
- **On touch.** The signpost's collider `on_hit` starts its conversation.
- **Picked up on touch.** The hammer's collider `on_hit` fires a quest event.

`test_projects/tiled_world` has a fourth: an inventory that opens on a press.
Nothing in `lib/` covers any of it.

[`Components::Targeting`](../../../lib/rgame/engine/components/targeting.rb) is
52 lines and answers exactly the first pattern's question — the nearest
collider in range on a layer — for a turret. It selects and does nothing else,
and its policy list is built to grow.

### F7

**Collision stops a step and never moves what stopped it.** *(measured)*

[`CollisionSystem#move`](../../../lib/rgame/engine/collision_system.rb) resolves
X, then Y fed the resolved X, taking the most restrictive answer from every
source. A source answers `resolve_x`, `resolve_y`, `blocker` and `moved`.
[`ActorBlockers`](../../../lib/rgame/engine/actor_blockers.rb) states the rule
this plan changes: *"blocking stops the mover, it never moves the thing it
hit"*.

The seam is ready for pushing anyway. A blocker is a `BoxCollider`, which
answers `#node` and `#layer`, so the pusher can reach what it pushed and ask
whether it is pushable. `Components::Mover` already owns what happens after a
step is computed, and `blocked_by:` is the declaration a `pushes:` would
parallel.

`Components::OccupiesCell` and `TileWorld#occupy`/`#vacate` landed with the
Tiled plan, and are what a grid-snapped crate moves between.

### F8

**The UI has one axis, no grid and no nesting.** *(measured)*

`UI::Stack` places buttons in a line and `UI::Ring` on a circle.
[`UI::Stepping`](../../../lib/rgame/engine/ui/stepping.rb) moves focus along one
axis, skipping disabled buttons and wrapping, and gives the *other* axis to the
focused button as `adjust`, which is what makes `UI::OptionButton` work.
`UI::Pointing` picks by direction, for a ring.

A navigation is duck-typed on `control`, `buttons_changed`, `update` and
`opened`; a layout on `arrange`, `bounds` and `axis`. So a grid layout and a
grid-aware navigation slot in without touching `Menu`.

What nothing owns: **focus crossing from one menu to another**, and **a menu
larger than the space it is drawn in**. `docs/api/ui.md` says so under "What
this is not".

~~[`Layout.each_cell`](../../../lib/rgame/engine/layout.rb) is the grid arithmetic,
written for viewports and usable as it stands.~~ **Wrong, found in the re-plan
of steps 5–7:** it divides a known total into even cells. A grid of fixed-size
slots has no total to divide; `UI::Stack`'s arithmetic over rows is the match.

`renderer.clipped` takes the **current transform's** coordinates, not the
window's — `rgame_canvas_push_clip` maps the rect through the transform before
narrowing the clip stack *(measured, in `canvas.c`)*. So a menu may clip in its
own coordinates, which is what a scrolling list would need. `push_layer`
**replaces** the band rather than accumulating it, so a nested
`layered(:debug)` inside a node's own band is the debug shapes' way up.

### F9

**A fade is a tween and a rect, and nothing draws one.** *(measured)*

`Util::Color` carries alpha, blending is on, and the `:overlay` band draws above
both world and HUD. `Engine::Tween` has been in use since `9abd338` by
`Components::Hop`, `examples/sound`, `examples/music`,
`test_projects/tiled_world/cutscene.rb` and every one-shot timer — **7
consumers** *(measured)*.

`Components::Pool` and `examples/pooling` are the particle machinery, minus the
particle: a pool, a `Velocity` and a lifetime.

### F10

**Audio plays, stops, and does nothing in between.** *(measured)*

[`AudioOut`](../../../lib/rgame/engine/audio_out.rb) is 35 lines and forwards
three calls: `play_sound`, `play_music`, `stop_music`. `AudioBus` and
`AudioDirector` are gone, so **an audio method now lands in three places**, not
the estimate's four: `Core::Audio`, the `an audio server` contract, and
`FakeAudio`.

What the C already gives, free:

- **`Song#volume=` and `Sample#volume=`** exist in C, in Ruby and in the fake,
  and the contract pins how they clamp. **A fade stepped from `update` needs no
  new C.**
- **miniaudio's own fades** — `ma_sound_set_fade_in_milliseconds`, with `-1`
  meaning "from the current volume" — are in the vendored header and unused.
- **`ma_sound_group`** exists for a volume per category. ~~Multiplying in
  `Core::Audio` reaches the same place with no C.~~ **Wrong, found in the
  re-plan of steps 9–12:** `Song#volume` would read back the product, which the
  `an audio server` contract refuses.

What it refuses: **resuming**.
[`rgame_song_play`](../../../ext/rgame_core/audio/audio.c) seeks to zero on every
play, deliberately, so pause and resume is a new entry point rather than a
wrapper.

`Core::Audio#play_music` does **not** stop the song playing before it. It
records the new one as `@playing_song`, and `stop_music` stops only that. Two
songs at once is therefore already possible, which is what a crossfade needs
and also what makes an unpaired `play_music` leak a voice.

### F11

**More than half a cutscene exists.** *(measured)*

[`test_projects/tiled_world/cutscene.rb`](../../../test_projects/tiled_world/cutscene.rb)
is 95 lines and works: `viewports.solo!(camera)` collapses the split,
`world_view.paused = true` freezes the world while the overlay keeps animating,
`players.accepting_joins = false` shuts the door, and a tween delays the hint.
`Components::PathFollow` walks a scripted path and emits `on_finished`.

What is missing is the script: beats with waits, each ending on a duration, a
signal or a press.

`Engine::Dialogue` and `UI::DialogueBox` landed with the dialogue plan, so a
cutscene that talks has something to talk with.

### F12

**Additive blending is GL 1.1, and the queue is what has to change.** *(measured)*

**The engine calls 21 distinct GL functions, at 56 call sites, and every one of
them is GL 1.1.** `glBlendFunc` is called
**once**, in
[`gl_backend.c`](../../../ext/rgame_core/graphics/gl_backend.c), with
`GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA` at setup. `GL_ONE` is core 1.0, so
additive drawing needs neither a loader nor an extension. What is *not* in 1.1
is `glBlendFuncSeparate` and `glBlendEquation`, and nothing here wants them.

The work is above GL. A draw command carries `z`, `order`, `texture`, `clip`
and its vertices, and
[`draw_queue.h`](../../../ext/rgame_core/graphics/draw_queue.h) says why the clip
travels with the command: **sorting reorders commands, so ambient state at draw
time would land on whichever quads sorted next to it.** A blend mode is in
exactly that position. It needs a field on the command and the batch, a
comparison in the batch test, a `set_blend` entry on the backend table, and the
recording backend that the Check suite substitutes.

`rgame_canvas` already has the stack to push one onto, beside the transform,
the clip and the layer.

### F13

**The gem ships one music track, and it is most of the assets.** *(measured)*

`examples/assets/` is 124 KB across fifteen files, of which `music.ogg` is 93 KB.
Its README measured four other tracks from the same CC0 pack for loop seam and
tail silence, so a second one is a choice already researched — and a second 90 KB
in a gem that ships to everyone.

### F14

**`test_projects/tiled_world` cannot be driven anywhere but here.** *(measured)*

It reads `media/`, which is gitignored because its contents cannot be
redistributed. `examples/assets/` can: a town map, a walking hero, a UI atlas,
icons, a click and a music loop, all CC0.

## What this resembles, in three piles

CLAUDE.md asks for this inventory in writing, with the third pile justified
rather than assumed.

### Reuse it

- **`Engine::Tween`** — every fade, crossfade, camera move, sliding crate and
  cutscene wait.
- **`Components::Pool`** — the particles.
- **`Components::OccupiesCell`** and `TileWorld#occupy` — the grid-snapped
  crate.
- **`Engine::Dialogue`** — a cutscene's talking.
- **`renderer.debug_box`, `circle`, `line`** — the debug shapes and the
  lightning bolt.
- **`Viewports#solo!`, `Node2D#paused`, `Players#accepting_joins`** — the
  cutscene's three switches.
- **`Components::PathFollow`** — a cutscene's actor walking.

### Extend or generalise it

- **`Components::Targeting` → interacting.** Both answer *what is nearest in
  range on this layer*. Two classes doing that would be the parallel-vocabulary
  smell, so `Interactor` extends it. [Open question 3](README.md#open-questions)
  keeps the doubt.
- **`UI::Stepping` → a grid.** Stepping owns wrapping and skipping disabled
  buttons. A grid changes the size of a step, not what a step is: up and down
  move by a row's width. A second navigation class would copy both rules.
- **`Components::Mover` → pushing.** `blocked_by:` says what stops a step.
  `pushes:` says what a step moves instead of stopping on. Same declaration,
  same place, same resolver.
- **`SceneStack` → naming and deferring.** Two games wrote the deferral, so it
  belongs under them rather than beside them.
- **`DebugOverlay` → one channel of a debug layer.** It stays what it is and
  stops being the whole of it.
- **`Core::Audio` → transitions.** Fades multiply a volume that already exists.

### Genuinely new

- **`UI::Tabs` and `UI::FocusGroup`.** Nothing here passes focus between two
  menus, and nothing switches pages. `UI::Menu` holds buttons and cannot hold
  menus. The re-plan of steps 5–7 moved `Tabs` to the middle pile: its bar is a
  `Menu`, and its pages are held the way `SceneStack` holds scenes.
- **`Components::Particles`.** A pool of things with a lifetime exists;
  spawning them along a spread with a colour over their life does not.
- **`Engine::Cutscene`.** A sequencer of steps, each ending on a duration, a
  signal or a press. `StateMachine` is the closest thing and is the wrong
  shape: it moves on events, lists what is available now, and is built for a
  menu of choices — a cutscene has one way forward and waits for time.
- **A blend mode on a draw command.** No draw state but the clip travels this
  way today.
