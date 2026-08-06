# Signals

Signals are the engine's typed take on the observer pattern: a tiny object that
holds a list of listener blocks and `emit`s to them. They are how decoupled parts
of the engine talk to each other — a `Button` tells a `Menu` it was clicked, a
`Selector` announces its value changed, gameplay asks the audio layer to play a
sound — without the emitter knowing who (if anyone) is listening.

Signals replace the earlier global event bus / `Node#on` observer API. There is no
central dispatcher and no string/symbol event types to match on: a signal *is* the
channel, named by the attribute that exposes it, and its arity is fixed when it is
defined.

`RGame::Engine::Signal` is pure Ruby — no graphics — and lives in
`lib/rgame/engine/signal.rb`.

## The Signal class: `Signal.define`

`Signal.define(*fields)` builds a signal **class**. Each instance is one channel:

```ruby
ClickSignal = Signal.define              # carries no payload
ChangeSignal = Signal.define(:index, :value)  # carries two values

sig = ChangeSignal.new
handle = sig.connect { |index, value| puts "#{index} -> #{value}" }
sig.emit(index: 2, value: :hard)         # prints "2 -> hard"
sig.disconnect(handle)                   # stops that listener
```

Three instance methods:

- **`connect(&block)`** — registers a listener and returns it as the *handle*. Listeners
fire in the order they connected.
- **`emit(...)`** — notifies every listener.
- **`disconnect(handle)`** — removes the listener returned by `connect`.

### Keyword in, positional out

The field names exist to give `emit` a **self-documenting, mistake-catching
signature** — you call `emit(index:, value:)`, not `emit(2, :hard)`, so a wrong or
missing field raises at the call site. But the *listener* block receives the values
**positionally**:

```ruby
ChangeSignal = Signal.define(:index, :value)
sig.connect { |index, value| ... }   # positional params
sig.emit(index: 2, value: :hard)     # keyword args -> it.call(2, :hard)
```

This is deliberate. Ruby blocks bind positional parameters cleanly but handle
keyword arguments awkwardly, so the generated `emit` translates `emit(x:, y:)` into
`it.call(x, y)`.

A single-field signal does not follow this keyword convention, in this case the single parameter is non-keyworded.

```ruby
PlaySound = Signal.define(:id)
sig.connect { @audio.play_sound(it) }
sig.emit(:boom)
```

### No per-emit allocation

`emit` forwards its arguments straight to each listener — it never collects them
into an array or hash. Defining the signature with explicit fields (rather than a
`*splat`) is what makes this allocation-free, which matters because some signals
fire every frame (the engine's rule: never allocate on the hot path).

## The DSL: declaring a signal slot

Hand-wiring a signal onto a class is repetitive — an ivar to hold the instance, a
public method to subscribe, and a way to emit:

```ruby
# Without the DSL:
ClickSignal = Signal.define
def initialize(...) = @on_clicked = ClickSignal.new
def on_clicked(&block) = @on_clicked.connect(&block)
def activate = @on_clicked.emit
```

`RGame::Engine::Signal::DSL` collapses that to one declaration. `extend` it, then declare
slots with `signal`:

```ruby
class Button < Control
  extend RGame::Engine::Signal::DSL

  signal :on_clicked                          # a no-arg signal
  # signal :on_changed, Signal.define(:index, :value)  # a typed one

  def activate = on_clicked_signal.emit
end
```

`signal :on_clicked` generates two methods:

- **`on_clicked(&block)`** — *public*. Subscribe a listener; returns the handle. This
  is the API observers use: `button.on_clicked { ... }`.
- **`on_clicked_signal`** — *private*. The lazily-built `Signal` instance. Emit
  through it from inside the class: `on_clicked_signal.emit`.

The signal is created on first use (`@on_clicked ||= type.new`), so the host wires
**nothing** in `initialize`. Pass a signal class as the second argument for a typed
slot; omit it for a no-arg signal.

A note on cost: the generated methods use `define_method`, and emitting goes through
the private reader rather than a bare ivar — one extra method dispatch per emit
(single-digit nanoseconds under YJIT, and `emit` itself stays a full-speed `def`).
Negligible for UI and per-frame signals. For a signal emitted thousands of times per
frame, hand-write it against a direct ivar instead.

## Two shapes of signal

**Per-instance signals (the DSL).** Each object owns its channels. This is the UI
pattern: every `Button` has its own `on_clicked`, every `Selector` its own
`on_changed`. The `signal` macro is built for exactly this (it stores the instance
in an ivar).

**A shared signal hub (module-level).** When one global channel serves the whole app,
expose signals as module state instead. `RGame::Engine::AudioBus` is the example: it holds
`Signal.define(:id).new` instances at module scope and exposes them through reader
methods, so gameplay anywhere does `RGame::Engine::AudioBus.on_play_sound.emit(:boom)`
and the `AudioDirector` connects once. The DSL doesn't apply here (there is no
per-instance ivar); the hub hand-rolls the readers.

## When to reach for a signal

Follow the engine's communication rules (see [Scene graph](scene_graph.md)):

- **Parent → child:** call methods directly. No signal needed; the parent holds the
  reference.
- **Child → parent, or sibling → sibling:** the child *exposes* a signal and the
  parent (or a parent-arranged observer) subscribes. A `Button` exposes `on_clicked`;
  its `Menu` parent connects in `on_add` and re-exposes a higher-level
  `on_selected(index, id)` to the scene. Edges stay direct node-to-node.
- **Cross-cutting app concerns** with no natural owner (audio, later maybe analytics):
  a module-level hub like `AudioBus`.

Keep the emitter ignorant of its listeners: a signal with no observers connected
emits harmlessly to nobody.
