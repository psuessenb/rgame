# Signals

**A signal is the engine's typed observer.** It holds a list of listener blocks
and `emit`s to them. Decoupled parts of the engine talk through signals. A
`UI::Button` reports that it was activated. A collider reports a hit. A
dialogue reports that it ended. The emitter never knows who listens, or
whether anyone does.

No central dispatcher exists, and no string or symbol event types need matching.
A signal *is* the channel. The attribute that exposes it names it, and its arity
is fixed when you define it.

`RGame::Engine::Signal` is pure Ruby, with no graphics, in
`lib/rgame/engine/signal.rb`.

## The Signal class: `Signal.define`

`Signal.define(*fields)` builds a signal **class**. Each instance is one channel:

```ruby
require 'rgame'

ClickSignal = RGame::Engine::Signal.define                   # carries no payload
ChangeSignal = RGame::Engine::Signal.define(:index, :value)  # carries two values

sig = ChangeSignal.new
handle = sig.connect { |index, value| puts "#{index} -> #{value}" }
sig.emit(index: 2, value: :hard)              # prints "2 -> hard"
sig.disconnect(handle)                        # stops that listener
```

A signal has three instance methods:

- **`connect(&block)`** registers a listener and returns it as the *handle*.
  Listeners fire in the order they connected.
- **`emit(...)`** notifies every listener.
- **`disconnect(handle)`** removes the listener that `connect` returned.

### Keyword in, positional out

**`emit` takes keywords; listeners receive positional values.** The field names
give `emit` a self-documenting signature. You call `emit(index:, value:)`, not
`emit(2, :hard)`, so a wrong or missing field raises at the call site:

```ruby
ChangeSignal = Signal.define(:index, :value)
sig.connect { |index, value| ... }   # positional params
sig.emit(index: 2, value: :hard)     # keyword args -> it.call(2, :hard)
```

Ruby blocks bind positional parameters cleanly but handle keywords awkwardly. The
generated `emit` therefore translates `emit(x:, y:)` into `it.call(x, y)`.

A signal with a single field takes its argument positionally, without a keyword:

```ruby
PlaySound = Signal.define(:id)
sig = PlaySound.new
sig.connect { puts "play #{it}" }
sig.emit(:boom)
```

### No per-emit allocation

**`emit` allocates nothing.** It passes its arguments straight to each listener,
never collecting them into an array or hash. The explicit fields make this
possible; a `*splat` signature would allocate. Some signals fire every frame, and
the engine never allocates on the hot path.

## The DSL: declaring a signal on a class

Wiring a signal onto a class by hand repeats itself. The class needs an ivar for
the instance, a public method to subscribe, and a way to emit:

```ruby
# Without the DSL:
ClickSignal = Signal.define
def initialize(...) = @clicked_signal = ClickSignal.new
def on_clicked(&block) = @clicked_signal.connect(&block)
def activate = @clicked_signal.emit
```

`RGame::Engine::Signal::DSL` reduces that to one declaration. `extend` it, then
declare each signal with `signal`, naming the event and then its fields:

```ruby
require 'rgame'

class Lever < RGame::Engine::Node2D
  extend RGame::Engine::Signal::DSL

  signal :pulled                    # no payload
  signal :changed, :index, :value   # a payload of two fields

  def pull = pulled_signal.emit
end

lever = Lever.new
lever.on_pulled { puts 'pulled' }
lever.pull
```

`signal :pulled` generates three methods, and adds the `on_` itself:

- **`on_pulled(&block)`** is *public*. It subscribes a listener and returns the
  handle. Observers call it: `lever.on_pulled { ... }`.
- **`disconnect_pulled(handle)`** is *public*. It ends the one connection that
  handle came from: `lever.disconnect_pulled(handle)`.
- **`pulled_signal`** is *private*. It returns the `Signal` instance, built on
  first use. The class emits through it: `pulled_signal.emit`.

**Ending a connection is public because it belongs to whoever made it**, while
emitting belongs to the class. A component that connects to a sibling in
`_attach` ends it in `_detach` with the handle it kept, so a pooled node
attached a second time does not collect a second listener:

```ruby
def _attach
  @collider = require_sibling(Collider)
  @handle = @collider.on_hit { |other| take(other) }
end

def _detach = @collider.disconnect_hit(@handle)
```

The reader builds the signal on first use and keeps it in `@rgame_pulled_signal`,
so the host wires **nothing** in `initialize`. A class keeping `@pulled` or
`@pulled_signal` of its own keeps it. The fields after the name are what `Signal.define` takes, and the
payload follows its rule: one field emits positionally, several as keywords.

**Name the signal after its event, a verb in the past tense.** `on_pulled`
then reads "when pulled happened". The DSL refuses a name that starts with
`on_`, and anything but Symbols after the name, raising `ArgumentError` when the
class is defined:

```ruby
require 'rgame'

begin
  Class.new(RGame::Engine::Node2D) { signal :on_pulled }
rescue ArgumentError => e
  e.message # => "signal :on_pulled: declare the event, signal :pulled; the DSL adds on_"
end
```

**A subclass cannot replace a generated method.** Defining `on_pulled` or
`pulled_signal` in a subclass raises `NameError` when the class is defined,
naming the signal and the class that declared it. A method meant as a hook but
named like the signal would otherwise replace the connect method, and every
block passed to it would be dropped. To react to a signal, connect a block to
it.

```ruby
require 'rgame'

class Lever < RGame::Engine::Node2D
  signal :pulled
end

begin
  Class.new(Lever) { def on_pulled = puts('pulled') }
rescue NameError => e
  e.name # => :on_pulled
end
```

**The DSL costs one extra method call per emit.** Emitting goes through the
private reader instead of a bare ivar. `emit` itself stays an ordinary `def`. UI
and per-frame signals never notice. For a signal emitted thousands of times per
frame, write it by hand against an ivar.

## Two shapes of signal

**Per-instance signals use the DSL.** Each object owns its channels. UI works this
way: every `UI::Button` has its own `on_activated`, and every `UI::OptionButton`
its own `on_changed`. The `signal` macro stores the instance in an ivar, which
suits exactly this case.

**A signal built by hand holds one channel outside the DSL.**
`RGame::Engine::Signal.define(:id).new` is a signal instance, and `connect`,
`disconnect` and `emit` work on it directly. A signal kept at module level holds
its listeners for as long as the process runs, and each listener holds whatever
its block holds. The engine keeps every signal on the object whose event it
reports.

## When to reach for a signal

Follow the engine's communication rules (see [Scene graph](scene_graph.md)):

- **Parent → child:** call methods directly. The parent holds the reference, so
  it needs no signal.
- **Child → parent, or sibling → sibling:** the child *exposes* a signal, and the
  parent or an observer the parent arranges subscribes. A `UI::Button` exposes
  `on_activated`, and the scene that adds it to a menu connects to it. Edges stay
  direct, node to node.
- **A service every node needs**, such as playing a sound: that is a request,
  not an event, and it wants exactly one receiver. Mount it as a
  [system](systems.md) and call it, as
  [`AudioOut`](audio.md#audioout--the-system-a-node-plays-sound-through) is.

Keep the emitter ignorant of its listeners. A signal with no listeners emits to
nobody, without error.
