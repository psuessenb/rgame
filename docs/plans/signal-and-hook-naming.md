# Naming signals, hooks and the engine's own methods

**Status: decisions 1–6 are taken, and every open question is settled.** The
roadmap at the end is rough on purpose; each step gets detailed when it starts.
Nothing here is implemented.

This started as a naming rule for signals. It grew into four changes to public
API, most with a guard, and a new skill, so it gets a plan. It is not a full plan: no
prior-art survey and no question rounds. It records what a conversation on
2026-09-22 established and decided, so none of it is lost before the work
starts.

## Goal

**Code should say which mechanism it is before anyone reads the class.** A
game author writing a subclass either connects a block to a signal or
overrides a hook. Today both are spelled `on_<something>`, so the name gives no
hint which to do, and getting it wrong is silent.

## What was established

Read at `be45504`, on the `dialogue-box` branch, which has since merged as
`f9bbf90`. Tagged *measured* where it was
run, not just read.

### Two mechanisms share one prefix

| | Signal | Hook |
|---|---|---|
| Declared by | `signal :on_ended, Signal.define(:transcript)`, one line | `def on_draw(renderer, view); end` in the base class |
| A game author | connects: `talk.on_ended { \|transcript\| ... }` | overrides: `def on_draw(renderer, _view) = ...` |
| Names today | mostly past tense: `on_changed`, `on_opened`, `on_activated` | mostly present tense: `on_add`, `on_draw`, `on_update` |
| Exceptions | `on_beat`, `on_timeout` (nouns) | `on_focus_changed`, `on_buttons_changed`, `on_opened` (past) |

Nothing enforces either tense, by code or by written convention. Some English
verbs read the same in both tenses (`hit`), so tense alone cannot tell the two
apart.

The two already share a name in one subsystem. `UI::Menu` declares
`signal :on_opened`, and `UI::Navigation` has the hook `def on_opened`.

### Both mix-ups are silent — *(measured)*

```ruby
class Lever < RGame::Engine::UI::Button
  def on_activated = puts('pulled')  # meant as a hook
end
lever.on_activated { open_gate }     # runs the override once, here, and connects nothing
lever.activate                       # nothing happens

node.on_add { register }             # meant as a signal: Ruby ignores the block
```

