# Dialogue, and the state machine beneath it

**Status: steps 0–5 are implemented.** Steps 0–6 of
[the roadmap](04-roadmap.md) are detailed; 4–6 were re-planned after step 3
landed. Steps 7 and 8 are deliberately rough and get re-planned once the layer
beneath them exists.

| File | What it holds |
|---|---|
| [00-requirement.md](00-requirement.md) | the request, verbatim |
| [01-current-state.md](01-current-state.md) | what the engine has today, and what blocks a dialogue |
| [02-prior-art.md](02-prior-art.md) | Ruby state-machine gems, dialogue tools, quest systems, and what was rejected |
| [03-design.md](03-design.md) | the machine, the facts, the dialogue, the box |
| [04-roadmap.md](04-roadmap.md) | the order to build it in |

## Goal

Let a game hold a conversation: lines a character says, responses a player
picks, and responses that only some players may pick. Keep where a conversation
has got to apart from how it looks, and ship one look — a text box with a
response list. Build the part underneath so that a quest's progress uses the
same machinery.

## Verdict

**Two layers, one of them general, and a view that knows neither's insides.**

1. **`Engine::StateMachine`** runs a **`Engine::StateGraph`**: *states* joined by
   *transitions*, each transition with an optional condition and effect. It
   lists every transition out of the current state with whether it is available
   now, and takes one. It counts visits per state. That is the whole machine,
   and a quest is one with no additions.
2. **`Engine::Dialogue`** runs a **`Dialogue::Script`**: a state graph whose
   states are *beats* — a speaker and a line — and whose transitions a player
   picks are *responses*. It adds the words and a transcript, and nothing that
   decides where the conversation goes.
3. **`UI::DialogueBox`** draws one dialogue in one player's layer: the speaker,
   the line revealed a character at a time and paged by `UI::Label`'s machinery,
   and the responses in a `UI::Menu`. It reads the dialogue and calls it; the
   dialogue never learns the box exists.

Beside them sits **`Components::Facts`**, a small store for flags that belong to
no object — "met the smith", "the bridge is down". Conditions read it, effects
write it. **It is also what a game saves**: a machine built with a `name:`
registers with it, so `facts.to_h` holds every flag and every named quest and
conversation, and `restore` puts them all back in any order. A game's save is
that one entry plus its own objects. Settings stay in a `Util::SaveFile` of
their own.

