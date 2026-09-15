# Signals

**A signal is the engine's typed observer.** It holds a list of listener blocks
and `emit`s to them. Decoupled parts of the engine talk through signals. A
`UI::Button` reports that it was activated. A collider reports a hit. Gameplay
asks the audio layer to play a sound. The emitter never knows who listens, or
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

Signal = RGame::Engine::Signal

ClickSignal = Signal.define                   # carries no payload
ChangeSignal = Signal.define(:index, :value)  # carries two values

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

## The DSL: declaring a signal slot

Wiring a signal onto a class by hand repeats itself. The class needs an ivar for
the instance, a public method to subscribe, and a way to emit:

```ruby
# Without the DSL:
ClickSignal = Signal.define
def initialize(...) = @on_clicked = ClickSignal.new
def on_clicked(&block) = @on_clicked.connect(&block)
def activate = @on_clicked.emit
```

`RGame::Engine::Signal::DSL` reduces that to one declaration. `extend` it, then
declare slots with `signal`:

```ruby
require 'rgame'

class Lever < RGame::Engine::Node2D
  extend RGame::Engine::Signal::DSL

  signal :on_pulled                                                  # a no-arg signal
  signal :on_changed, RGame::Engine::Signal.define(:index, :value)   # a typed one

  def pull = on_pulled_signal.emit
end

lever = Lever.new
lever.on_pulled { puts 'pulled' }
lever.pull
```

`signal :on_pulled` generates two methods:

- **`on_pulled(&block)`** is *public*. It subscribes a listener and returns the
  handle. Observers call it: `lever.on_pulled { ... }`.
- **`on_pulled_signal`** is *private*. It returns the `Signal` instance, built on
  first use. The class emits through it: `on_pulled_signal.emit`.

The reader builds the signal on first use, so the host wires **nothing** in
`initialize`. Pass a signal class as the second argument for a typed slot. Omit
it for a signal without a payload.

**The DSL costs one extra method call per emit.** Emitting goes through the
private reader instead of a bare ivar. `emit` itself stays an ordinary `def`. UI
and per-frame signals never notice. For a signal emitted thousands of times per
frame, write it by hand against an ivar.

## Two shapes of signal

**Per-instance signals use the DSL.** Each object owns its channels. UI works this
way: every `UI::Button` has its own `on_activated`, and every `UI::OptionButton`
its own `on_changed`. The `signal` macro stores the instance in an ivar, which
suits exactly this case.

**A shared hub holds signals at module level.** Use one when a single channel
serves the whole game. `RGame::Engine::AudioBus` holds its signals at module scope
and exposes them through readers. Gameplay anywhere calls
`RGame::Engine::AudioBus.play_sound(:boom)`, and the `AudioDirector` connects
once to `AudioBus.on_play_sound`. The DSL does not apply, because there is no
instance; the hub writes its readers by hand.

## When to reach for a signal

Follow the engine's communication rules (see [Scene graph](scene_graph.md)):

- **Parent → child:** call methods directly. The parent holds the reference, so
  it needs no signal.
- **Child → parent, or sibling → sibling:** the child *exposes* a signal, and the
  parent or an observer the parent arranges subscribes. A `UI::Button` exposes
  `on_activated`, and the scene that adds it to a menu connects to it. Edges stay
  direct, node to node.
- **Concerns that cut across the game** and have no natural owner, such as
  audio: use a module-level hub like `AudioBus`.

Keep the emitter ignorant of its listeners. A signal with no listeners emits to
nobody, without error.
