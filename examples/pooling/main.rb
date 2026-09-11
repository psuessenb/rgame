# frozen_string_literal: true

# Pooling — spawning a lot of things without building any of them.
#
# Run it:
#
#   ruby examples/pooling/main.rb
#
# **Space** switches between taking motes from a pool and building a fresh one
# every time. Watch the number. It exercises:
#   - Components::Pool — acquire, add as a child, reclaim on free;
#   - Engine::Pool — the free list underneath it;
#   - Components::DespawnOffscreen — retiring a mote that has left the world;
#   - Components::Timer — the spawn cadence, from `examples/timer`;
#   - Engine::CachedLabel — a readout that changes once a second, not per frame.
#
# ## The number on screen is the whole argument
#
# Everything else here is prose. The readout samples
# `GC.stat(:total_allocated_objects)` once a second and shows the difference, and
# switching modes moves it within a second or two of the press. Measured over a
# steady eighty motes a second:
#
#   pooled   about 140 objects a second
#   fresh    about 750
#
# Same spawn rate, same motes on screen, same draw calls. The gap is around seven
# and a half objects per mote — the node, its two components, and the few arrays
# and hashes a node keeps for them — and it is *entirely* what the pool removes.
#
# A steady sixty-frame-per-second loop that allocates is a GC pause waiting to
# happen, and a pause is not a slow frame: it is a visible hitch at a moment
# nobody chose. Bullets and particles are where it starts, because they are the
# things there are suddenly two hundred of.
#
# **The readout only means anything in a plain run.** Under
# `tools/drive_test_project.rb` both numbers land near eighty-five thousand,
# because the harness records every draw call it sees and that recording dwarfs
# everything the game does. Measure the thing you changed, in the configuration
# you care about.
#
# ## A game writes two lines and no bookkeeping
#
#     @pool.spawn { |mote| mote.reset(...) }   # acquire, initialise, add as a child
#     mote.queue_free                          # → back on the free list
#
# There is no acquire/add/reclaim bridge to write, because
# `Components::Pool#update` rides the tick and reclaims everything freed since
# the last one. Nothing in this file asks for a mote back, and
# `Components::DespawnOffscreen` — which knows nothing about pools — retires them
# by calling the same `queue_free` any other node would.
#
# ## A pooled node is an ordinary child
#
# It is in the tree, the traversal updates and draws it, its components run. The
# pool manages membership and nothing else. Pooling is not a parallel world with
# its own rules — which is worth saying, because the one rule it *does* add is
# easy to miss.
#
# ## The one rule: components go in `initialize`, not `on_add`
#
# `on_add` fires on **every** entry into the tree, and a pooled node enters it
# again on each spawn. A component added there is added a second time, and
# `add_component` refuses a slot that is already taken — so a pool that worked
# for one lifetime raises on the next. Mote below adds its components in
# `initialize`, where a node built by a factory outside the tree collects them
# once.
#
# The mirror of that rule is what makes reuse safe: `Components::Timer` re-arms
# itself in `on_attach`, and `Components::DespawnOffscreen` re-resolves its world
# bounds there, so a recycled node inherits neither a spent countdown nor the
# dimensions of the scene it came from.
#
# ## `reset` is the other half of a factory that builds blanks
#
# `Engine::Pool.new { Mote.new }` builds a blank, because it has no idea where the
# next mote will be or where it is going. `spawn` takes a block and runs it
# *before* the node enters the tree, which is where those answers get filled in.
#
# ## What it does not solve
#
# A cap. The pool grows to the high-water mark of how many are live at once and
# never shrinks, which is the intent — the memory is the point of the exercise —
# but a spawner that can outrun its despawn has no brake here.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

SPAWN_EVERY = 0.05 # seconds
PER_BURST   = 4
SPEED_MIN   = 70.0
SPEED_MAX   = 210.0
SAMPLE      = 1.0 # how often the allocation readout is taken
DEFAULT_SEED = 0x9001

# Far enough out that a mote is well off the screen before it is retired, so the
# despawn is never something you can see happening.
DESPAWN_MARGIN = 30.0

