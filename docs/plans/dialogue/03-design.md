# Design

Four pieces, each usable without the next:

```
Engine::StateGraph ──run by──→ Engine::StateMachine ──reads──→ Components::Facts
        ↑                              ↑                          (and the context)
Dialogue::Script (builds one) ──run by──→ Engine::Dialogue
                                               ↑ reads, calls
                                        UI::DialogueBox ──holds──→ UI::Label (with a reveal)
                                                        └─holds──→ UI::Menu
```

A graph is a **recipe**; a machine is **where one run of it has got to**. That
split is the save story: the recipe lives in code, and a save holds the machine's
state, its visit counts and the facts. It is the same split `examples/save_load`
makes between a scene and its save file.

## The state graph and the machine *(pure)*

### Building a graph

```ruby
HAMMER = Engine::StateGraph.build(start: :not_started) do
  state :not_started do
    on :accepted, to: :searching
  end

  state :searching do
    on :hammer_found, to: :found
  end

  state :found do
    on :returned, to: :done, then: :pay_reward
  end

  state :done
end
```

- **`state name`** declares a state. Its block declares the transitions out.
- **`on event, to:`** is a transition fired by name. **`go to:`** is one with no
  event, taken by picking it from the list. A dialogue's responses are the
  second kind; a quest's stages mostly use the first.
- **`to:` may be omitted**, which *ends* the machine: `state` becomes nil and
  `ended?` true. A dialogue's "Goodbye" is such a transition. A quest that can
  fail uses one too.
- **`if:` and `unless:`** are conditions. **`then:`** is an effect of taking the
  transition, and **`enter:`** on a state is an effect of arriving.
- **`build` checks the graph and freezes it.** A `to:` naming no state, a start
  that is not a state, and a state declared twice all raise `ArgumentError` at
  build, naming the state. A graph with a state nothing can reach is legal: a
  save may put the machine there.

### A condition or an effect is a block or a Symbol

```ruby
go to: :bribed, if: ->(m) { m.context.gold >= 50 }, then: ->(m) { m.context.gold -= 50 }
go to: :bribed, if: :can_bribe?, then: :pay_bribe          # the same, as names
```

A block is called with the machine, so one argument reaches all three things a
condition reads: `m.context`, `m.facts` and `m.visits(:state)`. A lambda written
with one parameter works, and nothing is passed that a writer must ignore.

A Symbol is sent to the context: `if: :can_bribe?` calls `context.can_bribe?`.
The context is the game's own object, so the question lives where the gold does,
and a predicate named once serves every conversation. **The machine checks at
construction that its context answers every Symbol in the graph**, and raises
`NoMethodError` naming the ones it does not. A misspelt predicate fails when the
conversation opens, not the first time a player reaches that branch.

### A file format later costs nothing now

Decision 2 left a data file for later and asked that nothing here make it
harder. Everything in a graph is already data except a block, and a Symbol can
stand for any block. A loader for YAML, or for a reading of Yarn, would call
`build` with `if: :can_bribe?` where the builder takes a lambda. So the rule the
steps hold is: **every option a builder takes accepts a Symbol wherever it
accepts a block.** Nothing else about a format needs deciding now.

### Running one

```ruby
quest = Engine::StateMachine.new(HAMMER, context: hero, facts: facts)

quest.state                  # => :not_started
quest.transitions            # => the transitions out of this state, a frozen Array
quest.available?(transition) # => whether its condition holds now
quest.take(transition)       # takes it; raises ArgumentError if not available
quest.fire(:accepted)        # takes the first available transition with that event; the transition, or nil
quest.visits(:searching)     # => 1
quest.ended?                 # => false
quest.on_changed { |from, to, transition| ... }
```

**Availability is asked, not stored.** `transitions` returns the state's own
frozen Array, built once with the graph, so reading it allocates nothing.
`available?` runs the condition each time it is called. A view that asks once
per beat pays once per beat; a game that asks every frame runs its conditions
every frame, which is its own choice. This is how the engine gives the game the
information and leaves the decision about showing it to the game.

**The rules the machine's specs pin:**

