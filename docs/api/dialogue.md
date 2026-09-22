# Dialogue and state machines

This page covers the machinery for a quest's stages and a conversation's
branches, and the store of flags they read and save. All of it is pure Ruby,
loads with `require 'rgame'`, and runs in a spec with no window.

## State machines

**A `StateGraph` is the recipe; a `StateMachine` is where one run of it has got
to.** The graph names states and the transitions out of each. The machine holds
the current state, counts how often each state was entered, and takes
transitions. One graph serves any number of machines, so a graph belongs in a
constant and a machine in the object that owns the quest.

State machines here are for decisions: state moves when a player chooses or an
event arrives, a few times a minute. Nothing in them runs per frame.

### Building a graph

`StateGraph.build(start:)` runs its block against a `StateGraph::Builder` and
returns a frozen `StateGraph`:

```ruby
require 'rgame'

HAMMER = RGame::Engine::StateGraph.build(start: :not_started) do
  state :not_started do
    on :accepted, to: :searching
  end

  state :searching do
    on :hammer_found, to: :found
  end

  state :found do
    on :returned, to: :done, then: ->(m) { m.context[:gold] += 100 }
  end

  state :done
end

HAMMER.start                              # => :not_started
HAMMER.state?(:found)                     # => true
HAMMER.transitions(:searching).first.to   # => :found
```

The builder has three methods:

| Call | Declares |
|---|---|
| `state name, enter: nil, data: nil` | a state. Its block declares the transitions out of it. `enter:` is an effect run on arriving. |
| `on event, to:, if:, unless:, then:, data:` | a transition taken when the machine fires `event` |
| `go to:, if:, unless:, then:, data:` | a transition with no event, taken by picking it from the machine's list |

- **`to:` may be left out.** Taking such a transition *ends* the machine.
- **`if:` and `unless:` are conditions.** A transition is available when `if:`
  holds and `unless:` does not.
- **`then:` is an effect** of taking the transition.
- **`data:` is carried through untouched.** A layer above keeps its own words
  there, such as a line of dialogue on a state or a label on a transition.

State names and events are Symbols. A state no transition reaches is legal; a
saved machine may be put there.

`build` checks the graph and raises `ArgumentError`, naming the culprit, for:

- a `to:` naming no state;
- a start that is not a state;
- a state declared twice, or inside another state's block;
- `on` or `go` outside a state block;
- a condition or effect that is neither callable nor a Symbol;
- a state name, event or `to:` that is not a Symbol.

The graph, its states, each state's Array of transitions and each transition
are frozen. `StateGraph#state` returns a `StateGraph::State`, with the `name`,
`enter`, `data` and `transitions` it was built with. Each transition is a
`StateGraph::Transition`, whose readers are `from`, `event`, `to`, `data`, and
`requires`, `forbids` and `effect` for the builder's `if:`, `unless:` and
`then:`. `StateGraph#state_names` lists every state's name in the order they
were declared. `StateGraph#each_symbol` yields every Symbol the graph uses as a
condition or effect, once each.

### Running one

`StateMachine.new(graph, context: nil, facts: nil, from: nil)` enters the start
state, counts it visited once and runs its `enter:` effect. `context` is the
game's own object that conditions ask. `facts` is a store of shared values the
machine keeps for its conditions to read.

```ruby
require 'rgame'

HAMMER = RGame::Engine::StateGraph.build(start: :not_started) do
  state(:not_started) { on :accepted, to: :searching }
  state(:searching) { on :hammer_found, to: :found }
  state(:found) { on :returned, to: :done, then: ->(m) { m.context[:gold] += 100 } }
  state :done
end

hero = { gold: 0 }
quest = RGame::Engine::StateMachine.new(HAMMER, context: hero)

quest.state                   # => :not_started
quest.fire(:returned)         # => nil — no transition for that event here
quest.fire(:accepted).to      # => :searching
quest.fire(:hammer_found)
quest.transitions.size        # => 1
quest.available?(quest.transitions.first) # => true
quest.take(quest.transitions.first)
quest.state                   # => :done
hero[:gold]                   # => 100
quest.visits(:searching)      # => 1
quest.visits(:elsewhere)      # => 0
```