# A blank when the factory builds it, a particular mote when `reset` is done with
# it. Both of its components are added here rather than in `on_add`, because a
# pooled node re-enters the tree on every spawn and `on_add` fires every time.
class Mote < RGame::Engine::Node2D
  SIZE = 7

  def initialize
    super(width: SIZE, height: SIZE)
    @velocity = add_component(RGame::Engine::Components::Velocity.new)
    add_component(RGame::Engine::Components::DespawnOffscreen.new(margin: DESPAWN_MARGIN))
    @color = RGame::Util::Color.new(255, 255, 255)
  end

  # Run by the spawner before this node enters the tree, which is the seam a
  # factory that builds blanks needs. Returns self so a fresh mote can be built
  # and placed in one expression.
  def reset(x, y, vx, vy, color)
    self.x = x
    self.y = y
    @velocity.vx = vx
    @velocity.vy = vy
    @color = color
    self
  end

  def on_draw(renderer, _view) = renderer.rect(-SIZE / 2, -SIZE / 2, SIZE, SIZE, color: @color)
end

# Emits motes on a cadence, either from a pool or by building each one, and the
# only difference between the two paths is the line that gets the node.
class Spawner < RGame::Engine::Node2D
  POOLED = RGame::Util::Color.new(120, 210, 150)
  FRESH  = RGame::Util::Color.new(235, 120, 100)

  def initialize(rng:, **)
    super(**)
    @rng = rng
    @pooled = true
  end

  def pooled? = @pooled
  def toggle = @pooled = !@pooled
  # Children, not `@pool.size`: both paths attach the mote as a child of this
  # node, and only one of them involves a pool. Counting the pool would make the
  # bar vanish in fresh mode and hide the thing being compared.
  def live = children.size

  def on_add
    @pool = add_component(RGame::Engine::Components::Pool.new { Mote.new })
    add_component(RGame::Engine::Components::Timer.new(SPAWN_EVERY))
      .on_timeout { PER_BURST.times { emit } }
  end

  private

  def emit
    if @pooled
      # Acquire, initialise, attach — one call, and the reclaim is already
      # arranged for.
      @pool.spawn { |mote| place(mote) }
    else
      # The same three steps written out, and a new object every single time.
      # Nothing else about the mote or the frame differs.
      add_node(place(Mote.new))
    end
  end

  def place(mote)
    angle = @rng.rand * Math::PI * 2
    speed = SPEED_MIN + (@rng.rand * (SPEED_MAX - SPEED_MIN))
    mote.reset(0, 0, Math.cos(angle) * speed, Math.sin(angle) * speed,
               @pooled ? POOLED : FRESH)
  end
end

# Samples the allocation counter once a second and shows the difference.
#
# A per-frame readout is the one thing CachedLabel cannot help with — a value
# that changes every frame has to be rebuilt every frame. Sampling on a slow
# timer makes it a value that changes once a second, which is exactly what the
# cache is for, and it is also the only way the number means anything: a single
# frame's allocations are noise.
class Meter < RGame::Engine::Node2D
  INK = RGame::Util::Color.new(255, 255, 255)

  def initialize(**)
    super
    @label = RGame::Engine::CachedLabel.new { |count| "objects allocated per second: #{count}" }
    @count = 0
    @last = 0
  end

  def on_add
    @last = GC.stat(:total_allocated_objects)
    add_component(RGame::Engine::Components::Timer.new(SAMPLE)).on_timeout { sample }
  end

  def on_draw(renderer, _view) = renderer.text(@label[@count], 0, 0, color: INK)

  private

  def sample
    now = GC.stat(:total_allocated_objects)
    @count = now - @last
    @last = now
  end
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(26, 30, 38)
  BAR = RGame::Util::Color.new(90, 100, 124)
  BAR_X = 12
  BAR_Y = 86
  BAR_H = 14
  BAR_SCALE = 2.4 # pixels per live mote

  MODE = { true => 'pooled — Space builds a fresh mote instead',
           false => 'fresh objects — Space goes back to the pool' }.freeze

  def initialize
    super
    @rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
    # Mounted outside the tree, so every DespawnOffscreen that attaches later
    # finds it — the same ordering the wrap in `examples/velocity` depends on.
    add_component(RGame::Engine::Components::World.new(width: WIDTH, height: HEIGHT))
  end

  def on_add
    @spawner = add_node(Spawner.new(rng: @rng, x: WIDTH / 2, y: HEIGHT / 2))
    @meter = add_node(Meter.new(x: 12, y: 34))
  end

  def on_control(actions)
    @spawner.toggle if actions.pressed?(:fire)
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
    renderer.text(MODE.fetch(@spawner.pooled?), 12, 12)
    # The live count as a bar rather than a number: it changes most frames, and
    # a label rebuilt every frame is the allocation this example is about.
    renderer.rect(BAR_X, BAR_Y, @spawner.live * BAR_SCALE, BAR_H, color: BAR)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Pooling',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
