# `RGame::Core::App`

The window and the frame loop. Subclass it, override the hooks you need, call
`run`.

```ruby
require 'rgame/core'

class MyGame < RGame::Core::App
  def initialize = super(width: 800, height: 600, caption: 'My Game')
end

MyGame.new.run   # returns when the loop stops
```

`App.new` takes keyword arguments only; all three are required. Creating one
opens a real window immediately.

## The frame loop

`run` drives the loop until something stops it, calling back into your object.
One rendered frame looks like this:

```
  poll input and window events   →  button_down / button_up / resize
                                    gamepad_connected / gamepad_disconnected
  frame_begin                    →  once, before any ticks
  update(dt)                     →  zero or more times (see below)
  needs_redraw?                  →  once; false skips the draw
  draw                           →  once, unless skipped
```

### `update(dt)` runs a *fixed* number of times, not once per frame

This is the most important thing to understand about the loop.

The simulation advances in fixed steps. Real elapsed time accumulates, and each
frame runs however many whole steps have come due — which may be **zero**
(the machine is rendering faster than the simulation needs) or **several** (a
frame took a long time and the simulation is catching up). Catch-up is capped,
so a very slow frame makes time slow down rather than spiral.

`dt` is always the same fixed step, currently **1/60 second**. It is never
wall-clock frame time. That is deliberate: it makes movement reproducible, and
it is why a test can drive `update` directly and simulate any amount of time.

The practical consequence: **do not sample input inside `update`.** A key held
for one frame would be read once or five times depending on how slow the last
frame was. Sample it in `frame_begin` instead, or rely on `Input`, which reads
a snapshot taken once per frame and therefore answers identically for every
tick of that frame.

### `needs_redraw?`

Return `false` and the draw is skipped for that frame; the simulation still
advances. Useful when nothing has changed and drawing is expensive. The default
is `true`.

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

Because `update` running at all means a step happened, `@dirty = true` inside
`update` is usually the whole rule you need.

## Hooks you can override

Every one has an inherited no-op default, so override only what you use.

| Hook | When |
|---|---|
| `frame_begin` | Once per frame, before that frame's ticks. Sample input here. |
| `update(dt)` | One fixed simulation tick. |
| `needs_redraw?` | Before drawing; `false` skips `draw`. Default `true`. |
| `draw` | Render one frame. |
| `button_down(id)` | A key was pressed. Auto-repeats are filtered, so a held key fires once. |
| `button_up(id)` | A key was released. |
| `resize(width, height)` | The window changed size. |
| `gamepad_connected(slot)` | A controller arrived in a player slot. |
| `gamepad_disconnected(slot)` | A controller left a slot. |

`id` is a value from [`RGame::Util::Controls`](input.md) — for example
`Controls::KEY_ESCAPE`.

### There is no built-in quit key

Closing the window stops the loop, because that really is the platform's
decision. Quitting on Escape is *your* decision, so the engine does not make it
for you:

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
| `ticks_ms` | Monotonic milliseconds since startup. For animation phase. |
| `fps` | Most recent frames-per-second reading, updated about once a second. |

`close` takes effect promptly — the loop checks between steps, so it will not
start further work in the current frame.

## Raw input queries

`App` exposes the input snapshot directly. Most code should use
[`RGame::Core::Input`](input.md), which takes symbolic action names instead of
numeric ids, but these are the primitives underneath:

| Method | |
|---|---|
| `input_down?(device, button_id)` | Is that button held on that device? |
| `input_axis(device, axis_id)` | Analog axis value; sticks −1.0…1.0, triggers 0.0…1.0. |
| `gamepad_present?(slot)` | Is a controller plugged into that player slot? |
| `gamepad_name(slot)` | Its human-readable name, or `nil`. |
| `gamepad_count` | How many controllers are connected. |

Note the query is `gamepad_present?`, not `gamepad_connected?` — the latter
name belongs to the hot-plug *hook* above, and two methods differing only by a
`?` would be a trap.

## When a hook raises

An exception thrown from any hook comes back out of `run` with its class,
message and backtrace intact. The loop shuts down cleanly first, so the window
is not left stranded:

```ruby
begin
  MyGame.new.run
rescue MyGameError => e
  # the loop has already stopped by the time this runs
end
```

A **non-local exit** — `throw`, `break` or `return` crossing out of a hook —
cannot be carried across the loop the same way, and is reported as a
`RuntimeError` telling you to use `close` instead. Use `close` to stop the
loop; it is the only supported way out other than closing the window.

## Several windows in one process

Creating more than one `App` works, and they may overlap in lifetime; the
engine keeps SDL alive until the last one is gone. This mostly matters for test
suites, which create and discard a window per example.
