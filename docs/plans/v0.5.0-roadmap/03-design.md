# The design, item by item

Sketches are code, and their names get built as written. Signals are past-tense
verbs, hooks take `_`, and nothing here defines a method starting with `on_`.

## 1. Input: a hold, a tap and a chord

### The declaration

Three keys join `buttons:`, `axis:` and `stick:` in an `InputMap` entry:

```ruby
map = RGame::Engine::InputMap.new(
  interact: { buttons: [Controls::KEY_E, Controls::PAD_A], tap: 0.3 },
  search:   { buttons: [Controls::KEY_E, Controls::PAD_A], hold: 0.6 },
  swap:     { all: [Controls::PAD_LEFT_SHOULDER, Controls::PAD_RIGHT_SHOULDER] }
)
```

| Key | Means |
|---|---|
| `hold:` | seconds the buttons must be down before this action presses |
| `tap:` | seconds within which the release must come for this action to press |
| `all:` | every id must be down; the action presses when the last of them arrives |

**One button backs two actions, one tapped and one held.** That is the whole
point, and it is what Unreal and Unity both do —
[02](02-prior-art.md#input-a-trigger-per-action-not-a-timer-per-caller). `E`
tapped opens the chest; `E` held searches it.

`hold:` and `tap:` are numbers, not `true`. A threshold that reads as a literal
in the map is one a rebinding screen can show and a designer can argue with.

### What a game reads

Nothing new but one query. The three existing ones keep their meaning, because
the mapper decides what "down" means per action before writing it:

```ruby
actions.pressed?(:search)     # the tick the hold threshold passes; once per press
actions.held?(:search)        # from then until the buttons come up
actions.released?(:search)    # when they do
actions.pressed?(:interact)   # the tick of a release that came in time
actions.held_for(:interact)   # seconds its buttons have been down; 0.0 at rest
```

A tap action is **a one-tick pulse**: `held?` is true for that tick only, so
`pressed?` and `released?` fall out of the machinery already there. A hold
action is a level that begins late.

### Inside the mapper

`poll` takes the timestep, and `Actions` grows a fourth hash beside `held`,
`prev_held` and `axes`:

```ruby
def poll(backend, dt)
  @held.each { |name, down| @prev_held[name] = down }
  return rest if @device.nil?

  @map.bindings.each do |name, binding|
    was_down = @down[name]
    now_down = down?(backend, binding)
    @held[name] = level(name, binding, was_down, now_down)
    @hold_times[name] = now_down ? @hold_times[name] + dt : 0.0
    @down[name] = now_down
    @axes[name] = axis_value(backend, binding) if binding.pairs || binding.stick
  end
  silence_chorded
  @actions
end
```

`level` is the only branch: a plain action is `now_down`; a hold action is
`now_down && @hold_times[name] >= binding.hold`; a tap action is
`was_down && !now_down && @hold_times[name] <= binding.tap`.

**A chord silences its parts.** Each chord binding knows, from construction,
which actions share its buttons, so `silence_chorded` walks a precomputed list
and writes `false`. No scanning, no allocation:

```ruby
Binding = Struct.new(:buttons, :pairs, :stick, :all, :hold, :tap, :silences)
```

`Players#poll(backend, dt)` and `Player#poll(backend, dt)` pass the timestep
down. `Players::Everyone` folds `held_for` as the largest of its members', as it
folds an axis.

`InputMap#button_for` answers `nil` for a chord. A prompt for one is two glyphs
and a plus sign, which is a different picture — the same reason an axis answers
nil today.

### What it refuses

- `hold:` and `tap:` on one action. An action is one or the other.
- `hold:` or `tap:` with no `buttons:` or `all:`.
- `all:` with fewer than two ids.
- A threshold that is not a positive number.

## 2. The debug layer

### A system of channels

```ruby
debug = node.system(RGame::Engine::Debug)
debug.shows?(:shapes)
debug.show(:shapes); debug.hide(:shapes); debug.toggle(:stats)
debug.define(:routes) { |renderer, view| ... }   # a game's own channel
```

`Engine::Debug` is a `Component` mounted on the root by `RGame::Game`, beside
`Players`, `Viewports` and `Facts`. It holds a flag per channel and the blocks
a game defined, and its `_draw` draws the stats overlay and every defined
channel in the `:debug` band.

Two channels ship. **`:stats`** is today's `DebugOverlay`, which stays what it
is and becomes one channel rather than the whole layer. **`:shapes`** is drawn
by the things that have shapes.

`Game` binds F1 to `:stats` and F3 to `:shapes`, and `game.debug_keys = false`
turns the development keys off — F2's quit included — for a build a player
runs.

### A shape draws itself

```ruby
class Components::BoxCollider < Engine::Component
  def _attach
    @debug = node.system(Engine::Debug)
    node.system(CollisionWorld)&.register(self)
  end

  def _draw(renderer, _view)
    return unless @debug&.shows?(:shapes)

    renderer.layered(:debug) { renderer.debug_box(box.offset_x, box.offset_y, box.width, box.height) }
  end
end
```

Three things make this the cheap shape. A collider's box is already in its
node's local space, so `Game/DrawInLocalSpace` is satisfied and the box lands
where the node is, in every viewport, with no camera arithmetic. `push_layer`
**replaces** rather than accumulates, so `:debug` wins whatever band the node
draws in. And a scene with no `Debug` mounted — every spec that builds a bare
tree — gets `nil` and draws nothing.

`renderer.debug_circle(cx, cy, radius)` joins `debug_box`, so a
`CircleCollider` has a shape to draw. It lands in the `a renderer` contract and
in `FakeRenderer` in the same commit as the renderer.

**Solid cells are drawn by `WorldView`**, which is the node that marks world
space and already draws once per viewport. It asks the scene's `TileWorld`
which of the cells in view are solid, and draws those. Nothing to mount, and a
scene without a `TileWorld` draws nothing.

## 3. Interacting and collecting

### The actor asks a question `Targeting` already answers

```ruby
class Components::Interactor < Components::Targeting
  signal :interacted, :target

  def initialize(range:, layer: :interactable, action: :interact, policy: :nearest)
    super(range: range, layer: layer, policy: policy)
    @action = action
  end

  def _control(actions)
    return if target.nil? || !actions.pressed?(@action)

    interacted_signal.emit(target)
  end
end
```

`Targeting` picks the nearest collider in range on a layer, every update, and
exposes the node. That is exactly what "what would I interact with" means, so
this adds the press and nothing else. `target` is also what a game draws its
prompt over.

Two consequences to state in the docs. A node holding both a `Targeting` and an
`Interactor` cannot be looked up by `get_component(Targeting)`, because both
match — it is looked up by name. And `:interact` joins
`InputMap::DEFAULT_ACTIONS`, so a game that declares nothing has a button for
it.

### The thing collects itself

```ruby
class Components::Collectable < Engine::Component
  signal :collected, :other

  def initialize(by:, sound: nil, free: true)

  def _attach
    @collider = require_sibling(Components::BoxCollider)
    @handle = @collider.on_hit { |other| take(other) if other.layer == @by }
  end

  def _detach = @collider.hit_signal.disconnect(@handle)
end
```

`take` emits `collected`, plays `sound` through `node.system(AudioOut)` if it
was given one, and calls `node.queue_free` unless `free: false`. A chest that
opens rather than vanishing passes `free: false` and listens.

**This is the second component that has to disconnect what it connected**,
which is the trigger `possible-todos.md` records under "A connection that ends
with its node". Step 3 says so rather than quietly writing the `_detach` again.

## 4. Pushing and pulling

### A mover moves what it cannot pass

```ruby
crate.add_component(Components::Pushable.new(blocked_by: %i[tiles wall crate]))

hero.add_component(Components::CharacterBody.new(speed: 80,
                                                 blocked_by: %i[tiles wall crate],
                                                 pushes: [:crate]))
hero.add_component(Components::Grab.new(action: :grab, layer: :crate, range: 20))
```

`pushes:` parallels `blocked_by:` exactly: one names what stops a step, the
other what a step moves instead. A layer in `pushes:` is normally in
`blocked_by:` too — a crate you can push is a crate you cannot walk through.

`Components::Pushable` is a `Mover` whose `take_step` does nothing. It moves
only when something asks it to, and it resolves that move against its own
`blocked_by:`, which is what makes a crate stop against a wall, against a tile,
and against another crate.

Inside `Mover#apply_move`, per axis:

1. Resolve the step. If nothing stopped it, done.
2. If the blocker's layer is in `pushes:` and its node holds a `Pushable`, ask
   it to move by the distance left on that axis.
3. Whatever it managed, resolve this mover's step again. A crate that moved
   nothing stops the pusher, with `on_blocked` as usual.

**Depth is capped.** A crate's own `pushes:` makes a crate push a crate, and a
ring of crates would recurse for ever, so a push carries a depth and stops at
`PUSH_DEPTH`. A pushed node never pushes the node that pushed it.

### Pulling is the same step, applied first

`Components::Grab` reads its action in `_control` and hands the mover what it
has hold of:

```ruby
def _control(actions)
  @mover.grabbed = actions.held?(@action) ? pushable_in_reach : nil
end
```

`apply_move` then moves the grabbed `Pushable` by the same delta **before**
resolving its own step, and clamps its own step to what the crate managed. So
backing into a wall with a crate in hand stops both.

Ordering is by phase, not by sibling order: `_control` runs for every component
before any `_update`, so the grab is always set before the step is taken. That
is the failure `Components::Mover`'s header warns about, avoided by putting the
two halves in different phases.

### The grid puzzle needs no engine change

A Sokoban block is a node with `Components::OccupiesCell`, a
`Components::Tween` and a listener on the hero's `on_blocked`: pushed in one
direction for long enough, it vacates its cell, tweens to the next one and
occupies that, if `TileWorld#solid?` says the next one is free. The engine
already has every part, so this lives in the example.

## 5. Inventory and equipment screens

Re-planned after step 4, and the roadmap's sketches supersede the ones below
where they differ. [What that re-plan changed](04-roadmap.md#re-planning-steps-57):
a group names the one menu that reads input, a direction a button does not
adjust crosses as well as the end of a line does, and a tab bar is a `Menu`.

### A grid is a layout, and stepping already knows how to step

```ruby
UI::Grid.new(columns: 5, item_width: 48, item_height: 48, spacing: 6)
```

`UI::Grid` answers `arrange`, `bounds` and `axis` like `UI::Stack`, and one
thing more: `columns`. `UI::Stepping` reads it when the layout answers it, and
a step up or down becomes a step of that many buttons instead of one.
Everything else it does — skipping disabled buttons, never leaving focus empty
— is unchanged, which is why this is one `if` rather than a second navigation
class.

Wrapping is per line: left and right wrap inside the row, up and down inside
the column.

### Focus crosses menus, and a group is what it crosses

```ruby
group = layer.add_node(UI::FocusGroup.new)
bag  = group.add_node(UI::Menu.new(x: 16,  y: 48, layout: grid))
worn = group.add_node(UI::Menu.new(x: 320, y: 48, layout: column))
group.current   # the one menu that reads input
```

A menu joins the nearest group above it as it enters the tree. Only the group's
`current` menu reads input; the others draw with nothing focused.

A `Stepping` about to wrap asks its menu's group first, and so does a direction
the focused button does not adjust. The group compares the
menus' bounds, finds the nearest one in that direction, and focuses its nearest
button; with no neighbour that way, the step wraps as it does today. So a bag
and a set of equipment slots become one screen, and neither menu knows the
other exists.

### Tabs take the shoulder buttons

```ruby
tabs = layer.add_node(UI::Tabs.new(x: 16, y: 12, layout: UI::Row.new(item_width: 96, item_height: 28),
                                   scope: 'inventory'))
gear = tabs.add(UI::PanelButton.new(label: 'gear'), equipment_screen)
tabs.on_changed { |page| ... }
```

`UI::Tabs` holds its bar as a `Menu` that nothing confirms, stepped by two
actions of its own. It holds its pages off its child list, the way `SceneStack`
holds scenes, draws and controls the page shown, and updates every page. It
reads two new actions from the universal UI set, `ui_tab_prev` and
`ui_tab_next`, bound to the shoulder buttons and to the keys
[open question 2](README.md#open-questions) picks. The bar's focused button is
the tab shown, and `ui_confirm` never reaches it: switching a page is a route of
its own, which is the console convention Unreal's CommonUI encodes.

### Scrolling shows whole rows

`UI::Column` and `UI::Grid` take `visible_rows:`. The menu draws only the rows
in its window, and moving focus past the edge scrolls the window by one row.

**Whole rows, and no clip.** A half-drawn row needs `renderer.clipped`, which
would work — a clip is mapped through the current transform, so a menu's own
coordinates are the right ones — but it buys nothing here: a list of items
reads better on row boundaries, and nothing has to think about what a clip does
inside a `PlayerLayer` that is already clipped to a viewport.

### Two examples, as dialogue had two

`examples/inventory` shows the parts: a grid of items, moving focus, one panel.
`examples/equipment` shows the screen a game ships: tabs switched with the
shoulder buttons, a set of clothes to put on and take off, and a bag that marks
what is worn.

## 6. Fades, sparkles and lightning

### A fade is a node in the overlay band

```ruby
fade = layer.add_node(Engine::ScreenFade.new(color: Util::Color.new(0, 0, 0)))
fade.cover(0.4)                       # to opaque
fade.reveal(0.4)                      # back to clear
fade.flash(0.15, color: WHITE)        # up and back down
fade.on_finished { ... }
```

It is an `Engine::Tween` and one rect the size of the view it is drawn into,
in the `:overlay` band, so it covers the world and the HUD and not the debug
layer. Its alpha is computed in `_update` and the colour it draws with is built
there too — once per tick rather than once per draw, which is what keeps the
draw path free of allocation with a colour that changes.

A storm's flash is this class with white and a short `:out` ease. A room
transition is `cover`, then the switch, then `reveal` — see item 8.

### Sparkles are a component over the pool that exists

```ruby
node.add_component(Components::Particles.new(
  count: 24, lifetime: 0.5..0.8, speed: 40..90, spread: Math::PI,
  size: 3, from: Util::Color.new(255, 240, 160), to: Util::Color.new(255, 120, 0, 0),
  gravity: 60, burst: true
))
particles.emit(x, y)
```

The parameter list is Godot's `CPUParticles2D` cut down to what sparkles, dust
and smoke need: a lifetime, a speed and a spread, a size, a colour walked from
`from` to `to` over each particle's life, and gravity. `burst: true` emits the
whole count at once; without it they stream.

It draws its particles itself, in its node's local space, and holds them in a
`Pool`, so a running emitter allocates nothing.

### A bolt is an example, and glow is C

A lightning bolt is `renderer.line(thickness:)` along a jagged path, redrawn
with a different jag every few frames, plus a `ScreenFade#flash`. The jaggedness
is taste rather than engine, so the bolt lives in `examples/effects`.

**What the engine adds is the blend mode**, because sparkles and a bolt look
like light only when they add to what is behind them:

```ruby
renderer.blended(:add) { ... }     # :alpha is the default
```

In C, a blend mode travels with a draw command exactly as the clip does, for
the reason `draw_queue.h` states: sorting reorders commands, so ambient state
at draw time lands on whichever quads sort next to it. That means a field on
`rgame_draw_command` and `rgame_draw_batch`, a comparison in the batch test, a
`set_blend` entry on the backend table, a push and pop on the canvas, and the
recording backend the Check suite substitutes. `glBlendFunc(GL_SRC_ALPHA,
GL_ONE)` is the whole of the GL side, and it is core 1.0.

## 7. Audio transitions

### Core gains the knobs; the engine decides when to turn them

```ruby
# RGame::Core::Audio
audio.music_volume(:theme, 0.4)        # this song's own volume
audio.pause_music(:theme)              # keeps the playhead
audio.resume_music(:theme)             # starts again without seeking  (new C)
audio.category_volume(:music, 0.7)     # a multiplier over every song
audio.category_volume(:effects, 0.5)   # ...and over every sample
```

Only `resume` needs C: `rgame_song_play` seeks to zero on every play, on
purpose, so resuming is a second entry point (`ma_sound_start` with no seek)
rather than a flag on the first. Everything else multiplies volumes that are
already there.

Each of these lands in three places in one commit: `Core::Audio`, the
`an audio server` contract, and `FakeAudio`.

### The engine holds the clock

```ruby
out = node.system!(Engine::AudioOut)
out.play_music(:theme, fade: 0.8)
out.stop_music(fade: 0.5)
out.crossfade(:battle, over: 1.2)
out.pause_music; out.resume_music
out.volume(:music, 0.7)
```

`AudioOut` keeps an `Engine::Tween` per running fade and steps the volume in
`_update(dt)`. A spec asserts a fade at 0.25 s by passing 0.25, which is the
whole reason the clock is here rather than on the audio thread.

A crossfade is two fades and two songs: `Core::Audio#play_music` leaves the
previous song playing, so the engine fades the old one down, the new one up,
and stops the old one when its fade ends.

If 60 volume steps a second are audible, the fallback is miniaudio's own ramp
between steps — `ma_sound_set_fade_in_milliseconds` with `-1` as the start
volume — which keeps the decision about *when* in the engine and hands the
smoothing to C. `examples/audio_transitions` exists to judge that by ear.

## 8. Scenes, transitions and doors

### The stack names its scenes and defers every switch

```ruby
stack = root.add_component(Scene::SceneStack.new)
stack.define(:title)   { TitleScene.new }
stack.define(:village) { |entrance:, hero:| VillageScene.new(entrance:, hero:) }

stack.replace(:village, entrance: :south_gate, carry: { hero: hero })
stack.push(:pause)
stack.pop
stack.on_changed { |scene| }
```

`push`, `pop` and `replace` record a request and return. `_update` applies it
before updating the current scene, so a switch asked for during `control` lands
at the start of the next tick and never takes apart a tree that is being
walked. Two requests in one tick collapse into one switch, which is what both
hand-written versions do today.

A `Node2D` may still be pushed directly — `stack.push(PauseScene.new)` — so a
scene built with arguments needs no name.

**`carry:` is how a node survives.** The stack removes each carried node from
its parent before the old scene leaves the tree, then hands it to the builder
as an ordinary keyword. Its components detach from the old scene's systems and
attach to the new one's, because that is what `exit_tree` and `enter_tree`
already do to any node that moves — [F4](01-current-state.md#f4).

### A transition is a fade the stack owns

```ruby
stack.transition = Scene::Fade.new(color: BLACK, cover: 0.25, reveal: 0.25)
```

With one set, a switch covers the picture, switches while covered, and reveals.
The stack holds a `ScreenFade` in the overlay band and drives it; with no
transition set, a switch is what it is today.

A door also fades the music, and that is the game's line rather than the
engine's: `on_changed` is where `out.stop_music(fade:)` goes.

### A door is an example

A door is a node with a collider and a `Collectable`-shaped listener, or an
`Interactor` target for one that opens on a press. It names the scene and the
entrance it leads to, and a scene places arriving nodes at the entrance it was
built with. On a map those doors come from an object layer through
`Engine::MapObjects`, which landed with the Tiled plan.

## 9. Cutscenes

```ruby
ARRIVAL = Engine::Cutscene::Script.build do
  run  { |c| c.viewports.solo!(c.camera) }
  run  { |c| c.world.paused = true }
  hold { |c| c.smith.walk_to(120, 80) }      # ends on its on_finished
  wait 0.4
  talk { |c| Engine::Dialogue.new(SMITH, context: c) }   # ends on its on_ended
  press                                      # ends on ui_confirm
  run  { |c| c.viewports.split!; c.world.paused = false }
end

scene = Engine::Cutscene.new(ARRIVAL, context: self)
scene.on_ended { @cutscene = nil }
```

Five kinds of step, and every one of them ends on something the engine already
says:

| Step | Ends when |
|---|---|
| `run` | at once, the tick it ran |
| `wait n` | `n` seconds have passed, on an `Engine::Tween` |
| `hold` | what the block returns emits `on_finished` |
| `talk` | the dialogue it returns emits `on_ended` |
| `press` | the player presses `ui_confirm` |

`Engine::Cutscene` takes `update(dt)` and `control(actions)` and emits
`on_ended`, mirroring `Engine::Dialogue`. `Components::Cutscene` rides a node's
update for a game that wants no wiring, mirroring `Components::Tween`.

**Skipping finishes the rest at once.** A held button calls `skip`, which runs
every remaining step's `skip` in order: `run` runs its block, `wait` ends,
`hold` and `talk` finish what they hold. The world therefore ends where the
cutscene would have left it — gates open, camera back, world unpaused — rather
than wherever it had got to.

The skip is a `hold:` action, which is item 1 used by item 9, and one of the
compositions the adventure project exists to run.

## 10. `test_projects/adventure`

One small top-down game, built on the CC0 art in `examples/assets/`, grown by
every step. It is where two features meet, and its drive script is the
acceptance test for that meeting:

| It holds | From step |
|---|---|
| a hero walking a `town.tmx` room, in split-screen with two seats | 0 |
| a chest opened by a tap and searched by a hold | 1, 3 |
| collider shapes on F3 | 2 |
| a crate to push, and one to pull | 4 |
| a bag per hero, holding what they collected and what they wear, and a lever | 7 |
| sparkles where a pickup was, and a storm | 8, 9 |
| music that fades as a door closes behind it | 10 |
| a second room through a door, with an entrance | 11, 12 |
| an arrival cutscene, skippable with a held button | 13 |

`examples/` still makes one point per file. This is the file where a pickup
reaching an inventory, and a door fading picture and sound together, are things
a run can report.
