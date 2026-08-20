# Input

Four pieces, in two layers:

- **`RGame::Util::Controls`** — the vocabulary: which number means "the left
  arrow key", "the A button", "player 2's controller". Plain values, usable
  without loading any graphics library.
- **`RGame::Core::Input`** — the raw query: is *this id* active on *this
  device*.
- **`RGame::Engine::InputMap`** — what those ids *mean*: one table per player,
  mapping a game's actions onto physical ids.
- **`RGame::Engine::ActionMapper`** — polls one player's device through their
  map once per tick and produces an `Actions` snapshot.

Plus **`RGame::Core::Gamepad`**, a readout of which controllers are plugged in,
for menus.

There is no mouse support, by design.

## Which layer do I want?

Almost always the engine layer. A game declares its actions, reads
`actions.held?(:fire)`, and never names a scancode outside its input map.
`RGame::Core::Input` is what the mapper polls; you reach for it directly only
when writing against `RGame::Core` alone, with no scene graph.

```ruby
RGame::Game.new(
  root: MyRoot.new,
  input_map: RGame::Engine::InputMap.new(
    fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
  )
)
```

## `RGame::Engine::InputMap`

One entry per action, naming physical ids directly. **This is the single table a
rebinding screen edits.**

```ruby
Controls = RGame::Util::Controls

map = RGame::Engine::InputMap.new(
  turn:   { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT], stick: Controls::AXIS_LEFT_X },
  thrust: { axis: [Controls::KEY_DOWN, Controls::KEY_UP], stick: Controls::AXIS_TRIGGER_RIGHT },
  fire:   { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
)
```

Three kinds of source, and one action may combine them:

| Key | Read with | Meaning |
|---|---|---|
| `buttons:` | `held?` / `pressed?` / `released?` | down if **any** listed id is down |
| `axis:` | `axis` | `[negative_id, positive_id]` — a digital axis from two buttons |
| `stick:` | `axis` | an analog axis id, for a real stick or a trigger |

When an action binds both `axis:` and `stick:`, **the larger deflection wins**.
That needs no per-device branching: a keyboard reads `0.0` for every axis and a
stick reads `false` for every key, so whichever device a player is on, the other
source contributes nothing.

### One table serves every device

Listing a key and a pad button in the same entry is safe, because **a device
only answers for its own kind of input** — asking a gamepad about a keyboard
scancode is `false`, never the keyboard's answer. So `fire` can be "Space or A",
and each player's device picks out the half that applies to it.

### A stick's sign is the device's

`AXIS_LEFT_Y` is positive **downwards**, like screen coordinates. An action that
wants the opposite ("thrust", "climb") negates at the call site or binds a
trigger instead — the map stays declarative rather than growing an inversion
flag every reader would have to check for.

### The universal UI set

Every map is merged over a universal set, so these exist whether or not a game
declares them:

`ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_confirm`, `ui_cancel`

Keyboard navigation and menus rely on them being there for **every** player. They
are prefixed so a game is free to use `:up` for something of its own, and a game
that wants different bindings just declares one:

```ruby
InputMap.new(ui_confirm: { buttons: [Controls::PAD_X] })
```

`ui_cancel` is Escape — which is why `RGame::Game`'s quit key is `F2`. The button
a player expects to back out of a menu belongs to the menu.

### Defaults and rebinding

`InputMap.default` is the UI set plus eight-way movement (`move_x`, `move_y`) on
the arrows or the left stick, and `fire`. A game wanting exactly that passes no
`input_map:` at all.

`#merge` returns a copy with some actions replaced, which is how a config screen
rebinds one without restating the rest:

```ruby
map = RGame::Engine::InputMap.default.merge(fire: { buttons: [Controls::KEY_RETURN] })
```

A malformed entry raises at construction — an unknown source key, an entry with
no source, an empty button list, an axis that is not a pair. That is deliberate:
the alternative is an action that reads as "never pressed" for the rest of the
program, discovered as a frame nobody can move in.

## `RGame::Engine::ActionMapper`

One per player. It polls that player's device through their map and returns the
`Actions` snapshot game logic reads.

