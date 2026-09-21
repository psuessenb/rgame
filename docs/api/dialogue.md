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
`then:`. `StateGraph#each_symbol` yields every Symbol the graph uses as a
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
| `watch` | calls its block with the state now, then after every transition and every restore; returns a handle |
| `unwatch(handle)` | stops calling a block `watch` returned |
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
every node reaches the same store with `node.system`:

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
  effect and emits no `on_changed`; its `watch` blocks hear the new state. With
  no entry it goes back to its start state, again running nothing.
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
machine is restored first. Then the watchers of each key whose value differs
run, then each named machine's. A watcher that reads another fact or machine
reads the restored one.

**A watcher belongs to the object that connected it.** A node that watches in
`on_add` unwatches in `on_remove`. A watcher left connected after its node is
gone keeps running, and one that moves a machine the node built finds that
machine replaced:

```ruby
class Gate < RGame::Engine::Node2D
  GRAPH = RGame::Engine::StateGraph.build(start: :shut) do
    state(:shut) { on :lower, to: :open }
    state :open
  end

  def on_add
    @facts = system(RGame::Engine::Components::Facts)
    @machine = RGame::Engine::StateMachine.new(GRAPH, facts: @facts, name: :gate)
    @bridge = @facts.watch(:bridge_down) { |down| @machine.fire(:lower) if down }
  end

  def on_remove = @facts.unwatch(@bridge)
end
```

**Settings are not facts.** Volume, key bindings and language belong to the
player, not to a save slot. Keep them in a `Util::SaveFile` of their own.
