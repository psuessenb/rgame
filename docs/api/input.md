# Input

Input has four pieces, in two layers:

- **`RGame::Util::Controls`** is the vocabulary. It says which number means "the
  left arrow key", "the A button" or "player 2's controller". These are plain
  values, usable without any graphics library.
- **`RGame::Core::Input`** is the raw query: is *this id* active on *this
  device*?
- **`RGame::Engine::InputMap`** says what those ids *mean*. Each player has one
  table that maps the game's actions onto physical ids.
- **`RGame::Engine::ActionMapper`** polls one player's device through their map
  once per tick. It produces an `Actions` snapshot.

**`RGame::Core::Gamepad`** adds a readout of the plugged-in controllers, for
menus.

rgame has no mouse support, by design.

## Which layer do I want?

**Use the engine layer.** A game declares its actions, reads
`actions.held?(:fire)`, and names a scancode only inside its input map. The
mapper polls `RGame::Core::Input`. Call `Input` directly only when you write
against `RGame::Core` alone, with no scene graph.

```ruby
require 'rgame/game'

Controls = RGame::Util::Controls

class MyRoot < RGame::Engine::Node2D; end

RGame::Game.new(
  root: MyRoot.new,
  input_map: RGame::Engine::InputMap.new(
    fire: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
  )
).start
```

## `RGame::Engine::InputMap`

An `InputMap` holds one entry per action and names physical ids directly. **A
rebinding screen edits this one table.**

```ruby
require 'rgame'

Controls = RGame::Util::Controls

map = RGame::Engine::InputMap.new(
  turn:   { axis: [Controls::KEY_LEFT, Controls::KEY_RIGHT], stick: Controls::AXIS_LEFT_X },
  thrust: { axis: [Controls::KEY_DOWN, Controls::KEY_UP], stick: Controls::AXIS_TRIGGER_RIGHT },
  fire:   { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
)
```

An entry uses up to three kinds of source, and may combine them:

| Key | Read with | Meaning |
|---|---|---|
| `buttons:` | `held?` / `pressed?` / `released?` | down if **any** listed id is down |
| `axis:` | `axis` | `[negative_id, positive_id]`, or a list of such pairs — a digital axis from buttons |
| `stick:` | `axis` | an analog axis id, for a real stick or a trigger |

`map[action]` returns an entry as an `InputMap::Binding`: a frozen Struct with
`buttons`, `pairs` and `stick`. `pairs` is always a list of pairs, even when the
entry gave one, and a source the entry does not use is `nil`.

A list of pairs binds several controls to one axis. The default `move_x` uses
this for the arrows, WASD and the d-pad:

```ruby
move_x: { axis: [[Controls::KEY_LEFT, Controls::KEY_RIGHT],
                 [Controls::PAD_DPAD_LEFT, Controls::PAD_DPAD_RIGHT]],
          stick: Controls::AXIS_LEFT_X }
```

When an action binds several axis sources, **the largest deflection wins**. No
per-device branching is needed. A keyboard reads `0.0` for every stick, and a
gamepad reads `false` for every key. The source for the other device contributes
nothing.

### One table serves every device

An entry can list a key and a pad button together, because **a device answers
only for its own kind of input**. A gamepad asked about a keyboard scancode
answers `false`; it never passes on the keyboard's state. So `fire` can be
"Space or A", and each player's device uses the half that applies to it.

### Prompts need the device's half

Reading an action needs no branch, but **showing** one does. A prompt saying
"press Space or A" tells players about hardware they are not holding.

```ruby
map.button_for(:fire, Controls::KEYBOARD)     # => KEY_SPACE
map.button_for(:fire, Controls.gamepad(0))    # => PAD_A
```

`button_for(action, device)` returns the first id bound to `action` that
`device` can press. It compares `Controls.pad_button?(id)` against
`Controls.gamepad?(device)`; the two id spaces never overlap. The first match
wins, so an entry's order is a prompt's preference. `ui_confirm` lists Return
before Space, so its prompt says Return.

`button_for` returns `nil` in three cases:

- nobody bound the action;
- the action has no buttons. A stick or digital axis is not a button, and needs
  a different picture;
- the entry has nothing for that kind of device.

It allocates nothing, so a HUD may call it every frame instead of caching a
string.

`examples/input_glyphs` shows the whole idea. It draws three prompts from a glyph
sheet keyed by button id. A seat moves between the keyboard and a controller
while you watch.

### A stick's sign is the device's

`AXIS_LEFT_Y` is positive **downwards**, like screen coordinates. An action that
wants the opposite, such as "thrust" or "climb", negates at the call site or
binds a trigger. The map stays declarative, with no inversion flag for every
reader to check.

