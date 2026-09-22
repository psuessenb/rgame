# Roadmap

Fifteen steps. Each is one branch and one pull request, and its sub-steps are
one commit each. **Steps 0–4 are detailed. Steps 5–14 are deliberately rough**
and get re-planned once the layer beneath them exists.

## Dependency shape

```
0 adventure ─→ 1 input ───────────────────────────────────────────────┐
               2 debug shapes                                          │ hold to skip
               3 interact + collect ─→ 5 grid + focus ─→ 6 tabs ─→ 7 screens
               4 push and pull                                         │
               8 fades + particles ─┬─→ 11 scenes ─→ 12 doors ─→ 13 cutscenes
               9 blend modes (C) ───┘                  │
               10 audio transitions ───────────────────┘
               14 fold back and delete the plan
```

Step 0 comes first because every later step adds to it. Input comes next, while
`poll(dt)` touches the fewest callers, and because a held button is what skips a
cutscene in step 13. The debug shapes come before pushing, which is far easier
to watch with the boxes on screen. Fades come before scenes, because a door
fades.

## The invariant every step preserves

> **Nothing added here reads a clock or allocates on a draw path.** Every one of
> these features animates — a fade, a particle, a reveal, a crate sliding, a
> cutscene waiting — and every one of them accumulates in `update(dt)` and
> draws from state.

`DebugOverlay`'s Δ/f is the standing check, and each step's driven run is where
a regression shows.

## What lands early, if the plan is abandoned

| After step | The defect it closes |
|---|---|
| 1 | a game cannot tell a tap from a hold, and writes its own timer per caller |
| 2 | a collision bug can only be found by reading numbers |
| 3 | every game writes "what am I standing next to" again, as `quests_and_dialogue` did three times |
| 4 | nothing in the world can be moved by walking into it |
| 8 | a scene cannot fade, so a transition cannot be written at all |
| 10 | music cuts rather than fades, and cannot be paused |

## Which roadmap item each step serves

| README item | Steps |
|---|---|
| better input-to-action mapping | 1 |
| debug layer, connected to collision | 2 |
| collectable and interactable nodes | 3 |
| pushing and pulling objects | 4 |
| inventory and equipment screens | 5, 6, 7 |
| visual effects | 8, 9 |
| audio transitions | 10 |
| scene manager, teleports and room transitions | 11, 12 |
| cutscenes | 13 |

---

## Step 0 — `test_projects/adventure`, the room everything is added to

Every later step has somewhere to land, and CLAUDE.md's composition test has
something to run. Building it first also means no step has to argue about where
its acceptance test goes.

It is small on purpose: a room, a hero who walks it, two seats, and a drive
script. Everything else arrives with the step that needs it.

### Shape

```
test_projects/adventure/main.rb      # Game.new(players: 2, root: Shell.new)
test_projects/adventure/shell.rb     # the root: a SceneStack with the room pushed
test_projects/adventure/room.rb      # WorldView, TileMapLayer.mount, the hero
test_projects/adventure/hero.rb      # CharacterBody + FeetCollider + CameraFollow
tools/drive/test_projects/adventure.rb
```

Art comes from `examples/assets/`: `town.tmx`, `tileset.png` and `hero.png`.
A test project is a game rather than teaching material, so it draws Strings and
ships no `locales/`.

### The rules the tests pin

1. **Two seats from the start.** Player 2 joins by pressing confirm on a second
   device, and the split appears without the room knowing.
2. **The hero is stopped by the map**, through `blocked_by: [:tiles]`.
3. **The drive script holds one timeline per device**, so the second player's
   arrival is scripted from tick 0.

### Tests

No specs of its own: a test project is verified by being driven. What it proves
is that all three layers work together, which no spec tier can.

### Verify

```
ruby tools/drive_test_project.rb test_projects/adventure/main.rb --ticks 240
```

reports two viewports' worth of draw calls, one scene entered, and 240 ticks
against its frames.

---

## Step 1 — a hold, a tap and a chord

The signature change is cheapest now: `poll` has 3 call sites in `lib/` and 70
in `spec/`, and every step after this adds callers. A held button is also what
step 13 skips a cutscene with, so it wants to exist long before then.

