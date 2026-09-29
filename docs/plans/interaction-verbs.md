# Interaction: the verbs a target answers

**Status:** step 1 is implemented. Step 2 is detailed. Step 3 folds the plan
back and deletes it.

This plan takes up "Several verbs on one target" from
[research/additional_0.5.0_features.md](research/additional_0.5.0_features.md),
which keeps the other five features of that batch.

## Verdict

**Move the verbs from the actor to the target.** A new `Components::Interaction`
on the target maps input action names to methods of its node:
`Interaction.new(interact: :open, search: :search)`. The actor's `Interactor`
keeps the reach and the target a prompt is drawn over. It reads the actions it
was given, and on a press it calls the handler of the nearest target that
answers that action. A handler that takes `by:` receives the actor.

That removes the three workarounds the adventure carries today: the hero's own
`_control` reading the second verb, the lever's `def search = nil`, and a nearer
lever swallowing a hold meant for the chest. The chest keeps one collider, so
the y-sort's one-box rule never comes up. Finding the target stays one
broadphase query a tick: 26–29 µs against 26 µs today in a scratch prototype,
and no allocation.

`Interactor` first ships in 0.5.0, so its constructor and its signal may change.
Its two callers change with it.

## The request

As it arrived, in the research:

> * Several verbs on one target (tap to read, hold to search). Interactor takes one
>   action, so you read the second one off interactor.target in your own _control.
>   The adventure test project does this.

## Goal

A target answers several verbs, each on an action of its own. An actor reaches
the nearest target answering each verb, and nothing of this is written in the
actor's own code.

## Hard constraints

1. The engine layer stays pure Ruby and headless. `Interaction` names no Core
   class.
2. The `Interactor`'s `_update`, and its `_control` on a tick without a press,
   allocate nothing. Both run every tick for every actor.
3. A node keeps one collider. The y-sort, every `Mover`, `Footing`, `Platform`
   and `Navigator` read the node's one box, and `Collectable` and `Checkpoint`
   read its one collider.
4. `Targeting` shipped in 0.4.0, so it changes only by addition. `Interactor`
   has not shipped.

## Decisions already taken

Taken in conversation on 2026-09-29, and not up for re-litigation here:

