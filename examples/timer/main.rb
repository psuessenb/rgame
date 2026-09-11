# frozen_string_literal: true

# Timer — things that happen on a clock, with nobody pressing anything.
#
# Run it:
#
#   ruby examples/timer/main.rb
#
# Watch the race; **Space** sets off the one-shot. It exercises:
#   - Components::Timer — a repeating interval that rides the node's tick;
#   - `repeating: false` — the same component as a one-shot that arms itself;
#   - `as:` — two cadences on one node, because a node holds one per slot;
#   - Engine::Timer — the pure accumulator underneath all of that.
#
# ## A spawner is not waiting for a key
#
# Every example before this one moved when something was pressed. A wave clock, a
# tower's rate of fire and an enemy every few seconds are none of them input, and
# they are what this is for.
#
# ## The race is the point, and the loser is the obvious implementation
#
# Both bars count beats at the same interval. The top one is a
# `Components::Timer`; the bottom one is four lines anybody would write:
#
#     @elapsed += dt
#     if @elapsed >= INTERVAL
#       @elapsed = 0.0      # <- this
#       beat
#     end
#
# The top bar wins every lap, and that line is why. A frame almost never lands
# exactly on an interval boundary, so `@elapsed` is a little *past* it when the
# beat fires — and zeroing throws that overshoot away. Every beat starts late by
# whatever was discarded, and the error adds up for as long as the program runs.
#
# `Engine::Timer#consume` subtracts the interval instead of zeroing, so the
# remainder carries into the next beat and the cadence stays true to the clock
# rather than to the frame it happened to be noticed on:
#
#     def consume
#       @elapsed -= @interval
#     end
#
# One character of difference, and the gap it opens is on screen. The interval
# here is deliberately not a whole number of frames — at a fixed sixtieth of a
# second and an interval of 0.07, a beat is 4.2 frames, and rounding that up to 5
# costs the naive bar about one lap in six.
#
# ## The catch-up half of the same idea
#
# `Components::Timer#update` fires `on_timeout` *once per whole interval* that
# elapsed, in a loop, rather than once per call. A step long enough to cover
# three intervals emits three times. Nothing in this example produces one — the
# loop is fixed-timestep — but a game that ever sees a long step wants the
# spawner to owe it three enemies rather than one.
#
# ## One component per slot, which is what `as:` is for
#
# A node holds one component per slot, and a slot defaults to the component's
# class — so a second `Components::Timer` added plainly would be refused. The top
# runner carries two: a fast `:beat` and a slow `:chime` that flips the marker
# beside it. Naming them is the whole of making that legal, and it is also how
# either is found again.
#
# ## The one-shot arms itself, which matters more than it sounds
#
# `repeating: false` fires once and goes inert, and `reset` re-arms it. The
# component calls `reset` from `on_attach`, so a node that leaves the tree and
# comes back gets a fresh countdown rather than inheriting a spent one. That line
# is what makes a pooled projectile with a lifetime work — see `examples/pooling`,
# where the same component retires what the pool hands out.
#
# ## What it does not solve
#
# Pausing a timer on its own. A `Components::Timer` stops when its node stops,
# because `paused` halts the node's whole update — which is usually what is
# wanted, and is not the same as a timer with its own switch.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

# 4.2 frames at a fixed sixtieth of a second, chosen so that rounding it up to a
# whole frame is a mistake with a visible size.
BEAT = 0.07
CHIME = 1.5
FUSE = 1.2 # how long the one-shot banner stays

TRACK_X = 60
TRACK_W = 480
LAP = 70 # beats to the end of the track

# The two runners share this, so the only difference between them is how each
# decides a beat has happened.
module Runner
  BAR_H = 26
  TRACK = RGame::Util::Color.new(44, 50, 64)

  def beats = @beats ||= 0

  def draw_track(renderer, color)
    renderer.rect(0, 0, TRACK_W, BAR_H, color: TRACK)
    renderer.rect(0, 0, TRACK_W * (beats.to_f / LAP), BAR_H, color: color)
  end
end