### Sub-steps

- **1a** — `poll(backend, dt)` threaded through `Players`, `Player` and
  `ActionMapper`, and `Actions#held_for`.
- **1b** — `hold:` and `tap:` in `InputMap`, and the level they produce.
- **1c** — `all:`, and the actions a held chord silences.

### Shape

```ruby
map = InputMap.new(
  interact: { buttons: [Controls::KEY_E, Controls::PAD_A], tap: 0.3 },
  search:   { buttons: [Controls::KEY_E, Controls::PAD_A], hold: 0.6 },
  swap:     { all: [Controls::PAD_LEFT_SHOULDER, Controls::PAD_RIGHT_SHOULDER] }
)

actions.held_for(:interact)   # seconds down, 0.0 at rest
actions.pressed?(:search)     # once, when the threshold passes
actions.pressed?(:interact)   # once, on a release that came in time

Binding = Struct.new(:buttons, :pairs, :stick, :all, :hold, :tap, :silences)
```

### The rules the tests pin

1. **`held_for` counts while any bound button is down** and is `0.0` the tick
   after they come up.
2. **A hold action presses once per press.** Holding for ten seconds is one
   `pressed?`, and `held?` stays true until release.
3. **A tap action presses on release**, and only if `held_for` never passed
   `tap:`. It is true for exactly one tick.
4. **A tap and a hold on the same button never both press.** Holding past the
   threshold means the release presses nothing.
5. **A chord presses when its last button arrives**, and reads held while all
   of them are down.
6. **A chord silences the plain actions on its buttons** while it is held, so
   `L` alone blocks and `L+R` swaps.
7. **An unknown source still raises**, and so do `hold:` with no buttons, both
   `hold:` and `tap:` on one action, `all:` with one id, and a threshold that
   is not a positive number.
8. **`Players::Everyone` folds `held_for` as the largest** of its active
   members'.
9. **A device that is nil reads nothing**, `held_for` included.
10. **Polling still allocates nothing**, holds and chords included.

### Tests

- `spec/rgame/engine/input_map_spec.rb`: each new key, each refusal, and
  `to_h` round-tripping a map that uses them.
- `spec/rgame/engine/action_mapper_spec.rb`: rules 1–6, driven by passing `dt`
  to `poll`; a hold that is released early; a tap that is too slow; a chord
  built up button by button.
- `spec/rgame/engine/actions_spec.rb`: `held_for` on an undeclared action
  raises `KeyError` like the rest.
- `spec/rgame/engine/action_mapper_allocation_spec.rb`: rule 10.
- `spec/rgame/engine/players_spec.rb` and the `Everyone` group: rule 8, with
  two players holding for different lengths.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/input_holds/main.rb --ticks 240
ruby tools/drive_test_project.rb examples/quick_wheel_pad/main.rb --gamepad --ticks 240
```

`examples/input_holds` ships with this step: one button that opens on a tap and
searches on a hold, and a chord that does a third thing, with the state drawn
as text. Its drive script holds the button for 40 ticks and then taps it, and
the run reports both.

The `--gamepad` run is what says the real device path still reaches a map that
now has three more kinds of entry. Every other driven example reports what it
reported on `main`, byte for byte.

---

## Step 2 — the debug layer, and shapes that draw themselves

Pushing (step 4) is built by watching boxes move, and every collision question
after it is asked with this on. It is also independent of everything else, so
it can land whenever.

### Sub-steps

- **2a** — `Engine::Debug`, its channels, and `RGame::Game` mounting one and
  binding F1 and F3.
- **2b** — `renderer.debug_circle`, in the contract and the fake.
- **2c** — the shapes: both colliders, and `WorldView` drawing the scene's
  solid and occupied cells.

### Shape

```ruby
debug = node.system(Engine::Debug)
debug.toggle(:shapes)
debug.define(:routes) { |renderer, view| ... }
debug.shows?(:routes)

