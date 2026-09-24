# Roadmap

**Status: steps 0 to 10 are implemented.** Sixteen steps. Each is one branch and one
pull request, and its sub-steps are one commit each. **Steps 0–12 are detailed.**
Steps 5–8 were planned after step 4 landed, and steps 9–12 after step 8. What
each re-plan found comes before its steps:
[steps 5–7](#re-planning-steps-57) and [steps 9–12](#re-planning-steps-912).
**Steps 13–15 are deliberately rough** and get re-planned once the layer beneath
them exists.

Step 7 was inserted by a review of the re-plan
([decision 19](README.md#decisions-already-taken)). The landed notes of steps
0–4 were written before that, so "step 13" there means today's step 14, and
"step 14" means step 15. The re-plan's heading keeps the numbers it was written
with: its steps 5–7 are today's 5, 6 and 8. The re-plan of steps 9–12 swapped
the two steps first numbered 9 and 10, so the C lands before the fade built on
it.

## Dependency shape

```
0 adventure ─→ 1 input ─→ 7 press gate ────────────────────────────────┐
               2 debug shapes                                          │ a press it saw start
               3 interact + collect ─→ 5 grid + focus ─→ 6 tabs ─→ 8 screens
               4 push and pull

               9 blend + opacity (C) ─→ 10 fades + particles ─┐
               11 audio transitions ──────────────────────────┴─→ 12 scenes ─→ 13 doors ─→ 14 cutscenes
                                                                                              ↑
               1 input: a held button skips ──────────────────────────────────────────────────┘
               15 fold back and delete the plan
```

Step 0 comes first because every later step adds to it. Input comes next, while
`poll(dt)` touches the fewest callers, and because a held button is what skips a
cutscene in step 14. The press gate comes before the screens, because a bag that
pauses its hero is where a press first outlives the node that should read it.
The debug shapes come before pushing, which is far easier
to watch with the boxes on screen. The canvas comes before fades, because a fade
is a rect drawn at an opacity. Fades and audio come before scenes, because a
scene arrives under a reveal with its music rising.

## The invariant every step preserves

> **Nothing added here reads a clock or allocates on a draw path.** Every one of
> these features animates — a fade, a particle, a reveal, a crate sliding, a
> cutscene waiting — and every one of them accumulates in `update(dt)` and
> draws from state.

`rake drive:allocations` is the standing check, and each step's driven run is
where a regression shows.

## What lands early, if the plan is abandoned

| After step | The defect it closes |
|---|---|
| 1 | a game cannot tell a tap from a hold, and writes its own timer per caller |
| 2 | a collision bug can only be found by reading numbers |
| 3 | every game writes "what am I standing next to" again, as `quests_and_dialogue` did three times |
| 4 | nothing in the world can be moved by walking into it |
| 5 | two open menus under one player both move and both confirm, and a bag cannot be a grid |
| 6 | a list longer than its panel cannot be shown, and a screen cannot have pages |
| 7 | a press begun while a node was paused, hidden or not yet there reaches it once it runs |
| 9 | nothing can glow, and nothing can fade a sprite, a line of text or a subtree |
| 10 | a scene cannot fade, so a transition cannot be written at all |
| 11 | music cuts rather than fades, cannot be paused, and a settings screen has one volume |
| 12 | every game with more than one scene writes its own deferred switch |

## Which roadmap item each step serves

| README item | Steps |
|---|---|
| better input-to-action mapping | 1, 7 |
| debug layer, connected to collision | 2 |
| collectable and interactable nodes | 3 |
| pushing and pulling objects | 4 |
| inventory and equipment screens | 5, 6, 8 |
| visual effects | 9, 10 |
| audio transitions | 11 |
| scene manager, teleports and room transitions | 12, 13 |
| cutscenes | 14 |

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

**Landed.** Four files and the drive script, as sketched. `rake spec` 3035
examples 0 failures, `rake spec:core` 476 examples 0 failures, `make test` 380
checks 0 failures. The driven run reports 240 ticks against 240 frames, one
scene pushed, 898 `tilemap` calls, 569 `sprite` calls, three clip rectangles —
the full window 271 times, each half 209 times — and no audio. Two runs are
byte-identical without a seed, because nothing in the project is random.

Rule 2 measures as `translates … y -103.0..298.0`. 298 is the fence's top edge
less the hero's height, with the feet box flush against it; player two holds
south for 140 ticks, which is 187 pixels of travel from y 240, so an unstopped
hero would end 129 pixels further south. Rule 1 measures as the clip count: 31
frames of one viewport, then 209 of two, with the room counting nothing.

What the sketch got wrong:

- **The project's name collides with a guard nobody thought about.**
  `spec/game_references_spec.rb` derives the forbidden words from
  `test_projects/`, and `examples/assets/README.md` records a Kenney pack titled
  *UI Pack - Pixel Adventure*. The spec now strips that title before matching,
  beside the `snake_case` strip that was already there. Every later step that
  adds a game keeps paying this: the guard treats a game's name as a word no
  other file may use.
- **`docs/project_structure.md` said test projects read from `media/`**, which
  this one does not — it reads the town map, its tileset and the hero sheet from
  `examples/assets/`. The entry now says they do not ship, so either directory
  is open to them.
- **No `CollisionWorld`.** The sketch's `blocked_by: [:tiles]` needs only a
  `TileWorld`; a `FeetCollider` in a scene with no broadphase stays a bare
  shape. Step 4's crate is what mounts the second index.
- **No `PlayerLayer`.** Nothing is drawn in screen space yet, so every layer in
  the report is in the `:world` band. The first step that adds a HUD splits
  that count.

---

## Step 1 — a hold, a tap and a chord

The signature change is cheapest now: `poll` has 3 call sites in `lib/` and 70
in `spec/`, and every step after this adds callers. A held button is also what
step 14 skips a cutscene with, so it wants to exist long before then.

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

**Landed.** Three sub-steps, one commit each, plus `examples/input_holds` and
the documentation. `make test` 380 checks 0 failures, `rake spec` 3095 examples
0 failures, `rake spec:core` 476 examples 0 failures, `rake docs:coverage`
nothing undocumented.

The driven run of the example reports 240 ticks against 240 frames, 1200 `text`
calls, 510 `rect`, one clip per frame, three translates and three sounds — one
per event. The budgets are the measurement, and its drive script records them:
0 sounds at 55 ticks, 1 at 56 when the hold reaches 0.6 s, 2 at 111 when a
release comes inside 0.3 s, 3 at 171 when the chord's second button arrives.
Rule 4 is the count still reading 1 at tick 110: the first press was held for a
second, so its release pressed nothing. Rule 6 is the `rect` count — the shield
draws for the 30 ticks its button is held alone and not for the 30 inside the
chord, so 510 rather than 540. The `--gamepad` run reports the same totals with
each event a tick or two later, which is SDL's own latency.

Every other driven example and test project reports what it reported on `main`,
byte for byte: 42 comparable runs. `test_projects/snake` and
`test_projects/asteroids` seed themselves from `Random.new` when `RGAME_SEED` is
unset, so two runs of *the same* code differ; they were compared under
`--seed 4242`.

What the sketch got wrong:

- **A chord cannot name one device, so `all:` takes a chord per device.** Every
  id of a chord has to be down at once, so a list naming a key and a pad button
  can never be pressed, and a game serving both devices would declare two
  actions with one meaning. `all:` now takes a chord or a list of chords, as
  `axis:` takes a pair or a list of pairs. The example is what exposed it: with
  one list, the `--gamepad` run exercises no chord at all.
- **`held_for` survives the tick of the release.** The sketch zeroed it on the
  poll that sees the buttons up, which is the tick `released?` is true — so
  `released?(:door) && held_for(:door) > 1.0` would read zero. It is zeroed on
  the tick after, which is what rule 1 said and the sketch's code did not do.
- **The poll counts before it decides.** The sketch's order made a hold fire one
  tick after its threshold. Counting first fires it on the tick the threshold
  passes, and the tap still reads the right duration because the count outlives
  the release.
- **`Struct.new(:tap)` overrides `Kernel#tap`.** `Lint/StructNewOverride` is
  disabled on that line with the reason: the member is named after the entry key
  it holds, and nothing in the engine taps a `Binding`.
- **Adding `let(:step)` to `players_spec.rb` put four groups over
  `RSpec/MultipleMemoizedHelpers`**, disabled for the file with a reason.

Two things this step deliberately left alone. `Components::ActionTrigger` and
`UI::Menu`'s `trigger:` still count their own seconds: a repeat on a cooldown
and a menu held open are not a threshold on a press, and step 13's "hold to
skip" is the case that will say whether either wants `held_for`. Sequences and
double taps stay out, as decision 3 says; step 14 records them in
`possible-todos.md`.

Documented in [docs/api/input.md](../../api/input.md) — the sources table, a
section on what each of the three declares, and the timestep `poll` takes — and
in `CHANGELOG.md`, which lists the three as added and the poll signature as
changed.

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

**Landed.** Three sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3136 examples 0 failures, `rake spec:core` 477 examples 0 failures,
`rake docs:coverage` nothing undocumented.

`RGame::Engine::Debug` is the system, mounted on the root beside the other four.
It holds `show`, `hide`, `toggle`, `shows?`, `channels` and `define`, and draws
the `:stats` overlay and every defined channel's block in the `:debug` band.
`DebugOverlay` keeps no flag of its own any more: `Debug` decides, and calls
`restart` when the channel goes on. `Game` gained `debug`, `debug_keys` and F3,
and `needs_redraw?` reads `shows?(:stats)`.

The acceptance run is `test_projects/adventure`. Its report matches `main` line
for line — 240 ticks against 240 frames, one scene pushed, 898 `tilemap`, 569
`sprite`, three clip rectangles, translates spanning y -103.0..298.0, no audio —
with two lines added: **26493 `debug_box` calls and 1074 layers in the `:debug`
band**. `--ticks 61` reports no shapes and `--ticks 62` reports one frame of
them, six layers: each hero's feet box and the map's solid cells, twice over for
the two viewports. Every other driven example and test project reports what it
reported on `main`, byte for byte: 42 comparable runs, with `asteroids` and
`snake` under `--seed 4242`.

What the sketch got wrong:

- **The adventure could not bind F3.** `Game` binds it to the same channel, and
  the two would toggle it twice per press and cancel out — the run would look as
  though nothing were bound. The project's own `debug` action is on F4 and
  `PAD_BACK`, and the switch lives in a `DebugToggle` component on the shell
  rather than in a node of the room, because a debug switch belongs to the
  project rather than to any one scene.
- **`:shapes` needed no `debug_circle` in the adventure**, but the contract did:
  the example that exercises a `CircleCollider` is a spec, not a driven project,
  because nothing under `examples/` or `test_projects/` mounts one on a scene
  with a debug layer. The renderer's colour constant lost its box in the same
  commit — `DEBUG_BOX_COLOR` is `DEBUG_COLOR`, since a box and a circle share it.
- **A `WorldView` has to look its `TileWorld` up in `_enter_tree`**, which means
  a scene that mounts the world *after* the view draws no cells. Every scene in
  the repository mounts it first, and `TileMapLayer` already depends on the same
  order, so the alternative — a lookup per viewport per frame — bought nothing.
- **Occupied cells need no separate channel.** `TileWorld#solid?` already counts
  a cell `OccupiesCell` marks, so the sub-step's "solid and occupied cells" is
  one loop and one colour. A spec pins it rather than the code distinguishing
  them.
- **`QuietRenderer` had no `clipped`**, so a `WorldView`'s whole `draw` could not
  be measured for allocations at all. It yields now, like `layered` and
  `translated`.

Documented in [docs/api/systems.md](../../api/systems.md#debug--a-switch-per-channel)
— the system, its two channels and `define` — with the keys in
[game.md](../../api/game.md#the-development-keys), the shapes in
[components.md](../../api/components.md#boxcollider), the cells in
[scene_graph.md](../../api/scene_graph.md#view-transforms-and-the-camera) and
`debug_circle` in [drawing.md](../../api/drawing.md#shapes).

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

**Landed.** Three sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3171 examples 0 failures, `rake spec:core` 477 examples 0 failures,
`rake docs:coverage` nothing undocumented.

`Components::Interactor` is a `Targeting` plus `_control`, and `:interact` is in
`InputMap::DEFAULT_ACTIONS` on E and the pad's X — a button nothing else in that
map uses. `Components::Collectable` connects to its own node's collider and acts
on the step a collider on the `by` layer touches it. Their two specs are 34
examples between them, and rule 7's is one that fails without the `_detach`:
`expected: 2, got: 3`.

The acceptance run is `test_projects/adventure`, and it reports **"chest" from
tick 0, "open" from 150 and "searched" from 206** on `--texts`. Both numbers are
the thresholds rather than the script: `interact`'s tap fires on the release of a
two-tick press at 148, and `search`'s 0.6 s is 36 ticks after the hold begins at
170. That is steps 1 and 3 meeting on one button, and nothing in a spec says it.
The rest of the report keeps step 2's numbers — 240 ticks against 240 frames, one
scene pushed, 898 `tilemap`, 569 `sprite`, three clip rectangles — and adds 678
`circle`, 449 `rect`, 449 `text`, 314 `debug_circle` and 4 sounds. Every other
driven example and test project reports what it reported at the branch point,
byte for byte.

`examples/collectables` reports "Coins: 0" through "Coins: 4" with no number
skipped, at ticks 0, 43, 87, 155 and 216, four sounds, and 1287 `circle` calls —
the coin count integrated over the run, which is the number that says the chest
spilled three.

What the sketch got wrong:

- **`require_sibling(BoxCollider)` would have made every collectable a
  rectangle.** A coin is round, and `CircleCollider` answers the same contact
  protocol, so the sketch's line ruled out the commonest pickup there is.
  `Components::Collider` is the module both include and the thing `Collectable`
  asks for; a node carrying both raises, which is `require_sibling`'s existing
  answer to an ambiguous match. The adventure's coins are circles for this
  reason, and that is also what gave `debug_circle` its first driven exercise —
  step 2 landed it with a spec and no project that mounts one.
- **`@collider.hit_signal.disconnect(@handle)` cannot be written.** The DSL keeps
  `hit_signal` private, deliberately, because emitting belongs to the class. The
  design's `_detach` would have raised `NoMethodError` on the first pooled node.
  `signal :hit` now also generates a public `disconnect_hit(handle)`, which is
  the smallest change that serves every signal in the engine rather than adding
  an escape hatch to the two colliders. **This is the trigger
  `possible-todos.md` records** under "A connection that ends with its node" —
  the second component that has to write the same `_detach` — and it is still
  open: the disconnect is now *possible*, not automatic.
- **The room needed a `CollisionWorld`, which step 0 expected step 4 to add.**
  A coin is a contact and a chest is a range query, and both read a broadphase
  the map alone never needed. Step 4's crate now arrives to an index that exists.
- **A tap and a hold cannot both be one `Interactor`.** One component per class
  per node, and `action:` is a single action, so the adventure's hold is read by
  the hero's own `_control` off `interactor.target`. That is what `target` being
  public is for, and it is the shape a game with three verbs on one target takes.
  Whether `Interactor` should take several actions is worth asking once something
  needs it twice.
- **A drive script under `tools/drive/test_projects/` cannot keep a comment.**
  Every comment in one is deleted when it is committed, so the adventure's
  script carries no header however often one is written — which is why every
  script in that directory has none and every script under
  `tools/drive/examples/` has one. The
  [write-example](../../../.claude/skills/write-example/SKILL.md) skill asks for
  a header stating what the report should show, so for a test project that
  statement lives here instead, in the landed note. The numbers above are it.
- **The generated disconnects broke `rake docs:coverage`**, which counts a
  public method as documented when its name appears in `docs/api/`. Naming every
  `disconnect_*` would say the same thing once per signal, so the check now reads
  one as documented when its `on_*` is — the rule it already applies to a setter
  and its reader.

Documented in [docs/api/components.md](../../api/components.md#interactor) —
`Interactor`, `Collectable` and `Collider` — with the default action in
[input.md](../../api/input.md#defaults-and-rebinding), the generated disconnect
in [signals.md](../../api/signals.md#the-dsl-declaring-a-signal-on-a-class), and
the example in [examples.md](../../api/examples.md#collectables).

Open question 3 — *does `Interactor` stay a subclass of `Targeting`?* — waited on
this step and is answered yes. Nothing in the step wanted a facing-aware policy,
and the subclass cost exactly one documented consequence: `get_component`
matches both, so a node holding both is asked by name.

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

**Landed.** Three sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3224 examples 0 failures, `rake spec:core` 477 examples 0 failures,
`rake docs:coverage` nothing undocumented.

`pushes:` is on `Mover`, so all four movers take it — `CharacterBody`,
`Velocity`, `PathFollow` and `Navigator` — and `Components::Pushable` is the
fourth kind of mover, one with no step of its own. `Components::Grab` is a
`Targeting` plus a held button, and `:grab` is in `InputMap::DEFAULT_ACTIONS` on
Left Shift and the pad's Y. `ActorBlockers` gained `passing`, which is what a
drag needs. `pushable_spec.rb` and `grab_spec.rb` are 40 examples between them,
and the `a mover` group adds three on `pushes:` to each mover's spec.

**Rule 1 holds across every driven run, not just the two.** All 45 drive scripts
on `main` — every example, every test project, the gamepad runs — report what
they reported there, byte for byte, after 4a. At the end of the step 44 still
do, and the one that differs is the adventure, because it grew. Every run was
compared under `--seed 4242` and 240 ticks.

`examples/push_pull` reports "Holding a crate" from tick 86 for 40 frames, the
length of the Shift hold exactly. `examples/block_puzzle` reports "Blocks home:
1 of 2" from tick 197 and "Solved!" from tick 597. The adventure's crate draws the
way it last moved, and `--texts` reports **"crate" from tick 0, "east" from 111
and "west" from 189**: player two pushes it along the fence, then holds Y and
pulls it back. The chest still reads "open" from 150 and "searched" from 206,
with four sounds, so the crate changed nothing it does not touch.

What the sketch got wrong:

- **Rule 7 is inverted: a layer in `pushes:` but not `blocked_by:` raises.** The
  sketch had it walked through, pushing nothing, with the docs asking for both.
  That is a rule the caller must remember, and the failure is silent — a crate
  the hero walks through. `Mover#initialize` raises `ArgumentError` naming the
  layer, and does the same for `:tiles` and `:bounds`.
- **A pushing mover resolves its axes in two moves.** `CollisionSystem#move`
  resolves X then Y in one call, so a crate met on X would still stand where it
  was when Y is resolved. A mover with `pushes:` calls it once per axis. One
  without calls it once, as before, which is how rule 1 stays byte-exact.
- **Pulling cannot move the crate first and clamp the mover.** The design's order
  deadlocks against a crate that is `blocked_by` its puller, which is what a
  crate must be for two players to hold it still from either side: the crate
  steps into the hero and moves nothing. Backing into a wall with the order
  reversed leaves the crate inside the hero. What shipped: the crate moves
  first, passing the mover; the mover follows as far as the crate went, passing
  the crate; and the crate comes back by whatever the mover fell short. That
  needed `ActorBlockers#passing`, and it widened `push`'s `by:` from "never
  pushed back" to "neither pushed back nor stopped by".
- **A crate's blockers are counted from one of its updates to the next.** Its
  pushes arrive during other movers' updates. With `Mover#_update`'s bookkeeping,
  a hero that updates after its crate made the crate report `on_unblocked` and
  `on_blocked` against the wall every tick. `Pushable` replaces `_update`, which
  `Mover`'s header had said nothing does.
- **A pushed crate re-indexes itself.** A crate declaring only `:tiles` has no
  `ActorBlockers` to re-bucket it after a move, so a mover resolving later in the
  same step would look for it in the cells it left. `Pushable#push` calls
  `CollisionWorld#reindex` whatever the crate declares.
- **A crate that went the whole way can still be reported, by rounding.**
  `x + w` after a snap need not equal the edge it snapped to, so the pusher's
  second resolve may name a crate that was not in the way. The pusher drops the
  crate when `Pushable#stopped?` says it was not cut short. A drag's correction
  likewise runs only when something stopped the mover, not whenever two floats
  differ.
- **`Grab` is a `Targeting`, the third.** The sketch's `pushable_in_reach` is the
  question `Targeting` answers, so `Grab` extends it, as `Interactor` does. It
  keeps what it took until the action is let go. One consequence surfaced:
  `Targeting` measures range from the node's origin, which for a sprite node is
  its top-left, so reach is lopsided — the adventure's hero needs a larger grip
  than a centred one would, and `examples/push_pull` puts its hero's origin at
  its centre instead.
- **The grid puzzle's listener cannot learn the block from `on_blocked`.** A block
  is a solid cell, so what stopped the hero is `TileBlockers::TILES`, which names
  no cell. The example works the cell out from the hero's position and heading.
  Nothing else in the design changed: `OccupiesCell`, a `Tween` and
  `TileWorld#solid?` are all it needs.
- **A node's HUD drawn from a scene that holds a `WorldView` is under the map.**
  `examples/block_puzzle`'s count was invisible until it moved to a node in the
  `:hud` band. `examples/pathfinding` on `main` draws its help lines the same
  way, and a captured frame shows none of them. That is recorded under the open
  questions rather than fixed here.

The caller that uses both is in `pushable_spec.rb`. A crate a hero pushes onto a
route a `Navigator` planned leaves a walker `blocked_by` crates standing behind
it for good, `on_blocked` by the crate's collider, because the route was planned
over the map and a crate is a collider. A walker that declares `pushes:
[:crate]` shoves it along the route and finishes.

Documented in [docs/api/components.md](../../api/components.md#pushable) —
`Pushable`, `Grab`, and `pushes:` and dragging under `Mover` — with the default
action in [input.md](../../api/input.md#defaults-and-rebinding), `passing` in
[internals.md](../../api/internals.md), and both examples in
[examples.md](../../api/examples.md#push_pull). `puzzle.tmx` is recorded in
`examples/assets/README.md`.

---

## Re-planning steps 5–7

Steps 5, 6 and 7 were re-planned at `3526096`, after step 4 landed. Reading the
code overturned three things the design recorded, and one question was settled.

### What was measured

| | |
|---|---|
| `rake spec` | 3224 examples, 0 failures, 25.2 s |
| `spec/rgame/engine/ui/` | 538 examples, 6.1 s |
| Menus built in `examples/` and `test_projects/` | 10, in 7 files |
| Scenes where one player has two open menus at once | **0** |
| Two open menus under one owner, after one `ui_down` and one `ui_confirm` | **both move focus, and both activate a button** |
| Readers of `layout.axis` | 1, `Stepping#attach` |
| Buttons whose `adjust` can answer anything but nil | 1, `OptionButton` |
| `Menu` subclasses | 2, `PanelMenu` and `RadialMenu`; `DialogueBox` holds a `Menu` |
| Default actions on the candidate tab keys | `E` is `:interact`, Left Shift is `:grab`; three examples bind Tab |

The fifth row shapes step 5. A script built two `Column` menus under one root
and pressed `ui_down`, then `ui_confirm`. Focus moved in both, and two buttons
activated. Nothing in the repository has met this, because the fourth row is
zero. A focus group therefore has to decide which menu reads input, and not only
where focus goes next.

### What the design got wrong

- **`Layout.each_cell` is not the grid's arithmetic.**
  [F8](01-current-state.md#f8) called it usable as it stands. It divides a known
  total into even cells, which suits viewports. A grid places fixed-size slots
  with spacing, and its total is the answer rather than the input. `UI::Grid`
  computes what `UI::Stack` computes, over rows.
- **A tab bar is a menu.** The design put `UI::Tabs` in the "genuinely new"
  pile. Its bar holds buttons, places them with a layout, scopes their labels,
  marks one, and steps between them, skipping disabled ones and wrapping. That
  is a `Menu` over `Stepping`, with two other actions and no confirm. The
  pages are held off the child list, the way `SceneStack` holds its scenes. So
  `Tabs` holds a `Menu` for its bar and adds the pages, and neither is new.
- **A group needs a current menu**, not only a way to cross. With the design's
  group, both menus would still read every press. So a group names one
  `current` menu, and a menu in a group that is not current reads no input.
- **A new `current` reads nothing until the next tick.** `Node2D#control`
  controls a group's menus one after another from one snapshot, and crossing
  happens inside the current menu's `_control`. A menu later in the tree would
  then read the press that crossed into it, and step again. A group therefore
  fixes which menu reads before any of them does.
- **A direction a column has no use for has to cross as well.** A bag grid
  beside a column of equipment slots is the equipment screen. In the column,
  left and right go to the focused button's `adjust`, and a plain button adjusts
  nothing. So the group also takes a direction the focused button does not
  adjust. That needs `Button#adjustable?`. Reading nil from `adjust` fails:
  `OptionButton#adjust` answers nil at the end of its values, and a volume row
  at its maximum would jump to the next menu. A game's own slider overrides
  `adjust` and would forget a second method, so `adjustable?` is worked out
  from whether a class overrides `adjust`.

### Decided in this re-plan

- **Q and E switch tabs on a keyboard**, beside the shoulder buttons. See
  [open question 2](README.md#open-questions).
- **`examples/equipment` draws its clothes in code.** No new asset ships.
- **`examples/inventory` lands with step 5 and grows in step 6**, so each UI
  step has a driven run of its own. Step 8 keeps `examples/equipment` and the
  adventure's bag.
- **A screen that opens is a `Tabs` that opens.** `Node2D#visible` was
  considered, because three things want a subtree left undrawn: a closed menu, a
  page not shown and a closed screen. Each of the three also wants its input
  stopped. Two flags a game must set together is the remembered rule this
  project refuses, so `Tabs` gets `open` and `close`, as `Menu` has.

### Three piles, for the UI steps

- **Reuse:** `Menu`, the skipping and wrapping in `Stepping#step`, `PanelMenu`,
  `IconButton`, a button's focused look for the shown tab, `PlayerLayer`,
  `SceneStack`'s way of holding scenes off its child list for the pages, and
  pausing a hero while their bag is open, as
  `test_projects/tiled_world/inventory.rb` does.
- **Extend:** `Stack` → `Grid`, the same slots over rows, as a subclass
  sharing one arithmetic. `Stepping` → a grid, and two named actions for a tab
  bar. `Menu` → `confirm:`, `current?` and a window of rows. `Button` →
  `adjustable?`.
- **Genuinely new:** `FocusGroup`, which decides which of one player's menus
  reads input. Nothing in the engine holds more than one menu for one player.

---

## Step 5 — the grid, and focus that crosses menus

Steps 6 and 8 lay everything out on a grid, and an equipment screen is two
menus that one player moves between. The step also closes the defect measured
above: two open menus under one player both answer every press.

### Sub-steps

- **5a** — `UI::Grid`, and `Stepping` moving across and down it.
- **5b** — `UI::FocusGroup`, `Menu#current?`, `Menu#group` and
  `Button#adjustable?`.
- **5c** — `examples/inventory`: a bag grid, a column of verbs beside it, and a
  panel naming the focused item. Its `locales/en.yml`, its drive script
  `tools/drive/examples/inventory.rb`, an `### inventory` entry in
  `docs/api/examples.md` and a row in `README.md` come with it.

### Shape

```ruby
grid = UI::Grid.new(columns: 4, item_width: 64, item_height: 64, spacing: 6)
grid.columns            # 4
grid.axis               # :horizontal — the order it fills in

group = layer.add_node(UI::FocusGroup.new)
bag   = group.add_node(UI::PanelMenu.new(x: 16, y: 48, layout: grid))
verbs = group.add_node(UI::PanelMenu.new(x: 340, y: 48,
                                         layout: UI::Column.new(item_width: 120, item_height: 32)))

group.menus             # [bag, verbs], in the order they joined
group.current           # bag: the first open menu with an enabled button
group.current = verbs   # verbs reads input from the next tick
group.cross(:right)     # current moves to the neighbour that way; false, and nothing moves, if none
bag.current?            # false: it draws, focuses nothing and reads no input
bag.group               # the group it joined, or nil

button.adjustable?      # false on a Button; true on any class that overrides adjust
```

**A menu joins the nearest `FocusGroup` above it** as it enters the tree, and
leaves it on exit. Nothing registers by hand, and a menu wrapped in a panel node
still belongs to the group around the panel. `Menu` joins in `enter_tree`
itself, not in the `_enter_tree` hook, so a game's subclass that overrides the
hook stays in its group.

**Three menus refuse a group**, and raise `ArgumentError` as they join one. A
menu with a `trigger:` opens only while its trigger is held, so a group could
never make it current. A `DialogueBox` holds a menu that advances its
conversation, and a group would stop it whenever another menu is current. And a
menu that answers to a different player than the group's others would never
read its own player's input.

**`Grid` is a `Stack` whose lines hold `columns` slots.** A `Column`'s lines
hold one slot, and a `Row`'s one line holds them all. One arithmetic places all
three, so `Grid < Stack` adds a line length and nothing else.

On a layout that answers `columns`, `Stepping` moves along the row with the
layout's axis pair and down the column with the other pair. Nothing in a grid is
adjusted. `step(delta)` moves along the row.

**`Stepping` asks the group before it wraps.** At the end of a line, and on a
direction the focused button is not `adjustable?` in, it calls
`menu.group&.cross(direction)` and wraps only when that answers false. A game's
own `Navigation` crosses the same way. `Pointing` never crosses.

**`adjustable?` is worked out once per class**, from whether the class
overrides `adjust`. A game's own slider then needs nothing more than the
`adjust` it already writes.

### The rules the tests pin

For the grid:

1. **A grid fills rows left to right, top to bottom**, `columns` to a row. Its
   bounds enclose the rows it uses, so a single short row is as wide as its
   buttons.
2. **Left and right step along the row, and up and down along the column.** A
   step down or up onto a row with no button in this column takes that row's
   last button.
3. **A step skips disabled buttons along its line**, and goes on to the next
   one.
4. **Past the end of a line, a step wraps inside it**, unless a group crosses
   it (rule 11). The end is where no enabled button is left before the edge. A
   line with no other enabled button leaves focus where it is.
5. **An explicit `axis:` other than the grid's raises** `ArgumentError`.
6. **`Column`, `Row` and `Ring` step as before.** The existing examples in
   `stepping_spec.rb` and `stack_spec.rb` pass unchanged.

For the group:

7. **One menu in a group is `current`, and only it reads input**: navigation,
   hotkeys and confirm. The others draw with nothing focused. The measured case
   is a test: one `ui_confirm` activates one button.
8. **`current` starts on the first menu to join that is open and has an enabled
   button**, and is nil while none has.
9. **Each tick, before its menus read input, a group re-checks `current`.** A
   current menu that is closed, has no enabled button or has left the tree
   hands over to the first that qualifies.
10. **Every change of `current` follows one rule**, whether a crossing,
    `current=`, a hand-over or the first menu to join made it. The menu left
    clears its focus and reads nothing more that tick. The menu entered reads
    no input until the next tick, and no confirm until it has seen confirm up.
    Its navigation decides where focus starts: `Stepping` takes the enabled
    button nearest the one left, or its first enabled button.
11. **A step past the end of a line crosses to the neighbour that way.** Only a
    group with no neighbour in that direction wraps.
12. **A direction the focused button is not `adjustable?` in crosses too.**
    From a column of plain buttons, left and right cross. On an `OptionButton`
    they adjust, even at the end of its values, and so they do on a game's
    button that overrides `adjust`.
13. **The neighbour is the nearest menu wholly beyond the current one's edge**
    in that direction. The gap between the two decides; the distance between
    centres across it breaks a tie. A closed menu and a menu with no enabled
    button are never neighbours.
14. **One press crosses once**, whichever of the two menus comes first in the
    tree. A grid above a column and a column left of a grid each land on the
    nearest button, not the one after it.
15. **`focus(index)` on a menu that is not current makes it current**, by
    rule 10, on the button asked for. A navigation never focuses a menu that is
    not current, so buttons added to one focus nothing there. Stepping's "focus
    is never empty" holds for the current menu.
16. **`current=` raises** `ArgumentError` for a menu outside the group.
17. **A menu with a `trigger:`, a `DialogueBox` and a menu of another player
    raise** `ArgumentError` as they join.
18. **Two players move in their own groups**, each in its own `PlayerLayer`.
19. **Stepping a grid, crossing, and a group's check each tick allocate
    nothing.**

### Tests

- `spec/rgame/engine/ui/grid_spec.rb`: rule 1 for a full grid, a short last row,
  a single row and no buttons.
- `spec/rgame/engine/ui/stepping_spec.rb`: a `describe 'across a grid'` group
  for rules 2–5.
- `spec/rgame/engine/ui/focus_group_spec.rb`: rules 7–18, with a grid and a
  column side by side, the same pair in the other tree order, a closed menu
  between two open ones, and a menu wrapped in a plain node.
- `spec/rgame/engine/ui/button_spec.rb` and `option_button_spec.rb`:
  `adjustable?`, and a `Button` subclass that overrides `adjust`.
- `spec/rgame/engine/ui/menu_spec.rb`: a menu outside any group is always
  `current?`, and its `group` is nil.
- `spec/rgame/engine/ui/focus_group_allocation_spec.rb`: rule 19.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/inventory/main.rb --ticks 300 --texts
```

`examples/inventory` holds eight items from `skills.json` and `icons.json` in a
four-column grid. Its slots are 64 pixels, the size of the larger atlas's
icons. Beside it stands a column of two verbs, use and drop, and a panel names
the focused item. The bag's buttons draw no captions, so the panel is the only
place an item's name is drawn as text. Crossing clears the bag's focus, so the
example keeps the item last focused there, and the verbs act on that one.

The drive script walks right along the first row and on into the verbs, drops
the item, and comes back left into the bag. It then presses up, which wraps
inside the column because nothing lies above.

`--texts` keeps a count and the tick a string first appeared, not the tick it
last did. So the script's header lists `--ticks` checkpoints and what each
report shows, as `tools/drive/examples/skill_bar.rb` does. Each item's name
first appears as focus reaches it, and the dropped item's count stands still
from the drop on. Rule 15 is pinned by its spec, not by this run: a bag
rebuilt while the verbs are current and focusing its first item again would
only raise a count the report already has.

`docs/api/ui.md`'s "What this is not" says there is no grid, which stops being
true here.

**Landed.** Three sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3315 examples 0 failures, `rake spec:core` 477 examples 0 failures,
`rake docs:coverage` nothing undocumented.

`UI::Grid` is a `Stack` that overrides one private method, the number of slots a
row holds, and `Column`, `Row` and `Grid` now place and bound their buttons with
one arithmetic. `Stepping` reads `columns` from a layout that answers it.
`UI::FocusGroup` holds the menus that joined it and the one that reads.
`Menu#current?`, `Menu#group` and `Button#adjustable?` are as sketched. The
focus group's spec is 49 examples, and its allocation spec measures the check
each tick, stepping a grid on both axes, and a crossing there and back, at
zero objects each.

The acceptance run is `examples/inventory`. `--texts` reports each item's name
from the tick focus reached it: Wrench from 21, Torch from 33, Hammer from 45.
"Used: Hammer" from 70, with the first click, is the crossing at the end of the
row. Had the row wrapped, Enter would have confirmed the Wand in the bag, which
does nothing. Hammer stops at 49 frames from the drop on tick 93. The crossing
back lands on the Watering can at 115, which the drop moved into the first
row's last slot, nearest Drop. Up at 136 wraps to the Gear at 137, the short last
row's last button, because no menu lies above the bag. 300 ticks against 300
frames, two clicks. The layout was also checked by eye, from frames captured
with `xwd` on a private Xvfb: the bag focuses nothing while the verbs are
current, and the panel keeps the item's name.

**Every menu that existed steps as it did.** All 47 drive scripts at the branch
point, every example, test project and gamepad run, report what they reported
there, byte for byte, under `--seed 4242`, 240 ticks and `--texts`. The first
capture of the adventure's baseline drew 238 frames against 240 ticks, the
fixed-timestep loop skipping two draws. A rerun matched the branch exactly.

What the sketch got wrong:

- **"Until the next tick" is counted in the group's own control passes.** A
  group has no tick number to read, so it counts the passes of its `control`
  and remembers the pass `current` changed on. A crossing, a hand-over and a
  `current=` from `update` all read from the next tick, as rule 10 says. A
  `current=` from a node the tree controls *before* the group reads in the same
  tick. Confirm still waits for confirm up, so only a navigation press could be
  read twice that way, and nothing in the repository sets `current` from there.
- **The navigation needed a fourth call.** Rule 10 has the navigation decide
  where focus starts, and the interface had no call for it. `Navigation#entered(from)`
  is it, with the button focused in the menu left. The base class focuses
  nothing, `Pointing` inherits that, and `Stepping` takes the nearest enabled
  button. With no button left, `Stepping` keeps an enabled focus the game set
  before the menu joined, rather than moving it to the first button.
- **The menu and its group talk through three `@api private` methods.**
  `FocusGroup#join`, `#leave` and `#reading?`, and `Menu#enter_from`, which
  resets the confirm wait and calls `entered`. None of them is a hook, so a game
  subclass of `Menu` could replace `enter_from` without a guard noticing. The
  seal covers only `Node2D` and `Component`.
- **A menu leaving the tree hands over on the next check, not at once.** When a
  whole group leaves, its menus leave one by one, and handing over at each exit
  would focus buttons, and play a game's focus sound, on a screen that is
  closing. `leave` clears `current`, and rule 9's check picks the next menu.
- **The player check reads `input_owner` up the tree, not `abs_input_owner`.**
  The resolved owner is only current once `control` has run, and a menu joins in
  `enter_tree`, before that.
- **A group knows a dialogue box's menu by its parent's class.** `join` refuses
  a menu whose parent is a `DialogueBox`. No keyword on `Menu` says "may not be
  grouped", because that would be a rule for the box's author to remember.
- **The first spec let the menu left press a hotkey after crossing.** Its focus
  was cleared, so confirm found nothing to press, and every example passed with
  the check for "still current" deleted. A mutation found it, and an example
  pressing a hotkey on the crossing tick now pins it.
- **`toolbox.md` said "The engine has no grid class of its own"**, about grids
  of values. It now says the engine holds a grid of values in no class of its
  own, since `UI::Grid` holds none.
- **RuboCop wanted two changes.** `FocusGroup#cross` answers true or false and
  is a command, so `Naming/PredicateMethod` is disabled on it with a reason, as
  on `Navigator#go_to`. `Game/NoNeedlessAllocation` refused a `%w[...].each` at
  the top level of the example, and three lines replace it.

For step 7: a group's menus that are not current are still controlled every
tick, and only their `_control` returns early. The press gate will not see them
as resuming, so the group's own rule stays, as `Menu`'s confirm wait does.

Documented in [docs/api/ui.md](../../api/ui.md#rgameengineuifocusgroup) — the
grid in the layouts table, stepping across a grid and in a focus group, the
group itself, and `current?`, `group`, `adjustable?` and `entered` in their
tables — with the example in [examples.md](../../api/examples.md#inventory), a
row in `README.md`, and three entries in `CHANGELOG.md`.

---

## Step 6 — tabs, and scrolling

A bag outgrows its panel once a game has more than a dozen things, and an
equipment screen is a second page beside the bag. Step 8 is built from both.
Both also change what a menu draws, so they land before any example depends on
them.

### Sub-steps

- **6a** — `confirm:` on `Menu`, `actions:` on `Stepping`, and `ui_tab_prev`
  and `ui_tab_next` in the universal set.
- **6b** — `UI::Tabs`.
- **6c** — `visible_rows:` on `Column` and `Grid`, and a menu that keeps its
  focus in view.
- **6d** — `examples/inventory` grows a page of key items and a bag longer than
  its panel, with a second drive script, `inventory_pad.rb`.

### Shape

```ruby
# In InputMap::UI, beside ui_confirm
ui_tab_prev: { buttons: [Controls::KEY_Q, Controls::PAD_LEFT_SHOULDER] },
ui_tab_next: { buttons: [Controls::KEY_E, Controls::PAD_RIGHT_SHOULDER] },

row   = UI::Row.new(item_width: 96, item_height: 28)
tabs  = layer.add_node(UI::Tabs.new(x: 16, y: 8, layout: row, scope: 'inventory'))
items = tabs.add(UI::PanelButton.new(label: 'items'), UI::FocusGroup.new)
keys  = tabs.add(UI::PanelButton.new(label: 'key_items'), UI::FocusGroup.new)

tabs.current            # items: the page shown
tabs.current = keys     # what a press of E does
tabs.on_changed { |page| ... }
tabs.open? ; tabs.open ; tabs.close
tabs.on_opened { ... } ; tabs.on_closed { ... }

# What Tabs builds its bar from, which a game may use alone
UI::Menu.new(layout: row, confirm: nil)                  # nothing confirms it; hotkeys still work
UI::Stepping.new(actions: %i[ui_tab_prev ui_tab_next])   # steps on these two, adjusts nothing, never crosses

grid = UI::Grid.new(columns: 4, item_width: 64, item_height: 64, spacing: 6, visible_rows: 3)
bag.first_row           # the top row in view
bag.rows_above          # 0 at the top; what a game draws a scroll arrow from
bag.rows_below
```

**The universal set shares buttons with games, as it already does.** Space is
both `ui_confirm` and `fire`. A game that chords the two shoulder buttons, as
`examples/input_holds` does, now also silences both tab actions while the chord
is held, and pressing the left one first shows the previous tab.

`Tabs#add(button, page)` puts the button in the bar and the page under the tabs,
and returns the page. A page is any node. `Tabs` places each page's origin at
the bottom of the bar's bounds, so a page's own `y` of 0 starts under the tabs.
The bar is the tabs' own and nothing outside reaches it, so no `add`, `clear`
or `close` on it can leave a tab without its page. Its focused button is the
shown tab, so a tab draws its focused look while the bar never reads
`ui_confirm`. `current` is read off that focus, so the two cannot disagree.

**Pages live off the child list**, the way `SceneStack` holds its scenes. Each
page's `parent` is the tabs, and each enters and leaves the tree with them.
`Tabs` controls and draws the page shown, and updates every page. The shown page
is controlled before the bar, so a switch takes effect from the next tick.

**`Tabs` bounds focus groups.** Its bar joins none. A menu inside a page joins a
group inside that page or none, because the search for a group stops at the
tabs. So a crossing never lands on the bar or on a hidden page. The bar can read
input beside a page's current menu because the two read different actions. A
`Tabs` inside another's page raises `ArgumentError`, since one press would
switch both.

A layout built with `visible_rows:` answers `visible_rows` and takes
`arrange(buttons, first_row)`, placing the row in view at the menu's origin.
`Menu` calls it that way and leaves the rows outside the window undrawn. A
layout without `visible_rows`, a game's own included, is called as today.
`first_row` belongs to the menu, because one layout may serve several menus.

### The rules the tests pin

For tabs:

1. **`ui_tab_next` and `ui_tab_prev` show the next and the previous enabled
   tab**, wrapping, and emit `on_changed` with the page shown.
2. **Only the shown page is controlled and drawn. Every page is updated.** A
   page keeps its state while hidden, so a menu's focus is where the player left
   it. Hiding is not pausing, as closing a menu is not: a button's pressed look
   runs out while its page is hidden.
3. **A page shown is first controlled on the next tick.** E and confirm on one
   frame switch the page and activate nothing on it.
4. **The first enabled tab's page is shown first.**
5. **`current=` does what a press does**, emits only on a change, and raises
   `ArgumentError` for a page the tabs do not hold.
6. **A tab's hotkey shows its page.**
7. **A closed `Tabs` draws nothing, and nothing under it reads input.** It still
   ticks, as a closed `Menu` does. `open` and `close` emit only on a change, and
   a `Tabs` starts open.
8. **`ui_confirm` never reaches the bar.** A menu built with `confirm: nil`
   activates nothing on a confirm, and `confirm:` naming another action confirms
   on that one.
9. **`Stepping.new(actions:)` reads those two actions and nothing else**,
   adjusts nothing and never crosses. Anything but two action names raises
   `ArgumentError`.
10. **The bar joins no group, and a page's menus join none above the tabs.** A
    `Tabs` inside another's page raises `ArgumentError`.
11. **Two players switch their own tabs.**

For scrolling:

12. **A menu over a layout with `visible_rows:` draws that many rows.** Its
    bounds are the whole window's, however many rows are filled, so a
    `PanelMenu`'s panel keeps its size as items come and go. A layout without
    `visible_rows:` keeps step 5's rule 1.
13. **Every change of focus scrolls the focused button into view**, by the
    fewest rows, whether navigation, the game's `focus` or a group crossing made
    it. A wrap from the last row to the first scrolls to the top.
14. **A crossing into a scrolled menu lands on the nearest enabled button in
    view.**
15. **`rows_above` and `rows_below` count the hidden rows** on each side, and
    are 0 when every row fits.
16. **`clear` scrolls to the top.**
17. **Switching tabs and scrolling allocate nothing.**

### Tests

- `spec/rgame/engine/ui/tabs_spec.rb`: rules 1–7, 10 and 11.
- `spec/rgame/engine/ui/menu_spec.rb`: rule 8, and rules 12, 13, 15 and 16.
- `spec/rgame/engine/ui/stepping_spec.rb`: rule 9.
- `spec/rgame/engine/ui/grid_spec.rb` and `column_spec.rb`: `arrange` with a
  first row, and the bounds of a window.
- `spec/rgame/engine/input_map_spec.rb`: the two actions in the universal set.
  The chord example's `contain_exactly(:block, :parry)` gains `ui_tab_prev` and
  `ui_tab_next`, which is the chord silencing tab switching.
- **The caller that uses all three**, in `tabs_spec.rb`: a page holding a group
  of a scrolled grid and a column. Focus scrolls the grid and crosses to the
  column, and rule 14 lands it back in view. The page switches away and back,
  and focus and scroll are where they were.
- `focus_group_allocation_spec.rb` gains rule 17.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/inventory/main.rb --ticks 400 --texts
ruby tools/drive_test_project.rb examples/inventory/main.rb --gamepad \
  --script tools/drive/examples/inventory_pad.rb --ticks 400 --texts
```

The bag holds twenty items in three visible rows, and a second page holds key
items. The two atlases hold thirteen icons, so icons repeat, but every item has
a name of its own and `--texts` tells them apart. The script walks down past the
window, switches to the key items with E and back with Q. The key items' names
first appear after the E, and their counts stand still from the Q on; the
script's header gives the checkpoints. The `--gamepad` run does the same on the
shoulder buttons.

**Every other driven example and test project reports what it reported at the
branch point**, byte for byte, compared as the verify skill describes.
`examples/input_holds` chords the shoulder buttons and `test_projects/adventure`
binds E, so those two would show the universal set's growth first.

Three places stop being true here: `docs/api/input.md`'s list of the universal
set, `docs/api/ui.md`'s "no scrolling lists", and the universal actions
`write-example` lists.

**Landed.** Four sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3399 examples 0 failures (3315 at the branch point), `rake spec:core`
477 examples 0 failures, `rake docs:coverage` nothing undocumented.

`Menu` takes `confirm:`, `Stepping` takes `actions:`, and the universal set
gains `ui_tab_prev` and `ui_tab_next` as sketched. `UI::Tabs` holds its bar and
its pages, and emits `on_changed`, `on_opened` and `on_closed`. `Column` and
`Grid` take `visible_rows:`, and a menu over one answers `first_row`,
`rows_above`, `rows_below` and `in_view?`. The tabs spec is 39 examples,
including the caller that uses all three: a page holding a group of a scrolled
grid and a column, switched away and back. The allocation spec measures
switching tabs both ways and scrolling a grid a row at a time, at zero objects
each.

The acceptance run is `examples/inventory`, with twenty items in three rows and
four key items on a second page: 400 ticks against 400 frames and two clicks.
The counts show the window. Every bag frame draws 12 images and every key-item
frame 4, so 4448 images is 356 bag frames and 44 key-item frames. The mark
below the bag is drawn every bag frame, and the mark above from the third step
down, tick 161, when the bag scrolls: 551 triangles. E on 182 shows "House
key" from 183, and the key items' counts stand still from Q on 226. At 228 a
frame adds 12 images and both marks, so the bag came back scrolled, on the item
it left. The `--gamepad` run on the shoulder buttons reports the same one tick
later. Frames captured with `xwd` on a private Xvfb show the tab shown, both
scroll marks, and a crossing into the verbs from a scrolled row.

**Every other driven run reports what it reported at the branch point**, byte
for byte: all 47 other scripts, under `--seed 4242`, 240 ticks and `--texts`,
`examples/input_holds` and `test_projects/adventure` among them. The baseline
was captured twice and agreed with itself, six reports drawing 239 frames in
both captures.

What the sketch got wrong:

- **Pages do not live off the child list.** A node held off it is never told
  its parent moved, because `Node2D#rgame_soil` walks `@children`, so a page
  would keep its old `world_x` once the tabs moved. Each page sits instead in a
  node the tabs add as a child, controlled only while its page is shown and
  drawn only while shown. That node is the page's `parent`, not the tabs. The
  tree's own entry, exit, sweep and transforms then reach every page with
  nothing overridden. **`SceneStack` has the same gap**: a scene pushed onto a
  host that then moves answers its old `world_x`. Nothing moves a stack's host
  today. It belongs to [step 12](#step-12--the-scene-stack-that-names-defers-and-transitions).
- **The bar is controlled before the pages, and the order does not matter.** A
  page shown is first controlled on the next of the tabs' own passes, counted
  as `FocusGroup` counts its own. That also holds when a page's own button
  switches to a page later in the tree, which the ordering alone did not cover.
  A `Tabs` opened by a node the tree controls earlier in the same tick is read
  that tick, the same case step 5 noted for `current=`.
- **The bar is a `Menu` subclass that reports its focus.** `current` is read
  off the bar's focus, so every route that moves it, a step, a hotkey,
  `current=` and the first tab added, goes through the bar's `focus`. The
  subclass and the page's holder are private constants. `on_changed` also
  emits for the first page shown, as its tab is added.
- **`Stack#arrange` allocated.** `each_with_index` built an object each call,
  harmless while `arrange` ran on `add` only. Scrolling calls it on a press, so
  it loops by index now.
- **`in_view?` is new.** Rule 14 needs `Stepping#entered` to know which buttons
  are in the window, so `Menu` answers `in_view?(index)`. A horizontal `Stack`
  refuses `visible_rows:`, having one row, which cost `Grid` a second
  overridden private method.
- **A clamp on `first_row` was dead code.** A menu's buttons shrink only
  through `clear`, which scrolls to the top. The clamp and that reset each hid
  the other from mutation, so the clamp went.
- **The example's items stopped naming their pictures.** Twenty names share
  thirteen images, so `ITEMS` maps each name to one. The help line grew to 636
  pixels in a 640-pixel window, and was shortened.

Documented in [docs/api/ui.md](../../api/ui.md#rgameengineuitabs): `Tabs`,
[a window of rows](../../api/ui.md#a-window-of-rows),
[two actions of its own](../../api/ui.md#two-actions-of-its-own) and `confirm:`,
with the universal set in [input.md](../../api/input.md#the-universal-ui-set),
the example in [examples.md](../../api/examples.md#inventory), and four entries
in `CHANGELOG.md`.

---

## Step 7 — a node reads only the presses it saw start

Step 8's bag pauses its hero, and a pause is where a press first outlives the
node that should have read it. `:interact` is a tap, which presses on release,
and the mapper computes edges whether a paused hero reads them or not. So E
pressed in the bag and released within 0.3 s after I closes it opens the chest
in reach, and E held across the close searches it late. The same press reaches
a scene that comes back to the top of the stack, a page shown again, and a node
added while a hold is running.

`Menu` already refuses such a press, for itself: it takes no confirm until it
has seen confirm up. Steps 5 and 6 each add a clause of the same kind, for a
menu a group enters and a page a tab shows. All of them answer one question,
whether this reader saw the press start. So this step answers it once, in
`Node2D#control`, for every node, and no component has to remember it. It is
[decision 19](README.md#decisions-already-taken).

Nothing here is genuinely new. `ActionMapper` records when each press began,
beside the `hold_times` it already keeps, and `Node2D#control` works out a gate
the way it works out `abs_input_owner`. `Menu`'s rule is the definition.

### Sub-steps

- **7a** — `ActionMapper` and `Players::Everyone` record the poll each press
  began on.
- **7b** — `Node2D#control` hands its components and `_control` a gate.

### Shape

```ruby
actions.poll_count              # which poll this snapshot is from; nil on one built by hand
actions.down_since(:interact)   # the poll its buttons went down on; nil while they are up
```

`down_since` survives the tick of the release, as `held_for` does, because a tap
presses on that tick.

**A node resumes** on the first poll it is controlled after one it was not.
That covers a paused node or ancestor, a scene below the top of the stack, a
hidden page, and a node's first control.

**Each node reads through a gate of its own**, made on its first control and
reused after. The gate answers `pressed?` and `released?` from the snapshot,
false for a press that began before the node resumed. It passes every other
query through. `Node2D`'s part of this is `rgame_` machinery, so a subclass
cannot switch it off.

`Menu`'s own wait stays. It also waits after its buttons change, which no gap in
control marks.

### The rules the tests pin

1. **A node reads the edges of a press only if the press began after it
   resumed.** A paused parent, a scene popped back to and a node added mid-hold
   each refuse the press that began before.
2. **The press that resumed a node is not its press either.** A press that
   began on the poll the node resumed is refused, as `Menu` refuses a press
   already down when it opens.
3. **Only `pressed?` and `released?` are gated.** `held?`, `axis` and
   `held_for` answer as before, so a direction held across a bag closing walks
   the hero.
4. **The next press reads as usual.** Releasing and pressing again is a press.
5. **A node whose `input_owner` changes resumes**, because it reads another
   player's presses from then on.
6. **A press of `players.everyone` began when its first member's did.**
7. **A snapshot built by hand gates nothing**, so a spec passing
   `Actions.new(...)` to `control` reads what it read before.
8. **Nothing allocates per poll.** A node makes its gate once.

### Tests

- `spec/rgame/engine/action_mapper_spec.rb` and `actions_spec.rb`:
  `poll_count` and `down_since`, and `down_since` on the tick a tap presses.
- `spec/rgame/engine/players_spec.rb`: rule 6.
- `spec/rgame/engine/node2d_press_gate_spec.rb`: rules 1–5 and 7, with a paused
  parent, a `SceneStack` popped back to, a node added mid-hold, and two players.
- **The caller that uses it**, in the same spec: a hero paused by a bag. E
  tapped across the unpause opens nothing, and the next tap opens.
- `spec/rgame/engine/node2d_control_allocation_spec.rb`: rule 8.
- `spec/rgame/engine/sealed_privates_spec.rb`: the new `rgame_` methods.

### Verify

```
bundle exec rake spec
```

**Every driven example and test project reports what it reported at the branch
point**, byte for byte, compared as the verify skill describes. A report that
changes names a press the gate now refuses, and the landed note says which.
Step 8's adventure run is where the gate is seen working, on a tap of E begun
in the bag and ended after it closes.

`docs/api/input.md` gains the rule, beside the edges it gates.

**Landed.** Two sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3455 examples 0 failures (3410 at the branch point), `rake spec:core`
477 examples 0 failures, `rake docs:coverage` nothing undocumented.

`Actions` answers `poll_count` and `down_since`, and `ActionMapper` and
`Players::Everyone` move the count on each poll. `Node2D#control` hands its
components and `_control` a `PressGate`, `@api private`, made on the node's
first control with a polled snapshot and kept. The gate spec is 15 examples:
rules 1–7 with a paused parent, a scene popped back to, a node added mid-hold,
an owner changing and a node everyone owns, and the caller that uses it, a hero
paused by a bag. A tap of E begun in the bag and ended after it closes opens
nothing, and the next tap opens the chest. The allocation spec measures a tick
and a resume at zero objects each. Nineteen mutations were run over the two
sub-steps. The three that survived the first draft each named a condition the
code did not need, now gone.

**No driven report changes for a refused press.** All 49 scripts ran on `main`
and on the branch, one tree after the other, under `--seed 4242`, 240 ticks and
`--texts`. 47 reports are identical, byte for byte. `examples/sprite` drew 219
frames on `main` under load and matched the branch when run again. The one
change is `examples/pooling`'s readout, which the next bullets explain. No
script presses across a pause, so step 8's adventure run is still where the gate
is seen working.

What the sketch got wrong:

- **A node's gate costs one object, once, and a fresh node pays it.** Measured
  in a plain run of `examples/pooling`, not under the harness: pooled motes
  steady at 111 objects a second on both trees, fresh motes 1306–1322 on `main`
  and 1386–1398 on the branch. That is 80 a second, one per mote at 80 motes a
  second. A pooled mote keeps its gate, so only the pool's first seconds read
  higher while it fills. A gate made only for nodes whose class or components
  override `_control` would save it, at the price of a per-class cache and a
  flag kept in step with `add_component`. Not done.
- **`down_since` outlives the release by a tick more for a tap.** The sketch had
  it survive the release tick, as `held_for` does. A tap presses on its release
  and releases on the tick after, and the gate asks when the press began on both
  ticks. So `down_since` lasts until the press has no edge left to report,
  and a hold let go before its threshold forgets it on the release.
- **The gate answers `actions_for` with the snapshot it gates.** `SceneStack`
  hands its component's `actions` to its scene when no `Players` is mounted,
  and that is now a gate. Each node in the scene then gates the raw snapshot
  itself.
- **A press on a node's very first tick is refused**, by rule 2. Seven examples
  of the existing specs pressed on the tick they built their tree, six in the
  interactor spec and one in the menu spec. Each now ticks once before it
  presses, as a running game would. Five expected the snapshot itself where a
  node now reads its gate, and read it through `actions_for`. A double of
  `Actions` answers `poll_count` with nil, as a snapshot built by hand does.
- **`FocusGroup` and `Tabs` keep their own wait.** The gate refuses edges only;
  those two stop every read on the tick a menu or page takes over. The case step
  5 left open stays open: a menu made current by a node the tree controls
  earlier in the same tick was controlled all along while not current, so it
  never resumes and the gate does not see it.

Documented in [docs/api/input.md](../../api/input.md#a-node-reads-only-the-presses-it-saw-start),
with `down_since` and `poll_count` beside `held_for`, links from
[scene_graph.md](../../api/scene_graph.md#pausing-a-subtree),
[components.md](../../api/components.md) and [game.md](../../api/game.md), a
`Changed` entry in `CHANGELOG.md`, and `down_since` added to the `held_for` entry.

---

## Step 8 — `examples/equipment`, and the adventure's bag

The screen a game ships, and the first place a pickup reaches an inventory.
Steps 5 and 6 each proved their own parts. Here those parts meet collecting,
pausing and a second player.

### Sub-steps

- **8a** — `examples/equipment`.
- **8b** — `--texts` per clip in `tools/drive_test_project.rb`.
- **8c** — the adventure's bag: what each hero carries, on a page beside what
  they wear.

### Shape

```
examples/equipment/main.rb
examples/equipment/locales/en.yml
tools/drive/examples/equipment.rb
tools/drive/examples/equipment_pad.rb

tools/drive_test_project.rb          # --texts also lists each clip's strings

test_projects/adventure/bag.rb       # one player's bag: a node holding a Tabs of Carried and Worn
test_projects/adventure/lever.rb     # a second interactable, with words of its own
test_projects/adventure/hero.rb      # carried, worn and carry, and the worn pieces drawn
test_projects/adventure/{main,room,coin,chest}.rb
tools/drive/test_projects/adventure.rb
```

`examples/equipment` is one `Tabs` with two pages:

```
 [ Gear ]  [ Bag ]
 ┌────────┐   Head [ straw hat ]    ┌────┬────┬────┐
 │  hero  │   Body [   empty   ]    │    │    │    │
 │ dressed│   Feet [   boots   ]    ├────┼────┼────┤
 └────────┘                         │    │    │    │
                                    └────┴────┴────┘
```

- **Gear** is one `FocusGroup` of a column of slots and a grid of the clothes
  that fit them. Choosing a piece wears it and replaces what that slot held.
  Choosing a slot takes its piece off. An empty slot stays enabled and says so,
  so taking the last piece off leaves focus where it is. The hero draws from
  `hero.png`, scaled up from its 16×22 frame, with the worn pieces drawn over it
  as shapes.
- **Bag** is a grid of everything carried, and a panel that names the focused
  piece and says, as text, whether it is worn.

**One outfit, read by everything.** The example holds one object that says
which piece each slot wears. The slots, both grids and the hero figure read it,
and nothing copies it. Six pieces, two per slot, each draw themselves as
shapes. A piece's button and the figure call that one drawing, so a piece and
its slot always agree.

The slot names, the pieces and the empty slot's word are keys in `en.yml`. The
example's header does not name the test project, because
`spec/game_references_spec.rb` fails a shipped file that does. An `### equipment`
entry in `docs/api/examples.md`, which the index spec requires, and a row in
`README.md` come with it.

**The hero owns what it carries and wears**, so no hook hands a bag's data to
the world:

```ruby
hero.carry(item)        # the one way in, for a coin and for the chest's hat
hero.carried            # what the Carried page lists
hero.worn               # what the Worn page shows, and what the hero draws
Bag.new(hero:)          # handed its hero, as tiled_world's Inventory is handed its walker
```

A coin calls `carry` on `other.node` from `Collectable#on_collected`. `other` is
the feet box that touched it, so the coin reaches the hero who took it. The
chest's search returns the hat, and the hero who searched carries it. The hero
draws the pieces it wears, and names them in words too, as the chest and the
crate draw their state.

**`Bag` is a node that holds a `Tabs`**, as `Inventory` holds its menu. A closed
`Tabs` reads no input, so something outside it has to read `bag`. The adventure
binds `bag` to I and the pad's Start. Each hero's bag lives in that player's
`PlayerLayer`, closes its `Tabs` as it enters, and pauses its hero while the
tabs are open.

**A press begun in the bag stays there.** Step 7 gates every press a node never
saw start, so E tapped in the bag and released after it closes reaches neither
the hero nor the chest.

### What the run proves

No engine class is expected in this step, so it has no specs of its own. If one
turns up, it arrives with its tests, as step 4's `ActorBlockers#passing` did.
The harness grows instead: `--texts` keeps a count and a first tick for each
clip as well as overall, and each `PlayerLayer` and each viewport is a clip of
its own. That is what ties a string to a player.

The adventure's run is what pins these:

1. **A coin reaches the bag of the hero who took it**, and never the other's.
   Each player takes a coin.
2. **The hero whose bag is open stands still. The other walks on.** A fifth coin
   lies where player one presses while moving through their bag. The audio
   count stays where it is until the bag closes.
3. **E switches a tab and opens nothing.** Player one stands by the lever, opens
   their bag and presses E. The lever's word stays until they close the bag and
   press E again. E is both `ui_tab_next` and `:interact`, and the paused hero
   reads neither of its own actions. A tap of E begun in the bag and ended after
   it closes opens nothing either, which is step 7 seen from a game.
4. **Player one's tabs and player two's switch apart.** Player two opens their
   bag with Start while player one's is open, and switches with the right
   shoulder button. Then player one switches with E.
5. **The hat the chest gave is drawn on the hero wearing it and on no other.**
   Its words rise by two a frame, one per viewport, not four.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/equipment/main.rb --ticks 400 --texts
ruby tools/drive_test_project.rb examples/equipment/main.rb --gamepad \
  --script tools/drive/examples/equipment_pad.rb --ticks 400 --texts
ruby tools/drive_test_project.rb test_projects/adventure/main.rb --ticks 600 --texts
```

The equipment run wears a piece, swaps it for the other one in that slot, and
takes it off, and looks at the Bag page after each. Taking a piece off draws the
empty slot's word, which the Body slot has drawn since tick 0, so no new string
shows it. The drive script's header therefore names the count or first tick that
proves each change, as `tools/drive/examples/skill_bar.rb` does.

The adventure's first 240 ticks keep the text ticks step 4 recorded: "open" from
150, "searched" from 206, "east" from 111 and "west" from 189. Its draw, clip and
band counts change: the first `PlayerLayer` adds a `:hud` band, and pushes each
player's region as a clip a second time each frame. The lever stands more than
`Hero::REACH` from player one's path in those ticks, so it cannot take the
chest's press. After them, the script plays rules 1 to 5 in that order. The
landed note records each rule with the tick it happened on, read off the report
at the script's checkpoints, as step 0 read its rules off the translate range.

**Landed.** Three sub-steps, one commit each. `make test` 380 checks 0 failures,
`rake spec` 3530 examples 0 failures (3526 at the branch point), `rake spec:core`
483 examples 0 failures, `rake docs:coverage` nothing undocumented, and `rake
drive:allocations` passes every project: `examples/equipment` at 4.6 objects a
second on 2.3% of ticks, the adventure at 36.4 on 3.4%. No engine class was
needed, so the step added no spec beyond the harness's.

`examples/equipment` is one `Tabs` of Gear and Bag over one `Outfit`. Its six
pieces draw themselves in `hero.png`'s sixteen-by-22 pixels, and the figure and
each `PieceButton` call that drawing through `renderer.scaled`. A slot is a
`PanelButton` whose `draw_foreground` names the piece it wears or "Nothing". The
keyboard run wears the Cloak ("Cloak" from 46), swaps it for the Tunic ("Tunic"
from 146) and takes that off ("Nothing" rising again from 258). The bag's panel
reads "Worn" for the Cloak until 110, "In the bag" for it from 167, and "In the
bag" for the Tunic from 279. "Cloak" stands at 100 from 189 on, so the slot
really changed. 400 ticks against 400 frames, and the `--gamepad` run reports
the same a tick later. Frames captured with `xwd` on a private Xvfb show the
character dressed and the bag's panel.

`--texts` lists each clip's strings under the innermost clip, when a run pushes
more than one. The adventure's Bag is a node holding a `Tabs` of Carried and
Worn, in each player's `PlayerLayer`, on I and the pad's Start. `Hero` owns
`carried`, `worn`, `carry`, `wear` and `take_off`; a coin carries itself onto
`other.node`, and the chest's search returns a hat. The run is 740 ticks, and
its first 240 keep step 4's text ticks. Read off the report at its checkpoints:

1. **Player one's region lists "coin x 3" and "hat" from 241, player two's
   "coin" from 251.** Neither region ever lists the other's.
2. **Player one's bag is open from 280 to 320, and the sound count holds at 4
   until 337.** The fifth coin sounds on 338, after the bag closed and the held
   Down walked the hero onto it. Player two meanwhile drags the crate east:
   "west" stops at 206 from 291.
3. **E in the bag at 452 shows "head: empty" from 453, and the lever keeps its
   word.** A tap begun in the bag at 498 and let go at 510, after I closed it at
   504, pulls nothing either. "pulled" appears from 532, the next tap. With
   `PressGate#pressed?` passing every edge through, the same run reads "pulled"
   from 511.
4. **Player two's region shows "head: empty" from 581**, the right shoulder
   pressed at 580 with player one's bag open since 550. Player one's E at 600
   switches only their own.
5. **Player two's region draws "hat" from 688**, the frame after player one
   wore it, once a frame to 740. Overall "hat" rises by 40 between 700 and 720,
   two a frame.

**Every other driven run reports what it reported at the branch point**, once
the new per-clip section is set aside: 49 scripts on `main` and 51 on the
branch, under `--seed 4242`, 240 ticks and `--texts`. Eight at a time dropped
frames in 16 of them. Run one at a time, 47 match byte for byte. `pooling`'s
readout differs by 1 to 4 objects a second, because it counts the harness's own
recording, and the adventure differs by what it grew: the lever, the fifth coin,
their debug shapes, a `:hud` band and each region clipped twice. Every text tick
in its first 240 matches.

What the sketch got wrong:

- **"The other walks on" cannot be read off translates.** Player two walked
  back over ground they had covered in the first 240 ticks, so no clip's count
  of distinct translates moved. They drag the crate east instead, which turns
  its word from "west" to "east" and shows in `--texts`.
- **Rebuilding the bag on every opening cost 55.5 objects a second** against
  the budget of 60: fourteen openings, each building its buttons again. A
  test project's drive script cannot say why its budget is raised, because a
  commit strips its comments. So `Hero#revision` counts changes to what it
  holds, and the bag rebuilds only when that moved: 36.4, with the report
  byte-identical.
- **The run takes 740 ticks, not 600.** Five rules played one after the other,
  each with a bag opened and closed, need about 500 after the first 240.
- **The adventure gained `item.rb`**, beside the files the sketch listed. A
  coin and a hat are the same kind of thing to a bag, and a lever answers
  `search` with nil, because the hero asks whatever is in reach to search.
- **"hat" is two strings in one.** Player one's Carried page lists it from 241,
  so rule 5's evidence is player two's region, which never holds a hat, and the
  overall rate.
- **The clothes grid is two columns, a row to a slot**, where the sketch drew
  three. A crossing from a slot then lands on a piece that fits it. The bag
  follows the same shape, so a step down from the Straw hat reaches the Cloak.
- **Per-clip texts are listed only for a run with more than one clip.** With
  one, the list repeats the overall one line for line.

Documented in [examples.md](../../api/examples.md#equipment), a row in
`README.md`, an entry in `CHANGELOG.md`, and `--texts` per clip in `CLAUDE.md`
and the [verify](../../../.claude/skills/verify/SKILL.md) skill.

---

## Re-planning steps 9–12

Steps 9 to 12 were re-planned at `ef1400e`, after step 8 landed. A question
round settled five things, and reading the code overturned seven the design
recorded. The two steps first numbered 9 and 10 changed places: the canvas's C
now comes first, because the fade is built on it.

### What was measured

| | |
|---|---|
| `rake spec` | 3530 examples, 0 failures, 28.0 s |
| Objects one `Util::Color.new` allocates | **1**. A colour built once a tick is 60 a second |
| `rake drive:allocations`' default budget | 60 objects a second, and 10% of ticks |
| Objects a particle's step allocates: `rand` over a Range, `Math.cos`, two ivar updates and an Array lookup | **none** beyond the loop's own, over 10,000 steps |
| GL functions called in `ext/` and `src/` | 23 distinct at 55 call sites, `glBlendFunc` at one of them |
| Places the canvas writes a vertex's colour | 2: `write_vertex`, and a replay's tint |
| What a draw command carries | `z`, `order`, `texture`, `clip` and its vertex span |
| Renderer methods that push and pop | 5: `rotated`, `translated`, `scaled`, `layered`, `clipped` |
| Where `Node2D#draw` draws a node's children | after `_draw` returns, so no `_draw` can wrap them |
| `AudioOut#play_music` and `#stop_music` callers | 2 each, in `examples/music` and asteroids |
| Sound groups in `audio.c` | one per sample, parented to nothing. A song plays straight to the endpoint |
| miniaudio's `defaultVolumeSmoothTimeInPCMFrames` | 0, so a volume change lands on one sample |
| `SceneStack` | 87 lines, and no class comment |
| Scene switches in games | 6: asteroids 1 and `menu_navigation` 3 through a hand-written `@pending`, `tiled_world` 1 and the adventure 1 pushed in `_enter_tree` |
| Scene switches in specs | 44, in `scene_stack_spec.rb` and `node2d_press_gate_spec.rb` |
| What the harness hooks to report scenes | `SceneStack#push` and `#pop` |
| `Game#update`'s order | poll, `control`, `update`, `sweep_freed` |
| The packed 0.4.0 gem | 1.64 MB, of which `music.ogg` is 93 KB |

### What the design got wrong

- **A colour built in `_update` still allocates.** Design item 6 moved a fade's
  colour out of `_draw` and into `_update`. A `Color` is frozen, so each one
  built is an object: 60 a second for a fade, and 60 a second for each particle
  whose colour changes with its age. The question round chose two answers.
  `Util::ColorRamp` builds a particle's colours once and answers one by age.
  `renderer.faded` multiplies the alpha of everything drawn inside it, so a fade
  draws one colour at a changing opacity.
- **No `_draw` can fade a subtree.** `Node2D#draw` draws a node's content and
  then its children, and `_draw` is only part of the first. A node that wraps
  its `_draw` in `faded` fades itself and not what it holds. So `Node2D#opacity`
  wraps both, the way the node's transform already does, and a `ScreenFade` is a
  rect that sets its own opacity.
- **An emitter cannot live on the thing it sparkles for.** A coin frees itself
  as it is taken, and its particles would go with it. A component also draws in
  its node's slot, so an emitter on the room would draw under the map's
  canopy. Particles go on a node of their own in the actors slot, and each coin
  is handed it.
- **A volume per category needs C.** Multiplied in Ruby, `Song#volume` would
  read back the product, and `an audio server` pins the volume a caller set.
  Each sample already plays through a sound group of its own, parented to
  nothing. A category is a group those groups and every song play through.
- **Stepping a volume once a tick may be audible, and a number can say.**
  miniaudio smooths a volume change over `defaultVolumeSmoothTimeInPCMFrames`
  frames, 0 today. One tick is 735 frames at 44.1 kHz. The offline device reads
  back what a fade stepped once a tick puts out, with and without smoothing.
  Decision 14's fallback becomes one line of config, and the example confirms
  by ear what the number says.
- **A switch lands in the sweep, not in the stack's `_update`.** The design
  applied a switch before updating the current scene. A switch asked for during
  control then landed that tick, and one asked for during update landed the
  next, so the tick depended on who asked. `queue_free` already answers this
  question: a change to the tree waits until nothing walks it. `Game#update`
  sweeps after control and update, and the stack already takes part through
  `_sweep_freed`. A switch that lands there lands after the whole tick, whoever
  asked. Both hand-written versions land theirs at the same moment: in the
  root's `_update`, after the scene's, with nothing left to walk.
- **One transition for every switch fades a pause menu to black.** The stack
  keeps a default, and each switch may name its own or none.

The harness needs one change the design did not foresee. It prepends `push` and
`pop` to report scenes. Both now only record a request, and a named push hands
the harness a Symbol, so it hooks the step that lands a switch instead.

### Decided in this re-plan

Settled in a question round, and recorded in the brief as
[decisions 20 to 24](README.md#decisions-already-taken).

- **Steps 9–12 are detailed.** Steps 13 and 14 stay rough until scenes can name
  and carry.
- **No second music track ships.** `examples/music` grows the fades, pause and
  resume, and the category volumes on its one track. The adventure, which does
  not ship, carries a second track from step 13. Its door crossfades between the
  rooms' music. [Open question 1](README.md#open-questions) is settled.
- **A colour that changes every tick has two answers.** `Util::ColorRamp` serves
  a colour that moves from one hue to another. `renderer.faded` and
  `Node2D#opacity` serve anything that fades as a whole. The second is C, and
  lands in step 9 beside the blend mode.
- **No scene reads input during a transition.** The scene leaving stands still
  under the cover, and the scene arriving runs under the reveal. The press gate
  then refuses any press begun during either.
- **A game names its own volume categories.** A song plays under `:music` and a
  sample under `:effects`, unless registered under another name.

### Three piles, for steps 9–12

- **Reuse:** `Engine::Tween` for every fade, the stack's transition and a
  flash's rise and fall, through its `:arc` ease. `Components::Timer` for the
  storm. The clip's way of travelling with each draw command, for the blend
  mode. The canvas's one pop for any push. `RenderedFrame` in `spec_core/`, to
  read pixels back, and the offline audio device, to read samples back. The
  sweep, for a switch. A node held off the child list, for the stack's fade. The
  press gate, for the first press after a transition.
- **Extend:** the canvas → a blend mode and an opacity on its stacks. The draw
  command and batch → a blend field. `Node2D#draw` → `opacity`. `Engine::Pool` →
  `reserve`. The audio device → a table of category groups, and `resume`.
  `Core::Audio` → categories by name, pause and resume, a song's volume and a
  stop by id. `AudioOut` → fades and a crossfade. `SceneStack` → names,
  deferral, `carry:`, transitions and `on_changed`. The harness → scenes
  reported where a switch lands, and the new audio calls.
- **Genuinely new:** `Util::ColorRamp`, because nothing maps a fraction to a
  colour. `Components::Particles`, because a pool of things with a lifetime
  exists but nothing spawns them along a spread. `Engine::ScreenFade`, which is
  thin: a tween, a rect and its own opacity. `Scene::Fade`, the value a
  transition is described by.

---

## Step 9 — blend modes and opacity on the canvas *(C)*

Step 10's sparkles and bolt look like light only when they add to what is behind
them, and its fade draws one colour at a changing opacity. Both are state on the
canvas, so both land here, in C, before anything draws with them. Only the blend
mode is GL state, and that decides how each one travels.

**A blend mode travels with each draw command, as the clip does.** Sorting
reorders commands, so a mode left current at draw time would land on whichever
quads sorted next to it. The command and the batch carry it, a batch ends where
it changes, and the submit loop tells the backend only when it changes.

**Opacity travels with each vertex, as the transform does.** The canvas
multiplies it into a vertex's alpha as it writes the vertex. Sorting cannot move
it, and batching never sees it. Nested pushes multiply.

### Sub-steps

- **9a** — a blend mode on the draw command: the canvas's stack, the field on the
  command and the batch, the batch split, `set_blend` on the backend table, the
  recording backend, and `glBlendFunc`.
- **9b** — opacity on the canvas: a stack of multipliers, applied in
  `write_vertex` and in a replay.
- **9c** — `renderer.blended` and `renderer.faded`, in the `a renderer` contract,
  `FakeRenderer` and `QuietRenderer`, with pixels read back in `spec_core/`.
- **9d** — `Node2D#opacity`.

### Shape

```c
/* graphics/draw_queue.h */
typedef enum { RGAME_BLEND_ALPHA = 0, RGAME_BLEND_ADD = 1 } rgame_blend;

typedef struct {
    double z;
    unsigned int order;
    unsigned int texture;
    rgame_rect clip;
    rgame_blend blend; /* travels with the command, for the reason the clip does */
    unsigned int first_vertex, vertex_count;
} rgame_draw_command;

rgame_vertex *rgame_draw_queue_alloc(rgame_draw_queue *queue, unsigned int count, double z,
                                     unsigned int texture, rgame_rect clip, rgame_blend blend);

/* graphics/backend.h: a member of rgame_draw_backend, issued only on a change */
void (*set_blend)(void *ctx, rgame_blend blend);

/* graphics/canvas.h */
void rgame_canvas_push_blend(rgame_canvas *canvas, rgame_blend blend); /* replaces */
void rgame_canvas_push_opacity(rgame_canvas *canvas, float opacity);   /* multiplies */

/* include/rgame/core.h: blend returns 0 without pushing while a recording is open */
int rgame_app_push_blend(rgame_app *app, int blend);
void rgame_app_push_opacity(rgame_app *app, float opacity);
```

```ruby
renderer.blended(:add) { renderer.circle(0, 0, 4, color: SPARK) }   # :alpha outside any block
renderer.faded(0.4) { renderer.image(:hero, 0, 0) }                 # 0.0 hides it, 1.0 changes nothing

node.opacity = 0.5   # the node and everything under it, at half its alpha
node.opacity         # 1.0 until set
```

`glBlendFunc(GL_SRC_ALPHA, GL_ONE)` is `:add`, and `GL_ONE_MINUS_SRC_ALPHA` in
place of `GL_ONE` is `:alpha`. Both are GL 1.0.

`Node2D#draw` wraps the node's content and its children in `faded` while
`opacity` is below 1, and draws nothing at 0. The rest of its drawing is as
today.

### The rules the tests pin

For the canvas:

1. **A batch ends where the blend mode changes**, as it does on a texture or a
   clip. Two additive quads with an alpha quad between them are three batches.
   The same three in one mode are one.
2. **The sort never reads the blend mode.** `z` and call order alone decide
   what is drawn over what.
3. **`set_blend` is issued only when the mode changes**, and every frame starts
   in `:alpha`.
4. **A blend mode inside another replaces it**, and `pop` restores the outer one.
5. **Opacity multiplies.** `faded(0.5)` inside `faded(0.5)` draws at a quarter.
   It scales a vertex's alpha, rounded to the nearest byte, and leaves its
   colour alone.
6. **A replay inside `faded` is faded**, and an opacity pushed inside `record`
   is baked into the recording.
7. **`blended` inside `record` raises**, as `clipped` does. A recording's batch
   carries no blend mode.
8. **`blended` refuses a mode it does not know, and `faded` a number outside
   0..1 or anything but a number**, in the fake as in the real renderer.

For the node:

9. **`opacity` fades the node's content and every child under it**, and a node
   at 0 draws nothing. A node at 1 pushes nothing.
10. **`opacity=` refuses what `faded` refuses.**
11. **Drawing allocates nothing**, at 1, below 1 and at 0.

### Tests

- `test/test_draw_queue.c`: rules 1 and 2.
- `test/test_backend.c`: rule 3, through the recording backend.
- `test/test_canvas.c`: rules 4–6.
- `spec/support/shared_examples/a_renderer.rb` and `fake_renderer_spec.rb`:
  `blended` and `faded` yield and pop, and rule 8. `QuietRenderer` gains both.
- `spec_core/rgame/core/renderer_spec.rb`: the renderer against the same group,
  rule 7, and the pixels. A quad of (128, 0, 0) drawn `:add` over (0, 0, 128)
  reads (128, 0, 128), and drawn `:alpha` reads (128, 0, 0). A white quad inside
  `faded(0.5)` over black reads 128, give or take one.
- `spec/rgame/engine/node2d_opacity_spec.rb`: rules 9–11, with a
  `FakeRenderer` recording `faded` around a parent's content and its child.

### Verify

```
make test
make ext-core && bundle exec rake spec:core
bundle exec rake spec
bundle exec rake drive:allocations
```

The pixels are what is true afterwards and was not before: a quad that adds to
what is behind it, and one drawn at half its alpha. Nothing draws with either
yet, so **every driven example and test project reports what it reported at
the branch point**, byte for byte, compared as the verify skill describes.
`Node2D#draw` is on every game's per-frame path, so `rake drive:allocations`
runs too.

`docs/api/drawing.md` gains both blocks, and `docs/api/scene_graph.md` gains
`opacity`.

**Landed.** Four sub-steps, one commit each. `make test` 401 checks 0 failures
(380 at the branch point), `rake spec` 3561 examples 0 failures (3530),
`rake spec:core` 499 examples 0 failures (483), `rake docs:coverage` nothing
undocumented, and `rake drive:allocations` passes every project.

The pixels read back exactly. A red quad of (128, 0, 0) added over blue
(0, 0, 128) reads (128, 0, 128), and the same quad drawn after the block reads
(128, 0, 0). White faded by half over black reads 128, and by half inside half
reads 64. An additive quad issued first but sorted last adds only itself, so
the mode stays with its own draws.

**Every driven run reports what it reported at the branch point**, compared as
the verify skill describes: 51 scripts under `--seed 4242`, 240 ticks and
`--texts`, one at a time, against two captures of `main`. The two captures
differed in `tiled_world_2p` and `tiled_world_inventory`, each dropping a frame
or two. 50 of the branch's reports match one capture byte for byte, once the
extension paths in the header are set aside. `pooling` draws the process's own
allocation rate, and its first second reads 42,620 against 42,616. Its second
and third seconds match exactly, on two runs of each tree.

What the sketch got wrong:

- **The fake, the renderer and the node had no shared check.** Each would
  have refused a bad mode or opacity with its own copy of the rule. So
  `RGame::Util::Blend` holds `MODES`, `mode?`, `index` and `opacity`, the way
  `Util::Z.offset` serves the renderer and its fake. `Node2D#opacity=` raises
  exactly what `renderer.faded` raises, and a spec compares the two.
  Step 10's particles can check their `blend:` with `Blend.mode!` when they are
  built.
- **`between?` raises on NaN.** `Float::NAN.between?(0, 1)` raises its own
  ArgumentError, "comparison of Float with 0 failed", so `Blend.opacity`
  compares with `>=` and `<=`, and disables `Style/ComparableBetween` with that
  reason.
- **No frame starts with a `set_blend`.** The backend's `begin_frame` already
  sets alpha blending, so the submit loop counts changes from there. A frame
  with no additive draw calls `set_blend` zero times, and every existing
  backend test kept its call indices.
- **Rule 7 is in the shared contract, not only in `spec_core`.** The fake
  refuses `blended` inside `record` too, as it refuses `clipped`. Rule 6's
  tests went into `test/test_recording.c`, beside the other replay tests.
- **The C clamps an opacity, and the Ruby refuses it.** `rgame_canvas_push_opacity`
  holds a value to 0..1 and takes NaN as 1, as the queue takes a NaN z as 0.
  The Ruby raises first, so a game never reaches the clamp.
- **A forwarded block allocates nothing.** `Style/ExplicitBlockArgument` asked
  `rgame_at_opacity` to pass `&` rather than yield from a block of its own.
  Measured on this Ruby, forwarding allocates nothing per call, so the cop's
  form is the one that shipped.
- **A faded pixel's alpha depends on the platform.** The first push failed on
  macOS: two pixel specs compared all four channels of half white over black,
  and blending writes the framebuffer's own alpha too, 0.75 there. macOS keeps
  that channel and Xvfb has none, so Linux read 255 and passed. The window is
  opaque either way, so the fade specs compare colour only, as the translucency
  spec before them already did. A red, green and blue check of the quarter fade
  passed on macOS, so the colours matched there.
- **The adventure allocates 36.9 objects a second, where `main` allocates
  36.4.** The traced difference is 5 of Ruby's call caches at the one new call
  site in `Node2D#draw`. Each fills once for a node class the adventure first
  draws after the warm-up, the bag's pages among them. None is per frame.

Documented in [drawing.md](../../api/drawing.md#blending-and-fading),
[scene_graph.md](../../api/scene_graph.md#opacity) and
[values.md](../../api/values.md#rgameutilblend), rows in `docs/api/README.md`,
and an entry in `CHANGELOG.md`.

---

## Step 10 — fades, particles, and `examples/effects`

Step 12 fades a scene, step 13 a door and step 14 a cutscene, and each draws
the same fade. Sparkles and a storm are what the adventure gains. Both are
engine-layer Ruby over step 9's canvas.

### Sub-steps

- **10a** — `Util::ColorRamp`.
- **10b** — `Engine::ScreenFade`.
- **10c** — `Engine::Pool#reserve`, and `Components::Particles`.
- **10d** — `examples/effects`: a fade, a flash, sparkles and a bolt. Its
  `locales/en.yml`, its drive script `tools/drive/examples/effects.rb`, an
  `### effects` entry in `docs/api/examples.md` and a row in `README.md` come
  with it.
- **10e** — the adventure: sparkles where a coin was taken, and a storm.

### Shape

```ruby
# Colours from one to another, built once
EMBER = RGame::Util::ColorRamp.new(Color.new(255, 240, 160), Color.new(255, 120, 0, 0), steps: 64)
EMBER.at(0.25)   # the Color a quarter of the way along; t is clamped to 0..1
EMBER.steps      # 64

# A rect the size of the view, fading
fade = layer.add_node(RGame::Engine::ScreenFade.new(color: BLACK))   # starts clear, in :overlay
fade.cover(0.4)                  # to opaque over 0.4 s, from wherever it is
fade.reveal(0.4)                 # to clear
fade.flash(0.15, color: GLARE)   # up and back down, in GLARE for this flash
fade.covered?                    # opaque, and still
fade.running?
fade.on_finished { ... }

# Particles, in their node's local space
sparkles = actors.add_node(RGame::Engine::Node2D.new)
particles = sparkles.add_component(RGame::Engine::Components::Particles.new(
  limit: 48, lifetime: 0.4..0.7, speed: 30.0..80.0,
  direction: -Math::PI / 2, spread: Math::PI, gravity: 90.0,
  size: 3, ramp: EMBER, blend: :add, rng: rng
))
particles.burst(16, x, y)   # 16 at once from (x, y)
particles.rate = 40         # a stream from the node's origin, per second; 0 stops it
particles.live              # how many are alive

pool = RGame::Engine::Pool.new { Spark.new }
pool.reserve(48)            # built now, so the first burst allocates nothing
```

**A fade sets its own opacity.** `ScreenFade` is a node in the `:overlay` band.
It steps an `Engine::Tween` in `_update` and writes the value to `opacity`, and
step 9's `Node2D#draw` does the rest. It draws one rect over
`view.origin_x, view.origin_y, view.width, view.height`. That covers the whole
window at the root, one region in a `PlayerLayer`, and the camera's view under a
`WorldView`. A flash is the tween with the `:arc` ease. A flash's colour carries
its own alpha, so a storm flashes in a translucent white with no keyword for a
peak.

**A particle is a plain object, not a node.** `Particles` holds its particles in
an `Engine::Pool`, reserved to `limit` as it attaches, so a running emitter
allocates nothing. It moves them in `_update` and draws each as a square of
`size`, in `ramp.at(age / lifetime)`, inside `renderer.blended(blend)`. `rng:`
is the game's own, so a seeded run places every particle the same.

### The rules the tests pin

For the ramp:

1. **`at(0)` is `from` and `at(1)` is `to`**, the objects passed. Every channel,
   alpha included, moves in a straight line between them.
2. **`at` clamps to 0..1 and allocates nothing.**
3. **`steps` below 2 raises**, and so does anything but two `Color`s.

For the fade:

4. **A fade starts clear, and a clear fade draws nothing.**
5. **`cover` and `reveal` start from the opacity the fade has**, so a cover
   begun during a reveal turns back from where the reveal got to.
6. **`flash` rises to its colour at half its duration and falls back to clear**,
   then draws in the fade's own colour again.
7. **`on_finished` fires once when a cover, a reveal or a flash ends**, and not
   for one replaced before its end.
8. **It fills the view it is drawn into**, in each of the three spaces above.
9. **Stepping and drawing a fade allocate nothing.**

For the particles:

10. **A burst places `count` particles at its point.** Each takes a lifetime and
    a speed from its range, and a heading within `spread` of `direction`.
11. **Each tick moves every particle by its velocity** and adds `gravity` to its
    downward speed. A particle whose age reaches its lifetime is freed.
12. **A particle draws in `ramp.at(age / lifetime)`**, in its node's local
    space, inside `blended(blend)`.
13. **Never more than `limit` are alive.** A burst past it places what fits and
    drops the rest.
14. **`rate` streams from the node's origin, and carries the fraction.** 40 a
    second is 2 in every 3 ticks, and none is lost to rounding.
15. **Two runs with the same seed place every particle the same.**
16. **A node leaving the tree takes its particles with it**, and enters again
    with none.
17. **Once reserved, bursting, streaming, stepping and drawing allocate
    nothing.**
18. **Two viewports draw the same particles**, and a paused node's particles
    hold still.

### Tests

- `spec/rgame/util/color_ramp_spec.rb`: rules 1–3.
- `spec/rgame/engine/screen_fade_spec.rb`: rules 4–8, reading `faded` and the
  rect off a `FakeRenderer`.
- `spec/rgame/engine/pool_spec.rb`: `reserve` builds that many and hands them
  out before calling the factory again.
- `spec/rgame/engine/components/particles_spec.rb`: rules 10–16 and 18.
- **The caller that uses both**, in the same file: a coin with a `Collectable`
  bursts a room's `Particles` where it stood as it is taken. The coin is freed
  that tick, and its sparkles run their lifetime out after it.
- `spec/rgame/engine/components/particles_allocation_spec.rb`: rules 9 and 17.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb examples/effects/main.rb --ticks 400 --texts
ruby tools/drive_test_project.rb test_projects/adventure/main.rb --ticks 740 --texts
bundle exec rake drive:allocations
```

`examples/effects` is a dark room with a few shapes in it, and a key per
effect. Enter covers the room and reveals it again, chained on `on_finished`.
L strikes a bolt: a jagged line from the top of the window, redrawn with a new
jag every three ticks for a quarter of a second, glowing under `:add`. The bolt
fades out through its own `opacity`, and the room flashes white with it. Space
bursts sparkles at the centre. A torch streams embers the whole time. The
example seeds its own `Random` as `examples/pooling` does, so two runs are
byte-identical.

The drive script presses each key in turn, and its header gives the
checkpoints. `faded` appears in the report only while the fade, the flash or the
bolt runs. `blended` appears every frame, because the torch never stops. The
`rect` count rises by a burst's sixteen and falls back to the torch's steady
count as they die. `line` appears only while the bolt shows.

In the adventure, a `Sparkles` node in the actors slot holds one `Particles`,
and each coin is handed it. The shell holds a `ScreenFade` and a
`Components::Timer` that flashes it every four seconds. The run shows three
things:

1. **A coin taken sparkles in both players' views**, which is two `blended`
   blocks a frame, and none once the burst's lifetime has run out.
2. **The storm's flash is drawn once a frame across the window**, not once per
   region, because the shell draws it at the root.
3. **The first 240 ticks keep step 4's text ticks**, and the rules step 8
   recorded keep theirs.

`docs/api/` gains `ScreenFade` beside the node types, `Particles` in
`components.md` and `ColorRamp` in `toolbox.md`.

**Landed.** Five sub-steps, one commit each. Two more followed: one pins a
fade starting covered for step 12, and one fixes the docs reference check,
which CI failed on. `make test` 401 checks 0 failures, as at
the branch point, since no C changed. `rake spec` 3626 examples 0 failures
(3561), `rake spec:core` 499 examples 0 failures (499), `rake docs:coverage`
nothing undocumented, and `rake drive:allocations` passes all 39 projects,
`examples/effects` among them.

**`examples/effects` reports its effects in the stretches they run.** The
report adds up a whole run, so the drive script's header gives the counts at
six tick budgets under `--seed 4242`: Enter at tick 30, L at 122, Space at 184,
and L and Space together at 256.

| `--ticks` | rect | line | blended | faded |
|---|---|---|---|---|
| 30 | 360 | 0 | 28 | 0 |
| 122 | 3124 | 0 | 120 | 70 |
| 184 | 5063 | 576 | 214 | 103 |
| 256 | 7929 | 576 | 333 | 103 |
| 320 | 10519 | 1152 | 476 | 136 |
| 400 | 13017 | 1152 | 556 | 136 |

The torch's embers open one `blended` a frame, all run long, and the last 80
ticks read its 80 alone. A bolt or a burst on screen adds one more a frame
each. `faded` grows only while the cover, the reveal, a flash or a bolt runs:
70 for the cover and reveal, none after tick 320. `line` grows only while a
bolt shows, 18 a frame for 32 frames of each strike. `rect` reads about 31 a
frame with the torch alone and about 40 while a burst lives. Under
`--allocations` it reads 6.4 objects a second on 6 of 301 ticks.

**The adventure shows the three things the sketch asked for**, in a 740-tick
run under `--seed 4242` compared with `main`:

1. **A coin taken sparkles in both players' views.** `blended` reads 184 in the
   first 240 ticks and 254 in 740. The one coin taken after tick 240 adds 70,
   which is 35 frames of two views.
2. **The storm's flash is drawn once a frame across the window.** `faded` and
   the `:overlay` layer both read 45, three flashes of 15 frames, and the rect
   spans the whole 640 by 480. None falls in the first 240 ticks.
3. **Every text, clip, translate and sound matches `main`**, at 240 ticks and
   at 740. Only `rect`, `blended`, `faded` and the world and overlay layer
   counts differ.

**Every other driven run reports what it reported at the branch point.** 50
scripts under `--seed 4242`, 240 ticks and `--texts`, one at a time, against a
capture of `main`, once the extension paths in the header are set aside. 48
matched on the first capture. `tiled_world` and `tiled_world_inventory` each
dropped a frame on one tree, 238 frames against 239, and matched byte for byte
when both trees ran them again.

What the sketch got wrong:

- **`ColorRamp` is a value, so it went beside `Color`.** The sketch put it in
  `toolbox.md`, but `values.md` holds every `RGame::Util` class and the index
  says so. `ScreenFade` went in `toolbox.md` beside `Tween`, because no page
  lists node types.
- **The emitter reserves its pool when it is built, not when it attaches.** A
  component is built once, and reserving in `initialize` needs no hook. A
  fresh emitter's first burst allocates nothing, but the first burst in the
  process fills Ruby's call caches once: 30 objects. The allocation spec runs
  the same calls on another emitter before it measures a fresh one.
- **`spread` is a half-angle.** "Within `spread` of `direction`" read two ways.
  It follows Godot: each particle heads up to `spread` either side, so
  `Math::PI` is every way, as the sketch's sparkles meant.
- **Carrying the fraction needs slack.** Three ticks of 40 a second add up to a
  hair under 2 in floating point, and a plain `floor` loses a particle. The
  carry takes 1e-9 of slack, and 600 ticks stream exactly 400.
- **A flash replaces a cover, so the example holds two fades.** `flash` rises
  from clear whatever the fade showed, as rule 6 says. A storm flashing over a
  covered fade would drop the cover, so `examples/effects` flashes a second
  `ScreenFade` over the room, and the adventure's storm is its own.
- **A fade can start covered with no new method.** Step 12's rule 11 needs a
  push onto an empty stack to start covered. `fade.opacity = 1` does it:
  `covered?` answers true and `reveal` starts from there. A spec pins it, and
  `toolbox.md` says so. Durations must be positive, as a `Tween`'s are, so
  `cover(0)` raises.
- **An empty emitter opens no blend block.** The sketch's "none once the
  burst's lifetime has run out" depends on it. `Particles#_draw` returns while
  nothing is alive.
- **Rule 9's allocation examples went in `screen_fade_spec.rb`,** beside the
  fade's other rules, rather than in the particles' allocation spec.
- **The adventure allocates 39.7 objects a second, where `main` allocates
  36.9.** Listing every site on both trees traces the 29 extra objects to one
  place each: the call caches at `ScreenFade#flash` and `_update` and at the
  timer's `_update`, filled on the first flash at tick 240, after the
  warm-up; the fade's `finished` signal, built when it first emits; and one
  more node class through `Node2D#draw`. The second and third flashes allocate
  nothing.

- **The docs reference check depended on load order.** `toolbox.md` is the
  first page to name `Util::Color`, and CI's `spec:core` failed on it on Linux
  and macOS while it passed locally. `ApiDocs.constant_index` kept a module
  under the first path its walk met. `Core::Renderer` and `Core::Recording`
  alias `Util::Color` as `Color`, so a walk that reached Core first indexed it
  only as `Core::Renderer::Color`. The index now keeps a module under its own
  name and every alias, and a spec builds the alias-first order to hold it.

Documented in [values.md](../../api/values.md#rgameutilcolorramp),
[toolbox.md](../../api/toolbox.md#screenfade--cover-the-view-and-flash-it),
[components.md](../../api/components.md#particles) and
[examples.md](../../api/examples.md#effects), with `Pool#reserve` in
`toolbox.md`, a row in `README.md`, rows in `docs/api/README.md`, and three
entries in `CHANGELOG.md`.

---

## Step 11 — audio transitions

A door in step 13 fades the music with the picture, and step 12's first room
arrives with its music rising. Every piece of that is a volume moved over time,
and a volume a game's settings screen scales. The C comes first, then the
device, then the engine's clock over it.

### Sub-steps

- **11a** — the device: a table of category groups, `rgame_song_resume`, and the
  measurement that decides volume smoothing. Check tests on the offline device.
- **11b** — `Core::Audio`: categories by name, pause and resume, a song's volume
  and a stop by id. The `an audio server` contract, `FakeAudio`, and the
  harness's `AudioProbe` reporting the new calls.
- **11c** — `AudioOut`: fades, a crossfade, pause and resume, and category
  volumes.
- **11d** — `examples/music` grows a fade in and out, pause and resume, and a
  volume per category.

### Shape

```c
/* include/rgame/core.h */
#define RGAME_AUDIO_CATEGORIES 16 /* 0 is music and 1 is effects; the rest are a game's */

void rgame_audio_set_category_volume(rgame_audio *audio, int category, float volume);
float rgame_audio_category_volume(const rgame_audio *audio, int category);
void rgame_sample_set_category(rgame_sample *sample, int category); /* re-attaches its group */
void rgame_song_set_category(rgame_song *song, int category);
void rgame_song_resume(rgame_song *song); /* starts again without seeking */
```

```ruby
# RGame::Core::Audio, the device
audio.register_sound(:line, sample, category: :voice)   # :effects when not given
audio.register_music(:theme, song)                     # :music when not given
audio.category_volume(:voice)                          # 1.0 until set
audio.set_category_volume(:voice, 0.8)                 # KeyError for a name nothing was registered under
audio.set_music_volume(:theme, 0.4)                    # that song's own volume
audio.pause_music                                      # the current song keeps its place
audio.resume_music                                     # and carries on from there
audio.stop_music(:theme)                               # that song; with no id, the current one, as today

# RGame::Engine::AudioOut, what a node calls
out = system!(RGame::Engine::AudioOut)
out.play_music(:theme, fade: 0.8)    # up from silence over 0.8 s; fade: 0 is today's call
out.stop_music(fade: 0.5)            # down to silence, then stopped
out.crossfade(:battle, over: 1.2)    # the current song down while :battle comes up
out.pause_music
out.resume_music
out.set_category_volume(:music, 0.7)
out.category_volume(:music)
out.fading?
```

**The groups belong to the device.** A sound keeps its device alive until the
last sound is freed, so the groups live inside the counted `rgame_audio` and go
with it. A game's category is built on first use. Past sixteen, registering
raises before C is reached.

**The engine names songs by id, and holds no song.** `AudioOut` steps a volume
with `set_music_volume(id, volume)` from `_update`, off two `Engine::Tween`s built
once. The harness reports every call the device receives, so a fade reads as
the count of its steps.

**`fade: 0` sends the device exactly what it sends today**, so asteroids, which
plays its music without a fade, reports what it reported.

### The rules the tests pin

For the device:

1. **A category volume multiplies every sound in it** and leaves each sound's
   own volume alone. The device's `volume` multiplies over all of them, as
   today.
2. **A sample plays under `:effects` and a song under `:music`** unless
   registered under another name. A sound registered twice plays under the last
   name.
3. **A name nothing was registered under raises `KeyError`**, in the fake as in
   the device, so a mistyped category fails rather than changing nothing.
4. **A seventeenth category raises `ArgumentError`.**
5. **`resume_music` carries on where `pause_music` stopped**, and does nothing
   while nothing is paused. `play_music` after a pause starts from the top, as
   it does after a stop.
6. **`stop_music(id)` stops that song**, and `stop_music` with no id is today's.

For the engine:

7. **A song asked for with `fade:` starts at volume 0 and reaches 1.0** after
   `fade` seconds, one step a tick.
8. **`stop_music(fade:)` lowers the current song to 0 and stops it** on the tick
   it arrives. It plays at 1.0 the next time.
9. **`crossfade` lowers the current song and raises the new one over the same
   time**, and stops the old one when it is silent. With no current song it is
   a fade in.
10. **A second crossfade before the first ends stops the song on its way out**,
    and brings the one coming in down from where it is.
11. **Asking for the song that is fading out brings it back up** from where it
    is, rather than starting it again.
12. **`pause_music` holds the song and its fade where they are**, and
    `resume_music` carries both on.
13. **A fade outlives the node that asked for it.** `AudioOut` is on the root,
    so a scene that stops its music with a fade on the way out still fades.
14. **Stepping a fade allocates nothing.**

For the output, measured in 11a:

15. **A fade stepped once a tick puts out no step larger than the smoothing
    allows**, if the measurement turns smoothing on. It also checks that a
    sample's first frames are not ramped by it, because a click with a soft
    attack is a different sound. The landed note records both numbers, with
    smoothing off and on.

### Tests

- `test/test_audio.c`: rules 1 and 2 as what comes out of the offline device, as
  the master volume's test reads it. Rule 5 through a cursor query for tests
  only, in `audio_internal.h` beside `rgame_audio_live_sounds`. Rule 15.
- `spec/support/shared_examples/an_audio_server.rb`, `fake_audio_spec.rb` and
  `spec_core/rgame/core/audio_spec.rb`: rules 1–6 at the level each can see.
- `spec/rgame/engine/audio_out_spec.rb`: rules 7–13, reading a volume at 0.25 s
  by passing 0.25.
- `spec/rgame/engine/audio_out_allocation_spec.rb`: rule 14.

### Verify

```
make test
make ext-core && bundle exec rake spec:core
bundle exec rake spec
ruby tools/drive_test_project.rb examples/music/main.rb --ticks 600 --texts
```

`examples/music` fades in on Enter and out on Escape, a second each. P pauses and
resumes. Up and Down move the music's volume, and Left and Right the effects',
a tenth at a time, with a blip on each press so the effects' volume has
something to scale. The text shows the state and both volumes. Its report shows
sixty volume steps for each fade, a pause and a resume, and a blip per press.
**The one thing the report cannot say is how a fade sounds.** The measured
number in rule 15 is the check, and a person listening to this example is its
confirmation.

**Every other driven example and test project reports what it reported at the
branch point**, byte for byte.

`docs/api/audio.md` gains fades, the crossfade, pause and resume, and
categories.

---

## Step 12 — the scene stack that names, defers and transitions

Two games hand-write the same deferred switch, and step 13's door needs a switch
that carries a hero and fades. The deferral is required for correctness, so the
engine makes it ([decision 5](README.md#decisions-already-taken)). Steps 10 and
11 are what a transition draws and sounds with.

### Sub-steps

- **12a** — deferral in the sweep, `define`, keywords and `on_changed`. The
  harness hooks the landing, the 44 switches in specs land through a sweep, and
  `SceneStack` gets a class comment.
- **12b** — asteroids and `menu_navigation` lose their hand-written deferral.
- **12c** — `carry:`.
- **12d** — transitions: `Scene::Fade`, the stack's `transition` and a switch's
  `transition:`. `menu_navigation`'s Play fades, and the adventure's room arrives
  under a reveal with its music rising.

### Shape

```ruby
stack = root.add_component(RGame::Engine::Scene::SceneStack.new)
stack.define(:title) { TitleScene.new }
stack.define(:game_over) { |score:| GameOverScene.new(score:) }
stack.define(:village) { |hero:, entrance:| VillageScene.new(hero:, entrance:) }

stack.push(:title)                     # a name, or a Node2D as today
stack.replace(:game_over, score: 12)   # keywords reach the builder
stack.replace(:village, entrance: :south_gate, carry: { hero: hero })
stack.pop
stack.current                          # the top scene, once a switch has landed
stack.pending?                         # a switch asked for that has not landed
stack.on_changed { |scene| ... }       # each time a switch lands; nil once the stack is empty

stack.transition = RGame::Engine::Scene::Fade.new(color: BLACK, cover: 0.25, reveal: 0.25)
stack.push(:pause, transition: nil)    # this switch without one
stack.transitioning?
```

`Scene::Fade` is a frozen value: a colour and two durations. The stack builds one
`ScreenFade` from it and holds it off the host's child list, as it holds its
scenes, so the fade enters and leaves the tree with the host. The stack draws it
after every scene, so it covers the host's view in `:overlay`.

**A switch lands in the sweep**, where `queue_free` lands, through the
`_sweep_freed` the stack already overrides. A replace lands as a pop and then a
push. Those two private steps are what the harness hooks, and it prints each
scene's class as it does today.

### The rules the tests pin

1. **A switch lands in the sweep after the tick that asked for it**, whichever
   node asked. A switch asked for outside a tick lands in the first sweep.
   `current` changes then, not when asked.
2. **Two switches asked for before a sweep keep only the last**, as both
   hand-written versions did.
3. **A name the stack was not given raises `KeyError` when asked**, not when it
   would land.
4. **Keywords reach the builder.** `define` raises for a builder that declares
   `carry` or `transition`, which the stack keeps for itself.
5. **`carry:` takes each node from its parent as the switch lands**, before the
   old scene leaves the tree. It hands each to the builder under its key. The
   node's components leave the old scene's systems and join the new one's.
   `carry:` beside a node rather than a name raises.
6. **`on_changed` fires once per switch that lands**, with the new top scene,
   after that scene entered the tree.
7. **With a transition, the fade covers, the switch lands in the sweep after
   the cover ends, and the fade reveals.**
8. **During a transition no scene is controlled.** The scene leaving is not
   updated. The scene arriving is updated from the tick after it lands.
9. **The first press a scene reads after a transition began after it.** The
   scene resumes, so the press gate refuses any press begun during the
   transition.
10. **A switch asked for during a cover replaces the pending one.** One asked for
    during a reveal covers again, from where the reveal got to.
11. **A push onto an empty stack starts covered and reveals**, because there is
    nothing to cover.
12. **A switch's `transition:` overrides the stack's for that switch**, and
    `nil` means none.
13. **The harness reports each landed switch as `pop` and `push`**, with the
    scene's class, as today.
14. **A tick with no switch pending or running allocates nothing.**

### Tests

- `spec/rgame/engine/scene/scene_stack_spec.rb`: its 41 switches land through a
  helper that sweeps. Rules 1–6, 12 and 14 are new.
- `spec/rgame/engine/scene/scene_stack_transition_spec.rb`: rules 7–11.
- `spec/rgame/engine/node2d_press_gate_spec.rb`: its 3 switches sweep.
- **The caller that uses both**, in `scene_stack_spec.rb`: a hero carried from
  one scene to another, each with a `TileWorld` and a `CollisionWorld`. Its
  collider leaves the first index and joins the second, and its
  `CharacterBody` is stopped by the second map.
- `spec/rgame/engine/scene/scene_stack_allocation_spec.rb`: rule 14.

### Verify

```
bundle exec rake spec
ruby tools/drive_test_project.rb test_projects/asteroids/main.rb --seed 4242 --ticks 240 --texts
ruby tools/drive_test_project.rb examples/menu_navigation/main.rb --ticks 320 --texts
ruby tools/drive_test_project.rb test_projects/adventure/main.rb --ticks 780 --texts
```

**After 12b, asteroids and `menu_navigation` report what they reported at the
branch point**, byte for byte. That is what proves the engine's switch covers
what theirs did. Their `@pending` and their `_update` are gone, and
`menu_navigation`'s header section "Nothing switches scenes while the tree is
being walked" says the stack defers.

**After 12a, the adventure and `tiled_world` start one tick later.** Each pushes
its first scene in `_enter_tree`, which used to land at once and now lands in
the first sweep. So every text tick the adventure's report records moves by
exactly one, and a tick that moves by any other number is a change the step did
not intend. `tiled_world` reads `media/` and is compared where that exists.

After 12d, `menu_navigation`'s Play reports `faded` for the cover's and the
reveal's frames, and nothing for Settings, which is pushed with
`transition: nil`. No input reaches a scene during a transition, so the drive
script waits the transition out after Play before it presses Enter, and its
header says why.

The adventure opens under a half-second reveal. Its `on_changed` asks for
`music.ogg` with the same fade, so its report shows thirty volume steps beside
thirty frames of `faded`: the picture and the sound arrive together. The room
reads no input while it is revealed, and the keyboard's track starts walking at
tick 10. So each of the script's tracks gains a lead of thirty idle ticks, and
the run grows by as many. Every text tick then moves by the same number, one
for the sweep and thirty for the reveal, and the landed note checks that it
does. The storm's timer is not input, so its flashes keep their ticks.

`docs/api/scene_graph.md`'s scene stack section gains names, the deferral,
`carry:` and transitions, and `docs/api/examples.md`'s `menu_navigation` entry
stops describing a hand-written switch.

---

## Step 13 — doors, entrances, and the teleport example *(rough)*

`examples/doors`: two rooms, a door between them that carries the hero and
places them at a named entrance, and a warp pad that moves them inside one
room. The adventure gains its second room. Doors come from a Tiled object layer
through `Engine::MapObjects`, and a door is a `replace` with `carry:` under the
stack's transition.

The adventure's door also crossfades between the rooms' music. The second track
is committed under `test_projects/adventure/` and does not ship
([decision 21](README.md#decisions-already-taken)). Which track waits on this
step: [open question 5](README.md#open-questions).

Watch for: `on_changed` fires when a switch lands, which is after the cover.
A crossfade that should start with the cover wants a signal at the request, or
the door starts it itself.

## Step 14 — cutscenes *(rough)*

`Engine::Cutscene::Script`, `Engine::Cutscene` and `Components::Cutscene`, with
the five step kinds and a skip that finishes the rest. `examples/cutscene`, and
the adventure's arrival scene, skipped with a held button. A cutscene that fades
uses step 10's `ScreenFade`.

`test_projects/tiled_world/cutscene.rb` is the 95 lines this replaces: the step
is done when that file could be written with the script instead.

## Step 15 — fold the plan back and delete it

Move what is still true into the documentation and remove
`docs/plans/v0.5.0-roadmap/`.

- **`docs/api/input.md`** — holds, taps and chords, `held_for`, and the
  presses a node never saw start.
- **`docs/api/systems.md`** — `Engine::Debug` and its channels; `AudioOut`'s
  transitions.
- **`docs/api/components.md`** — `Interactor`, `Collectable`, `Pushable`,
  `Grab`, `Particles`, `Cutscene`, and `pushes:` on `Mover`.
- **`docs/api/ui.md`** — the grid, focus groups, tabs and scrolling, and a
  rewritten "What this is not".
- **`docs/api/scene_graph.md`** — the scene stack's names, the deferral,
  `carry:` and transitions; `Node2D#opacity`; `ScreenFade`.
- **`docs/api/drawing.md`** — `blended`, `faded`, `debug_circle`.
- **`docs/api/audio.md`** — fades, crossfades, pause and resume, and categories
  a game names.
- **`docs/api/examples.md`** — every example this plan added.
- **`docs/api/toolbox.md`** — `Engine::Cutscene` beside `Tween` and `Timer`;
  `Util::ColorRamp`.
- **`docs/plans/possible-todos.md`** — new entries with their triggers:
  input sequences and double taps; ducking; a crossfade between two live
  scenes, which needs the render target already recorded there; partial rows in
  a scrolling menu; blend modes beyond `:add`, such as multiply; particles that
  stay where they were emitted when their node moves, Godot's `local_coords`;
  and a second music track in the gem, for a crossfade a shipped example can
  show. And the "connection that ends with its node" entry records that its
  trigger fired in step 3.
- **`CHANGELOG.md`** — checked against everything the plan shipped, per
  [update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
- **`README.md`** — the roadmap loses the nine items and says what is left.

### Verify

`rake` with no argument: `make test`, `rake spec`, `rake spec:core`. Every
driven example and both test projects report what they reported. `rake
docs:coverage` reports nothing undocumented. `docs/plans/v0.5.0-roadmap/` is
gone, and `grep -r v0.5.0-roadmap docs/` finds nothing.