Overriding a signal's name replaces the connect method that `Signal::DSL`
generated, so no listener is ever connected. Passing a block to a hook does
nothing, because Ruby ignores a block that a method does not use. Neither
raises. This is the failure
[Design out misuse](../../CLAUDE.md#design-out-misuse-the-right-thing-must-be-the-easy-thing)
rejects, and the same kind `Engine::SealedPrivates` already guards against for
machinery methods.

### The first case that raised it

`UI::DialogueBox#on_portrait`, added in step 5 of the dialogue plan, named a
thing, not an event. It was renamed `on_draw_portrait` on the same branch
(`be45504`). It is a hook, not a signal, which is how the two families came up.

### Renames are cheap now

As of 2026-09-22 the only user of rgame is its author. The gems are published,
but no search engine finds it. So the renames below cost only the engine's own
code, examples, specs and docs, and need no deprecation path. That is a fact
about the world, not about the code, and it stays out of CLAUDE.md.

### What was counted

| | |
|---|---|
| `signal` declarations in `lib/` | 18 |
| `signal` declarations in `examples/` and `test_projects/` | 7 |
| `<name>_signal` emit sites | 27, all inside the declaring class |
| Callers of `<name>_signal` from outside its class | 0: no `send(:on_x_signal)` anywhere |
| Declarations passing a signal class built elsewhere | 0: every one passes nothing or `Signal.define(...)` inline |
| Signals built outside the DSL | 3, all in `AudioBus` |
| Hook overrides (`def`) in `lib`, `examples`, `test_projects`, `spec` and `docs` | `on_draw` 104, `on_add` 58, `on_control` 40, `on_update` 35, `on_attach` 21, `on_detach` 6, `on_remove` 5, `on_focus_changed` 3, `on_draw_portrait` 3, `on_buttons_changed` 2, `on_opened` 2 |
| `Component` work hooks overridden (`def update`, `control`, `draw`), counted by file, roughly | update 17, control 6, draw 4 |
| Sealed machinery methods (`_` prefix) | 9, all in `Node2D`; `Component` has none |

The nine are `_children_in_order`, `_children_unsorted`, `_draw_content`,
`_in_local_space`, `_place_in_rotated_parent`, `_resolve_inherited`,
`_resolve_transform`, `_soil` and `_sort_children`.

## Decisions already taken

These were decided in conversation and are not reopened inside this plan.

### 1. A signal is declared by its event, and the DSL adds `on_`

**The declaration names the event, with no prefix. The DSL generates the
connect method with `on_` in front, so the connect side stays as it is:**

```ruby
signal :activated                      # no payload
signal :changed, :index, :value        # a payload of two fields

button.on_activated { ... }            # unchanged for every listener
changed_signal.emit(index: 2, value: :hard)   # inside the declaring class
```

What `signal :changed, :index, :value` generates:

| Generated | Visibility | Today's equivalent |
|---|---|---|
| `on_changed(&block)`: connects, returns the handle | public | `on_changed` |
| `changed_signal`: the Signal, built on first use, to emit on | private | `on_changed_signal` |
| `@changed_signal`: the instance variable behind it | — | `@on_changed` |

The rules the DSL follows:

1. **Fields are Symbols after the name**, and the DSL builds the class with
   `Signal.define(*fields)`. The form that passes a signal class
   (`signal :on_changed, ChangeSignal`) goes. Nothing in the engine, the
   examples or the test projects uses it; only the `Signal` module's own
   comment shows it. If a shared payload type is ever wanted, a Class as the
   second argument cannot be mistaken for a Symbol, so it can come back
   without breaking the short form.
2. **The payload behaves as it does now.** One field emits positionally,
   several emit as keywords, because `Signal.define` decides that and still
   does.
3. **The instance variable carries the `_signal` suffix, never the bare
   name.** A bare `@finished` would collide with state a class keeps under the
   same word. `Components::PathFollow` already has a `@finished` flag and
   `signal :on_finished`; with a bare name the first emit and the flag would
   overwrite each other, and nothing would raise.
4. **The emit reader is `<name>_signal`**, so an emit reads
   `activated_signal.emit`.
5. **The DSL refuses a name that starts with `on_`**, raising at class
   definition. That catches a declaration in the old style, and an `on_on_`
   connect method.
6. **The name is a verb in the past tense.** The test behind it: `on_<name>`
   reads as "when <name> happened". This is a written rule, not a check; no
   guard can tell tense. It roughly matches Godot, whose signals are past-tense
   verbs (`pressed`, `body_entered`) with no prefix, with `_on_` kept for
   handlers.

Every declaration renamed under rule 6. Most only lose `on_`:

| Today | Declared as | Connected as |
|---|---|---|
| `on_activated`, `on_changed`, `on_opened`, `on_closed`, `on_ended`, `on_finished`, `on_triggered`, `on_blocked`, `on_unblocked`, `on_joined`, `on_separated`, `on_hit` | the same word without `on_` | unchanged |
| `Dialogue#on_beat` | `beat_entered` | `on_beat_entered` |
| `Components::Timer#on_timeout` | `elapsed` | `on_elapsed` |
| `examples/` and `test_projects/`: `on_pressed`, `on_destroyed`, `on_confirmed` | without `on_` | unchanged |
| `test_projects/asteroids`: `on_fire` | `fired` | `on_fired` |

Why the two that change:

- **`on_beat` fails the test.** "When beat happened" does not parse, and "on
  beat" reads as the rhythm idiom. `beat_entered` names what and what happened.
  It also shows the distinction that matters: it fires only for beats, not for
  the line-less states a conversation passes through, which
  `StateMachine#on_changed` does hear. "Entered" is the word the script already
  uses, since a beat takes `enter:`. `arrived` (after the private `arrive` that
  emits it) was rejected: arrived where?
- **`on_timeout` passes the test, but `elapsed` also meets the tense rule and
  loses nothing.** "The interval elapsed" is true on every tick of a repeating
  timer, where "timeout" suggests an end. .NET's `System.Timers.Timer` names its
  event `Elapsed`. `expired` was rejected for the same reason as "timeout".
- **`on_hit` stays, but it is a weak pass.** It fires when two colliders start
  to touch, and its partner is `separated`. "Hit" suggests one thing striking
  another. Worth another look if the collision API changes anyway.

`AudioBus` is outside the DSL, and decision 4 removes it, so no signal is
left that the DSL does not declare.

### 2. The engine's own methods take `rgame_`, not `_`

The nine sealed methods in `Node2D` become `rgame_children_in_order`,
`rgame_draw_content` and so on. `Engine::SealedPrivates` keys on `rgame_`
instead of `_`, and `spec/rgame/engine/sealed_privates_spec.rb` follows. The
rule in CLAUDE.md, "`Node2D` and `Component`: an underscore seals a method",
changes with it.

- **Why `rgame_`:** it matches the C layer, whose engine functions are already
  `rgame_app_push_clip` and the like. No game names a method that by accident,
  and it greps cleanly.
- **Why not `__`:** it reads like Ruby's own `__send__` and `__id__`, and is easy
  to misread next to `_`.
- **Why not `engine_`:** a racing game's car node could have an `engine_power`.
- **Why a written rule although a guard exists:** the guard fires after the
  name is written. Stating the rule saves the round of naming a method wrongly,
  being refused, and renaming it.

### 3. Hooks take a leading `_`, not `on_`

A hook is a method the engine calls and a game overrides. It takes a leading
`_`, and `on_` then means a signal and nothing else. It matches Godot's
`_draw`, `_process` and `_enter_tree`. The `_` means "the engine calls this, you
don't", which is true of a hook. That meaning only holds once decision 2 has
freed `_` from marking machinery, so 2 lands first.

The hooks are guarded as well. Two guards were proposed; which to build is
settled with the implementation:

- **Overriding a signal.** `Signal::DSL` knows every name it generated. A
  subclass that `def`s one can raise at class definition, as `SealedPrivates`
  does.
- **A misspelled hook.** In `Node2D` and `Component`, a subclass that defines a
  `_` method which is not a known hook (`_updte`) could raise. Without it a
  misspelled hook is never called, and nothing says so.

The names after the prefix are [decision 5](#5-a-hook-is-named-after-the-step-it-runs-in).

**`UI::Navigation`'s three `on_` methods take plain names: `control`, `opened`
and `buttons_changed`.** They are not hooks on a subclass of the engine's
machinery. They are an interface a `Menu` calls on a separate strategy object,
and `Navigation` has no machinery behind these names to protect. It already
names its other two methods without a prefix, `attach` and `update`, so all
five then read alike. This also ends the clash with `UI::Menu`'s `on_opened`
signal.

Two alternatives were rejected:

- **Plain names for hooks.** `draw`, `update` and `control` are the machinery,
  and specs call `root.update(dt)` directly. Freeing those names would cost the
  headless-spec story.
- **`did_` and `will_`.** They fit notification hooks but not work hooks. A
  node does not `did_draw`; it draws.

### 4. Audio becomes a system on the root, and `AudioBus` goes

**`Game` mounts an audio system on the root, like `Players`, `Viewports` and
`Components::Facts`. A node plays a sound by calling it, not by emitting on a
global module.**

```ruby
node.system(RGame::Engine::AudioOut).play_sound(:boom)
```

It is taken first, because it removes the one signal user the DSL does not
cover, and decision 1 then applies to every signal in the engine.

**Signals were the wrong mechanism.** Read at `be45504`:

- **`AudioBus` carries commands, not events.** Its names are imperative:
  `play_sound`, `play_music`, `stop_music`. The docs call them "facts", but
  they are requests.
- **A command wants exactly one receiver.** Two listeners would play every
  sound twice.
- **Zero listeners is the failure that already happened.** `signals.md` says a
  signal with no listeners "emits to nobody, without error". That is how a
  forgotten director setup went silent, and why `Game#start` now subscribes
  one.
- **The bus adds no decoupling.** The events it was meant to separate from
  playback already exist as per-node signals: `on_hit`, `on_activated`,
  `on_destroyed`. A scene that wants a sound on a hit connects to `on_hit` and
  plays one. What the bus adds is a way to reach the sound device from
  anywhere, and reaching a shared object from anywhere in the tree is what a
  system is for (`docs/api/systems.md`).

**What the move removes:**

- the module-level state in `AudioBus`, and the module itself;
- `AudioDirector#subscribe`, `#unsubscribe` and the handles they keep;
- the `ensure` in `Game#start` that unsubscribes the director;
- the paragraph, in `AudioDirector`'s comment and in `docs/api/toolbox.md`,
  explaining how a global listener keeps an `App` and its window alive. A
  system on the root is released with the tree;
- the `after { director.unsubscribe }` in `audio_director_spec.rb`, which keeps
  examples from leaking into each other through the global;
- the "module-level hub" section of `docs/api/signals.md`, and its advice to
  use one for concerns that cut across the game. `AudioBus` is its only
  instance.

**What it costs:**

- **Only a node in the tree reaches it.** Every current call site is one: an
  `on_control`, an `on_activated` block, an `on_remove` (the node is still in
  the tree then), and scene methods. That is 5 call sites in `examples/`, 5 in
  `test_projects/asteroids`, and the docs.
- **Code that is not a node** is handed a node or the system. A quest effect
  that wants a sound needs its machine's `context:` to be something that can
  reach one, such as the node the game built the quest in.
- **An engine spec of a node that plays a sound** mounts a `FakeAudio`-backed
  system in the example. That replaces subscribing to a global and
  unsubscribing after.

**The layering does not change.** The system holds the audio server handed to
it and calls it by name, as `AudioDirector` does today. `Core::Audio` already
answers `play_sound`, `play_music` and `stop_music`.

**`Game` gains an `audio:` keyword**, beside `input:`.
`tools/drive_test_project.rb` records sounds today by redefining `audio` on the
game's class, so the audio server can be wrapped in a probe. `input:` is the
seam the same tool already uses for input, and `audio:` replaces the
redefinition with the same kind of seam.

**`Game` needs no wider refactoring.** Most of it is glue that is specific by
design: the renderer, the presentation, the asset loaders, the locales, and
polling input once per tick. The one repetition is the systems: each is built
in `initialize`, mounted in `start` and exposed with an `attr_reader`. That is
three blocks today and four with audio. A registry for four lines would
generalise ahead of any need, since nothing replaces a default system yet.

`Engine::I18n` is the other global module. It stays: it holds process-wide
data with no handle behind it, and `Text` reads it on draw paths, where a tree
lookup would cost.

**The system is called `AudioOut`.** It takes over what `AudioDirector` does,
and `AudioDirector` goes with `AudioBus`. The name is dry but accurate. The
others were rejected:

- **`Audio`** would be legal in `Engine`, but `RGame::Engine::Audio` and
  `RGame::Core::Audio` would sit side by side, and `Game` and the docs name
  both. Every "Audio" in prose would need its namespace.
- **`AudioBus`**: in audio tooling a bus is a mixing channel, like Godot's
  audio buses or the music and effects groups a volume slider controls. If
  rgame grows volume groups, that is the name they want. Keeping it would also
  keep a name whose meaning changed underneath it.
- **`Speakers`**: the dialogue system already uses the word, for who says a
  line (`speakers.smith`).
- **`Mixer`** stays free. It implies volume and mixing, which this does not do.
- **`AudioDirector`** described a subscriber reacting to events, not a system a
  node calls.

**A missing `AudioOut` raises, naming what is missing.** `Game` mounts it on the
root, and a game never needs to replace or remove it. So a missing one happens
in a spec or a driven run, and the message says what to do: "no AudioOut
system on the root; `RGame::Game` mounts one, a spec mounts one built on
`FakeAudio`". Plain `node.system(...)` returns nil, and `nil.play_sound` would
name nil, not the system.

That needs a lookup that raises. The happy path costs what `Node2D#system`
costs: a walk up the parent chain and a scan of the anchor's components, which
allocates nothing. The message String is built only in the branch that raises.
Whether the lookup is a raising variant of `Node2D#system`, which `Players`,
`Viewports` and `Facts` could use too, or specific to audio, is decided in
step 1.

### 5. A hook is named after the step it runs in

**The name after the `_` is the step the engine is performing when it calls
the hook, in the present tense.** The machinery already carries those step
names, so most hooks follow from it:

| Machinery | Hook today | Hook |
|---|---|---|
| `Node2D#draw`, `#update`, `#control` | `on_draw`, `on_update`, `on_control` | `_draw`, `_update`, `_control` |
| `Node2D#enter_tree`, `#exit_tree` | `on_add`, `on_remove` | `_enter_tree`, `_exit_tree` |
| a component attaching and detaching | `on_attach`, `on_detach` | `_attach`, `_detach` |
| `Node2D#draw`, `#update`, `#control`, for a component | `draw`, `update`, `control` | `_draw`, `_update`, `_control` |
| `Button#focused=` | `on_focus_changed(focused)` | `_gain_focus`, `_lose_focus` |
| `UI::DialogueBox`'s draw | `on_draw_portrait` | `_draw_portrait` |

Why this shape, from how others name their hooks:

- **Work hooks are the step's name nearly everywhere.** Godot's `_process` and
  `_draw`, Unity's `Update`, LÖVE's `love.update(dt)` and `love.draw()`, and
  Gosu's `update` and `draw`, from which rgame's loop came.
- **Notification hooks vary.** Godot names the transition after its own step
  (`_enter_tree`, `_exit_tree`), Unity and Bevy use a present-tense event
  (`OnEnable`, `on_add`), and Ruby core the past participle (`inherited`,
  `included`). Godot's shape fits rgame, whose machinery is already called
  `enter_tree` and `exit_tree`.
- **Tense becomes a second cue.** The prefix tells the mechanism apart. Hooks
  are then present tense (`_enter_tree`) and signals past tense (`on_entered`),
  so the two conventions never produce the same shape.

Two rows are more than a rename:

- **`Component`'s work hooks have no prefix today.** A component author
  overrides `update(dt)`, `control(actions)` and `draw(renderer, view)`
  directly, because `Component` wraps no machinery around them. So `Node2D`
  says `on_update` where `Component` says `update`, and the two classes a game
  subclasses already disagree. Under this decision both say `_update`.
- **`on_focus_changed(focused)` splits into `_gain_focus` and `_lose_focus`.**
  A present-tense `_change_focus` reads as a command, and the hook changes
  nothing. Only two specs override it.

### 6. The rules live in a `write-ruby-code` skill

**A new skill, `.claude/skills/write-ruby-code/`, holds the Ruby rules**, next
to `write-c-code`. The three naming rules go there. The fold-back step decides
what else moves from CLAUDE.md; candidates are the `Node2D` and `Component`
sealing rule, the `Engine::Text` rule for a label built from a changing value,
and the Ruby conventions line.

**`write-plan` must load it before a Ruby sketch.** A skill loads when its
description matches the task or when something says to load it, and
`write-plan` links only `write-prose` today. That matters here, because names
get decided in plans. `on_portrait` came from the dialogue plan's step 5c
sketch, `def on_portrait(renderer, speaker); end` in `04-roadmap.md`, and was
implemented as written. So:

- `write-plan` gains a line: a step's concrete shape is code, so load
  `write-ruby-code`, or `write-c-code` for C, before writing it. It is the
  pattern CLAUDE.md already uses for `write-prose`.
- `write-ruby-code`'s description names "a Ruby sketch in a plan" as a
  trigger, as a second way in.
- CLAUDE.md lists it with the other skills in "Code comments, documentation
  and code style".

## Open questions

1. ~~**Do hooks need a naming convention after the prefix?**~~ **Settled: a
   hook is named after the step it runs in, present tense.** See
   [decision 5](#5-a-hook-is-named-after-the-step-it-runs-in).
2. ~~**Where do the three rules live?**~~ **Settled: in a new
   `write-ruby-code` skill, which `write-plan` loads before a Ruby sketch.** See
   [decision 6](#6-the-rules-live-in-a-write-ruby-code-skill).
3. ~~**What happens to `AudioBus`?**~~ **Settled: it goes, and audio becomes a
   system on the root.** See
   [decision 4](#4-audio-becomes-a-system-on-the-root-and-audiobus-goes).
4. ~~**What is the audio system called, and what does a missing one do?**~~
   **Settled: `AudioOut`, and a missing one raises with a message naming it.**
   See [decision 4](#4-audio-becomes-a-system-on-the-root-and-audiobus-goes).

## What this does not cover

- Renaming anything beyond signals, hooks, the sealed machinery and the audio
  system. Other public names keep theirs.
- Moving `Engine::I18n` off its global module. See decision 4.
- A cop that checks a signal's tense. Rule 6 is a written rule.
- `Components::Mover`'s private `take_step` and other hooks an engine subclass
  writes for its own subclasses. `SealedPrivates` does not cover them today,
  and this plan does not change that.

## Roadmap *(rough)*

Each step is a branch and a pull request, and gets detailed once the step
before it lands.

```
1 audio system ─→ 2 signal DSL ─→ 3 rgame_ prefix ─→ 4 hooks take _ ─→ 5 rules written, plan deleted
```

1. **`AudioOut` on the root.** Decision 4: the system mounted by `Game`, the
   raising lookup, `Game`'s `audio:` keyword, the call sites in `examples/` and
   `test_projects/asteroids`, the drive tool's probe moved onto `audio:`, and
   `AudioBus` and `AudioDirector` removed. The docs that name it change:
   `audio.md`, `toolbox.md`, `signals.md`, `game.md`, `components.md`,
   `systems.md` ("The three systems `Game` mounts" becomes four) and
   `examples.md`.
2. **The signal DSL and every declaration.** Decision 1 with its guard, the
   renames in its table, `docs/api/signals.md`, the `Signal` module comment, a
   comment in `tools/strip_comments.rb` that names `signal :on_hit`, and the
   declarations `spec/tools/comment_stripper_spec.rb` feeds the stripper as
   text.
3. **`rgame_` for the machinery.** Decision 2, with `SealedPrivates`, its spec
   and the CLAUDE.md rule.
4. **Hooks take `_`.** Decisions 3 and 5, with the guards. `Component`'s
   work hooks, the split focus hook and `Navigation`'s plain names are part of
   it. It is the largest step:
   about 280 `on_` definitions and about 27 component work hooks, plus their
   calls and docs.
5. **Fold back and delete this plan.** Decision 6: `write-ruby-code` with the
   naming rules and whatever else moves from CLAUDE.md, the line in
   `write-plan`, and the listing in CLAUDE.md. `CHANGELOG.md` gets checked
   against every rename.