game.debug_keys = false     # a build a player runs
```

### The rules the tests pin

1. **A channel is off until something switches it on**, and an unknown channel
   name raises rather than staying quietly dark.
2. **`:stats` is the overlay that exists**, with its numbers unchanged.
3. **A collider with no `Debug` above it draws nothing** and asks nothing of
   the tree per frame.
4. **A shape draws in its node's local space**, so it lands on the node in
   every viewport, and `Game/DrawInLocalSpace` passes.
5. **Shapes draw in the `:debug` band**, above everything, whatever band their
   node draws in.
6. **A defined channel's block is called once per frame** while it is on, and
   never while it is off.
7. **Nothing allocates while a channel is off**, and the shapes allocate
   nothing while on.
8. **`debug_circle` refuses what `debug_box` refuses**, in the fake as in the
   real renderer.

### Tests

- `spec/rgame/engine/debug_spec.rb`: channels, `define`, the refusal.
- `spec/rgame/engine/components/box_collider_spec.rb` and the circle's: a
  `FakeRenderer` records a `debug_box` at the node's own offsets with the
  channel on, and nothing with it off.
- `spec/rgame/engine/world_view_spec.rb`: solid cells drawn once per viewport,
  and nothing for a scene with no `TileWorld`.
- `spec/support/shared_examples/a_renderer.rb` and `fake_renderer_spec.rb`:
  `debug_circle`.
- `spec_core/`: the real renderer against the same group.

### Verify

```
bundle exec rake spec
make ext-core && bundle exec rake spec:core
ruby tools/drive_test_project.rb test_projects/adventure/main.rb --ticks 240
```

The adventure binds a `debug` action (F3 and a pad button) that calls
`debug.toggle(:shapes)` from its own node, because the scripted backend drives
polled input and never reaches `Game#button_down`. Its drive script presses it
at tick 60, and the report shows `debug_box` calls appearing from that tick.

---

## Step 3 — interacting, and collecting