```ruby
mapper = RGame::Engine::ActionMapper.new(map, device: Controls.gamepad(0))
actions = mapper.poll(input)

actions.held?(:fire)      # is it down now
actions.pressed?(:fire)   # did it go down this tick
actions.released?(:fire)  # did it come up this tick
actions.axis(:turn)       # -1.0..1.0
```

**The device is what makes two players work.** Every query carries it, so two
mappers over the *same* map read two different controllers, and each keeps its
own previous-frame state so their edge queries are independent. Reassign
`mapper.device` to follow a hot-plug.

`dead_zone:` (default `0.15`) ignores a resting stick, which genuinely reports
small non-zero values. It **rescales** rather than merely cutting off, so a stick
leaving the dead zone ramps from zero instead of jumping to `0.15`.

`RGame::Game` builds one of these for you and polls it once per tick; a game
normally sees only the `Actions` handed to `control`.

## Players, seats and joining

`RGame::Engine::Players` is a root-scoped system holding who is playing. Each
`RGame::Engine::Player` owns a device, an `InputMap`, a camera and a UI root —
the action *names* are the game's and shared, the buttons behind them are not.

```ruby
RGame::Game.new(root: MyRoot.new, players: 2)
```

`players:` is how many **seats** the game has, and therefore the most people who
can play it. Player 0 starts on the keyboard; the rest start empty. An empty
seat draws no viewport, so a two-seat game with nobody in the second one is an
ordinary full-screen single-player game.

### A device is seated when someone uses it

Not when it is plugged in. Plugging a controller in says something about
hardware; seating a player creates a camera, a viewport and a screen split, and
that follows a statement of intent — a **`ui_confirm` press** on the device.

One action rather than "any input", because a stick resting slightly off centre
must never seat a player. An edge rather than held, so one press does one thing.
It is read through the map of whoever would receive the device, so rebinding
`ui_confirm` rebinds "press to join" with it.

```ruby
players = node.system(RGame::Engine::Players)

players.on_unassigned_input = :join       # :join | :takeover | :ignore
players.accepting_joins = false           # temporarily refuse
players.on_joined { |player| spawn(player) }
```

| Policy | A press on a device nobody holds | Default when |
|---|---|---|
| `:join` | fills the next free seat | there is more than one seat |
| `:takeover` | becomes the **primary** player's device | there is one seat |
| `:ignore` | nothing; the game calls `players.seat(device)` itself | — |

`:takeover` is single-player's answer: one person already playing who picks up a
controller is not a second person arriving. Their keyboard becomes unassigned,
so using it again takes them back — last device used wins. And if their
controller is unplugged they fall back to the keyboard rather than the game
going dead in their hands.

`accepting_joins = false` refuses both, which is what a cutscene or a mid-round
lockout wants.

`on_joined` fires with the player who got the device, which is how a scene
spawns their character without polling for one. See `examples/15_tiled_world`.

## `RGame::Core::Input`

The raw query, and deliberately nothing more.

```ruby
input = RGame::Core::Input.new(app)

input.down?(Controls::KEY_SPACE)                             # keyboard
input.down?(Controls::PAD_A, device: Controls.gamepad(0))    # player 1's pad
input.axis(Controls::AXIS_LEFT_X, device: Controls.gamepad(0))
```

`down?` and `axis` read a snapshot the engine takes **once per frame**, when it
pumps events. That is what makes them safe to call from `update`: a frame can run
several simulation ticks, and every tick sees the same answer. Reading hardware
directly would make a held key behave differently depending on how slow the
previous frame was.

Ids are numbers, and they cross into C, so passing anything else raises
`TypeError`. No dead zone is applied here — this is the hardware's answer.

### It used to hold the binding tables

It took `down?(:fire)` and resolved `:fire` through one of three tables passed to
its constructor. Those tables are gone. Binding moved up to `InputMap` for two
reasons: a rebinding screen has to be able to edit the table, and the engine
layer may not name `RGame::Core` at all; and with a player per device, the table
is a per-player value rather than a property of the one object that talks to the
hardware.

### Devices

Device 0 is the keyboard, and it is the default — so single-player code never
mentions devices at all. Controllers follow, one per player slot:

```ruby
Controls::KEYBOARD       # => 0
Controls.gamepad(0)      # the first controller
Controls.gamepad(1)      # the second
Controls::MAX_GAMEPADS   # how many slots exist
```