1. `take` runs, in order: the transition's `then:`, the state change, the visit
   count, the new state's `enter:`, then `on_changed`. The effect reads where
   the machine was; `enter:` and the listeners read where it is.
2. A machine built without `from:` counts its start state as visited once, and
   runs its `enter:`. One built with `from:` runs nothing.
3. Taking a transition not listed for the current state raises.
4. Taking or firing from inside one of the same machine's effects or listeners
   raises. A second machine may be driven from there — that is how a dialogue
   moves a quest on.
5. `fire` with no available transition for the event returns nil and changes
   nothing. A quest in the wrong stage ignores an event meant for another.
6. An ended machine lists no transitions and fires nothing.

### Saving one

```ruby
quest.to_h                                                            # => { state: :searching, visits: { not_started: 1, searching: 1 } }
quest = Engine::StateMachine.new(HAMMER, context: hero, facts: facts, from: save.read[:hammer])
```

`to_h` is what `Util::SaveFile#write` takes, and `from:` accepts what `read`
returns: Symbol keys, and the state as a String, because JSON turned the Symbol
into one.

**A machine resumes at construction, not after it.** Built without `from:`, it
enters its start state and runs that state's `enter:`. Built with `from:`, it
runs no effect and emits nothing: it is put back where it was, not walked
through the steps that led there. A `restore` called on a machine already built
would come too late — the start state's `enter:` would have run, and a greeting
that sets `met_smith` would set it again on every load. A constructor cannot be
called in the wrong order.

**`from:` raises for a state the graph does not have.** A save from an older
version of the game names a stage that no longer exists, and resetting the
quest silently would lose a player's progress hours later. The game decides how
to migrate. This mirrors `SaveFile`'s own rule that writing raises: a failure
with no safe answer is reported, not swallowed. `from: nil` — no save yet —
starts fresh, so `save.read[:hammer]` needs no branch.

## The facts *(a component, pure)*

```ruby
root.add_component(Engine::Components::Facts.new)

facts = node.system(Engine::Components::Facts)
facts[:met_smith] = true
facts[:wolves] = facts.fetch(:wolves, 0) + 1
facts.to_h                 # => { met_smith: true, wolves: 1 }
facts.restore(save.read.fetch(:facts, {}))
facts.on_changed { |key, value| ... }
```

A system on the root, found with `node.system` like `Players`, so every node
reaches the same store and none is handed it through a constructor.

**It takes only what survives a save.** Keys are Symbols. Values are `nil`,
`true`, `false`, an Integer, a Float or a String; anything else raises
`TypeError` on assignment. A Symbol value is refused because JSON brings it
back a String, and a condition comparing against `:open` would then fail after
every load — a bug no spec written without a save round trip would catch.

## The dialogue *(pure)*

### Writing one

```ruby
SMITH = Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
  beat :greeting, speaker: :smith, line: 'greeting' do
    respond 'ask_work', to: :work, once: true
    respond 'hammer',   to: :thanks, if: ->(d) { d.context.quests[:hammer].state == :found },
                        then: ->(d) { d.context.quests[:hammer].fire(:returned) }
    respond 'bribe',    to: :bribed, if: :can_bribe?, then: :pay_bribe
    respond 'bye'
  end

  beat :work, speaker: :smith, line: 'work', to: :greeting,
              enter: ->(d) { d.context.quests[:hammer].fire(:accepted) }
  beat :thanks, speaker: :smith, line: 'thanks', to: :greeting
  beat :bribed, speaker: :smith, line: 'bribed'
end
```

`Dialogue::Script.build` builds a `StateGraph` through a builder that adds two
words to `state` and `go`:

- **`beat name, speaker:, line:`** is a state carrying a speaker and a line.
  `line:` is a key under the script's `scope:`, or an `Engine::Text` for a line
  with variables, with `vars:` giving them as a block or a Symbol.
- **`respond label, to:`** is a transition a player picks, carrying a label key
  under the same scope. A beat with responses waits for one.
- **A beat's own `to:`** is where it goes when the player continues. A beat
  with neither responses nor `to:` ends the conversation when the player
  continues. A beat with both raises at build: a player would have no way to
  tell a continue from a choice.