**The engine ships its own machine rather than pointing at a gem.** The popular
gems declare states on a *class*, which fits one lifecycle per model and does not
fit a conversation built from data. And a dialogue the engine runs cannot sit on
a gem: rgame ships one runtime dependency. See
[02-prior-art.md](02-prior-art.md#ruby-state-machine-gems).

**The engine decides availability; the game decides visibility.** Every option
reaches the game with `available?`. The box takes `unavailable: :hide` or
`:disable`, and a game with its own view reads the flag directly. Yarn Spinner,
Godot's Dialogue Manager and Dialogic 2 all settled here.

## What was measured before planning

Taken at `118660a`, on this checkout.

| | |
|---|---|
| `rake spec` | 2424 examples, 0 failures, 21.2 s |
| State machines in `lib/rgame/engine/` | **0** — no `@state`, no state-shaped `case` |
| Examples or test projects with a conversation | **0** of 29 (25 examples, 4 test projects) |
| `UI::Menu` methods that remove a button | **0** — `add` only ([menu.rb](../../../lib/rgame/engine/ui/menu.rb)) |
| `renderer.clipped` coordinates | **window**, not the node's local space ([app.c:765](../../../ext/rgame_core/app/app.c#L765)) |
| Every prefix of a 43-character line, built once | 9 µs, 48 objects |
| Reading a prebuilt prefix 1000 times | 0 objects |
| Measuring every prefix of that line with `text_width` | 182 µs |
| `aasm` / `state_machines` / `micromachine` | 6.0.0 / 0.202.0 / 3.0.0 (last release 2017) |

## Hard constraints

1. **The engine layer may not name `RGame::Core`.** Everything here but the
   renderer calls is `RGame::Engine`, and a spec runs a whole conversation with
   no window.
2. **One runtime gem dependency, `rexml`, and no more.** The machine is ours.
3. **Text a player reads is a translation key.** A line, a speaker's name and a
   response label are keys, drawn through `Engine::Text`. `Game/NoLiteralText`
   holds it.
4. **Nothing on a draw path allocates or reads a clock.** The reveal advances in
   `update(dt)`, and `draw` indexes into strings built before it.
5. **No class, method, argument or doc sentence in this feature says "node"**
   for a part of a graph. The scene graph owns the word.
6. **`Node2D` and `Component` subclasses obey `SealedPrivates`.** The box and
   `Facts` choose, per non-public method, machinery (`_`) or seam.
7. **A fake must refuse what the real thing refuses.** If a step adds a renderer
   method, it lands in `a renderer` and in the fake in the same commit.

## Decisions already taken

Settled in the question round before this plan was written. Not up for
re-litigation inside the plan.

1. **Textbook words below, story words above.** The machine has *states* and
   *transitions*. A dialogue's states are *beats* and the transitions a player
   picks are *responses*. A quest's states are *stages*, a word only the docs
   use. Everyone who has met a state machine knows the lower layer, and the
   upper one reads like a script.
2. **A Ruby builder now; a data file is a possible-todo.** The builder is the
   graph's own construction API, and a later loader calls the same API. So the
   design keeps every part of a graph expressible as data: a condition or
   effect may be a Symbol naming a predicate the game registers, not only a
   block. See [03-design.md](03-design.md#a-file-format-later-costs-nothing-now).
3. **Conditions read a context the game hands in, plus the shared facts.** The
   bribe reads `hero.gold` from the hero; the game does not copy its gold into a
   store. The game saves its own objects as it does today.
   *Revised after the first draft:* the facts hold every named machine's state
   and visits, so the machines are one entry in a save rather than one line
   each. Listing each machine by hand was a rule a game had to remember, and
   forgetting one reset a quest silently. See
   [03-design.md](03-design.md#saving-the-world).
4. **"Going back" is a cycle in the graph, not an undo.** A response may lead to
   an earlier beat. Visit counts let a condition hide a question already asked.
5. **The shipped box reveals text a character at a time**, and confirm skips the
   reveal. No portrait: the box exposes a hook a game draws one from.
6. **Decision graphs only.** State moves on a choice or an event, a few times a
   minute. Per-frame behaviour — animation states, enemy AI — is out, and goes
   into `possible-todos.md` with its trigger: the second hand-rolled state
   machine in NPC code.
7. **A box sits in a `PlayerLayer`**, so a conversation belongs to the player
   who started it. *Revised by decision 12:* one conversation shown to every
   player in split screen is not a case to support.
8. **A text log ships.** The dialogue keeps a transcript, and the box can show
   it.
9. **Voice clips are out**, with everything that comes with them, and are not a
   possible-todo: nothing would trigger one.

Settled in a second question round, when steps 4–6 were re-planned:

10. **The engine keeps the transcript; the game decides what to do with it.** A
    transcript lasts one `Dialogue`. `on_ended` hands it to the game, which may
    save it, show it on a screen that is not saved, or ignore it. The engine
    makes saving possible — `to_h` and `Transcript.from` — and saves nothing by
    default. A signal rather than a return value, because the box calls
    `respond`, not the game. A whole-game backlog is a game listening to each
    dialogue's `on_ended`.
11. **`unavailable:` is a required keyword on the box.** Whether a response the
    player cannot pick is shown is a game decision, and a default would be the
    engine deciding for every game that does not look.
12. **One dialogue, one box, and the box has no input rule of its own.** In
    split screen everything belongs to a player: one player talks, in one box on
    their part of the screen, and the others are elsewhere. The only shared case
    is a conversation during `solo!`, where the game picks who drives it by
    setting the box's `input_owner`. "Everyone" is an input owner of its own,
    `Players#everyone`, because a title screen or a pause menu during `solo!`
    asks the same question.
13. **The continue is a button in the box's menu.** On a beat that continues,
    the menu holds one button, drawn as the ▼ marker, so every confirm the box
    acts on goes through the menu's press rules.
14. **The log is a paged `UI::Label` over the transcript**, *a* representation
    of it, as the box is of the dialogue. A game with its own log reads the
    transcript instead.

## Open questions

1. ~~**Does the transcript go into a save?**~~ **Settled — the game decides.**
   See [decision 10](#decisions-already-taken).
2. ~~**Default for `unavailable:`.**~~ **Settled — there is none; the keyword is
   required.** See [decision 11](#decisions-already-taken).
3. ~~**Does `RGame::Game` mount a `Facts` on the root by itself?**~~ **Settled
   in step 1 — yes.** `Game` mounts one beside `Players` and `Viewports`, and
   `game.facts` returns it. The counter-question was whether a game ever wants
   more than one store. The one case found is a second lifetime: a roguelike's
   unlocks beside its current run. That case still wants the root store, and
   mounts its second on the run's scene, where `node.system` finds it first.
   See step 1's landed note in [the roadmap](04-roadmap.md).
4. ~~**How a shared conversation takes input.**~~ **Settled — it is not a
   case in split screen, and during `solo!` the box's `input_owner` decides.**
   See [decision 12](#decisions-already-taken).

5. **Should a watch end when the node that made it leaves the tree?** A node
   that watches a fact in `on_add` must unwatch in `on_remove`, as with every
   signal the engine has. Forgetting is loud for a watch that moves a named
   machine, and silent for one that only sets a node's own state. Tying a
   connection to a node's lifetime would fix every signal, not only these, so
   it is a question for the engine rather than this plan. Found in step 1.
   Blocks nothing.

## What this does not deliver

- **A file format for graphs.** A possible-todo, kept possible by decision 2.
- **Per-frame state machines.** Decision 6.
- **Voice, lip-sync, or any audio per line.** Decision 9.
- **Portraits, speech bubbles over heads, or a box that follows a speaker.** The
  shipped box sits at a fixed place in a player's layer; the hook lets a game
  draw a portrait, and a game builds anything else on the dialogue directly.
- **Cutscenes.** A cutscene is beats with waits and fades between them, and
  wants the tween the complexity estimate names first. It builds on this plan
  and is not part of it.
- **Rich text inside a line** — colour, emphasis, an icon mid-sentence.
- **Breaking between characters**, for scripts written without spaces. Still
  under "Text layout past a label" in [possible-todos.md](../possible-todos.md).
