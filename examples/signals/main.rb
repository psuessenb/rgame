# frozen_string_literal: true

# Signals — a node announcing that something happened, to nobody in particular.
#
# Run it:
#
#   ruby examples/signals/main.rb
#
# **Enter** stands on the plate. Hold **Space** and hold **E**: both feed one
# component, at different rates. It exercises:
#   - Signal::DSL — `signal :on_pressed` on a node of your own;
#   - Signal.define(:field) — a signal that carries a payload;
#   - Components::ActionTrigger — one component, several actions, one signal;
#   - the connect handle, and the one place in the engine that can use it.
#
# ## The plate does not know what a door is
#
# That sentence is the whole reason signals exist. A plate that opened a door
# would have to be handed a door, which means whatever built the plate would have
# to know about doors, and a plate with nothing to open would be a special case
# to write. Instead the plate says *that it was pressed* and stops:
#
#     on_pressed_signal.emit
#
# The door and the lamp connect to it, and neither appears anywhere in the
# plate. Adding a third thing that reacts is one line, in the third thing.
#
# ## Declaring one is a single line
#
#     class Plate < RGame::Engine::Node2D
#       signal :on_pressed
#     end
#
# `Node2D` extends `Signal::DSL`, so every node and every component has this
# available. That one line generates two methods:
#
#   `on_pressed { ... }`   public — subscribe, and get a handle back
#   `on_pressed_signal`    private — the Signal itself, to emit on
#
# **Emitting is private on purpose.** Only the plate can say the plate was
# pressed. That is the same "give the user a blank hook, keep the machinery
# separate" rule that makes `on_draw` overridable while `draw` is not: the thing
# a stranger is invited to do is the safe one.
#
# ## A payload, for signals that have something to say
#
# `signal :on_pressed` carries nothing, because "it happened" is all there is.
# `Signal.define(:action)` builds one that carries a field, and
# `Components::ActionTrigger` uses exactly that:
#
#     signal :on_triggered, Engine::Signal.define(:action)
#
# The engine allows one component of a class per node, so a node that wanted a
# separate component per action could not have one. Emitting the action name
# instead lets a single trigger serve `fire` and `poke` together, and the
# listener filters. Hold both keys here and watch the two counters move at
# different rates: one component, two cooldowns.
#
# ## The handle, and why almost nothing uses it
#
# `on_pressed { ... }` hands back a handle, and there is no public way to give it
# back — `on_pressed_signal` is private, and `disconnect` lives on the Signal.
# That is deliberate rather than missing. **A node's listeners die with the
# node**, so a subtree that goes away takes its subscriptions with it and there
# is nothing to leak.
#
# The exception is the one signal that outlives everything. `Engine::AudioBus` is
# a *module*, so it is built the other way round — it exposes its Signals
# publicly rather than through the DSL — and `Engine::AudioDirector` disconnects
# from them when it is released:
#
#     @bus.on_play_sound.disconnect(@handles[0])
#
# It has to. A module-level hub holds its listeners for as long as the process
# runs, and the one that was forgotten there held the audio device, which held
# the asset manager, which held the window. Reach for the public-Signal shape
# when a hub outlives its subscribers, and for the DSL everywhere else.
#
# ## What it does not solve
#
# Ordering. Listeners are called in the order they connected, and nothing here
# offers a priority — if two reactions must happen in a particular order, the
# thing that cares should own both rather than connecting twice.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

Controls = RGame::Util::Controls

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# A plate that announces presses. It has no idea anything is listening, and
# nothing below it in this file is named anywhere inside it.
class Plate < RGame::Engine::Node2D
  signal :on_pressed

  PLATE_W = 150
  PLATE_H = 34
  UP   = RGame::Util::Color.new(110, 120, 140)
  DOWN = RGame::Util::Color.new(210, 190, 110)

  def initialize(**)
    super(width: PLATE_W, height: PLATE_H, **)
    @down = false
  end

  def on_control(actions)
    @down = actions.held?(:stand_on_plate)
    # An edge, not the held state: one press is one event, however long the key
    # stays down. The Signal has no opinion on that — deciding when a thing has
    # happened is the emitter's job.
    on_pressed_signal.emit if actions.pressed?(:stand_on_plate)
  end

  def on_draw(renderer, _view)
    renderer.rect(0, 0, PLATE_W, PLATE_H, color: @down ? DOWN : UP)
  end
end