### The universal UI set

**Every map merges over a universal UI set**, so these actions exist whether a
game declares them or not:

- `ui_up`, `ui_down`, `ui_left`, `ui_right`, `ui_confirm`, `ui_cancel` are
  buttons.
- `ui_radial_x` and `ui_radial_y` are axes on the left stick, the arrow keys and
  the d-pad. A menu built with [`Pointing`](ui.md#pointing) reads them.

Keyboard navigation and menus need these actions for **every** player. The `ui_`
prefix leaves `:up` free for the game. To change a binding, declare it:

```ruby
RGame::Engine::InputMap.new(ui_confirm: { buttons: [Controls::PAD_X] })
```

By default the radial axes share the left stick with `move_x` and `move_y`. They
remain separate actions. A game that walks on the left stick can move its wheel
to the right stick without touching movement.

`ui_cancel` is Escape. That is why `RGame::Game` quits on `F2`: players expect
Escape to back out of a menu.

### Defaults and rebinding

`InputMap.default` is the UI set plus eight-way movement and `fire`. `move_x` and
`move_y` sit on the arrows, WASD, the d-pad and the left stick. A game that wants
exactly this passes no `input_map:`.

`#merge` returns a copy with some actions replaced. A config screen uses it to
rebind one action without restating the rest:

```ruby
map = RGame::Engine::InputMap.default.merge(fire: { buttons: [Controls::KEY_RETURN] })
```

**A malformed entry raises at construction.** That covers an unknown source key,
an entry with no source, an empty button list, and an axis that is not a pair.
Otherwise the action would read as "never pressed" for the rest of the program.
Someone would discover it as a frame where nothing moves.

## `RGame::Engine::ActionMapper`

Each player has one `ActionMapper`. It polls that player's device through their
map and returns the `Actions` snapshot game logic reads.

```ruby
mapper = RGame::Engine::ActionMapper.new(map, device: Controls.gamepad(0))
actions = mapper.poll(input)

actions.held?(:fire)      # is it down now
actions.pressed?(:fire)   # did it go down this tick
actions.released?(:fire)  # did it come up this tick
actions.axis(:turn)       # -1.0..1.0
```

**Asking about an undeclared action raises `KeyError`**, naming the action and
listing the declared ones. A mistyped name fails on the first tick instead of
reading as "never pressed".

**The device lets two players share one map.** Every query carries the device,
so two mappers over the *same* map read two different controllers. Each mapper
keeps its own previous-tick state, so their edge queries stay independent.
Reassign `mapper.device` to follow a hot-plug.

`dead_zone:` (default `0.15`) ignores a resting stick, which reports small
non-zero values. It **rescales** the range instead of cutting it off, so a stick
leaving the dead zone ramps up from zero.

`RGame::Game` builds the mappers and polls them once per tick. A game normally
sees only the `Actions` passed to `control`.

## Players, seats and joining

`RGame::Engine::Players` is a root-scoped system that knows who is playing. Each
`RGame::Engine::Player` owns a device, an `InputMap`, a camera and a UI root.
Players share the game's action *names* but not the buttons behind them.

```ruby
RGame::Game.new(root: MyRoot.new, players: 2)
```

`players:` sets how many **seats** the game has, which is the most people who
can play. Player 0 starts on `Game`'s `device:`, the keyboard by default; the
other seats start empty. An empty
seat draws no viewport. A two-seat game with one player looks like an ordinary
full-screen game.

`player.active?` is `false` while that seat is empty. `players.each_active` yields
only the seated players, and `players.active_count` counts them.

### A device is seated when someone uses it

**Plugging a controller in seats nobody.** A plug says something about hardware.
Seating a player creates a camera, a viewport and a screen split. That needs a
statement of intent: a **`ui_confirm` press** on the device.

Joining waits for one action, not for any input, so a stick resting off centre
never seats a player. It reacts to the press edge, not to a held button, so one
press does one thing. `Players` reads the press through the map of the player who
would receive the device. Rebinding `ui_confirm` therefore rebinds "press to
join".

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

**`:takeover` serves single-player games.** A solo player who picks up a
controller is not a second person arriving. Their keyboard becomes unassigned,
and a `ui_confirm` press on it switches back. The last device used wins, in both
directions. Only `ui_confirm` switches; W does nothing. To switch on any key, set
`:ignore` and assign `players.primary.device` yourself. If the controller is
unplugged, the player falls back to the keyboard, so the game keeps responding.

**Under `:join` and `:ignore`, unplugging a controller empties its seat.** The
player's device becomes `nil`, so they draw no viewport until a device is seated
again. `players.seat(device)` fills the first empty seat and returns that player,
or `nil` when every seat is taken or joins are refused.

`accepting_joins = false` refuses both joins and takeovers. Use it during a
cutscene or a mid-round lockout.

`on_joined` fires with the player who received the device. A scene uses it to
spawn that player's character without polling. `examples/split_screen` shows the
whole flow in one file. The game opens full-screen for one player and splits
when a controller presses A.

## `RGame::Core::Input`

`Input` answers the raw query and nothing more.

```ruby
input = RGame::Core::Input.new(app)

input.down?(Controls::KEY_SPACE)                             # keyboard
input.down?(Controls::PAD_A, device: Controls.gamepad(0))    # player 1's pad
input.axis(Controls::AXIS_LEFT_X, device: Controls.gamepad(0))
```

**`down?` and `axis` read a snapshot the engine takes once per frame**, when it
pumps events. So they are safe to call from `update`. A frame can run several
simulation ticks, and every tick sees the same answer. Reading the hardware
directly would make a held key depend on how slow the previous frame was.

Ids are numbers that cross into C, so anything else raises `TypeError`. `Input`
applies no dead zone; it returns the hardware's answer.

### Devices

**Device 0 is the keyboard, and the default**, so single-player code never names
a device. Controllers follow, one per player slot:

```ruby
Controls::KEYBOARD       # => 0
Controls.gamepad(0)      # the first controller
Controls.gamepad(1)      # the second
Controls::MAX_GAMEPADS   # how many slots exist
```

A device answers only for its own kind of input. A gamepad asked about a
keyboard key answers `false`. Otherwise player two's pad would echo player one's
keys. The keyboard has no axes, so `axis` on it returns `0.0`.

## `RGame::Util::Controls`

`Controls` is the id vocabulary. Both `require 'rgame'` **and**
`require 'rgame/core'` load it. The ids are plain integers, so a configuration
screen can name a key without opening a window.

**Keys**: the 81 keys a Western keyboard reliably has.

| | |
|---|---|
| Letters | `KEY_A` … `KEY_Z` |
| Digits | `KEY_1` … `KEY_9`, `KEY_0` |
| Whitespace and editing | `KEY_RETURN`, `KEY_ESCAPE`, `KEY_BACKSPACE`, `KEY_TAB`, `KEY_SPACE` |
| Punctuation | `KEY_MINUS`, `KEY_EQUALS`, `KEY_LEFTBRACKET`, `KEY_RIGHTBRACKET`, `KEY_BACKSLASH`, `KEY_SEMICOLON`, `KEY_APOSTROPHE`, `KEY_GRAVE`, `KEY_COMMA`, `KEY_PERIOD`, `KEY_SLASH` |
| Function row | `KEY_CAPSLOCK`, `KEY_F1` … `KEY_F12` |
| Navigation | `KEY_INSERT`, `KEY_HOME`, `KEY_PAGEUP`, `KEY_DELETE`, `KEY_END`, `KEY_PAGEDOWN` |
| Arrows | `KEY_LEFT`, `KEY_RIGHT`, `KEY_UP`, `KEY_DOWN` |
| Modifiers | `KEY_LCTRL`, `KEY_LSHIFT`, `KEY_LALT`, `KEY_RCTRL`, `KEY_RSHIFT`, `KEY_RALT` |

**A scancode is a position, not a letter.** `KEY_A` is the key marked A on a
QWERTY board and Q on AZERTY. That suits `WASD` movement. A rebinding screen has
to explain it to players. The engine only compares numbers.

**Some keys are left out on purpose**: the numpad (most laptops lack one), the
GUI key (Windows on a PC, Command on a Mac), the print-screen cluster, and any key
whose position depends on the layout. Adding a key takes three edits: a
`#define` in `ext/rgame_core/include/rgame/core.h`, a `_Static_assert` against
the SDL scancode, and a constant here. `spec/rgame/util/controls_spec.rb` checks
that all three agree.

**Gamepad buttons**: `PAD_A`, `PAD_B`, `PAD_X`, `PAD_Y`, `PAD_BACK`,
`PAD_GUIDE`, `PAD_START`, `PAD_LEFT_STICK`, `PAD_RIGHT_STICK`,
`PAD_LEFT_SHOULDER`, `PAD_RIGHT_SHOULDER`, `PAD_DPAD_UP`, `PAD_DPAD_DOWN`,
`PAD_DPAD_LEFT`, `PAD_DPAD_RIGHT`.

Some buttons exist only on some hardware. They read as never pressed on a pad
without them: `PAD_MISC1` (share/capture/microphone), `PAD_PADDLE1` …
`PAD_PADDLE4` (Xbox Elite), `PAD_TOUCHPAD` (PS4/PS5).

**Axes**: `AXIS_LEFT_X`, `AXIS_LEFT_Y`, `AXIS_RIGHT_X`, `AXIS_RIGHT_Y`,
`AXIS_TRIGGER_LEFT`, `AXIS_TRIGGER_RIGHT`. Sticks read −1.0 to 1.0, with **y
positive downwards**. Triggers read 0.0 to 1.0. `Controls` applies no dead zone.
A resting stick reports small non-zero values, and the game decides where to cut
them off.

**Devices**: `KEYBOARD`, `GAMEPAD_FIRST`, `MAX_GAMEPADS`, and
`Controls.gamepad(slot)`.

**This module holds the vocabulary only**, with no binding tables.
`RGame::Engine::InputMap` says what an id *means*, one map per player.

Buttons and keys share one numbering, split into ranges. One "is it held" query
therefore serves every device. Use the constants; you never need the numbers.

A prompt has to know **which side of the split** an id is on, so `Controls` names
the check:

```ruby
Controls.gamepad?(device)   # a controller slot, or the keyboard?
Controls.pad_button?(id)    # a pad button, or a key?
```

`BUTTON_GAMEPAD_FIRST` marks the boundary. It is the C engine's own
`RGAME_BUTTON_GAMEPAD_FIRST`, checked against the header like every other id.
[`InputMap#button_for`](#prompts-need-the-devices-half) is built from these two
checks.

## `RGame::Core::Gamepad`

`Gamepad` tells a menu what is plugged in, for screens like "Player 2: connect a
controller". Button reads go through `Input`.

```ruby
pads = RGame::Core::Gamepad.new(app)

pads.count                                # how many are connected
pads.max_slots                            # how many slots exist
pads.connected?(0)                        # is slot 0 filled?
pads.name(0)                              # => "Xbox Controller" — or nil
pads.device(0)                            # the id Input wants for that slot
pads.each_connected { |slot, name| ... }  # lowest slot first
```

`device(slot)` connects `Gamepad` to `Input`. A menu that finds a pad can drive
it without knowing how devices are numbered.

An out-of-range slot returns an answer instead of raising, so a UI loop needs no
bounds checks.

### Slots are stable across a replug

**A controller that drops out and returns gets the same slot back**, so player 2
stays player 2. The engine remembers which device last used each slot. A new
controller takes the lowest free slot.

Two identical controllers report the same hardware id, so "the slot that
remembers this controller" is ambiguous. The engine resolves it the way players
expect. Two matching pads take slots 0 and 1. Whichever is unplugged gets its own
slot back when it returns.

## Reacting to hot-plug

`Gamepad` answers "what is connected now". The `App` hooks report when that
changes:

```ruby
require 'rgame/core'

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

When a controller is unplugged mid-press, the engine clears its buttons and axes.
A button held at that moment does not stay stuck down.

## `RGame::Core::VirtualGamepad`

**`VirtualGamepad` plugs a synthetic controller into a running `App`, for tests
that need the gamepad path with no hardware.** SDL fabricates the device inside
the process. The `App` seats it and calls `gamepad_connected` on its next frame,
as it would for a real pad, and `Input` reads its buttons and axes. It serves
tests, not gameplay; rgame's own Core suite drives its gamepad and hot-plug specs
through it.

```ruby
pad = RGame::Core::VirtualGamepad.new   # raises RuntimeError unless an App is open

pad.set_button(0, true)                  # button 0, which Input reads as Controls::PAD_A
pad.set_axis(0, -32_768)                 # axis 0 is Controls::AXIS_LEFT_X, fully left
pad.button_down?(0)                      # the raw button, before controller mapping
pad.game_controller?                     # does SDL have a mapping for it?
pad.attached?                            # is it still a live device?
pad.detach                               # the App calls gamepad_disconnected

RGame::Core::VirtualGamepad.pump         # apply pad state SDL has not applied yet
RGame::Core::VirtualGamepad.sdl_error    # what SDL last said
```

**Buttons and axes take SDL's own numbers.** A button number is a `Controls` pad
id minus `Controls::BUTTON_GAMEPAD_FIRST`. An axis number is the `Controls` axis
id itself. `set_axis` takes -32768 to 32767 and raises `RangeError` outside it.

`set_button` and `set_axis` return true when SDL accepts the change. SDL may
still apply a change later: outside an `App`'s frame loop a press reads back
only after one `VirtualGamepad.pump`. A test that must see a press land checks
`button_down?` and pumps until it does.

`detach` does nothing when called a second time. A pad that is never detached
stays plugged in until the last `App` is destroyed, because collecting the
object does not unplug it. SDL shuts down with the last `App` and takes every
virtual pad with it. After that every method except `detach` raises
`RuntimeError`.