| Method | Answers |
|---|---|
| `state` | the current state; nil once ended |
| `transitions` | the frozen Array of transitions out of the current state; an empty one once ended |
| `available?(transition)` | whether its conditions hold now |
| `take(transition)` | takes it, and returns it |
| `fire(event)` | takes the first available transition for `event`, and returns it; nil when none is |
| `visits(name)` | how often the machine entered `name`; 0 for a state never entered |
| `ended?` | whether a transition with no `to:` was taken |
| `on_changed` | connects a listener, called with the old state, the new one and the transition |
| `name` | the `name:` it was built with, or nil |

**Availability is asked, not stored.** `available?` runs the transition's
conditions on every call. `transitions` returns the state's own frozen Array,
so reading it, and reading `visits`, allocates nothing. The machine says what
may be taken; what a game shows of the rest is the game's decision.

**`take` raises `ArgumentError`** for a transition not listed for the current
state, or not available. `available?` raises the same way for a transition from
another state. **`fire` never raises for an event with no available
transition.** It returns nil and changes nothing, so a quest in the wrong stage
ignores an event meant for another.

**Taking a transition runs, in order:** its `then:` effect, the state change,
the visit count, the new state's `enter:`, then `on_changed`. An effect reads
where the machine was; `enter:` and the listeners read where it is.

**A machine cannot move itself from inside its own effect or listener.**
`take` or `fire` called there raises `RuntimeError`. Driving a *different*
machine from there works, and is how a conversation moves a quest on.

An ended machine lists no transitions and fires nothing.

### Conditions and effects: a block or a Symbol

A block is called with the machine, so one argument reaches `context`, `facts`
and `visits`:

```ruby
go to: :bribed, if: ->(m) { m.context.gold >= 50 }, then: ->(m) { m.context.gold -= 50 }
```

A Symbol is sent to the context. `if: :can_bribe?` calls `context.can_bribe?`,
so the question lives with the data it reads, and one predicate serves every
graph:

```ruby
require 'rgame'

class Hero
  attr_accessor :gold

  def initialize = @gold = 80
  def can_bribe? = gold >= 50
  def pay_bribe = self.gold -= 50
end

GUARD = RGame::Engine::StateGraph.build(start: :blocked) do
  state(:blocked) { go to: :bribed, if: :can_bribe?, then: :pay_bribe }
  state :bribed
end

hero = Hero.new
guard = RGame::Engine::StateMachine.new(GUARD, context: hero)
guard.take(guard.transitions.first)
hero.gold      # => 30

begin
  RGame::Engine::StateMachine.new(GUARD, context: Object.new)
rescue NoMethodError => e
  e.message    # => "Object does not answer :can_bribe?, :pay_bribe"
end
```

**The machine checks every Symbol when it is built.** It raises `NoMethodError`
listing each one the context does not answer, or all of them when there is no
context. A misspelt predicate fails when the machine is built, not when a player
first reaches that branch.

### Saving and resuming

`to_h` returns the state and the visit counts, in the shape
`RGame::Util::SaveFile#write` takes. `from:` takes what `SaveFile#read` returns
and puts a new machine back where the saved one was:

```ruby
require 'rgame'
require 'tmpdir'

HAMMER = RGame::Engine::StateGraph.build(start: :not_started) do
  state(:not_started) { on :accepted, to: :searching }
  state(:searching) { on :hammer_found, to: :found }
  state :found
end

quest = RGame::Engine::StateMachine.new(HAMMER)
quest.fire(:accepted)
quest.to_h     # => { state: :searching, visits: { not_started: 1, searching: 1 } }

Dir.mktmpdir do |dir|
  save = RGame::Util::SaveFile.new('slot1.json', dir: dir)
  save.write(hammer: quest.to_h)

  save.read[:hammer]  # => { state: 'searching', visits: { not_started: 1, searching: 1 } }
  resumed = RGame::Engine::StateMachine.new(HAMMER, from: save.read[:hammer])
  resumed.state       # => :searching
end
```

