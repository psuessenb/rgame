# `RGame::Core::App`

`App` owns the window and runs the frame loop. Subclass it, override the hooks
you need, and call `run`.

```ruby
require 'rgame/core'

class MyGame < RGame::Core::App
  def initialize = super(width: 800, height: 600, caption: 'My Game')
end

MyGame.new.run   # returns when the loop stops
```

`App.new` takes keyword arguments only. It requires `width:`, `height:` and
`caption:`. `media_root:` is optional and defaults to `'media'`. The constructor
opens a real window at once.

## What the app owns

The app builds two objects on first use. A game needs exactly one of each:

```ruby
require 'rgame/core'

class MyGame < RGame::Core::App
  def initialize = super(width: 640, height: 480, caption: 'demo', media_root: 'assets')
end

app = MyGame.new
app.assets   # => RGame::Core::AssetManager — rooted at media_root
app.audio    # => RGame::Core::Audio — the sound device
```

**A game never constructs either of them.** An image belongs to one OpenGL
context, so whatever loads it must know the app. The app builds its asset manager
once, and scenes load through it by path. No class has to pass the app along to
reach an image.

Both objects are built on first use. `RGame::Core::Renderer.new(app)` asks for the
asset manager, so any app that draws has one. An app that never plays a sound
never opens a sound device; the first sound request opens it.

`media_root` is read-only and fixed at construction. It has no writer: changing
the root after a load would leave one cache keyed against two roots.

[Assets](assets.md) describes the asset manager.

## The frame loop

`run` drives the loop until something stops it, and calls back into your object.
One rendered frame runs these steps:

```
  poll input and window events   →  button_down / button_up / resize
                                    gamepad_connected / gamepad_disconnected
  frame_begin                    →  once, before any ticks
  update(dt)                     →  zero or more times (see below)
  needs_redraw?                  →  once; false skips the draw
  draw                           →  once, unless skipped
  frame_end                      →  once, after draw, unless skipped
```

### `update(dt)` runs a *fixed* number of times, not once per frame

**The simulation advances in fixed steps.** Each frame adds the real elapsed
time to an accumulator. The frame then runs every whole step that has come due.
That can be **zero** steps, when the machine renders faster than the simulation
needs. It can be **several**, when a slow frame forces the simulation to catch
up. The loop caps catch-up, so a slow frame slows time down instead of spiralling.

`dt` is always the same fixed step: **1/60 second**. It is never wall-clock
frame time. A fixed step makes movement reproducible. It also lets a test call
`update` directly and simulate any amount of time.

**Do not sample input inside `update`.** A frame may run one tick or five, so a
key held for one frame would be read a varying number of times. Sample input in
`frame_begin`, or use `Input`. `Input` reads a snapshot taken once per frame, so
it answers the same for every tick of that frame.

### `needs_redraw?`

Return `false` to skip the draw for that frame. The simulation still advances.
Use it when nothing changed and drawing costs a lot. The default is `true`.

```ruby
def update(_dt)
  @dirty = true if something_moved
end

def needs_redraw? = @dirty

def draw
  # ...
  @dirty = false
end
```

`update` runs only when a step happened. Setting `@dirty = true` there is usually
the whole rule.

## Hooks you can override

Every hook inherits a default that does nothing. Override only what you use.

| Hook | When |
|---|---|
| `frame_begin` | Once per frame, before that frame's ticks. Sample input here. |
| `update(dt)` | One fixed simulation tick. |
| `needs_redraw?` | Before drawing; `false` skips `draw`. Default `true`. |
| `draw` | Render one frame. |
| `frame_end` | After `draw` reaches the GPU, before the buffer swap. Not called when the draw was skipped. |
| `button_down(id)` | A key was pressed. The loop filters auto-repeats, so a held key fires once. |
| `button_up(id)` | A key was released. |
| `resize(width, height)` | The window changed size. |
| `gamepad_connected(slot)` | A controller arrived in a player slot. |
| `gamepad_disconnected(slot)` | A controller left a slot. |