1. **The verbs live on the target, in one component, as method names.** Blocks,
   and one component per verb, were weighed and rejected. See
   [Considered and rejected](#considered-and-rejected).
2. **A verb's key is the input action's name.** There is one vocabulary, the
   `InputMap`'s. `Interaction.new(interact: :open)` answers the `interact`
   action by calling `open`.
3. **A handler receives the actor as `by:` when it takes it.** `def open`
   ignores who acted, and `def search(by:)` hands the hat to `by`. A coin
   already acts on whoever touched it, so the direction is not new.
4. **The collider keeps its name.** `BoxBody` was weighed. rgame's
   `CharacterBody` is already a body, and a mover. The engines surveyed call the
   geometry a collider or a shape, and keep "body" for what moves or is solid.
   See [Prior art](#prior-art).
5. **The adventure changes last.** Step 1 rewrites the engine and keeps every
   caller working. Step 2 gives the adventure its second verb.
6. **The `Interactor` keeps no signal.** The handler on the target is the one
   place a press acts, and both listeners in the repository move there. A game
   that wants the actor to react to every interaction gets a signal when one
   asks for it.
7. **An `Interaction` raises at attach for an action no player's input map
   declares.** A misspelled key, `serach:`, would otherwise never be pressed and
   never raise. `Rooms` reaches `Players` at attach (`rooms.rb:139`), so the
   check can run there too. A scene without `Players`, such as a headless spec,
   skips it.

## What was measured before planning

At commit `117a423`, on Ruby 4.0.5 without YJIT. The prototype rows come from a
scratch script, not committed: 40 colliders 40 px apart, 10 of them targets, and
the hero among them with a reach of 56. Each figure is the best of two runs of
20,000 calls to one component's `_update`.

| | |
|---|---|
| `Interactor.new` outside specs and docs | 2: `examples/collectables/main.rb:150`, `test_projects/adventure/hero.rb:63` |
| `on_interacted` listeners | 4: `collectables/main.rb:184` and `adventure/hero.rb:66`, both `&:open`; `node2d_press_gate_spec.rb:245`; `collectable_spec.rb:235` |
| Examples in `interactor_spec.rb` | 13 |
| `docs/api/` lines naming `Interactor` | `components.md` 446, 823, 852 and the section at 928–952; `input.md` 230; `examples.md` 75 and 80 |
| Comments naming `Interactor` | `grab.rb` 23 and 26; the adventure's `bag.rb`, `hero.rb`, `chest.rb` and `lever.rb`; the collectables header |
| Targets answering a verb they have no use for | 1: `lever.rb:41`, `def search = nil` |
| Two Interactors in named slots, a tap and a hold on one key | work *(measured, in the research)*: a tap fires only the first, a hold only the second |
| A second `BoxCollider` on the chest, on a layer for the second verb | the adventure's drive raises at the first sorted draw, `Multiple components match BoxCollider`, from `node2d.rb:710` *(measured)* |
| `as:` outside specs | `examples/timer`, as `:beat` and `:chime`; `docs/api/`, as `:spawn` and `:life`; none in `lib/` or `test_projects/` |
| Finding the target, today's `Interactor` | 25.7 µs a tick, 0 objects *(measured)* |
| Broadphase, then `get_component(Interaction)` on each candidate | 26.0–28.5 µs a tick, 0 objects *(measured)* |
| A scene-wide list of interactions instead of the broadphase | 3.5–5.5 µs at 10 targets, 44 µs at 100, 174 at 400, 673 at 1,600. The broadphase stays at 27–35 µs at every count *(measured, 1,600 colliders)* |
| One press, today's `&:open` listener | 0.09 µs, 0 objects *(measured)* |
| One press, `public_send(:open)` | 0.12–0.17 µs, 0 objects *(measured)* |
| One press, `public_send(:search, by:)` | 0.29 µs, 1 object *(measured)* |
| One press, a block run with `instance_exec` | 0.14 µs, 1 object *(measured)* |
| `Actions#pressed?` for an action no map declares | raises, `actions.rb:82-83` |
| `Symbol#to_proc` called with a second argument | `ArgumentError` *(measured, in the research)* |

## What it resembles

**Reuse:**

- **`Targeting`**: the range, the policy and the `CollisionWorld` it queries.
  `Interactor` stays its subclass.
- **`require_sibling(Collider)`**: an `Interaction` needs its node in the
  broadphase, box or circle.
- **`Actions#pressed?`**: it raises on an action no map declares, which catches a
  misspelled action on the actor's side.

**Extend:**

- **`Interactor`** grows from one action to several, and from "a collider on
  this layer" to "a node whose `Interaction` answers this action".
- **`ActionTrigger`** is the shape: one component covering several actions,
  keyed by action name. `Interaction` takes the same key.
- **`Collectable`** is the direction: the target acts on whoever reached it, as a
  coin calls `carry` on whoever touched it.

**Genuinely new:** `Interaction`. Today nothing on a target declares what it
answers. The layer said it, and a collider has one layer.

**Resembles it, and left alone:** `Grab` is a verb on a target too, the crate.
It stays a `Targeting` on a layer. A grab holds across ticks and hands the crate
to the mover, where a verb is one press and one call.

## Prior art

The engines surveyed split the geometry from what it is used for, and none of
them calls the geometry a body:

| Engine | Geometry | What moves or is solid | A shape only queries read |
|---|---|---|---|
| Unity | `BoxCollider2D`, `CircleCollider2D` | `Rigidbody2D` | a collider with `isTrigger` |
| Godot | `CollisionShape2D` | `StaticBody2D`, `CharacterBody2D` | `Area2D` |
| Box2D | a shape on a fixture | `b2Body` | a fixture with `isSensor` |
| Bevy / Avian | `Collider` | `RigidBody` | a `Sensor` marker |
| KAPLAY | `area()` | `body()` | `area()` without `body()` |
| Excalibur | `Collider`, holding a `Shape` | `Body` | `CollisionType.Passive` |
| Defold | shapes on a collision object | Dynamic, Kinematic, Static | the Trigger type |

rgame's collider is solid only to a mover that names its layer in
`blocked_by:`, which puts it closer to KAPLAY's `area()` than to a body. The
survey decided the naming, decision 4. It did not decide the interaction API.

Sources:
[Unity: Collider2D.isTrigger](https://docs.unity3d.com/ScriptReference/Collider2D-isTrigger.html),
[Godot: Using Area2D](https://docs.godotengine.org/en/stable/tutorials/physics/using_area_2d.html),
[Box2D: Simulation](https://box2d.org/documentation/md_simulation.html),
[Avian: Sensor](https://idanarye.github.io/bevy-tnua/avian2d/collision/collider/struct.Sensor.html),
[KAPLAY: Physics](https://kaplayjs.com/docs/guides/physics/),
[Excalibur: Collision Types](https://excaliburjs.com/docs/collisiontypes/),
[Defold: Collision objects](https://defold.com/manuals/physics-objects/).

## Considered and rejected

- **Two Interactors on one layer, and every target answers every verb.** This
  works today with no engine code. But a nearer lever swallows a hold meant for
  the chest, and every target needs a method for every verb, as `lever.rb:41`
  shows.
- **Two Interactors, and the listener checks `respond_to?`.** The lever loses its
  placeholder. But a misspelled handler does nothing without a word, and the
  nearer lever still swallows the hold.
- **Two Interactors, and a layer per verb.** The chest carries a second
  `BoxCollider` on `:searchable`. The y-sort raises at the first draw
  *(measured)*, and every other reader of the node's one shape raises at attach.
  Fixing that needs a rule for extra shapes, an `Area` or a `Sensor`, with no
  other caller yet. The todo for a hitbox beside a feet box keeps that question.
- **One Interactor with `actions:`, emitting `interacted(target, action)`.** This
  was the research's option B. It runs one query, but a verb still goes to the
  nearest target whether it answers or not. The extra argument also breaks both
  `&:open` listeners with `ArgumentError`.
- **Blocks as handlers**, `with_interaction(:open) { ... }`. A block's `self` is
  wherever it was written. A block written in the room that builds a lever reads
  the room's ivars, and nothing raises. `instance_exec` fixes that for one object
  a press *(measured)*. A block also keeps its method's locals alive, and nothing
  about it can be checked at attach.
- **One `Interaction` per verb, in named slots.** Each verb gets a home for its
  own state. But the verb is written twice, in `Interaction.new(:search)` and
  `as: :search`. `get_component(Interaction)` raises on two, and two
  interactions for one verb go unnoticed. A slot the component names itself, its
  verb, would fix all three. Every `as:` today is a purpose its owner chose,
  though, so that hook would serve one caller. It waits, as open question 3.
- **A scene-wide list of interactions instead of the broadphase.** It is five
  times faster at 10 targets and slower past about 60 *(measured)*. The
  broadphase's cost does not grow with the number of targets.

## Design

### `Components::Interaction`

```ruby
module RGame
  module Engine
    module Components
      # What a node does when an actor's Interactor presses it: one method of
      # the node for each input action it answers.
      #
      #   chest.add_component(Interaction.new(interact: :open, search: :search))
      #
      #   def open = ...          # a handler may ignore who acted,
      #   def search(by:) = ...   # or take the actor as `by:`
      class Interaction < Engine::Component
        # `handlers` maps an input action's name to the name of a method on the
        # node. Raises ArgumentError with none, and for a name not a Symbol.
        def initialize(**handlers)
          super()
          @rgame_handlers = handlers.freeze
          @rgame_actions = handlers.keys.freeze
          @rgame_passes_by = {}
        end

        # The actions this answers, in the order given.
        sealed_reader :actions

        # hot-path
        def answers?(action) = @rgame_handlers.key?(action)

        # Calls the node's handler for `action`. `by` is the node that acted,
        # passed to a handler that takes a `by` keyword.
        def perform(action, by:) = ...

        # Raises without a Collider on the node, for a handler the node does
        # not have, and for an action no player's input map declares. Works
        # out which handlers take `by:`.
        def _attach = ...
      end
    end
  end
end
```

The rules its spec pins:

1. It answers exactly the actions it was given.
2. `perform` calls the node's method for the action, and passes `by:` only when
   that method takes a `by` keyword.
3. Attach raises `ArgumentError` for a method the node does not have. The
   message names the node's class, the action and the method.
4. Attach raises when the node has no collider. A box and a circle both do.
5. `new` raises with no actions, and for a method name that is not a Symbol.
6. A node holds one. A second one raises, since both take the class's slot.
7. Attach raises `ArgumentError` for an action no player's input map declares,
   naming the action. A scene without `Players` skips the check. Decision 7.

### `Components::Interactor`

```ruby
module RGame
  module Engine
    module Components
      class Interactor < Targeting
        def initialize(range:, actions: [:interact], policy: :nearest)
          super(range:, layer: nil, policy:)
          @rgame_actions = actions.dup.freeze
          @rgame_answerers = Array.new(actions.size)   # nearest Interaction per action
          @rgame_distances = Array.new(actions.size)
        end

        # The actions this reads, so a game can label its prompts:
        # `player.input_map.button_for(action, player.device)`.
        sealed_reader :actions

        # `target`, Targeting's reader, is the nearest node answering any of
        # `actions`. This is the nearest node answering `action`, or nil.
        def target_for(action) = ...

        # One query_circle pass fills the target and each action's answerer.
        # hot-path
        def _update(_dt) = ...

        # hot-path
        def _control(input)
          i = 0
          while i < @rgame_actions.size
            action = @rgame_actions[i]
            answerer = @rgame_answerers[i]
            answerer.perform(action, by: node) if input.pressed?(action) && answerer
            i += 1
          end
        end
      end
    end
  end
end
```

`layer:`, `action` and `on_interacted` go, the signal by decision 6. `target`
stays, for prompts.

The rules its spec pins:

1. `target` is the nearest node in range whose `Interaction` answers any of
   `actions`, or nil. A collider without an `Interaction` is never a target.
2. `target_for(action)` is the nearest node that answers `action`. It passes
   over a nearer node that does not.
3. A press on an action calls `perform(action, by: node)` on that action's
   answerer. It does so once per press, never while the action is held, and
   never when nothing answers.
4. It never targets its own node.
5. It asks every one of its actions `pressed?` each tick, before looking for an
   answerer. So an action the owner's map does not declare raises on the first
   control, whether or not anything is in reach.
6. Each player's Interactor reads that player's actions, so `by:` is that
   player's actor.
7. `_update`, and `_control` on a tick without a press, allocate nothing.

## Roadmap

```
1 Interaction + Interactor ──→ 2 the adventure's second verb ──→ 3 fold back
  (every caller keeps working)
```

### Step 1 — `Components::Interaction`, and an `Interactor` that reads it (pure)

Everything after this depends on the two components existing, and the
`Interactor`'s new constructor breaks both callers. So this step changes the
engine and every caller in one branch, and keeps each of them behaving as
before. The adventure changes only mechanically here, so step 2 can be read on
its own as the second verb.

- **1a. `Components::Interaction`.** A new file and its spec. Nothing uses it
  yet.
- **1b. The `Interactor` reads Interactions, and every caller follows.**
  - `examples/collectables`: the chest takes `Interaction.new(interact: :open)`.
    The room's `on_interacted` and the hero's delegator for it go. The header's
    paragraphs on the Interactor are rewritten, following
    [write-example](../../.claude/skills/write-example/SKILL.md).
  - `test_projects/adventure`: the chest and the lever take
    `Interaction.new(interact: :open)`, and the hero drops its `on_interacted`.
    The hero keeps its `_control` for `search`, and the lever its
    `def search = nil`, so the run reads as before. Step 2 removes both.
  - `node2d_press_gate_spec.rb` and `collectable_spec.rb`: their chests take an
    `Interaction`.
- **1c. Documentation.** A section for `Interaction` in `components.md`, and the
  `Interactor` section rewritten. The mentions at `components.md` 446, 823 and
  852, `input.md:230` and `examples.md:75-80`, and the header of `grab.rb`. The
  Unreleased `Interactor` entry in `CHANGELOG.md` describes both components.

**Tests:**

- `spec/rgame/engine/components/interaction_spec.rb`, new: the seven rules for
  `Interaction`.
- `spec/rgame/engine/components/interactor_spec.rb`, rewritten: the seven rules
  for `Interactor`, keeping the two-player cases.
- `node2d_press_gate_spec.rb` and `collectable_spec.rb`: the composed cases,
  with their assertions unchanged.

**Verify:**

- `rake spec` is green, and `rake spec:core` for the doc references and the
  coverage of `Interaction`'s public names.
- `ruby tools/drive_test_project.rb examples/collectables/main.rb --texts`
  reports what its script's header promises: "Coins: 0" to "Coins: 4" at ticks
  0, 43, 87, 155 and 216, "Press E" from tick 121 for 17 frames, and 1287
  `circle` calls.
- The adventure, driven with `--seed 4242 --texts --ticks 1640`, draws the texts
  it drew at `117a423`: "open" from tick 262, "searched" from 318, "hat" from
  353 and "pulled" from 644.
- `rake drive:allocations` passes.

**Landed.** The branch is `interaction-component`, with one commit per sub-step.
`Interaction` has `new(**handlers)`, `actions`, `answers?` and
`perform(action, by:)`. The `Interactor` has `new(range:, actions: [:interact],
policy: :nearest)`, `actions`, `target` and `target_for`, as sketched. Both
driven reports are byte-identical to `main`'s. `rake spec` passes 4524 examples:
19 in `interaction_spec.rb`, and 22 in `interactor_spec.rb`, up from 13.
`rake spec:core` passes 555, and `docs:coverage` finds no undocumented name.
`rake drive:allocations` passes all 44 projects.

- **The `Interactor` costs 6 µs a tick more than the prototype said.** In the
  measured arrangement, in one session, `main`'s layer-based `_update` takes
  21.8–22.6 µs and the landed one 28.0–29.2 µs, with one action or two. Both
  allocate nothing. The prototype had put the gap at 0.3–3 µs, against a 26 µs
  baseline taken in another run.
- **The adventure allocates 52 objects more over its run**: 82.3 a second on
  4.1% of ticks, against 80.2 on 3.9% at `main`, under a budget of 90. The trace
  puts the difference at attach. The chest and the lever are built again with
  each room, and each `Interaction#_attach` runs `require_sibling` and reads its
  handlers' parameters. A handler's first press allocates 5 objects while Ruby
  caches the call, and every later press allocates 0 *(measured)*.
- **The collectables Verify line was stale before this step.** The drive
  script's header said "Press E" from tick 121 for 17 frames. `main` draws it
  from tick 117 for 21 frames: the chest comes into reach ten ticks before it
  stops the hero. 1b corrects the header. The acceptance check is `main`'s own
  report.
- **Rule 6 held only without `as:`.** A second `Interaction` in a slot of its
  own would have made `get_component(Interaction)` raise at the Interactor's
  first update. `Interaction#_attach` now counts its node's Interactions and
  raises there.
- **Attach refuses a handler that needs an argument other than `by:`**, naming
  the method. The sketch would have raised `ArgumentError` on the first press.
- **The `Interactor` checks its `actions:`.** An empty list, a name that is not a
  Symbol, or a name given twice raises at construction. A name given twice would
  have performed twice per press. `target_for` raises for an action it does not
  read, where the sketch returned nil.
- **For step 2:** the adventure's chest and lever still sit on `:interactable`,
  and nothing in the adventure reads that layer any more. The collectables hero
  still reads it through `blocked_by:`.

Documented in `docs/api/components.md` under `Interaction` and `Interactor`,
with a complete example the doc specs run, and in `CHANGELOG.md`'s Unreleased
entry.

### Step 2 — The adventure searches through its Interaction

This is the change parked on the `interactor-verbs` branch, redone on this
design. The adventure is the one project with two verbs on one target, so it is
the acceptance test for step 1: a tap and a hold on one button reach two
handlers of one chest.

- **The chest** takes `Interaction.new(interact: :open, search: :search)`. Its
  `search(by:)` hands the hat to `by.carry` rather than returning it.
- **The lever** keeps `Interaction.new(interact: :open)`, and loses
  `def search = nil`.
- **The hero** takes `Interactor.new(range: REACH, actions: %i[interact search])`
  and loses its `_control`.
- **The header comments** of `hero.rb`, `chest.rb`, `lever.rb` and `bag.rb` say
  where each verb lives.
- **The `interactor-verbs` branch**, parked at `9542b9e`, is deleted. This step
  replaces it.

**Verify:** the adventure's texts match step 1's run. "searched" from tick 318
and "hat" from 353 show the hold reached `search`, and "pulled" from 644 shows
the tap still reaches the lever. `rake drive:allocations` passes.

### Step 3 — Fold the plan back and delete it

- Check `docs/api/components.md` and `input.md` against the landed code.
- Remove "`Interactor` takes one action" from `possible-todos.md`, under "Loose
  ends from cutscenes and interacting".
- Correct the header of `action_trigger.rb`. It says the engine allows one
  component of a class per node, and `as:` allows several.
- Move every open question still open to `possible-todos.md`, each with its
  trigger.
- Run [learn-from-mistakes](../../.claude/skills/learn-from-mistakes/SKILL.md)
  over the landed notes.
- Delete this file.

**Verify:** `CHANGELOG.md`'s Unreleased section describes `Interaction` and the
reworked `Interactor` the way a user of 0.4.0 reads them, per
[update-changelog](../../.claude/skills/update-changelog/SKILL.md). `rake spec`
and `rake spec:core` are green.

## Open questions

1. ~~**Does the `Interactor` keep a signal?**~~ **Settled: no.** See
   [decision 6](#decisions-already-taken).
2. ~~**Does an `Interaction` check its action names against the players' input
   maps?**~~ **Settled: it raises at attach.** See
   [decision 7](#decisions-already-taken).
3. **A slot the component names itself.** Deferred on 2026-09-29. It moves to
   `possible-todos.md` in step 3.
4. **`policy: :facing`**, the research's feature 2. The `Interactor` runs its own
   query, so a facing policy has to reach it as well as `Targeting#pick`. This
   does not block; the facing plan owns it.
5. **A verb a target cannot answer right now.** A searched chest still answers
   `search`, and its handler finds nothing. A prompt drawn per verb would still
   offer it. This waits for a game that draws a prompt per verb.

## What this does not deliver

- Choosing by facing: the research's feature 2.
- Extra shapes on one node, an `Area` or a `Sensor`: the todo for a hitbox
  beside a feet box.
- Availability or a prompt per verb: open question 5.
- `Grab` as a verb.