Three hand-written copies exist in `examples/quests_and_dialogue`
([F6](01-current-state.md#f6)), which is two more than the rule of thumb allows.
The step after this one needs a crate to grab, and grabbing is this question
asked again.

### Sub-steps

- **3a** — `Components::Interactor` on `Targeting`, and `:interact` in
  `InputMap::DEFAULT_ACTIONS`.
- **3b** — `Components::Collectable`.
- **3c** — `examples/collectables`, and the adventure's chest and coins.

### Shape

```ruby
hero.add_component(Components::Interactor.new(range: 56, layer: :interactable))
  .on_interacted { |target| target.open }

coin.add_component(Components::Collectable.new(by: :hero, sound: :blip))
  .on_collected { |_other| purse.add(:coin) }

chest.add_component(Components::Collectable.new(by: :hero, free: false))
```

### The rules the tests pin

1. **`target` is the nearest node in range on the layer**, and nil for none —
   `Targeting`'s behaviour, unchanged.
2. **`on_interacted` fires once per press**, and never while nothing is in
   range.
3. **A press with a target out of range does nothing**, and a target leaving
   range clears `target` on the next update.
4. **`Collectable` fires on a collider of the layer it names**, and ignores
   every other.
5. **It frees its node by default** and keeps it with `free: false`.
6. **It plays its sound through the tree's `AudioOut`**, and plays nothing
   when given none.
7. **It disconnects on detach**, so a pooled node that is collected twice
   fires twice, not three times.
8. **Two players each interact with their own target**, because an `Interactor`
   reads the actions of whoever owns its node.

### Tests

- `spec/rgame/engine/components/interactor_spec.rb`: rules 1–3 and 8, the last
  with two heroes and one chest between them.
- `spec/rgame/engine/components/collectable_spec.rb`: rules 4–7, with a
  `FakeAudio` for the sound.
- **The caller that uses both**, in the same file: a hero with an `Interactor`
  walking onto a `Collectable` chest that does not free itself, opening it with
  a press, and collecting the coin inside on touch.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/collectables/main.rb --ticks 240 --texts
ruby tools/drive_test_project.rb test_projects/adventure/main.rb --ticks 240
```

`examples/collectables` is coins picked up by walking over them and a chest
opened with a press, with a counter drawn from an `Engine::Text`. The `--texts`
run is what shows the counter moving. In the adventure, the chest opens on a
tap and is searched on a hold — steps 1 and 3 meeting, and the first thing the
project proves that no spec does.

---

## Step 4 — pushing, and pulling

The one step that changes how existing movers resolve, so it goes in while the
number of movers is small and the driven examples still cover them. It needs
step 2's boxes to watch and step 1's `held?` for the grab.

### Sub-steps

- **4a** — `pushes:` on `Mover`, and `Components::Pushable`.
- **4b** — `Components::Grab`, and pulling.
- **4c** — `examples/push_pull`, `examples/block_puzzle`, and the adventure's
  crate.

### Shape

```ruby
crate.add_component(Components::Pushable.new(blocked_by: %i[tiles wall crate]))

hero.add_component(Components::CharacterBody.new(speed: 80,
                                                 blocked_by: %i[tiles wall crate],
                                                 pushes: [:crate]))
hero.add_component(Components::Grab.new(action: :grab, layer: :crate, range: 20))
```

### The rules the tests pin

1. **A step that is not blocked is unchanged.** Every existing mover resolves
   exactly as it did.
2. **A blocker on a pushed layer moves by what is left of the step**, on the
   axis that was stopped.
3. **A crate resolves its own step.** Against a wall it moves nothing, and the
   pusher stops flush against it with `on_blocked`.
4. **A crate half-way to a wall moves half-way**, and the pusher follows that
   far.
5. **A crate pushes a crate**, and a ring of crates stops at `PUSH_DEPTH`
   rather than recursing.
6. **A pushed node never pushes back** the node that pushed it.
7. **A layer in `pushes:` but not `blocked_by:` is walked through**, as it is
   today, and pushes nothing. The docs say to declare both.
8. **A grabbed crate moves with the mover**, in any direction, including
   backwards.
9. **A grabbed crate that cannot move stops the mover.**
10. **Letting the action go lets the crate go**, the same tick.
11. **Two players may push the same crate**, and it moves once per pusher's
    step rather than twice in one.

### Tests

- `spec/rgame/engine/components/mover_spec.rb` and the `a mover` shared group:
  rule 1 over every existing subclass.
- `spec/rgame/engine/components/pushable_spec.rb`: rules 2–7, on a scene with a
  `CollisionWorld` and a `TileWorld`, so a crate meets both kinds of blocker.
- `spec/rgame/engine/components/grab_spec.rb`: rules 8–10.
- **The caller that uses both**: a crate pushed onto a cell a `Navigator` had
  planned through, which is `possible-todos.md`'s open question about routes,
  and the step states what happens rather than fixing it.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/collision_tiles/main.rb --ticks 240
ruby tools/drive_test_project.rb examples/jump_topdown/main.rb --ticks 240
ruby tools/drive_test_project.rb examples/push_pull/main.rb --ticks 240
```

**The first two are the point of this step's verification.** They are the
movers that existed before it, and their reports must match `main` byte for
byte. A change there is a change in feel, which is the risk this step carries
and the only thing that catches it.

---

## Step 5 — the grid, and focus that crosses menus *(rough)*

`UI::Grid` as a layout, `UI::Stepping` reading its `columns`, and
`UI::FocusGroup` passing focus between menus laid side by side. No new
navigation class: a grid changes the size of a step, not what a step is.

Re-plan once step 3 has landed, because the inventory's contents come from it.
Watch for: wrapping inside a row against wrapping to the next row, and what a
group does when the neighbouring menu has no enabled button.

## Step 6 — tabs, and scrolling *(rough)*

`UI::Tabs` holding a node per page off its child list, `ui_tab_prev` and
`ui_tab_next` in the universal set, and `visible_rows:` on `UI::Column` and
`UI::Grid`. [Open question 2](README.md#open-questions) picks the keys before
this step starts.

## Step 7 — `examples/inventory` and `examples/equipment` *(rough)*

Two examples, as dialogue had two: one showing the parts, one showing the
screen a game ships — tabs, clothes put on and taken off, and a bag that marks
what is worn. The adventure's bag holds what step 3 collected.

## Step 8 — fades, and particles *(rough)*

`Engine::ScreenFade` and `Components::Particles`, plus `examples/effects`: a
fade, a flash, sparkles and a bolt. Everything here is engine-layer Ruby over
`Engine::Tween` and `Components::Pool`.

Watch for: the colour a fade draws with changes every tick, so it is built in
`_update` and never in `_draw`.

## Step 9 — a blend mode on a draw command *(rough, and C)*

`renderer.blended(:add) { ... }`, carried through the draw queue the way a clip
is. A field on the command and the batch, a comparison in the batch test, a
`set_blend` entry on the backend table, the recording backend, and
`glBlendFunc(GL_SRC_ALPHA, GL_ONE)`.

Follow [write-c-code](../../../.claude/skills/write-c-code/SKILL.md). The Check
suite asserts the batching: two additive quads and one alpha quad between them
are three batches, and the same three in one blend mode are one.

## Step 10 — audio transitions *(rough)*

`Core::Audio` gains `music_volume`, `pause_music`, `resume_music` and
`category_volume`; `Song#resume` is the one new C entry point. `AudioOut` gains
`fade:`, `crossfade`, the pause pair and the category volume, each driven by a
tween in `_update`.

`examples/audio_transitions` exists to be listened to, and
[open question 1](README.md#open-questions) — which second track, and whether it
is worth 90 KB in the gem — is answered before this step starts.

## Step 11 — the scene stack that names and defers *(rough)*

`define`, `carry:`, deferral in `_update`, `on_changed`, and `Scene::Fade` as a
transition the stack drives. The two hand-written switches in
`test_projects/asteroids` and `examples/menu_navigation` come out in the same
step, which is what proves the engine's version covers what they did.

Watch for: the drive harness prepends `push` and `pop` to report scenes, so a
deferred switch must still go through them.

## Step 12 — doors, entrances, and the teleport example *(rough)*

`examples/doors`: two rooms, a door between them that carries the hero and
places them at a named entrance, and a warp pad that moves them inside one
room. The adventure gains its second room. Doors come from a Tiled object layer
through `Engine::MapObjects`.

## Step 13 — cutscenes *(rough)*

`Engine::Cutscene::Script`, `Engine::Cutscene` and `Components::Cutscene`, with
the five step kinds and a skip that finishes the rest. `examples/cutscene`, and
the adventure's arrival scene, skipped with a held button.

`test_projects/tiled_world/cutscene.rb` is the 95 lines this replaces: the step
is done when that file could be written with the script instead.

## Step 14 — fold the plan back and delete it

Move what is still true into the documentation and remove
`docs/plans/v0.5.0-roadmap/`.

- **`docs/api/input.md`** — holds, taps and chords, and `held_for`.
- **`docs/api/systems.md`** — `Engine::Debug` and its channels; `AudioOut`'s
  transitions.
- **`docs/api/components.md`** — `Interactor`, `Collectable`, `Pushable`,
  `Grab`, `Particles`, `Cutscene`, and `pushes:` on `Mover`.
- **`docs/api/ui.md`** — the grid, focus groups, tabs and scrolling, and a
  rewritten "What this is not".
- **`docs/api/scene_graph.md`** — the scene stack's names, `carry:` and
  transitions; `ScreenFade`.
- **`docs/api/drawing.md`** — `blended`, `debug_circle`.
- **`docs/api/audio.md`** — fades, crossfades, pause and resume, categories.
- **`docs/api/examples.md`** — every example this plan added.
- **`docs/api/toolbox.md`** — `Engine::Cutscene` beside `Tween` and `Timer`.
- **`docs/plans/possible-todos.md`** — new entries with their triggers:
  input sequences and double taps; ducking; a crossfade between two live
  scenes, which needs the render target already recorded there; partial rows in
  a scrolling menu. And the "connection that ends with its node" entry records
  that its trigger fired in step 3.
- **`CHANGELOG.md`** — checked against everything the plan shipped, per
  [update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
- **`README.md`** — the roadmap loses the nine items and says what is left.

### Verify

`rake` with no argument: `make test`, `rake spec`, `rake spec:core`. Every
driven example and both test projects report what they reported. `rake
docs:coverage` reports nothing undocumented. `docs/plans/v0.5.0-roadmap/` is
gone, and `grep -r v0.5.0-roadmap docs/` finds nothing.
