# Dialogue and state machines

This page covers the machinery for a quest's stages and a conversation's
branches. Both are pure Ruby, load with `require 'rgame'`, and run in a spec
with no window.

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
