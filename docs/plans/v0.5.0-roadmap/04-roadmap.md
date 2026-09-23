# Roadmap

**Status: steps 0 to 4 are implemented.** Fifteen steps. Each is one branch and one
pull request, and its sub-steps are one commit each. **Steps 0–7 are detailed**;
5–7 were re-planned after step 4 landed, and
[what that re-plan found](#re-planning-steps-57) comes before them. **Steps 8–14
are deliberately rough** and get re-planned once the layer beneath them exists.

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
| 5 | two open menus under one player both move and both confirm, and a bag cannot be a grid |
| 6 | a list longer than its panel cannot be shown, and a screen cannot have pages |
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
  step has a driven run of its own. Step 7 keeps `examples/equipment` and the
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

Steps 6 and 7 lay everything out on a grid, and an equipment screen is two
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

---

## Step 6 — tabs, and scrolling

A bag outgrows its panel once a game has more than a dozen things, and an
equipment screen is a second page beside the bag. Step 7 is built from both.
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

---

## Step 7 — `examples/equipment`, and the adventure's bag

The screen a game ships, and the first place a pickup reaches an inventory.
Steps 5 and 6 each proved their own parts. Here those parts meet collecting,
pausing and a second player.

### Sub-steps

- **7a** — `examples/equipment`.
- **7b** — `--texts` per clip in `tools/drive_test_project.rb`.
- **7c** — the adventure's bag: what each hero carries, on a page beside what
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

**A press can outlive the pause.** `:interact` is a tap, which fires on
release, and the mapper computes edges whether a paused hero reads them or not.
So E pressed in the bag and released within 0.3 s after I closes it opens what
is in reach, and E held across the close searches late. That takes I pressed
with E already down. The fix is every component acting only on a press it saw
start, as `Menu` does, which is an engine change this step does not make. It
goes to `possible-todos.md`.

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
   reads neither of its own actions.
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

`docs/plans/possible-todos.md` gains the press that outlives a pause.

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