# Beats on a Components::Timer, which carries the remainder forward.
class TrueRunner < RGame::Engine::Node2D
  include Runner

  BAR = RGame::Util::Color.new(120, 210, 150)
  MARK_ON = RGame::Util::Color.new(255, 226, 130)
  MARK_OFF = RGame::Util::Color.new(70, 78, 96)
  MARK = 18

  def initialize(**)
    super
    @beats = 0
    @chimed = false
  end

  # Two timers, two slots. Without the names the second would be refused, and
  # `get_component(Components::Timer)` would have no single answer to give.
  def on_add
    add_component(RGame::Engine::Components::Timer.new(BEAT), as: :beat)
      .on_timeout { @beats += 1 }
    add_component(RGame::Engine::Components::Timer.new(CHIME), as: :chime)
      .on_timeout { @chimed = !@chimed }
  end

  # Resetting the lap is this node's business rather than the timer's: the timer
  # counts time and the owner decides what a count means.
  def lap? = @beats >= LAP

  def restart = @beats = 0

  def on_draw(renderer, _view)
    draw_track(renderer, BAR)
    renderer.rect(TRACK_W + 14, 4, MARK, MARK, color: @chimed ? MARK_ON : MARK_OFF)
  end
end

# The same cadence, written the way it comes out first. It is slower, and the
# only reason is the line that throws the overshoot away.
class NaiveRunner < RGame::Engine::Node2D
  include Runner

  BAR = RGame::Util::Color.new(235, 120, 100)
  MARK = RGame::Util::Color.new(255, 255, 255)
  MARK_W = 3

  def initialize(**)
    super
    @beats = 0
    @elapsed = 0.0
    @shortfall = 0
  end

  def on_update(dt)
    @elapsed += dt
    return if @elapsed < BEAT

    # Discarding the overshoot is the bug. `@elapsed -= BEAT` here and the two
    # bars finish level.
    @elapsed = 0.0
    @beats += 1
  end

  # Remembered before it is cleared, because how far this bar had got when the
  # other one finished *is* the size of the error. The marker lands in the same
  # place every lap, which is the other half of the point: the gap is a steady
  # rate, not a one-off stumble.
  def restart
    @shortfall = @beats
    @beats = 0
    @elapsed = 0.0
  end

  def on_draw(renderer, _view)
    draw_track(renderer, BAR)
    return if @shortfall.zero?

    renderer.rect(TRACK_W * (@shortfall.to_f / LAP), 0, MARK_W, BAR_H, color: MARK)
  end
end

# A banner that takes itself away. Nothing removes it from outside.
class Fuse < RGame::Engine::Node2D
  BANNER = RGame::Util::Color.new(120, 200, 255)
  INK = RGame::Util::Color.new(20, 26, 34)
  BANNER_W = 260
  BANNER_H = 30

  def on_add
    add_component(RGame::Engine::Components::Timer.new(FUSE, repeating: false))
      .on_timeout { queue_free }
  end

  def on_draw(renderer, _view)
    renderer.rect(0, 0, BANNER_W, BANNER_H, color: BANNER)
    renderer.text('one-shot — this removes itself', 10, 8, z: 1, color: INK)
  end
end

class Scene < RGame::Engine::Node2D
  BACKDROP = RGame::Util::Color.new(28, 32, 42)
  FUSE_X = 60
  FUSE_Y = 370

  def on_add
    @truth = add_node(TrueRunner.new(x: TRACK_X, y: 150))
    @naive = add_node(NaiveRunner.new(x: TRACK_X, y: 210))
  end

  # The lap is settled here, where both runners are visible, so that neither of
  # them needs to know the other exists.
  def on_update(_dt)
    return unless @truth.lap?

    @truth.restart
    @naive.restart
  end

  def on_control(actions)
    return unless actions.pressed?(:fire)
    # One at a time: a second banner would sit exactly on top of the first.
    return if @fuse&.in_tree?

    @fuse = add_node(Fuse.new(x: FUSE_X, y: FUSE_Y))
  end

  def on_draw(renderer, view)
    renderer.rect(0, 0, view.width, view.height, color: BACKDROP)

    renderer.text('Both bars beat every 0.07s. One of them is right', 12, 12)
    renderer.text('Components::Timer — the remainder carries forward', TRACK_X, 126)
    renderer.text('@elapsed = 0.0 — the overshoot is thrown away', TRACK_X, 244)
    renderer.text('the white mark is where this bar was when the other finished',
                  TRACK_X, 264)
    renderer.text('The square blinks on a second, slower timer on the same node',
                  TRACK_X, 296)
    renderer.text('Space sets off a one-shot', TRACK_X, 336)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Timer',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