`id` is a value from [`RGame::Util::Controls`](input.md), such as
`Controls::KEY_ESCAPE`.

`frame_end` is the one point where a test can read back the frame it drew.
Game code rarely needs it.

### There is no built-in quit key

Closing the window stops the loop, because the platform decides that. Quitting
on Escape is *your* decision, so the engine leaves it to you:

```ruby
def button_down(id)
  close if id == RGame::Util::Controls::KEY_ESCAPE
end
```

## Window methods

| Method | |
|---|---|
| `run` | Runs the loop until it stops. Returns `self`. |
| `close` | Asks the loop to stop. Safe to call from inside any hook. |
| `width`, `height` | Current window size. |
| `caption`, `caption=` | The window title. |
| `fullscreen?`, `fullscreen=` | Whether the window covers the screen. |
| `ticks_ms` | Monotonic milliseconds since startup. For measuring frames, not for drawing. |
| `fps` | Most recent frames-per-second reading, updated about once a second. |

`close` takes effect promptly. The loop checks between steps and starts no more
work in the current frame.

`ticks_ms` is the raw clock. A draw never reads it: animation accumulates its own
time in `update`.

### Fullscreen

```ruby
require 'rgame/core'

app = RGame::Core::App.new(width: 640, height: 480, caption: 'demo', fullscreen: true)  # opens fullscreen
app.fullscreen = !app.fullscreen?                                                      # switches either way
```

**To open fullscreen, pass `fullscreen: true` to the constructor.** Setting it
after the window is up also works, but shows one windowed frame first. Players
read that flash as a broken startup. A game whose settings say fullscreen passes
the setting to `new`.

`width` and `height` still matter when the window opens fullscreen. The window
takes that size when it leaves fullscreen.

rgame uses **desktop** fullscreen: the window covers the screen at the screen's
own resolution. The display never changes mode. The switch is instant, needs no
mode list, and leaves other windows alone. The game gets a bigger view, not a
different one.

**Switching resizes the window**, so the loop calls
[`resize`](#hooks-you-can-override) with the new size. A user dragging a window
edge triggers the same call. Everything that lays out against the window learns
of the change through that one path. So a scene reads the `view` it is drawn
with, not the width it passed to `new`.

A layout written against fixed numbers will not follow a bigger view.
[`scale_mode:`](game.md#scale_mode--what-width-and-height-mean) on `RGame::Game`
offers the alternative: keep a logical size and scale it onto the window.

`examples/fullscreen` shows both ways to open, the switch, and every scale mode.

## Raw input queries

`App` exposes the input snapshot directly. Code written against Core alone
usually calls [`RGame::Core::Input`](input.md) instead, whose `down?` and `axis`
default the device to the keyboard. A game on `RGame::Game` reads actions and
never calls either. These queries are the primitives underneath:

| Method | |
|---|---|
| `input_down?(device, button_id)` | Is that button held on that device? |
| `input_axis(device, axis_id)` | Analog axis value; sticks −1.0…1.0, triggers 0.0…1.0. |
| `gamepad_present?(slot)` | Is a controller plugged into that player slot? |
| `gamepad_name(slot)` | Its human-readable name, or `nil`. |
| `gamepad_count` | How many controllers are connected. |

The query is named `gamepad_present?`, not `gamepad_connected?`. The hot-plug
*hook* above owns that name, and two methods that differ only by a `?` invite
mistakes.

## When a hook raises

`run` re-raises any exception from a hook, with its class, message and backtrace
intact. The loop shuts down cleanly first and closes the window:

```ruby
begin
  MyGame.new.run
rescue MyGameError => e
  # the loop has already stopped by the time this runs
end
```

A **non-local exit** cannot cross the loop that way. That covers `throw`,
`break` or `return` leaving a hook. `run` reports it as a `RuntimeError` that
tells you to use `close`. Only `close` and closing the window stop the loop.

## Several windows in one process

A process can create more than one `App`, and their lifetimes may overlap. The
engine keeps SDL alive until the last one is gone. Test suites rely on this: they
create and discard a window per example.