# Reacts by opening. It knows about the plate; the plate does not know about it.
class Door < RGame::Engine::Node2D
  FRAME = RGame::Util::Color.new(70, 78, 96)
  LEAF  = RGame::Util::Color.new(180, 140, 96)
  DOOR_W = 64
  DOOR_H = 96
  SPEED = 2.2 # fractions of the doorway per second

  def initialize(plate:, **)
    super(width: DOOR_W, height: DOOR_H, **)
    @plate = plate
    @open = false
    @openness = 0.0
  end

  # Connecting is the whole of the wiring, and it happens here rather than in
  # `initialize` because the plate has to exist first — which in this scene it
  # does, but a listener built outside the tree would not be able to rely on it.
  def on_add = @plate.on_pressed { @open = !@open }

  def on_update(dt)
    target = @open ? 1.0 : 0.0
    step = SPEED * dt
    @openness += (target - @openness).clamp(-step, step)
  end

  def on_draw(renderer, _view)
    renderer.rect(0, 0, DOOR_W, DOOR_H, color: FRAME)
    # The leaf slides up into the frame, so an open door is a short one.
    leaf = DOOR_H * (1.0 - @openness)
    renderer.rect(0, DOOR_H - leaf, DOOR_W, leaf, color: LEAF) if leaf > 1.0
  end
end

# Reacts by lighting, and knows nothing about the door reacting to the same
# thing. Two listeners on one signal, neither aware of the other.
class Lamp < RGame::Engine::Node2D
  OFF = RGame::Util::Color.new(64, 62, 56)
  ON  = RGame::Util::Color.new(255, 226, 130)
  RADIUS = 22
  FADE = 1.6

  def initialize(plate:, **)
    super(width: RADIUS * 2, height: RADIUS * 2, **)
    @plate = plate
    @glow = 0.0
  end

  def on_add = @plate.on_pressed { @glow = 1.0 }

  # The glow is state advanced by dt, not a clock read while drawing — the
  # standing rule, and the reason pausing this node would freeze it mid-fade.
  def on_update(dt)
    @glow -= dt * FADE
    @glow = 0.0 if @glow.negative?
  end

  def on_draw(renderer, _view)
    renderer.circle(0, 0, RADIUS, color: @glow.positive? ? ON : OFF)
    renderer.circle(0, 0, RADIUS * @glow, color: ON) if @glow.positive?
  end
end

# One component, two actions, one signal carrying which. The counters are
# separate so the two cooldowns are visible as different rates rather than
# described as them.
class Repeater < RGame::Engine::Node2D
  FIRE_COOLDOWN = 0.20
  POKE_COOLDOWN = 0.55
  PIP = 12
  GAP = 5
  ROW = 26
  FIRE_COLOR = RGame::Util::Color.new(235, 120, 100)
  POKE_COLOR = RGame::Util::Color.new(120, 200, 255)
  MAX_PIPS = 28

  def initialize(**)
    super
    @counts = { fire: 0, poke: 0 }
  end

  def on_add
    trigger = add_component(
      RGame::Engine::Components::ActionTrigger.new(fire: FIRE_COOLDOWN, poke: POKE_COOLDOWN)
    )
    # The payload is what makes one listener enough. Without it this would need
    # a signal per action, and the component is allowed only one of itself per
    # node to hang them on.
    trigger.on_triggered { |action| @counts[action] += 1 }
  end

  def on_draw(renderer, _view)
    draw_row(renderer, @counts[:fire], 0, FIRE_COLOR)
    draw_row(renderer, @counts[:poke], ROW, POKE_COLOR)
  end

  private

  # Counted in rectangles rather than in text, because a row makes two rates
  # comparable at a glance in a way two numbers do not.
  # hot-path
  def draw_row(renderer, count, y, color)
    [count, MAX_PIPS].min.times do |i|
      renderer.rect(i * (PIP + GAP), y, PIP, PIP, color: color)
    end
  end
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(30, 34, 44)

  def on_add
    plate = add_node(Plate.new(x: 60, y: 150))
    # Both are handed the plate and connect themselves. The plate is handed
    # nothing at all.
    add_node(Door.new(plate: plate, x: 300, y: 110))
    add_node(Lamp.new(plate: plate, x: 480, y: 158))
    add_node(Repeater.new(x: 60, y: 330))
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)

    renderer.text('Enter stands on the plate — the door and the lamp both answer', 12, 12)
    renderer.text('Neither of them is named anywhere inside the plate', 12, 34)
    renderer.text('Hold Space and hold E: one ActionTrigger, two cooldowns', 12, 290)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Signals',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  # `stand_on_plate` rather than reading `ui_confirm` directly, and the reason is
  # the trap that costs an afternoon: **a key already in the default map keeps
  # doing its old job too.** `ui_confirm` is Enter *and* Space, and Space is
  # `fire`, which the ActionTrigger below reads — so a plate on `ui_confirm`
  # would also be pressed by the key that is supposed to only feed the repeater.
  # Two actions may read one key, both fire, and nothing warns.
  input_map: RGame::Engine::InputMap.default.merge(
    stand_on_plate: { buttons: [Controls::KEY_RETURN] },
    poke: { buttons: [Controls::KEY_E] }
  )
)

game.start
