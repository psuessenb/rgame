# Roadmap

**Status: steps 0–3 are implemented.** Steps 4–6 are detailed. Steps 7 and 8 are rough on purpose and get
re-planned when the step before them lands.

Each step is one branch and one pull request; each lettered sub-step is one
commit. [implement-step](../../../.claude/skills/implement-step/SKILL.md) covers
the rest.

## Dependency shape

```
0 state machine ─→ 1 facts ─→ 2 dialogue ─→ 4 transcript ─┐
                                                          ├─→ 5 box ─→ 6 log, everyone ─→ 7 example ─→ 8 fold back
                                3 label reveal ───────────┘
```

Step 3 depends on nothing here and can land at any point before 5.

## The invariant every step preserves

> **Where a conversation has got to never depends on whether, or how, it is
> drawn.** The machine, the facts and the dialogue load with `require "rgame"`,
> and `spec/` drives each of them to the end with no renderer.

From step 5 on, the box's spec drives a script through the box and compares its
transcript with the one the same script produces with no box.

## What lands even if the plan stops

| Through step | What a game has |
|---|---|
| 1 | quests: a state machine with conditions, events, visit counts and saves, and a shared facts store |
| 2 | branching dialogue for a game that draws its own box, and a spec check that no conversation strands a player |
| 3 | a typewriter reveal on any `UI::Label`, and `examples/intro` using it |
| 4 | a transcript of every conversation, handed to the game when it ends, which it may save |
| 5 | the shipped dialogue box, for one player or one per player in split screen |
| 6 | a log over the transcript, and one input owner for every player — a box, a title screen or a pause menu during `solo!` |

## What each step documents

The machine, the facts and the dialogue get one new page,
`docs/api/dialogue.md`, linked from the index in `docs/api/README.md`. Step 0
creates it, and each later step adds its own section. The reveal goes into the
`UI::Label` section of `docs/api/ui.md`, the box and its log into a section of
their own there, and `Players#everyone` into `docs/api/input.md`. The rules are in
[write-docs](../../../.claude/skills/write-docs/SKILL.md); the doc specs run every
example on the page.

---

## Step 0 — `Engine::StateGraph` and `Engine::StateMachine` *(pure)*

Everything else stands on it, and it is the one piece with no view to hide a
wrong rule behind. It lands first and alone, so its rules are argued with specs
and nothing built on top yet.

### 0a. The graph and its builder

```ruby
module RGame
  module Engine
    class StateGraph
      def self.build(start:, &) # => a frozen StateGraph

      attr_reader :start
      def state?(name)
      def transitions(name)       # => the frozen Array of transitions out of `name`
      def each_symbol             # yields every Symbol given as a condition or effect

      # One transition, frozen. `event` and `to` may be nil. The builder's
      # `if:`, `unless:` and `then:` land in `requires`, `forbids` and `effect`,
      # since Ruby keywords make poor reader names.
      Transition = Data.define(:from, :event, :to, :requires, :forbids, :effect, :data)

      # What `build`'s block runs against.
      class Builder
        def state(name, enter: nil, data: nil, &)
        def on(event, to: nil, if: nil, unless: nil, then: nil, data: nil)
        def go(to: nil, if: nil, unless: nil, then: nil, data: nil)
      end
    end
  end
end
```

`data:` is where a layer above keeps what the machine never reads — a beat's
line, a response's label. The machine passes it through untouched.

Rules:

1. `build` raises `ArgumentError`, naming the culprit, for: a `to:` naming no
   state; a start that is not a state; a state declared twice; `on` or `go`
   outside a `state` block.
2. A condition or effect is a callable or a Symbol. Anything else raises at
   build.
3. The graph, each state's transition Array and each transition are frozen.
4. A state no transition reaches is legal.

### 0b. The machine

```ruby
class StateMachine
  extend Signal::DSL
  signal :on_changed, Signal.define(:from, :to, :transition)

  def initialize(graph, context: nil, facts: nil, from: nil)
  attr_reader :graph, :context, :facts, :state

  def transitions               # => graph.transitions(state), or a frozen empty Array once ended
  def available?(transition)
  def take(transition)          # => the transition
  def fire(event)               # => the transition taken, or nil
  def visits(name)              # => an Integer, 0 for a state never entered
  def ended?
end
```

