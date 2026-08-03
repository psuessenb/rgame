# Input

Three pieces work together:

- **`RGame::Util::Controls`** — the vocabulary: which number means "the left
  arrow key", "the A button", "player 2's controller". Plain values, usable
  without loading any graphics library.
- **`RGame::Core::Input`** — translates your game's *actions* (`:fire`,
  `:confirm`) into those ids and asks the app whether they are held.
- **`RGame::Core::Gamepad`** — which controllers are plugged in, for menus.

There is no mouse support, by design.

## `RGame::Core::Input`

```ruby
input = RGame::Core::Input.new(app)

input.down?(:fire)                 # keyboard — the single-player default
input.down?(:fire, device: pad)    # a specific controller
input.axis(:move_x, device: pad)   # => Float
```

`down?` and `axis` read a snapshot the engine takes **once per frame**, when it
pumps events. That is what makes them safe to call from `update`: a frame can
run several simulation ticks, and every tick sees the same answer. Reading
hardware directly would make a held key behave differently depending on how
slow the previous frame was.

### Actions, not keys

You ask for `:fire`, not for the space bar. The mapping lives in a binding
table, so the same game code works for a keyboard player and a controller
player:

| Action | Keyboard | Gamepad |
|---|---|---|
| `:left` `:right` `:up` `:down` | arrow keys | dpad |
| `:confirm` | Return | A |
| `:fire` | Space | A |

Asking for an action nothing is bound to raises `KeyError`.

### Devices

Device 0 is the keyboard, and it is the default — so single-player code never
mentions devices at all. Controllers follow, one per player slot:

```ruby
Controls = RGame::Util::Controls

Controls::KEYBOARD       # => 0
Controls.gamepad(0)      # the first controller
Controls.gamepad(1)      # the second
Controls::MAX_GAMEPADS   # how many slots exist
```

A device only answers for its own kind of input. Asking a gamepad about a
keyboard key is `false`, never the keyboard's answer — otherwise player two's
pad would echo player one. The keyboard has no axes, so `axis` on it is `0.0`.

### Rebinding

A binding table is just a Hash of action to id, and the ids are ordinary values
from `Util`, so a game can build its own and hand it over:

```ruby
controls = RGame::Util::Controls
bindings = controls::DEFAULT_KEYBOARD.merge(fire: controls::KEY_RETURN)

input = RGame::Core::Input.new(app, bindings: bindings)
```

`Input.new` accepts three optional tables:

| Keyword | Default | Used for |
|---|---|---|
| `bindings:` | `Controls::DEFAULT_KEYBOARD` | keyboard buttons |
| `pad_bindings:` | `Controls::DEFAULT_PAD` | controller buttons |
| `axis_bindings:` | `Controls::DEFAULT_AXES` | analog axes |

The defaults are frozen, so `merge` a copy rather than mutating them.

## `RGame::Util::Controls`

The id vocabulary. Available from `require 'rgame'` **and** from
`require 'rgame/core'`, because these are plain integers with nothing behind
them — a game's configuration screen can name a key without pulling in a window.

**Keys** — `KEY_LEFT`, `KEY_RIGHT`, `KEY_UP`, `KEY_DOWN`, `KEY_RETURN`,
`KEY_SPACE`, `KEY_ESCAPE`, `KEY_F1`.

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

**Default tables** — `DEFAULT_KEYBOARD`, `DEFAULT_PAD`, `DEFAULT_AXES`.

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
    @moving_left = @input.down?(:left, device: @device)
  end
end
```

A controller unplugged mid-press has its buttons and axes cleared, so a button
held at that moment does not stay stuck down.