- **`speaker:` is a Symbol the game owns.** Its name is drawn from the key
  `speakers.<speaker>`, and the same Symbol is what a portrait hook receives.
- **`once: true`** is `unless: "the target was ever visited"`, written once.

### Running one

```ruby
talk = Engine::Dialogue.new(SMITH, context: hero, facts: facts)

talk.speaker              # => :smith
talk.name                 # => the Engine::Text for speakers.smith
talk.line                 # => the Engine::Text for smith.greeting
talk.responses            # => this beat's responses, a frozen Array
talk.available?(response) # => whether its condition holds now
talk.respond(response)    # picks it
talk.continue             # for a beat without responses
talk.waiting_for_response?
talk.ended?
talk.on_beat  { |beat| ... }
talk.on_ended { ... }
talk.transcript           # => every beat shown and every response picked, in order
talk.to_h                 # and Dialogue.new(SMITH, ..., from: h) resumes one
```

`Dialogue` holds a `StateMachine` and forwards to it. It adds the words, the
transcript, and the rule that a beat either waits for a response or continues —
nothing that decides where the conversation goes. `visits`, `context` and
`facts` read through, so a condition written for a dialogue reads the same as
one written for a quest.

### The invariant

> **Where a conversation has got to never depends on whether, or how, it is
> drawn.**

A spec drives a `Dialogue` from greeting to goodbye with no box, and the box's
spec drives the same script through the box and asserts the same transcript.

### The transcript *(rough — step 4)*

A record, not a history the machine can walk back through (decision 4). Each
entry holds the speaker Symbol and the `Engine::Text` it drew, so a log drawn
after a language switch reads in the new language. A line with variables keeps
the values it was shown with, not the ones its `Text` holds now. Whether the
transcript goes into a save is open question 1.

## The reveal *(extends `UI::Label`)*

```ruby
label = UI::Label.new(text: talk.line, width: 440, lines_per_page: 3, reveal: 40)   # characters per second

label.revealed?     # => whether the page is fully shown
label.reveal_all    # shows the rest of the page at once — what confirm does first
```

A label with `reveal:` shows its page a character at a time. It counts in
`update(dt)`, as `Animator` counts frames, and a new page starts from nothing.
Without `reveal:` it draws as it does today.

**It draws prefixes it built before the frame.** When a page appears, the label
builds every prefix of each of its lines once, as frozen Strings, counted in
grapheme clusters so an accented letter is never drawn half-built. A three-line
page costs about 30 µs and 150 objects, once
([F4](01-current-state.md#f4-a-clip-cannot-hide-the-unrevealed-part-of-a-line--measured)).
`draw` then indexes into those Arrays and allocates nothing. A page whose lines
change identity between an `update` and a `draw` — a language switch — draws
fully revealed for that frame rather than building in `draw`.

What a label reveals is the label's business. When to call `reveal_all`, and
what confirm does next, is its owner's. That is the division `UI::Label`
already has for turning pages.

## The box *(rough — step 5)*

`UI::DialogueBox` is a `Node2D` that holds one `Dialogue`, a `UI::Label` for the
line, and a `UI::Menu` for the responses, and sits in a `PlayerLayer`.

- **Confirm does the next thing**, in order: reveal the rest of the page, turn
  the page, then continue — or, on a beat that waits, hand focus to the menu.
- **`unavailable: :hide | :disable`** decides what happens to a response whose
  condition fails. `:disable` adds it as a disabled button, which `Stepping`
  already skips. Its default is open question 2.
- **Availability is asked once per beat**, when the responses appear. The box
  asks nothing per frame.
- **The panel is a style**, `UI::ShapeStyle` or `UI::NineSliceStyle`, as a
  button's is.
- **A portrait is a hook** the box calls with the speaker Symbol. The box draws
  no portrait of its own.
- **The menu needs a way to drop its buttons** (F3), which is the step's first
  sub-step.
- **One conversation on every player's screen** is two boxes over one
  `Dialogue`. How the two take input is open question 4.

The box is the one place that hands the dialogue's data to another component —
responses into buttons. That is its job as a view, not a seam two systems
should have shared: the dialogue has no buttons, and the menu has no beats.
