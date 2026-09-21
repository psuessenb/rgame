# Roadmap

**Status: steps 0–1 are implemented.** Steps 0–3 are detailed. Steps 4–7 are rough on
purpose and get re-planned when the step before them lands.

Each step is one branch and one pull request; each lettered sub-step is one
commit. [implement-step](../../../.claude/skills/implement-step/SKILL.md) covers
the rest.

## Dependency shape

```
0 state machine ─→ 1 facts ─→ 2 dialogue ─→ 4 transcript ─┐
                                                          ├─→ 5 box ─→ 6 example ─→ 7 fold back
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
| 2 | branching dialogue for a game that draws its own box |
| 3 | a typewriter reveal on any `UI::Label`, and `examples/intro` using it |

## What each step documents

The machine, the facts and the dialogue get one new page,
`docs/api/dialogue.md`, linked from the index in `docs/api/README.md`. Step 0
creates it, and each later step adds its own section. The reveal goes into the
`UI::Label` section of `docs/api/ui.md`. The rules are in
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
`name:`, `watch` and `unwatch` on `Engine::StateMachine`, as four commits, one
per sub-step. A fifth has `Game` mount the store. `docs/api/dialogue.md` has a
"Facts" section with two headless examples the doc specs run, and the index row
names it. `CHANGELOG.md` has one
more entry under Added. `docs/plans/possible-todos.md` has "State machines for
per-frame behaviour".

`rake spec` ran 2756 examples, 0 failures, in 22.2 s; the three new files hold
38 of them. `rake spec:core` ran 474, 0 failures, and `rake docs:coverage`
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
- **`watch` needs an `unwatch`.** The sketch returned a handle with nothing to
  pass it to. Both `Facts` and `StateMachine` gained `unwatch(handle)`. A node
  that watches in `on_add` unwatches in `on_remove`, as every signal in the
  engine asks. Forgetting is loud here: the stale watcher moves a retired
  machine and raises. See open question 5.
- **The machine needs three `@api private` methods for the facts to call.**
  `parse_saved` checks an entry, `place` puts the machine there silently, and
  `notify_watchers` runs its watch blocks. The split lets `restore` check every
  machine before it moves any, and call watchers only once every fact and every
  machine is back. `Facts#register` is the fourth.
- **A machine's watch hears every transition, not only a changed state.** A
  cycle back into the same state calls it, since visits changed.
- **A machine's `name` must be a Symbol**, and a String raises `TypeError`, as a
  fact's key does.
- **Values that differ include `1` and `1.0`.** Both `on_changed` and `watch`
  compare with `eql?`, since a save writes them differently.
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

### Verify

`rake spec` green. The three spec files run a whole conversation with no
renderer in the process — the invariant, checked by `no_graphics_spec.rb`
having nothing new to say. The page gains a "Dialogue" section, with the smith
script as its example.

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

---

## Step 4 — the transcript *(rough)*

Decision 8. `Dialogue#transcript` records each beat shown and each response
picked, holding the speaker Symbol and the `Text` drawn, with a line's variables
frozen as they were shown. Settle open question 1 — whether it goes into
`to_h` — when the entry's shape exists. The box's log view is step 5's.

## Step 5 — `UI::DialogueBox` *(rough)*

Starts with `UI::Menu` learning to drop its buttons (F3), as its own commit with
its own specs. Then the box, as sketched in
[the design](03-design.md#the-box-rough--step-5): confirm's order, the
`unavailable:` switch, availability asked once per beat, a style for the panel,
the portrait hook, and a log view over the transcript. Settles open questions 2
and 4. The spec asserts the invariant: the same transcript through the box as
without it. Also covers two boxes in two `PlayerLayer`s over two conversations,
and one conversation shown to both players.

## Step 6 — `examples/dialogue` *(rough)*

One village, per [write-example](../../../.claude/skills/write-example/SKILL.md): a
hero who walks, a smith with the script from the design, a hammer to find, and
gold to bribe with. One conversation starts on confirm next to the smith
(`CollisionWorld#nearest`), and a sign starts one by walking into it
(`BoxCollider#on_hit`), answering the question the request asked. F5 saves
`facts.to_h` and the hero's gold; loading resumes the quest, the smith's visits
and the gold. A
drive script plays the quest through, with `--texts` showing the unavailable
bribe become available.

## Step 7 — fold back and delete the plan

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
reveal, the box and the example, checked against every step's pull request per
[update-changelog](../../../.claude/skills/update-changelog/SKILL.md).
`grep -rn 'plans/dialogue' docs lib examples` finds nothing. `rake spec` and
`rake spec:core` green.