Rules — the six in
[the design](03-design.md#running-one), plus:

7. With both `if:` and `unless:`, the first must hold and the second must not.
8. `available?` on a transition from another state raises, as `take` does.

### 0c. Symbols, saving and resuming

- **A Symbol is sent to the context.** At construction the machine walks
  `graph.each_symbol` and raises `NoMethodError` listing every one the context
  does not answer. A graph with Symbols and no context raises the same way.
- **`to_h` and `from:`**, as in [the design](03-design.md#saving-one): the state
  as a Symbol and the visits as a Hash; `from:` takes String or Symbol state
  names, runs no effect, emits nothing, and raises `ArgumentError` for a state
  the graph lacks. `from: nil` starts fresh.
- A round trip through `Util::SaveFile` in a temporary directory, not a
  hand-written Hash, so the spec sees what JSON really returns.

### Tests

`spec/rgame/engine/state_graph_spec.rb`: each build error; frozen parts; `data:`
passed through; `each_symbol` finds conditions and effects on transitions and
states.

`spec/rgame/engine/state_machine_spec.rb`: the start state counted and entered;
the order of effect, change, count, enter, signal; `take` refusing an unlisted
and an unavailable transition; `fire` ignoring an event with no available
transition; `if:` with `unless:`; ending on a transition with no `to:`; an ended
machine listing nothing; re-entry from an effect and from a listener raising;
driving a second machine from an effect working; a Symbol predicate and effect
reaching the context; a missing predicate raising at construction, naming it;
`to_h`; resuming from a `SaveFile` round trip with no effect run; an unknown
saved state raising; `transitions` and `visits` allocating nothing
(`allocate_nothing`).

### Verify

`rake spec` green with the two new files. A quest from the design's `HAMMER`
graph, driven through all four stages in a spec, saved, and resumed at
`:found`. `docs/api/dialogue.md` exists with a "State machines" section whose
examples the doc specs run.

**Landed.** `Engine::StateGraph` in `lib/rgame/engine/state_graph.rb` and
`Engine::StateMachine` in `lib/rgame/engine/state_machine.rb`, as three commits,
one per sub-step. `docs/api/dialogue.md` has the "State machines" section, with
four headless examples the doc specs run and assert, and a row in the index.
`CHANGELOG.md` has one entry under Added.

`rake spec` ran 2716 examples, 0 failures, in 21.3 s; the two new files hold
46 of them. `rake spec:core` ran 474, 0 failures, and `rake docs:coverage`
reported 0 of 167 classes with undocumented names. `make test` ran 380 checks,
0 failures. The HAMMER quest runs through all four stages in
`state_machine_spec.rb`, saves through a `SaveFile` at `:found`, and resumes
there to finish and pay the reward.

What the sketch got wrong or left out:

- **The graph needs a reader for a state.** The sketch listed `transitions`
  but nothing returned a state's `enter:` or `data:`, which the machine runs
  and step 2's beats carry. `StateGraph#state(name)` returns a frozen
  `StateGraph::State` with `name`, `enter`, `data` and `transitions`.
- **State names, events and `to:` must be Symbols**, and anything else raises
  at build. `from:` turns a saved String back into a Symbol, so a state named
  by a String could never be resumed. The same rule step 1 applies to fact
  keys.
- **A `state` inside another state's block raises** too, a fifth build error
  the sketch did not list.
- **A saved nil state resumes the machine ended.** `to_h` of an ended machine
  has `state: nil`, and step 2's named dialogue that ended (rule 11) needs to
  read that back.
- **Re-entry raises `RuntimeError`**, the class the sketch left open. A
  listener that raises after the move leaves the machine moved: the state
  change is not rolled back. Nothing needs a rollback yet.
- **The missing-Symbol error names the context's class**, not its `inspect`,
  which for a game's hero would print every instance variable.
- **`facts:` is only kept.** Nothing reads it until step 1 builds the store.

---

## Step 1 — `Components::Facts`, and a quest that uses it *(pure)*

A condition that reads a flag needs somewhere for the flag to live before a
dialogue can read one. It also lets the machine meet its first real caller
before dialogue shapes it: a quest written against the finished step 0 either
reads well, or tells us what step 0 got wrong while it is still cheap.

### 1a. The store

```ruby
module RGame
  module Engine
    module Components
      class Facts < Engine::Component
        extend Signal::DSL
        signal :on_changed, Signal.define(:key, :value)

        def [](key)
        def []=(key, value)
        def fetch(key, ...)
        def key?(key)
        def delete(key)
        def watch(key, &)       # calls now, then on every differing value; returns the handle
        def to_h                # => { values:, machines: }, frozen
        def restore(hash)       # replaces every fact and machine entry; nil clears
      end
    end
  end
end
```

Rules:

1. Keys are Symbols; a String key raises `TypeError` rather than being turned
   into one, so a lookup by String cannot miss a fact set by Symbol.
2. Values are `nil`, `true`, `false`, an Integer, a Float or a String. Anything
   else raises `TypeError`, naming the key and the class. A Symbol value is
   refused with a message saying why: it would come back from a save a String.
3. Assigning the value a key already holds emits nothing.
4. `restore` accepts what `SaveFile#read` returns and checks every value by
   rule 2. It emits no `on_changed`, and calls `watch` blocks for each key
   whose value differs. `restore(nil)` clears everything.
5. `watch` calls its block with the current value when connected, including
   nil for a key never set.
6. No non-public method without a `_`, or `sealed_privates_spec.rb` lists it as
   a seam. There is no reason for one to be a seam.

### 1b. Machines by name

A game saves the facts, and the facts save every machine that has a name —
[the design](03-design.md#saving-the-world) has why.

```ruby
StateMachine.new(graph, context: nil, facts: nil, from: nil, name: nil)

class StateMachine
  def name
  def watch(&)          # calls now with the state, then on every change, restores included
end
```

Rules:

1. `name:` without `facts:`, or with `from:`, raises `ArgumentError`.
2. A second live machine under a name raises, unless the first has ended.
3. A named machine built after `restore` resumes from its entry, by the rules
   `from:` already has. With no entry it starts fresh.
4. `restore` puts each live named machine where its entry says, or at its start
   state with no entry. It runs no effect and emits no `on_changed`; `watch`
   blocks hear the new state.
5. An entry no live machine claims survives `restore` and `to_h` unchanged.
6. `restore` validates every value and every claimed entry first, and on a
   failure changes nothing.

### 1c. A quest across two machines

No new class: a spec where a hammer quest and a second machine — a gate that
opens when the facts say the bridge is down — share one `Facts` mounted on a
root, and each moves on because of the other. The gate follows the fact with
`watch`. This is the first caller using both the machine and the store. If it
reads badly, step 0 changes here.

### 1d. The record of what was left out

`docs/plans/possible-todos.md` gains "State machines for per-frame behaviour",
with decision 6's trigger: the second hand-rolled state machine in NPC or
animation code. It goes in now rather than at fold-back, so it cannot be lost
if the plan stops.

### Tests

`spec/rgame/engine/components/facts_spec.rb`: each accepted value type; each
refused one, with the Symbol message; String keys refused; `on_changed` once per
real change; `to_h` frozen and a copy; `restore` from a `SaveFile` round trip;
`restore` firing no `on_changed` and each differing `watch`; a failed `restore`
changing nothing; found with `node.system` from a descendant.

`spec/rgame/engine/components/facts_machines_spec.rb`: each rule of 1b, with
machines built both before and after `restore`.

`spec/rgame/engine/state_machine_quest_spec.rb`: the two-machine quest, through
to the end, saved as one `facts.to_h` and resumed. The gate is open after the
load without the spec opening it.

### Verify

`rake spec` green. The quest spec reads as a game author would write it — no
helper the spec invented to make the API bearable. The page gains a "Facts"
section. Open question 3 (whether `Game` mounts `Facts`) is answered in the
landed note.

**Landed.** `Components::Facts` in `lib/rgame/engine/components/facts.rb`, and
`name:` on `Engine::StateMachine`, as four commits, one per sub-step. A fifth
has `Game` mount the store, and a sixth removes the machine's `watch`.
`docs/api/dialogue.md` has a "Facts" section with two headless examples the doc
specs run, and the index row names it. `CHANGELOG.md` has one more entry under
Added. `docs/plans/possible-todos.md` has "State machines for
per-frame behaviour".

`rake spec` ran 2755 examples, 0 failures, in 22.2 s; the three new files hold
37 of them. `rake spec:core` ran 474, 0 failures, and `rake docs:coverage`
reported 0 of 168 classes with undocumented names. `make test` ran 380 checks,
0 failures. The quest spec builds both machines in `on_add` of two ordinary
nodes, as a game would, with no helper. It saves one `facts.to_h` at `:found`
and resumes in a village built after the load and in one built before. The gate
is open both times without the spec opening it. A save with no entry for the
gate opens it from the `bridge_down` fact alone.

What the sketch got wrong or left out:

- **Rule 2 of 1b was wrong, and 1c found it.** Refusing a second live machine
  under a name broke every scene a player enters twice: the machine built in
  `on_add` the first time is never ended, so the second `on_add` raised. That is
  the ordinary place to build a quest. **A new machine under a name now takes
  over.** It resumes where the old one had got to, and the old one raises
  `RuntimeError` if it is moved again. Two objects driving one quest still
  fail, on the first move rather than at build. Step 2's rule 11 composes with
  this unchanged.
- **A machine needs no `watch`; the sketch's was built and then removed.** It
  was meant for a mirror of a quest's state that hears a load. Nothing needs
  one: a transition's effect sets a fact, the save brings the fact back, and the
  scene watches the fact. The fact names what the scene cares about, such as
  `bridge_down`, and survives a quest's stages being renamed. Code that reads a
  machine when it needs to, such as a condition or a quest log drawing
  `quest.state`, needs no watcher either. The quest spec's gate already worked
  this way, and the machine's `watch` had no caller but its own specs.
- **`Facts#watch` needs an `unwatch`.** The sketch returned a handle with
  nothing to pass it to. A node that watches in `on_add` unwatches in
  `on_remove`, as every signal in the engine asks. Forgetting is loud when the
  stale watcher moves a retired machine, which raises. See open question 5.
- **The machine needs two `@api private` methods for the facts to call.**
  `parse_saved` checks an entry and `place` puts the machine there silently.
  The split lets `restore` check every machine before it moves any, and call
  fact watchers only once every fact and every machine is back.
  `Facts#register` is the third.
- **A machine's `name` must be a Symbol**, and a String raises `TypeError`, as a
  fact's key does.
- **Values that differ include `1` and `1.0`.** Both `Facts#on_changed` and
  `Facts#watch` compare with `eql?`, since a save writes them differently.
- **Step 2 has a name clash to settle.** `StateMachine#name` is the name it is
  saved under, while step 2's sketch gives `Dialogue#name` the speaker's
  `Engine::Text`. One of them needs another word before step 2 is written out;
  `speaker_name` for the dialogue's reads well.

Open question 3, whether `Game` mounts `Facts`: **yes, in a fifth commit.**
The spec mounted it with one line, and forgetting fails loudly on the first
named machine. But a store every save goes through is the engine's job. The
question that settled it was whether a game ever wants two stores. The only
case found is two lifetimes, such as a roguelike's unlocks beside its current
run. That case still wants the root store and mounts a second on the run's
scene, where `node.system` finds it first; `docs/api/dialogue.md` says so.
`Game#facts` returns the store, which exists from `Game.new`, so a game can
restore a save before `start`. A driven scratch game built a named machine in
`on_add` through `node.system` and found `game.facts`. `docs/api/systems.md`
now lists three systems `Game` mounts.

---

## Step 2 — `Engine::Dialogue` and `Dialogue::Script` *(pure)*

The words on top of the machine. It comes before any drawing so that the box
in step 5 is built against a dialogue whose rules are already pinned — and so
that the first conversation tested is one that reads and moves a quest, the
composition CLAUDE.md asks to be exercised first.

### 2a. The script

```ruby
class Dialogue
  class Script
    def self.build(start:, scope: nil, &) # => a frozen Script
    attr_reader :graph, :scope

    # Adds beat and respond to StateGraph::Builder's words.
    class Builder < StateGraph::Builder
      def beat(name, speaker:, line:, vars: nil, to: nil, enter: nil, &)
      def respond(label, to: nil, if: nil, unless: nil, then: nil, once: false)
    end
  end
end
```

Rules:

1. A beat compiles to a state whose `data` is its speaker and its line `Text`.
   Its own `to:` compiles to `on :continue, to:`. A beat with no responses and
   no `to:` compiles to `on :continue` with no `to:`, which ends it.
2. A beat with responses *and* a `to:` raises at build.
3. `line:` and `respond`'s label are keys under `scope:`, or an
   `Engine::Text`, used as it is. Anything else raises `TypeError`, as
   `Paragraph` does, so a String no translation reaches cannot get in.
4. `once: true` adds the condition "the target was never visited". On a
   response with no `to:` it raises: nothing to have visited.
5. `vars:` is a block or a Symbol returning the line's variables, called on
   entering the beat.
6. `state`, `on` and `go` still work inside a script, for a state with no line —
   a branch point that decides by condition alone.

### 2b. The run

```ruby
class Dialogue
  signal :on_beat, Signal.define(:beat)
  signal :on_ended

  def initialize(script, context: nil, facts: nil, from: nil, name: nil)
  attr_reader :script

  def speaker            # => the speaker Symbol, or nil once ended
  def name               # => the Engine::Text for speakers.<speaker>
  def line               # => the beat's Engine::Text, given its vars
  def responses          # => this beat's responses, a frozen Array
  def available?(response)
  def respond(response)
  def continue
  def waiting_for_response?
  def ended?
  def visits(beat) ; def context ; def facts
  def to_h
end
```

Rules:

7. `respond` on a beat that does not wait, or `continue` on one that does,
   raises. The box never has to guess which one confirm means.
8. `name` and `line` return the same `Text` object each time the beat is the
   same, so a label holding one needs no rebuild.
9. A conversation passing through a state with no line — rule 6 — arrives at
   the next beat within one `respond` or `continue`, and a state with no line
   and no available transition raises, naming it: the conversation would hang.
10. The context's Symbols are checked at construction, as the machine's are.
11. `name:` follows step 1b's rules, except that a saved conversation that has
    ended starts again at the first beat and keeps its visits. So `once:`
    holds across every conversation with a named dialogue, and within one
    conversation with an unnamed one.

*Settled before building, with the user:* the speaker's name is
`speaker_name`, and `name` stays the name the dialogue is saved under, as a
machine's is. And a second hang joins rule 9:

12. Arriving at a beat that waits for a response, with none available, raises,
    naming the beat. The player would have no way out.

### 2c. Checking every path *(added before building)*

Rules 9 and 12 raise while a player plays, which is the last moment to find a
dead end. A spec should find it first. `Engine::Exploration` walks every path a
dialogue or a machine can take and reports where one gets stuck:

```ruby
report = Engine::Exploration.run { Engine::Dialogue.new(SMITH, context: Hero.new, facts: Components::Facts.new) }

report.problems    # => [] — or one String per problem, with the path that reaches it
report.ends?       # whether some path ends
report.stuck       # each position with no way on, and the path there
report.unreached   # the states no path entered
report.truncated?  # whether it stopped at a limit before it had seen every position
```

Rules:

1. **The block builds a fresh world**, and the walk replays each path in a new
   one. Effects and facts behave as in play, and a condition sees only what the
   block set up and the walk's own moves changed.
2. **A move is any available transition**: a response or a continue for a
   dialogue, and any transition, fired or picked, for a machine.
3. **A position is stuck** when a move raises, or when a machine has
   transitions and none is available. A machine's state with no transitions is
   an end, as a quest's `:done` is.
4. **Positions are compared by state, the states visited, and the facts**,
   with visits counted as entered or not. A repeatable question does not
   multiply positions, and a condition that counts visits past one is explored
   as if it did not.
5. **`problems` lists every stuck position, no end reached, and a truncated
   walk.** Unreached states are not a problem, since the world a spec builds
   may leave a branch shut on purpose; a spec asserts on `unreached` itself.
6. **A block that builds a different world on a replay raises**, rather than
   reporting paths that do not exist.

It returns Strings rather than shipping an RSpec matcher, so a game's spec
writes `expect(report.problems).to eq([])` and the gem stays free of RSpec.

### Tests

`spec/rgame/engine/dialogue/script_spec.rb`: each rule of 2a.

`spec/rgame/engine/dialogue_spec.rb`: greeting to goodbye; a response hidden by
a condition still listed with `available?` false; `once:` dropping a question
after its answer; going back to an earlier beat; `vars:` reaching the line; each
misuse of rule 7; a lineless branch; resuming mid-conversation from a save;
a named dialogue talked to twice keeping a `once:` question hidden.

`spec/rgame/engine/dialogue_quest_spec.rb`: the smith script from the design,
with the hammer quest from step 1 on the context and a `Facts` on the root. A
response is unavailable until the quest reaches `:found`; taking it moves the
quest to `:done`; the bribe is unavailable with too little gold and available
with enough.

`spec/rgame/engine/exploration_spec.rb`: each rule of 2c, over a machine and a
dialogue; a dead beat and a hanging lineless state found with their paths; the
hammer quest and the smith script both reported clean.

### Verify

`rake spec` green. The three spec files run a whole conversation with no
renderer in the process — the invariant, checked by `no_graphics_spec.rb`
having nothing new to say. The page gains a "Dialogue" section, with the smith
script as its example.

**Landed.** `Dialogue::Script` in `lib/rgame/engine/dialogue/script.rb`,
`Engine::Dialogue` in `lib/rgame/engine/dialogue.rb` and `Engine::Exploration`
in `lib/rgame/engine/exploration.rb`, as five commits: one adding 2c to this
roadmap, one per sub-step, and one for the documentation, and then this
note.
`docs/api/dialogue.md` has a "Dialogue" section and a "Checking every path"
section, with five headless examples the doc specs run and assert, and the
index row names all three classes. `CHANGELOG.md` has two more entries under
Added.

`rake spec` ran 2835 examples, 0 failures, in 24.7 s; the four new files hold
75 of them. `rake spec:core` ran 474, 0 failures, and `rake docs:coverage`
reported 0 of 175 classes with undocumented names. `make test` ran 380 checks,
0 failures. The smith script runs from greeting to goodbye with no renderer in
the process, and `no_graphics_spec.rb` passes unchanged. In
`dialogue_quest_spec.rb`, the hammer response is unavailable until the quest
reaches `:found`; taking it moves the quest to `:done` and pays 100 gold. The
bribe is unavailable at 0 gold, available at 60, and leaves 10. An exploration
of that world reports no problems, with `:thanks` and `:bribed` unreached.

What the sketch got wrong or left out:

- **A line with `vars:` cannot be shared between conversations.** Rule 8 kept
  one `Text` per beat, on the frozen script. Two players talking to the smith
  at once would each call `with` on it, and both boxes would draw the last
  values. Each dialogue now clones such a line on first entry and keeps the
  clone, so rule 8 holds per dialogue. A line without variables stays shared.
- **A condition is called with the machine, not the dialogue.** The design
  writes `->(d) { d.context }`. The machine calls its blocks with itself, and
  the machine answers `context`, `facts` and `visits` exactly as the dialogue
  does, so the design's scripts run unchanged. Passing the dialogue would have
  needed a new keyword on `StateMachine` for no reader either lacks.
- **`vars:` Symbols are not in the graph.** They live in a beat's `data`, so the
  machine's construction check never saw them. `Script#each_symbol` adds them,
  and `StateMachine.check_answers`, `@api private`, lets the dialogue check
  every Symbol with one error.
- **`vars:` and the line must agree at build.** A line with variables and no
  `vars:` would raise on its first read, and `vars:` on a key line has no names
  to fill. Both raise `ArgumentError` at build.
- **`once:` and `unless:` cannot be combined.** Both land in the transition's
  `forbids`, and joining them in a block would hide an `unless:` Symbol from
  the construction check. Passing both raises.
- **Inside a beat, `on` and `go` raise, and `respond` outside one raises.** A
  beat's ways out are its responses and its `to:`, which is what lets
  `waiting_for_response?` read the first transition's event and allocate
  nothing.
- **States with no line that loop raise too**, a third way to hang the sketch
  did not list, found when a state is reached twice without a beat between.
- **Any save of an ended conversation starts again**, `from:` as well as
  `name:`. A dialogue that is ended when built is of no use to anything.
- **`StateMachine#available?` returned a condition's own value.** A condition
  answering nil made `available?` nil. It now answers true or false, with an
  example in `state_machine_spec.rb`.
- **A one-field signal emits positionally.** `on_beat_signal.emit(beat:)`
  handed listeners a Hash; `Signal.define` takes a single field as a plain
  parameter. The spec caught it.
- **The graph needed two more readers.** `StateGraph.assemble`, `@api private`,
  lets `Script` build through its own builder, and `StateGraph#state_names`
  lets `Exploration` list what it did not reach. `Dialogue#beat` returns the
  beat's name, which the sketch left out.
- **2c needed `key:`.** A condition on the context, such as gold earned in a
  loop, is invisible to positions compared by state, visits and facts. Without
  `key:` the walk takes every return to the greeting as the same position and
  never reaches the purchase. The spec shows both.
- **2c's replay guard fired on its own first caller.** The quest spec's first
  exploration added a new hero to one shared root on every replay, so the
  facts carried over; the walk raised on the first replay, as rule 6 says.
  Each replay now builds a new root.

Where it got documented: `docs/api/dialogue.md`, sections "Dialogue" and
"Checking every path", and `StateGraph#state_names` under "Building a graph".

---

## Step 3 — a reveal on `UI::Label`

Independent of everything above, and useful without it: an intro that types
itself out. It is here, before the box, so that the box composes a finished
label rather than growing its own text code.

### 3a. Prefixes and the count *(pure)*

The label builds each line's prefixes — one frozen String per grapheme cluster —
when its page's Array changes identity, which `Paragraph` guarantees happens
exactly when the text, the width or the page changes. A private helper, or a
small class beside `Paragraph` if the label grows too big to read; the step
decides by reading the result.

### 3b. The label's surface

```ruby
UI::Label.new(text:, width:, reveal: nil, **)   # characters per second, or nil for none

def revealed?
def reveal_all
```

Rules:

1. Without `reveal:`, drawing is unchanged, call for call.
2. With it, a new page starts with nothing shown, and `update(dt)` shows
   `reveal * elapsed` grapheme clusters, carried across lines in reading order.
3. `reveal_all` shows the whole page; `revealed?` is true once it is shown.
4. Turning the page, a new text and a new width each start the reveal again.
5. A draw between a page change and the next `update` draws the new page fully
   revealed, and builds nothing.
6. A paused label does not reveal: time enters through `update`.
7. `draw` allocates nothing, revealing or not.

### 3c. `examples/intro` types itself out

The example's header says a typewriter "belongs to a dialogue system, which this
is not". It now belongs to the label. Confirm reveals the page, then turns it;
the timer starts when a page is revealed. The drive script and the header change
with it, per [write-example](../../../.claude/skills/write-example/SKILL.md).

### Tests

`spec/rgame/engine/ui/label_spec.rb` gains each rule; `rule 7` is an
`allocate_nothing` example over 200 draws mid-reveal. A German line with an
umlaut built from a combining mark reveals it whole.

### Verify

`rake spec` green, and
`ruby tools/drive_test_project.rb examples/intro/main.rb --texts` shows prefixes
of the first line growing and the full pages after, with no missing keys.

**Landed.** `reveal:`, `revealed?` and `reveal_all` on `UI::Label` in
`lib/rgame/engine/ui/label.rb`, and `examples/intro` typing itself out, as four
commits: the reveal (3a and 3b together), a fix that driving the example found,
the example, and the documentation. `docs/api/ui.md` has a section "Revealing a
page a character at a time", and the intro's entries in `examples.md`,
`README.md` and `CHANGELOG.md` say it types itself out. The label's and the
intro's changelog entries were edited in place, since both are unreleased.

`rake spec` ran 2855 examples, 0 failures; `label_spec.rb` holds 38, 20 of
them new. `rake spec:core` ran 474, 0 failures, and `rake docs:coverage`
reported 0 of 175 classes with undocumented names. `make test` ran 380 checks,
0 failures. 200 draws mid-reveal allocate nothing. "Mu\u0308de", with the
umlaut built from a combining mark, shows "Mu\u0308" after two characters.

The intro, driven with `--ticks 1200 --texts` in both languages, draws "L" from
tick 2 and the first line whole from tick 59. Nothing of the story is drawn
whole at tick 0. Enter at tick 120 shows the rest of page 1 at tick 121. Every
later page starts one second plus 20 ms a character after the one before was
fully shown, about 210 ticks for a full page: English pages at 335 and about
735, German at about 332, 705 and 1092. The hint is drawn 735 frames in English
and 1092 in German, and no key is missing.

What the sketch got wrong or left out:

- **3a and 3b were one commit.** The prefixes are three private helpers on the
  label, with nothing to call them or spec them until 3b's surface exists. The
  label grew by about ninety lines, so no class beside `Paragraph` was needed.
- **Rule 5 would have flashed a page.** A page turned after the label's own
  update in a tick would draw whole for one frame, then blank, then type out.
  `page=`, `with` and `width=` now build the new page at once, off the draw
  path, so a turn starts from nothing on the next frame. Only a change the
  label cannot see coming, a language switch or `with` called on the `Text`
  itself, still reaches rule 5's whole-page draw.
- **The first frame is drawn before the first update**, so a label that built
  in `update` drew the first page whole and then blanked it. Driving the intro
  showed it; the spec had not. The label builds its page in `on_add`.
- **It builds nothing before it enters the tree.** `with` and `width=` often
  run in a node's `initialize`, before `Game` loads the translations, where a
  lookup would count as a missing key. One consequence: a label whose `Text`
  names variables now raises on entering the tree if `with` was never called,
  where before it raised on the first draw.
- **Each prefix sits where its whole line will stand**, which the sketch did not
  say. A centred line placed by its prefix's width would slide left as it grew.
- **`Components::Timer` cannot be stopped.** The intro's hold counts from a
  page being fully shown, so the root resets the one-shot on every tick while
  the page types. It works and reads plainly, but step 5's box may want a timer
  it can hold.
- **A flat hold after the reveal read as a stall.** The intro first kept its
  six seconds per page, counted from the page being shown, and a page sat
  finished for longer than it took to read. The hold is now one second plus
  20 ms a character, from `UI::Label#page_length`, a reader the sketch did not
  list. The reader has read along while the page typed, so the hold is only the
  time to finish.
- **The hint has never been visible, and the drive could not tell.** The
  intro's backdrop `rect` defaults to z 50 and its hint `text` to z 10, so the
  backdrop covers the hint in the same `on_draw`. Nine other examples hide
  their help text the same way. The drive records the calls, not what reaches
  the screen, so it reported the hint drawn on every frame. It is fixed in the
  engine's defaults on a branch of its own.

Where it got documented: `docs/api/ui.md`, "Revealing a page a character at a
time", and the `UI::Label` table.

---

## Re-planning steps 4–6

Steps 4–6 were re-planned after step 3 landed, in a question round whose
answers are now decisions 10–14 in [the brief](README.md#decisions-already-taken).
The old step 5 held a menu change, a label change, the box, a log view and a
shared conversation, which is two pull requests. It is now step 5, the box, and
step 6, the log view and an input owner that stands for every player.

### What was measured

Taken at `e251f69`, on this checkout.

| | |
|---|---|
| `rake spec` | 2856 examples, 0 failures, 20.9 s |
| A menu handed a button during a held confirm | **activates it on the release** — F3 was wrong; see below |
| `UI::Label` / `Engine::Paragraph` methods that change the text | **0** — both take `text:` once |
| Keeping one line's variables: clone its `Text`, give it the values | 6 objects |
| Breaking a 200-entry log at 440 px with `Typeface#text_lines` | 2.2 ms |
| Input owners that stand for more than one player | **0** — `Players#actions_for` answers for one |
| `renderer.triangle` | exists, in `a renderer` and the fake — the continue marker needs no new method |

**F3 was wrong, and the box would have tripped on it.** *(measured)*
[01-current-state.md](01-current-state.md#f3-a-menu-can-list-responses-and-cannot-change-them--measured)
says the confirm that finishes a line "will not" be read as a choice. A scratch
script built a parent that adds a button on a confirm press, as the box does
when a line ends at a beat that waits. The button activated on the release. The
menu keeps one `@confirm_seen_up` for its lifetime and `add` resets only the new
button's hotkey flag, while `Node2D#control` runs a parent's `on_control` before
its children's. So the menu reads the same press in the same tick. Step 5a fixes
it.

### What the three steps resemble

- **Reuse.** `UI::Menu` and its press rules, for every confirm the box reads,
  the continue included (decision 13). `UI::Label` with its reveal, for the
  line and for the log. `Text.computed`, for a log that renders again only when
  an entry arrives or the language changes. `input_owner`, for who drives the
  box. `queue_free`, for a box that removes itself.
- **Extend.** `UI::Menu` learns to drop its buttons. `Paragraph` and `Label`
  learn to change their text. `Players` learns an owner that stands for all of
  them. `Facts`' value check becomes the transcript's too: both answer "does this
  survive a `SaveFile`".
- **Genuinely new.** `Dialogue::Transcript` — nothing records a sequence of
  translated text — and `UI::DialogueBox`, the view.

---

## Step 4 — `Dialogue::Transcript` *(pure)*

The box's log in step 6 reads it, and a game receives it when a conversation
ends. It comes before the box so that the box is built against a record whose
rules are pinned, and it is small enough to land alone.

The engine keeps the transcript and hands it over; the game decides what to do
with it (decision 10). So it saves and restores, and nothing saves it by
default.

### 4a. The record

```ruby
class Dialogue
  signal :on_ended, Signal.define(:transcript)

  def initialize(script, context: nil, facts: nil, from: nil, name: nil, transcript: nil)
  def transcript   # => the Transcript, growing until the conversation ends, then frozen

  class Transcript
    include Enumerable

    # One line shown or one response picked. `speaker` and `speaker_name` are
    # nil for a response; `response` is nil for a line.
    Entry = Data.define(:beat, :speaker, :speaker_name, :text, :vars, :response)

    def each(&)
    def size
    def [](index)
    def empty?
  end
end
```

Rules:

1. **Arriving at a beat records its line**, re-arriving through a cycle
   included. A state with no line records nothing.
2. **`respond` records the response** before the next beat's line.
3. **`continue` records nothing**, and neither does a page turn: the line is
   already there.
4. **A line with variables keeps the values it was shown with.** Its entry holds
   a clone of the line's `Text`, given those values, and `vars` holds them
   frozen. A later visit with other values leaves the earlier entry as it was. A
   line without variables shares the script's `Text`.
5. **`on_ended` emits the transcript, frozen**, and `transcript` returns that
   same object afterwards.
6. **A conversation resumed with `from:` or `name:` starts an empty
   transcript.** Where a conversation has got to and what it said are two saves,
   and a game makes the second only if it wants to.
7. Reading allocates nothing: `each`, `size`, `[]`.

### 4b. Saving and restoring

```ruby
class Transcript
  def to_h                       # => { entries: [{ beat:, vars: }, { beat:, response: }] }, frozen
  def self.from(saved, script)   # => a Transcript, for Dialogue.new(transcript:)
end
```

Rules:

8. **An entry saves its beat and either its variables or its response's index**
   among the beat's responses. The words come back from the script, so a log
   restored after a language switch reads in the new language.
9. **`to_h` checks every variable by `Facts`' value rule** and raises
   `TypeError` naming the entry and the key. The check is `Facts`' own, made
   callable, not a copy. Only `to_h` checks, so a game that never saves never
   meets the rule.
10. **`from` accepts what `SaveFile#read` returns** — String beat names
    included — and raises `ArgumentError` for a beat the script lacks, a
    response index past the beat's responses, or variables that do not match
    the line's names.
11. `transcript:` on `Dialogue.new` continues the given transcript, which must
    be unfrozen; a frozen one is copied. It is how a game that saves
    mid-conversation gets its log back.

### Tests

`spec/rgame/engine/dialogue/transcript_spec.rb`: rules 1–4 over the smith
script; a cycle back to the greeting recorded twice; a lineless state recorded
nothing; a line with `vars:` keeping its first values after a second visit;
`to_h` through a `SaveFile` round trip and `from`; a restored log reading in
German after a locale switch; each refusal of rule 9 and rule 10;
`allocate_nothing` over reading.

`spec/rgame/engine/dialogue_spec.rb` gains: `on_ended` carrying the frozen
transcript; a resumed conversation starting an empty one; `transcript:`
continuing a saved one.

### Verify

`rake spec` green. The smith conversation, driven to the end with no renderer,
hands its listener a transcript whose `to_h` survives a `SaveFile` and reads in
German after `from`. `docs/api/dialogue.md` gains a "Transcript" section with a
headless example, saying that nothing saves a transcript unless the game does.

---

## Step 5 — `UI::DialogueBox`

The view the requirement asks for: "*a* possible representation", with the
speaker, the line typed out and paged, and the responses. It is built on a
finished dialogue (step 2), a finished reveal (step 3) and a finished record
(step 4), so the box adds only what a view adds.

### 5a. `UI::Menu#clear`, and a confirm that began before the buttons

```ruby
class Menu
  def clear   # => the menu
end
```

Rules:

1. `clear` removes every button from the menu and from the tree, focuses
   nothing, sets the bounds to zero and tells the navigation.
2. **A change to the buttons forgets a confirm already down.** After `add` or
   `clear`, the menu takes no confirm press until it has seen confirm up. This
   is the fix for the F3 finding, and it holds for `add` alone.
3. **A menu whose buttons change during its own `on_control`** — from a button's
   `on_activated` — reads no more input that tick, so a hotkey loop never
   presses a button added mid-loop.
4. A closed menu may be cleared.

Tests in `spec/rgame/engine/ui/menu_spec.rb`: each rule; the scratch script from
the measurements as a spec, a parent adding a button on a confirm press, now
activating nothing; clearing from `on_activated` and adding new buttons, none of
them pressed.

### 5b. A label and a paragraph that change their text

```ruby
Paragraph#text=(text)   # a key or an Engine::Text, as initialize takes
Label#text=(text)
```

Rules:

5. Either takes what `initialize` takes and refuses the rest with the same
   `TypeError`.
6. **`Label#text=` always starts again**: page 0, nothing revealed. It does so
   for the same `Text` object too, since the box shows a beat entered twice in a
   row with the same `Text`.
7. A label in the tree builds the new page at once, off the draw path, as
   `page=` does.

Tests in `paragraph_spec.rb` and `label_spec.rb`.

### 5c. The box

```ruby
module RGame
  module Engine
    module UI
      class DialogueBox < Node2D
        UNAVAILABLE = %i[hide disable].freeze

        def initialize(dialogue:, unavailable:, width:, lines_per_page: 3, reveal: 40,
                       typeface: Util::Typeface.default, panel: ShapeStyle::DEFAULT,
                       button_style: ShapeStyle::DEFAULT, padding: 12, portrait_width: 0, **)

        attr_reader :dialogue, :unavailable

        # A blank hook: draws the speaker's portrait in the `portrait_width`
        # the box keeps free at its left. Draws nothing unless a subclass does.
        def on_portrait(renderer, speaker); end
      end
    end
  end
end
```

It holds a `UI::Label` for the line, with the reveal, and a `UI::Menu` with a
`UI::Column`. On a beat that continues, or until a waiting beat's line is fully
shown, the menu holds one button: the continue marker, `activate_on: :press`,
drawn as a triangle with `renderer.triangle`. Every confirm the box acts on goes
through the menu's press rules (decision 13), so the box reads no input itself.

Its height is fixed at construction, from the most responses any beat in the
script has, so the box never resizes during a conversation.

Rules:

8. **`unavailable:` is required**, `:hide` or `:disable`; anything else raises
   `ArgumentError` (decision 11).
9. **Confirm does the next thing**: reveal the rest of the page; else turn the
   page; else, on a beat that continues, `continue`.
10. **A waiting beat's responses replace the marker once its last page is fully
    shown**, by the reveal or by confirm. By rule 2 the confirm that finished the
    line picks nothing.
11. **Availability is asked once per beat**, when the responses appear. No
    condition runs on a frame without a move.
12. `:hide` adds the available responses only. `:disable` adds all of them and
    disables the rest, so `Stepping` passes over them.
13. **After each move the box reads the dialogue back**: the new line through
    `Label#text=`, the speaker, and the marker. The box is the only thing that
    moves its dialogue (decision 12), so it needs no listener.
14. **When the conversation ends, the box frees itself** with `queue_free`. The
    game hears `Dialogue#on_ended`, with the transcript. A box built over an
    ended dialogue raises `ArgumentError`.
15. **The box answers to its `input_owner`**, as every node does: inside a
    `PlayerLayer`, that layer's player; unowned, the primary player (decision
    12).
16. **`draw` allocates nothing**, revealing or not. The speaker's name is the
    dialogue's `Text`, drawn as it is.
17. The panel is `panel.draw(renderer, :idle, width, height)`, the call a
    button's style already answers, so `NineSliceStyle` works too.

### 5d. The box documented

`docs/api/ui.md` gains "A dialogue box", and `docs/api/dialogue.md` links to it
from "Dialogue". The section says what happens during `solo!`: a `PlayerLayer`
draws nothing while collapsed, so the box goes in the `:overlay` band, with
`input_owner` set to whoever drives it.

### Tests

`spec/rgame/engine/ui/dialogue_box_spec.rb`, in a `FakeRenderer`:

- **The invariant**: the smith script driven through the box and driven
  directly, with the same picks, produce transcripts whose `to_h` are equal.
- Each of rules 8–17, with rule 11 counting condition calls over 100 ticks.
- A box added while confirm is held reveals nothing until confirm is let go and
  pressed again — the conversation opened by confirm next to the smith.
- A beat entered twice in a row types out again.
- `on_portrait` called with the speaker, in local space; the default draws
  nothing.
- Two players, two `PlayerLayer`s, two boxes over two dialogues: player 2's
  confirm moves only player 2's conversation.
- A box in the `:overlay` band during `solo!`, driven by player 2 through
  `input_owner`.

### Verify

`rake spec` green, the invariant spec included. `rake docs:coverage` reports
nothing undocumented. A scratch game driven with `tools/drive_test_project.rb
--texts` talks to the smith from greeting to goodbye in both languages, and
shows the bribe drawn disabled with `unavailable: :disable` and absent with
`:hide`. That scratch game is not committed; step 7 is its committed form.

---

## Step 6 — the log, and an input owner for every player

Two things the box needs that are not the box. The log is a second view,
over the transcript. The input owner answers "who drives the box during
`solo!`" when the answer is everyone, and it belongs to input rather than to
dialogue: a title screen or a pause menu shown during `solo!` asks the same
question.

### 6a. `Players#everyone`

```ruby
class Players
  def everyone   # => an input owner standing for every active player
end

box.input_owner = node.system(Players).everyone
```

Rules:

1. **Everyone acts as one controller whose buttons are the OR of theirs.**
   `held?` is true when any active player holds the action. `pressed?` and
   `released?` are that union's edges, so a press while another player holds
   the action is no press. One press does one thing, as the menu's own rules
   already demand.
2. `axis` is the active players' value of largest magnitude.
3. An action no active player declares raises, as `Actions` does. One some
   players declare reads from those.
4. **It is built once a tick, in `Players#poll`, into reused hashes.** Reading it
   allocates nothing. With no active player, it reads the primary player.
5. A `PlayerLayer` given it raises `ArgumentError`: everyone has no region of
   the screen. The message names the `:overlay` band.

Tests in `spec/rgame/engine/players_spec.rb`: each rule, with two players
pressing and holding in turn; `allocate_nothing` over reads.

### 6b. The log view

```ruby
UI::DialogueBox.new(..., log: nil, log_entry: nil)
# log:       an action that opens and closes the log, or nil for none
# log_entry: a Text.computed(:speaker, :line) formatting one line, or nil for the default
```

The log is a `UI::Label` over a `Text.computed` whose block joins the
transcript's entries, one paragraph each. It renders again only when an entry
arrives or the language changes (measured: 2.2 ms for 200 entries), and only
while the log is open. It is *a* representation of the transcript, as the box
is of the dialogue (decision 14); a game with its own log reads the transcript
from `on_ended` or `Dialogue#transcript`.

Rules:

6. `log: nil` reads no action for it.
7. **Pressing `log` opens the log in place of the line and the responses**,
   showing its last page. `ui_up` and `ui_down` turn the pages; `log` or
   `ui_cancel` closes it.
8. **While the log is open, the conversation does not move** and the line's
   reveal holds.
9. The default `log_entry` joins the speaker's name and the line with a colon,
   and a response entry shows its label alone. Both are punctuation, not words,
   and a game whose language wants another form passes its own `log_entry`.
10. Drawing the open log allocates nothing once it is laid out.

Tests in `dialogue_box_spec.rb`: each rule; a language switch while the log is
open; the log after `transcript:` restored a saved conversation.

### 6c. Documented

`docs/api/input.md` gains "Everyone at once", and the box's section in
`docs/api/ui.md` gains the log.

### Verify

`rake spec` green. A spec with two players and a box in the `:overlay` band
during `solo!`, owned by `everyone`: player 1 reveals a line, player 2 continues
it, and a press by one while the other holds confirm moves nothing.

---

## Step 7 — `examples/dialogue` *(rough)*

One village, per [write-example](../../../.claude/skills/write-example/SKILL.md): a
hero who walks, a smith with the script from the design, a hammer to find, and
gold to bribe with. One conversation starts on confirm next to the smith
(`CollisionWorld#nearest`), and a sign starts one by walking into it
(`BoxCollider#on_hit`), answering the question the request asked. The box opens
the log on a key. F5 saves `facts.to_h` and the hero's gold; loading resumes
the quest, the smith's visits and the gold. A drive script plays the quest
through, with `--texts` showing the unavailable bribe become available.

## Step 8 — fold back and delete the plan

Per [implement-step](../../../.claude/skills/implement-step/SKILL.md): whatever is
still true moves into `docs/api/`, and `docs/plans/dialogue/` is deleted. Run
[learn-from-mistakes](../../../.claude/skills/learn-from-mistakes/SKILL.md) over
every landed note.

- `docs/plans/possible-todos.md` gains "A file format for dialogue and state
  graphs", with decision 2's reasoning and a trigger: a writer who will not
  write Ruby, or a game importing Yarn. The "Text layout past a label" entry
  loses its dialogue-box trigger, answered or restated by what step 5 shipped.
- Item 4 of `docs/plans/research/roadmap-complexity-estimate-v0.5.0.md` gets a
  line saying it landed, as item "text measurement" did.

### Verify

`CHANGELOG.md` names the state machine, the facts, the dialogue, the label's
reveal, the transcript, the box, `Players#everyone` and the example, checked
against every step's pull request per
[update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
`grep -rn 'plans/dialogue' docs lib examples` finds nothing. `rake spec` and
`rake spec:core` green.