A device only answers for its own kind of input. Asking a gamepad about a
keyboard key is `false`, never the keyboard's answer — otherwise player two's pad
would echo player one. The keyboard has no axes, so `axis` on it is `0.0`.

## `RGame::Util::Controls`

The id vocabulary. Available from `require 'rgame'` **and** from
`require 'rgame/core'`, because these are plain integers with nothing behind
them — a game's configuration screen can name a key without pulling in a window.

**Keys** — `KEY_LEFT`, `KEY_RIGHT`, `KEY_UP`, `KEY_DOWN`, `KEY_RETURN`,
`KEY_SPACE`, `KEY_ESCAPE`, `KEY_F1`, `KEY_F2`.

**Gamepad buttons** — `PAD_A`, `PAD_B`, `PAD_X`, `PAD_Y`, `PAD_BACK`,
`PAD_GUIDE`, `PAD_START`, `PAD_LEFT_STICK`, `PAD_RIGHT_STICK`,
`PAD_LEFT_SHOULDER`, `PAD_RIGHT_SHOULDER`, `PAD_DPAD_UP`, `PAD_DPAD_DOWN`,
`PAD_DPAD_LEFT`, `PAD_DPAD_RIGHT`.

**Axes** — `AXIS_LEFT_X`, `AXIS_LEFT_Y`, `AXIS_RIGHT_X`, `AXIS_RIGHT_Y`,
`AXIS_TRIGGER_LEFT`, `AXIS_TRIGGER_RIGHT`. Sticks read −1.0 to 1.0 with **y
positive downwards**; triggers read 0.0 to 1.0. No dead zone is applied — where
to put one is a game decision, and a resting stick genuinely does report small
non-zero values.

**Devices** — `KEYBOARD`, `GAMEPAD_FIRST`, `MAX_GAMEPADS`, and
`Controls.gamepad(slot)`.

This module is the **vocabulary only**. It carries no binding tables — what an id
*means* is `RGame::Engine::InputMap`, one per player.

Buttons and keys share one numbering, partitioned into ranges, so a single
"is it held" query serves every device. You never need the numbers themselves —
use the constants.

## `RGame::Core::Gamepad`

A readout for menus — "Player 2: connect a controller". Reading a *button* goes
through `Input`; this answers what is plugged in.

```ruby
pads = RGame::Core::Gamepad.new(app)

pads.count                                # how many are connected
pads.max_slots                            # how many slots exist
pads.connected?(0)                        # is slot 0 filled?
pads.name(0)                              # => "Xbox Controller", or nil
pads.device(0)                            # the id Input wants for that slot
pads.each_connected { |slot, name| ... }  # lowest slot first
```

`device(slot)` is the bridge to `Input`: a menu that has just found a pad can
drive it without knowing how devices are numbered.

Out-of-range slots answer rather than raising, so a UI loop needs no bounds
checks.

### Slots are stable across a replug

A controller that falls out and comes back returns to the **same** slot, so
player 2 stays player 2. The engine remembers which device last occupied each
slot; a genuinely new controller takes the lowest free one.

Two identical controllers report the same hardware id, so "the slot that
remembers this controller" is ambiguous for them. The rule resolves it the way
a player expects: two matching pads take slots 0 and 1, and whichever is
unplugged gets its own slot back when it returns.

## Reacting to hot-plug

Polling with `Gamepad` answers "what is connected now". The `App` hooks tell you
when that changes:

```ruby
class MyGame < RGame::Core::App
  def initialize
    super(width: 800, height: 600, caption: 'demo')
    @pads = RGame::Core::Gamepad.new(self)
    @input = RGame::Core::Input.new(self)
  end

  def gamepad_connected(slot)
    puts "controller in slot #{slot}: #{@pads.name(slot)}"
  end

  def gamepad_disconnected(slot)
    puts "controller left slot #{slot}"
  end

  # Read whichever device player one currently has.
  def frame_begin
    @device = @pads.connected?(0) ? @pads.device(0) : RGame::Util::Controls::KEYBOARD
  end

  def update(_dt)
    @moving_left = @input.down?(RGame::Util::Controls::KEY_LEFT, device: @device)
  end
end
```

A controller unplugged mid-press has its buttons and axes cleared, so a button
held at that moment does not stay stuck down.
