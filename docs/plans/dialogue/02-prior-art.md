# Prior art

Three questions, asked of the tools that answer them best: whether a Ruby gem
should run the machine, how dialogue tools shape a conversation, and how games
track a quest.

## Ruby state-machine gems

Checked on RubyGems at the time of writing *(measured)*:

| Gem | Version | Runtime dependencies | Shape |
|---|---|---|---|
| `state_machines` | 0.202.0 (2026-07) | none | states and events declared on a class |
| `aasm` | 6.0.0 (2026-07) | `concurrent-ruby` | states and events declared on a class |
| `statesman` | 13.3.0 (2026-08) | none | a class per machine, transitions stored as records |
| `workflow` | 3.1.1 (2024-06) | none | states and events declared on a class |
| `finite_machine` | 0.14.1 (2023-10) | `concurrent-ruby`, `sync` | a class or an instance |
| `micromachine` | 3.0.0 (2017-08) | none | an instance: `machine.when(:confirm, new: :confirmed)` |

**Every popular gem describes a class's lifecycle.** `aasm` and
`state_machines` put states and events in the class body, and generate methods
per event on it — `order.ship!`, `order.may_ship?`. That is right for an order
or an account: one diagram, thousands of objects. A conversation is the reverse:
one object per diagram, and dozens of diagrams per game. Written as a class, each
conversation would be a class with a generated method per response.

**The one instance-shaped gem is too small.** `micromachine` takes a machine per
instance, which is the right shape. It has no guard on a transition, so it
cannot express the bribe, and it has had no release since 2017.

**And the engine cannot depend on any of them.** rgame ships one runtime gem,
`rexml`, and CLAUDE.md treats a second as a deliberate decision. A dialogue box
the engine ships needs a machine the engine ships.

So the machine is ours, and its whole surface fits on a page: build a graph,
list what leads out of the current state and whether it is available, take one,
fire an event, count visits, save and restore. `docs/api/` should still say when
a game is better served by a gem: a lifecycle shared by many objects of one
class, such as every door in a level, fits `state_machines` better than a graph
per door.

## Dialogue tools

| Tool | A conversation's unit | A response | A failed condition | Visit counts | State it owns |
|---|---|---|---|---|---|
| [Ink](https://github.com/inkle/ink/blob/master/Documentation/WritingWithInk.md) | knot, stitch | choice | **dropped** before the game sees it | per knot and stitch | its own variables |
| [Yarn Spinner](https://docs.yarnspinner.dev/api/csharp/yarn/yarn.optionset/yarn.optionset.option/yarn.optionset.option.isavailable) | node | option | delivered, `IsAvailable` false | `visited()`, `visited_count()` | its own variables |
| [Godot Dialogue Manager](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/2to3.md) | title | response | delivered, `is_allowed` false (since v3) | — | none: reads the game's objects |
| [Dialogic 2](https://docs.dialogic.pro/classes/class_dialogicchoiceevent.html) | timeline | choice | per choice: hide or disable | — | its own variables |

**What they agree on.**

- **A response carries a condition, and a failed one reaches the game.** Three
  of four hand it over flagged. The two that changed their minds changed toward
  this: Godot's Dialogue Manager made it the default in v3, and Yarn Spinner's
  Unity view gained `showUnavailableOptions`. Ink is the exception, and its
  unit of writing is prose, not a menu.
- **A conversation is a graph with cycles.** Every one of them jumps back to an
  earlier unit by name. None keeps an undo history.
- **A line is addressed, not inlined.** Yarn Spinner tags every line with an id
  for its string tables; Dialogue Manager exports lines to CSV for translators.
  In rgame the line is a translation key from the start.
- **A log is a record the dialogue keeps, drawn by the game.** Dialogic 2 keeps
  one in its [History subsystem](https://docs.dialogic.pro/classes/subsystem_history.html);
  Ren'Py ships a history screen.

**Where they differ, and which side rgame takes.**

- **Who owns the variables.** Ink, Yarn and Dialogic own theirs, so a game
  copies its gold in. Dialogue Manager owns none: its conditions read the game's
  objects directly, through
  [`extra_game_states`](https://github.com/nathanhoad/godot_dialogue_manager/blob/main/docs/Conditions_Mutations.md).
  rgame takes Dialogue Manager's side for objects — a context the game hands in
  — and adds a small store for flags nothing owns (decision 3).
- **Whether a response is once-only by default.** Ink's `*` choice disappears
  once taken and `+` makes one sticky. rgame's responses stay by default. A
  condition over visit counts hides one, and `once: true` is the shorthand for
  "only while its target has never been visited". Ink ties once-only to the
  choice itself; tying it to the target lets the machine count states only,
  which is one Hash in a save.

**What none of them gives us.** Each is a language with a compiler, or an editor
plugin, or both. None separates the machine from the dialogue: Yarn's virtual
machine runs Yarn and nothing else, and a quest in any of them is a conversation
nobody reads. None is written for a translation table the game already has.
Their lessons carry over; their shape does not.

## Quest systems

- **Stages.** Skyrim's Creation Kit gives each quest numbered stages, set and
  tested by script (`SetStage`, `GetStage`). Most quests only move forward, and a
  stage is a state.
- **A facts database.** The Witcher's REDkit keeps a
  [facts database](https://redkitwiki.cdprojektred.com/facts.htm): named
  numbers, set by quest blocks and scripts, tested by quest conditions. A value
  of 1 means "true" by convention. That is `Components::Facts`, and the name
  comes from there.

**A quest is a state machine whose transitions fire on events**, where a
dialogue's fire on choices. The same graph serves both if a transition can be
taken by name (an event) or by picking it from a list (a choice). That is the
whole generalisation, and it is the design's reason for one machine.

## Considered and rejected

**Wrap a gem behind our own API.** It would let a game use the gem's extras.
It fails constraint 2 — one runtime dependency — and every candidate is
class-shaped, so the wrapper would generate a class per conversation to fit it.

**Owned variables, as Ink and Yarn do.** Self-contained, and a file format could
express every condition. But the game must copy its gold into the store before
each conversation, and a copy someone forgets is a bribe offered to a player who
spent the money. Rejected by decision 3; the facts store covers only what no
object owns.

**A history stack with `back`.** A browser's back button for dialogue, useful
for undo and for a log. Effects already run cannot be undone — the bribe is
paid — so `back` would restore the state and not the world. The log is a
transcript instead: a record, not a transition. Rejected by decision 4.

**A dialogue class that is not a state machine.** A tree of beats, walked by
the box. It is less code on day one. It would be the second graph walker the day
a quest needs one, which is the parallel-vocabulary smell CLAUDE.md names:
beat/state, response/transition, visited/visited, two of each.

**A new text widget for the reveal.** A `Typewriter` node beside `UI::Label`.
It would duplicate paging, alignment, the width and the language switch. A
reveal is a label that shows less of its page, so it extends the label.

**A clip to hide what is not yet revealed.** One draw of the whole line, clipped
at the revealed width, would build no prefixes. Clips are in window coordinates
and a node draws in local space ([F4](01-current-state.md#f4-a-clip-cannot-hide-the-unrevealed-part-of-a-line--measured)),
so the box would have to know where it is on screen, which
`Game/DrawInLocalSpace` forbids.