- **A machine resumes at construction.** Built with `from:`, it runs no effect
  and emits nothing. It is put back where it was, not walked through the steps
  that led there, so a start state's `enter:` does not run again on every load.
- **State names may come back as Strings.** JSON turns a Symbol into one, and
  `from:` turns it back.
- **`from: nil` starts fresh**, so `save.read[:hammer]` needs no branch for "no
  save yet".
- **A saved state the graph lacks raises `ArgumentError`.** A save from an older
  version of a game may name a stage that no longer exists, and the game decides
  how to migrate it.
- **An ended machine saves a nil state**, and resumes ended.

`to_h` and `from:` suit a machine a game saves by hand. A game's quests
normally take a `name:` instead, and the facts save them with everything else.
See [Saving the world](#saving-the-world).

## Facts

**`Components::Facts` holds the flags that belong to no object**: "met the
smith", "the bridge is down", "wolves killed". It is a system on the root, so
every node reaches the same store with `node.system`. `RGame::Game` mounts one
when it starts, and `game.facts` returns it. Outside a `Game`, as in a spec,
mount it yourself:

```ruby
require 'rgame'

root = RGame::Engine::Node2D.new
root.add_component(RGame::Engine::Components::Facts.new)
smithy = root.add_node(RGame::Engine::Node2D.new)

facts = smithy.system(RGame::Engine::Components::Facts)
facts[:met_smith] = true
facts[:wolves] = facts.fetch(:wolves, 0) + 1

facts[:wolves]            # => 1
facts[:bridge_down]       # => nil — never set
facts.key?(:bridge_down)  # => false
```

| Method | Does |
|---|---|
| `facts[key]` | the value, or nil for a key never set |
| `facts[key] = value` | sets it |
| `fetch(key, ...)` | as `Hash#fetch`: a default, a block, or `KeyError` |
| `key?(key)` | whether the key was set |
| `delete(key)` | removes the key, and returns its value |
| `on_changed` | connects a listener, called with the key and the new value |
| `watch(key)` | calls its block with the value now, then with every value that differs; returns a handle |
| `unwatch(handle)` | stops calling a block `watch` returned |
| `to_h` | every fact and every named machine, frozen |
| `restore(saved)` | replaces all of them with a saved `to_h` |

A state machine built with `facts:` reads them in its conditions as `m.facts`.

**The store takes only what a save brings back unchanged.** Keys are Symbols.
Values are nil, true, false, an Integer, a Float or a String. Anything else
raises `TypeError`, naming the key and the class, and so does a String key.

**A Symbol value is refused.** JSON brings `:open` back as `"open"`, so a
condition comparing against `:open` would fail after every load. The error says
to store the String.

### `on_changed` and `watch`

**`on_changed` reports a change made in play**, so a listener may act on it:
the tenth wolf spawns the boss. Setting the value a key already holds emits
nothing. A restore never emits, so loading a save with ten wolves spawns no
second boss.

**`watch` keeps something in step with one fact.** It calls its block with the
value at once, nil for a key never set. It then calls it with every value that
differs, restores included. A gate that opens when the bridge is down uses
`watch`, so it opens after a load too.

A value that differs counts `1` and `1.0` as different, as a save would write
them.

### Saving the world

**A machine built with a `name:` registers with its facts.** `facts.to_h` then
holds every flag and every named machine, and `restore` puts them all back. A
game saves one entry and never lists its quests:

```ruby
require 'rgame'
require 'tmpdir'

HAMMER = RGame::Engine::StateGraph.build(start: :not_started) do
  state(:not_started) { on :accepted, to: :searching }
  state(:searching) { on :hammer_found, to: :found }
  state :found
end

facts = RGame::Engine::Components::Facts.new
quest = RGame::Engine::StateMachine.new(HAMMER, facts:, name: :hammer)
facts[:met_smith] = true
quest.fire(:accepted)

facts.to_h  # => { values: { met_smith: true }, machines: { hammer: { state: :searching, visits: { not_started: 1, searching: 1 } } } }

Dir.mktmpdir do |dir|
  save = RGame::Util::SaveFile.new('slot1.json', dir: dir)
  save.write(world: facts.to_h)

  loaded = RGame::Engine::Components::Facts.new
  loaded.restore(save.read[:world])
  again = RGame::Engine::StateMachine.new(HAMMER, facts: loaded, name: :hammer)
  again.state         # => :searching
  loaded[:met_smith]  # => true
end
```

`name:` is a Symbol, needs `facts:`, and takes the place of `from:`: passing
both raises `ArgumentError`.

**Order does not matter.**

- **A machine built after `restore`** resumes from its entry, by the rules
  `from:` has, running no effect. With no entry it starts fresh.
- **A machine built before `restore`** is put where its entry says. It runs no
  effect and emits no `on_changed`. With no entry it goes back to its start
  state, again running nothing.
- **`restore(nil)`**, for no save yet, clears every fact and puts every named
  machine back at its start.
- **An entry no machine claims is kept**, and `to_h` writes it back, so a quest
  the player has not met this session survives the next save.

**A machine built under a name another already holds takes over from it.** The
new machine starts where the old one had got to. The old one raises
`RuntimeError` if it is moved again. So a scene the player leaves and enters
again builds its quests anew and loses nothing, and two objects both driving
one quest fail on the first move.

**`restore` checks everything before it changes anything.** A value the store
would refuse, or an entry naming a state its machine's graph lacks, raises and
leaves every fact and every machine as it was.

**`restore` calls watchers once the whole world is back.** Every fact and every
machine is restored first, then the watchers of each key whose value differs
run. A watcher that reads another fact or a machine reads the restored one.

**To keep the scene in step with a quest, watch a fact the quest sets.** A
transition's effect writes the fact, the save brings it back, and a watcher
hears it after a load as well as in play. A machine has no `watch` of its own:
a fact names what the scene cares about, such as `bridge_down`, and keeps
working when a quest's stages are renamed. Code that reads a machine when it
needs to, such as a condition or a quest log that draws `quest.state`, needs no
watcher.

**A watcher belongs to the object that connected it.** A node that watches in
`_enter_tree` unwatches in `_exit_tree`. A watcher left connected after its node is
gone keeps running, and one that moves a machine the node built finds that
machine replaced:

```ruby
class Gate < RGame::Engine::Node2D
  GRAPH = RGame::Engine::StateGraph.build(start: :shut) do
    state(:shut) { on :lower, to: :open }
    state :open
  end

  def _enter_tree
    @facts = system(RGame::Engine::Components::Facts)
    @machine = RGame::Engine::StateMachine.new(GRAPH, facts: @facts, name: :gate)
    @bridge = @facts.watch(:bridge_down) { |down| @machine.fire(:lower) if down }
  end

  def _exit_tree = @facts.unwatch(@bridge)
end
```

**A second store is for a second lifetime.** A roguelike keeps unlocks that
outlast every run beside flags that reset with each one. Mount a second `Facts`
on the run's scene node. `node.system` looks at the scene before the root, so
the run's nodes and quests find the run's store, and the game saves both
entries. Code inside the run reaches the root store with
`node.root.get_component(RGame::Engine::Components::Facts)`.

**Settings are not facts.** Volume, key bindings and language belong to the
player, not to a save slot. Keep them in a `Util::SaveFile` of their own.

## Dialogue

**A `Dialogue::Script` is a conversation's recipe; a `Dialogue` is one
conversation running it.** A script is a state graph whose states are *beats*,
a speaker saying a line, and whose picked transitions are *responses*. A
dialogue holds a `StateMachine` over that graph and adds the words. Nothing in
it decides where the conversation goes that the machine does not.

A dialogue draws nothing. [`UI::DialogueBox`](ui.md#rgameengineuidialoguebox)
shows one on screen, and a game with its own box drives the dialogue itself.

Two examples show a conversation running. [`dialogue`](examples.md#dialogue)
holds one on a black screen and nothing else.
[`quests_and_dialogue`](examples.md#quests_and_dialogue) is a village where
talking to the smith moves a quest on, and one facts entry saves both.

### Writing a script

`Dialogue::Script.build(start:, scope:)` runs its block against a
`Dialogue::Script::Builder` and returns a frozen script:

```ruby
require 'rgame'

class Hero
  attr_accessor :gold

  def initialize = @gold = 0
  def can_bribe? = gold >= 50
  def pay_bribe = self.gold -= 50
end

SMITH = RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
  beat :greeting, speaker: :smith, line: 'greeting' do
    respond 'ask_work', to: :work, once: true
    respond 'bribe', to: :bribed, if: :can_bribe?, then: :pay_bribe
    respond 'bye'
  end

  beat :work, speaker: :smith, line: 'work', to: :greeting
  beat :bribed, speaker: :smith, line: 'bribed'
end

SMITH.beat?(:work)                  # => true
SMITH.graph.transitions(:work).size # => 1
```

The builder adds two words to `state`, `on` and `go`:

| Call | Declares |
|---|---|
| `beat name, speaker:, line:, vars: nil, to: nil, enter: nil` | a state where `speaker` says `line`. Its block declares its responses. |
| `respond label, to:, if:, unless:, then:, once: false` | a response the player may pick, inside a beat's block |

- **A beat with responses waits for one.** A beat without them continues to its
  `to:` when the player moves on, and ends the conversation with no `to:`. A
  beat with both raises `ArgumentError`: a player could not tell a continue from
  a choice.
- **A line and a label are translation keys under `scope:`**, or an
  `Engine::Text` used as it is. Anything else raises `TypeError`, so no String a
  translation cannot reach gets in.
- **A speaker is a Symbol the game owns.** Its name is the key
  `speakers.<speaker>`, outside the scope, so every script shares one table of
  names.
- **`once: true` hides a response once its target was entered.** It needs a
  `to:`, and takes the place of `unless:`: passing both raises.
- **`vars:` fills a line's variables** on entering the beat. It is a block
  called with the machine, or a Symbol sent to the context, and returns a Hash.
  The line must be an `Engine::Text` built with those names; a line with
  variables and no `vars:`, or `vars:` on a line without them, raises.
- **`on` and `go` inside a beat raise.** Outside one, `state`, `on` and `go`
  declare a state with no line: a branch point the conversation passes straight
  through, deciding by condition alone.
- **`respond` outside a beat raises.**

Everything `StateGraph.build` refuses, a script refuses too. A beat's state
carries a `Dialogue::Script::Beat` as its `data`, with `speaker`,
`speaker_name`, `line` and `vars`. A response's transition carries a
`Dialogue::Script::Response`, whose `label` is the `Text` to show.
`Dialogue::Script#each_symbol` yields every Symbol the script sends to its
context, `vars:` included.

### Running one

`Dialogue.new(script, context: nil, facts: nil, from: nil, name: nil,
transcript: nil)` starts the conversation at the script's first beat:

```ruby
require 'rgame'

SMITH = RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
  beat :greeting, speaker: :smith, line: 'greeting' do
    respond 'ask_work', to: :work, once: true
    respond 'bye'
  end

  beat :work, speaker: :smith, line: 'work', to: :greeting
end

talk = RGame::Engine::Dialogue.new(SMITH)

talk.beat                          # => :greeting
talk.speaker                       # => :smith
talk.speaker_name.key              # => 'speakers.smith'
talk.line.key                      # => 'greeting'
talk.waiting_for_response?         # => true
talk.responses.map { it.data.label.key } # => ['ask_work', 'bye']

talk.respond(talk.responses.first)
talk.beat                          # => :work
talk.continue
talk.available?(talk.responses.first) # => false — once: after the answer
talk.visits(:greeting)             # => 2

talk.respond(talk.responses.last)
talk.ended?                        # => true
talk.line                          # => nil
```

| Method | Answers |
|---|---|
| `beat` | the beat the conversation is at; nil once ended |
| `speaker` | that beat's speaker Symbol |
| `speaker_name` | the `Text` for `speakers.<speaker>` |
| `line` | the beat's line `Text`, filled by its `vars:` |
| `responses` | the beat's responses, a frozen Array; empty on a beat that continues |
| `waiting_for_response?` | whether the beat waits for a response |
| `available?(response)` | whether its conditions hold now |
| `respond(response)` | picks it, and returns it |
| `continue` | moves on from a beat without responses |
| `ended?` | whether the conversation has ended |
| `visits(beat)` | how often the conversation entered `beat` |
| `context`, `facts`, `name`, `to_h` | as the machine's |
| `transcript` | what the conversation has said; see [The transcript](#the-transcript) |
| `on_beat_entered` | connects a listener, called with each beat the conversation enters |
| `on_ended` | connects a listener, called with the frozen transcript when the conversation ends |

`speaker`, `speaker_name` and `line` are nil once the conversation has ended.

**A beat either waits or continues, and each call refuses the other kind.**
`respond` on a beat that continues, and `continue` on one that waits, raise
`RuntimeError`, as both do once the conversation has ended. `respond` and
`available?` raise `ArgumentError` for a response not listed for the beat, and
`respond` for one not available. Whatever drives the dialogue never has to
guess what confirm means.

**A condition, an effect or a `vars:` block is called with the machine.** It
reads `context`, `facts` and `visits` exactly as a quest's condition does. A
Symbol is sent to the context. The dialogue checks every Symbol in the script,
`vars:` included, when it is built, and raises `NoMethodError` naming each one
the context does not answer.

**`line` and `speaker_name` return the same `Text` each time the beat is the
same**, so a label holding one needs no rebuild. A line with `vars:` holds the
values it was given on entering the beat, until the beat is entered again. Each
dialogue keeps its own copy of such a line, so two conversations over one script
show their own values. Reading `responses`, `beat` and `line` allocates nothing.

**A state with no line is passed through within the same move.** The dialogue
takes its first available transition and arrives at the next beat. Two cases
would leave the player stuck, and both raise `RuntimeError`, naming the state:

- a state with no line and no available transition, or states with no line
  that loop without reaching a beat;
- a beat that waits for a response with none available.

Each raises while a player plays, so a spec should find them first; see
[Checking every path](#checking-every-path).

### Saving a conversation

A dialogue saves as a machine does. `to_h` and `from:` save one by hand, and
`name:` saves it in its facts with every other named machine. A save of a
conversation that had ended starts it again at its first beat and keeps its
visits:

```ruby
require 'rgame'

SMITH = RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
  beat :greeting, speaker: :smith, line: 'greeting' do
    respond 'ask_work', to: :work, once: true
    respond 'bye'
  end

  beat :work, speaker: :smith, line: 'work', to: :greeting
end

facts = RGame::Engine::Components::Facts.new
talk = RGame::Engine::Dialogue.new(SMITH, facts:, name: :smith)
talk.respond(talk.responses.first)
talk.continue
talk.respond(talk.responses.last)

again = RGame::Engine::Dialogue.new(SMITH, facts:, name: :smith)
again.beat                               # => :greeting
again.available?(again.responses.first)  # => false
```

So `once:` holds across every conversation with a named dialogue. An unnamed
dialogue starts with no visits, and its `once:` lasts one conversation. A
dialogue saved in the middle of a conversation resumes at the beat it was on.

### The transcript

**A dialogue records what it says, and hands the record to the game when the
conversation ends.** `transcript` returns a `Dialogue::Transcript`: each line
shown and each response picked, in order. `on_ended` passes it to its
listeners, frozen. The engine saves nothing: a game shows it, saves it or drops
it.

```ruby
require 'rgame'

Hero = Struct.new(:gold) do
  def purse = { gold: }
end

SMITH = RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
  gold = RGame::Engine::Text.new('gold', :gold, scope: 'smith')

  beat :greeting, speaker: :smith, line: 'greeting' do
    respond 'ask_gold', to: :purse
    respond 'bye'
  end

  beat :purse, speaker: :smith, line: gold, vars: :purse, to: :greeting
end

hero = Hero.new(5)
talk = RGame::Engine::Dialogue.new(SMITH, context: hero)
kept = nil
talk.on_ended { kept = it }

talk.respond(talk.responses.first)
talk.continue
hero.gold = 80
talk.respond(talk.responses.first)
talk.continue
talk.respond(talk.responses.last)

kept.select(&:vars).map(&:vars) # => [{ gold: 5 }, { gold: 80 }] — each visit as it was shown
kept[1].text.key                # => 'ask_gold'
kept.last.text.key              # => 'bye'
kept.frozen?                    # => true
```

Each entry is a `Transcript::Entry`:

| Field | A line | A response |
|---|---|---|
| `beat` | the beat that said it | the beat it was picked at |
| `speaker`, `speaker_name` | who said it: the Symbol, and the `Text` for its name | nil |
| `text` | the line's `Text` | the response's label `Text` |
| `vars` | the values it was shown with, frozen; nil for a line without variables | nil |
| `response` | nil | the `StateGraph::Transition` picked |

**A line keeps the values it was shown with.** Its entry holds a `Text` of its
own, so a later visit to the same beat with other values leaves it as it was. A
line without variables shares the script's `Text`. Every entry's text follows a
language switch, as any `Text` does.

A continue records nothing, since its line is already there. A state with no
line records nothing either. `each`, `size`, `[]`, `last` and `empty?` read the
entries and allocate nothing, and the class is `Enumerable`.

#### Saving one

`to_h` returns the transcript as a frozen Hash, and `Transcript.from(saved,
script)` rebuilds it:

```ruby
require 'rgame'
require 'tmpdir'

SMITH = RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
  beat :greeting, speaker: :smith, line: 'greeting' do
    respond 'ask_work', to: :work
    respond 'bye'
  end

  beat :work, speaker: :smith, line: 'work', to: :greeting
end

talk = RGame::Engine::Dialogue.new(SMITH)
talk.respond(talk.responses.first)
talk.transcript.to_h # => { entries: [{ beat: :greeting }, { beat: :greeting, response: 0 }, { beat: :work }] }

Dir.mktmpdir do |dir|
  save = RGame::Util::SaveFile.new('slot1.json', dir:)
  save.write(talk: talk.to_h, log: talk.transcript.to_h)

  loaded = save.read
  log = RGame::Engine::Dialogue::Transcript.from(loaded[:log], SMITH)
  resumed = RGame::Engine::Dialogue.new(SMITH, from: loaded[:talk], transcript: log)
  resumed.continue
  resumed.transcript.map(&:beat) # => [:greeting, :greeting, :work, :greeting]
end
```

An entry saves its beat and either its variables or its response's index among
the beat's responses. The words come back from the script, so a transcript
restored after a language switch reads in the new language.

- **`to_h` holds each variable to the rule facts are held to**: nil, true,
  false, an Integer, a Float or a String. It raises `TypeError` naming the entry
  and the variable. Only `to_h` checks, so a game that never saves a transcript
  never meets the rule.
- **`from` takes what `SaveFile#read` returns**, beat names as Strings
  included. It raises `ArgumentError` for a beat the script lacks, a response
  its beat does not list, and variables that do not match the line's names.

**Where a conversation has got to and what it said are two saves.** A
conversation resumed with `from:` or `name:` starts a new transcript, holding
the beat it resumes at. `transcript:` hands it one to record on instead. The
dialogue then records the beat it resumes at only if the transcript does not
already end with that beat's line, as one saved mid-conversation does. A frozen
transcript is copied, and one of another script raises `ArgumentError`.

## Checking every path

**`Exploration.run` walks every path a dialogue or a machine can take, and
reports where one gets stuck.** Its block builds a fresh world and returns the
dialogue or machine in it. The walk replays each path in a world of its own, so
effects and facts behave as in play:

```ruby
require 'rgame'

SHUT = RGame::Engine::Dialogue::Script.build(start: :greeting, scope: 'guard') do
  beat :greeting, speaker: :guard, line: 'greeting' do
    respond 'pass', to: :gate, if: ->(m) { m.facts[:pass] }
    respond 'bye'
  end

  beat :gate, speaker: :guard, line: 'gate' do
    respond 'enter', if: ->(m) { m.facts[:key] }
  end
end

report = RGame::Engine::Exploration.run do
  facts = RGame::Engine::Components::Facts.new
  facts[:pass] = true
  RGame::Engine::Dialogue.new(SHUT, facts:)
end

report.ends?          # => true
report.ending         # => ['greeting: bye']
report.problems.size  # => 1
report.stuck.first.state # => :gate
report.stuck.first.path  # => ['greeting: pass']
```

| Method | Answers |
|---|---|
| `problems` | one String per problem, with the path that reaches it; empty when every path has a way on and some path ends |
| `stuck` | each position with no way on, an `Exploration::Stuck` with `path`, `state` and the `error` a move raised |
| `ends?` | whether some path ends |
| `ending` | the moves of the shortest path to an end |
| `unreached` | the states no path entered |
| `truncated?` | whether the walk stopped at a limit with positions left |
| `positions` | how many distinct positions the walk saw |

A game's spec asserts on `problems`, which prints each failure in full:

<!-- doc-example: skip — an RSpec file, run by a game's own suite -->
```ruby
it 'lets the player out of every beat' do
  report = RGame::Engine::Exploration.run { RGame::Engine::Dialogue.new(SMITH, context: Hero.new) }
  expect(report.problems).to eq([])
end
```

- **A move is any available transition**: a response or a continue for a
  dialogue, and any transition, fired or picked, for a machine.
- **A position is stuck** when a move raises, a condition raises, or a machine
  has transitions and none is available. A block that raises while it builds
  the world is reported too.
- **An end** is an ended dialogue or machine, or a machine's state with no
  transitions, as a finished quest's is.
- **A condition sees only the world the block built** and what the walk's own
  moves changed. A branch the world shuts shows in `unreached`, which is not a
  problem: a spec that expects every state reached asserts `unreached` is empty,
  or builds a second world with the branch open.
- **Positions are the same when the state, the states ever entered and the
  facts match.** Visits count as entered or not, so a question the player may
  ask again and again is one position. A condition that counts visits past one
  is explored as if it did not.
- **A condition that reads the context needs `key:`**, a block called with the
  dialogue or machine that returns what the condition reads. Without it, gold
  earned in a loop looks like the same position and a purchase is never
  reached.
- **The walk stops at `max_moves:`, 100 by default, or `max_positions:`,
  10 000**, and a walk cut short is a problem. A counter in the facts that grows
  on every loop produces a new position each time and reaches the limit.
- **The block must build the same world every time.** A replay that arrives
  somewhere the first walk did not raises `ArgumentError`, so a world built
  from shared state, or a random one, fails loudly.
