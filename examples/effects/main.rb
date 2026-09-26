# frozen_string_literal: true

# Effects — a fade, a flash, sparkles and a lightning bolt, in a dark room.
#
# Run it:
#
#   ruby examples/effects/main.rb
#
# **Enter** covers the room in black and reveals it again. **L** strikes a bolt
# of lightning, and the room flashes white with it. **Space** bursts sparkles in
# the middle of the room. The torch on the left streams embers the whole time.
# It exercises:
#   - Engine::ScreenFade — a cover, a reveal, and a flash in a translucent white;
#   - Components::Particles — a stream of embers and a burst of sparkles;
#   - Util::ColorRamp — each particle's colour for its age, built once;
#   - Node2D#opacity — the bolt fading out as a whole;
#   - Renderer#blended — light that adds to what is behind it.
#
# ## Nothing here builds a colour after it starts
#
# Every effect changes how it looks every tick, and none of them builds a
# `Color` to do it. A fade and the bolt keep their colours and change their
# `opacity`, which `Node2D#draw` applies to everything they draw. A particle
# reads its colour off a `ColorRamp` built when the file loads. The particles
# live in a pool built when their emitter is. So the example allocates nothing
# once it runs, whichever key is pressed.
#
# ## Light adds
#
# The embers, the sparkles and the bolt draw inside `renderer.blended(:add)`,
# so where two overlap they get brighter, and over the dark floor they glow.
# The fade and the flash draw in the ordinary `:alpha` mode, because a cover
# should hide what is behind it.
#
# ## What it does not solve
#
# The bolt is jagged by taste, not by physics: a random offset at each of a few
# points, drawn again every few ticks. It does not branch, and it lights
# nothing around it. A room that is lit by it needs a light map, and the engine
# has none.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`, and every name the example defines stays off
# the top level. docs/api/README.md says why, under "A game's own module".
module EffectsExample
  Engine = RGame::Engine
  Util = RGame::Util

  WIDTH  = 640
  HEIGHT = 480
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml
  DEFAULT_SEED = 0xB017

  Color = Util::Color
  Controls = Util::Controls

  # A torch that streams embers upwards. The embers rise because their gravity
  # points up, and fade because their ramp ends at alpha 0.
  class Torch < Engine::Node2D
    STICK = Color.new(96, 64, 40)
    EMBER = Util::ColorRamp.new(Color.new(255, 230, 140), Color.new(200, 40, 0, 0))

    def initialize(**)
      super
      embers = add_component(Engine::Components::Particles.new(
                               limit: 64, lifetime: 0.6..1.1, speed: 20.0..45.0, spread: 0.35,
                               gravity: -30.0, size: 3, ramp: EMBER, blend: :add
                             ))
      embers.rate = 30
    end

    def _draw(renderer, _view) = renderer.rect(-3, 0, 6, 40, color: STICK)
  end

  # A jagged line from the top of the window to the floor. It jags again every
  # three ticks while it shows, then holds still and fades out through its own
  # opacity.
  class Bolt < Engine::Node2D
    SEGMENTS = 9
    JAG = 18.0
    REJAG = 3 # ticks
    SHOW = 0.25 # seconds at full strength
    FADE = 0.3 # seconds to fade out after that
    GLOW = Color.new(110, 130, 255, 170)
    CORE = Color.new(230, 235, 255)

    def initialize(length:, **)
      super(**)
      @length = length
      @points = Array.new((SEGMENTS + 1) * 2, 0.0)
      @age = SHOW + FADE
      @ticks = 0
      self.opacity = 0
    end

    def _enter_tree
      @rng = system!(Engine::Components::RandomSource)
    end

    def strike
      @age = 0.0
      @ticks = 0
      jag
      self.opacity = 1
    end

    def _update(dt)
      return if @age >= SHOW + FADE

      @age += dt
      @ticks += 1
      jag if @age < SHOW && (@ticks % REJAG).zero?
      self.opacity = @age < SHOW ? 1 : [1.0 - ((@age - SHOW) / FADE), 0.0].max
    end

    def _draw(renderer, _view)
      renderer.blended(:add) do
        i = 0
        while i < SEGMENTS * 2
          segment(renderer, i, 7.0, GLOW)
          segment(renderer, i, 2.0, CORE)
          i += 2
        end
      end
    end

    private

    def segment(renderer, i, thickness, color)
      renderer.line(@points[i], @points[i + 1], @points[i + 2], @points[i + 3], thickness:, color:)
    end

    def jag
      i = 0
      while i <= SEGMENTS
        @points[i * 2] = i.zero? || i == SEGMENTS ? 0.0 : (@rng.rand - 0.5) * 2.0 * JAG
        @points[(i * 2) + 1] = @length * i / SEGMENTS
        i += 1
      end
    end
  end

  # The room, and the keys. The two fades and the bolt's flash sit in the
  # :overlay band, over the room and its text.
  class Room < Engine::Node2D
    BACKDROP = Color.new(14, 16, 24)
    FLOOR = Color.new(34, 36, 48)
    PILLAR = Color.new(52, 56, 74)
    FLOOR_Y = 360
    GLARE = Color.new(235, 240, 255, 150)
    SPARK = Util::ColorRamp.new(Color.new(255, 255, 255), Color.new(80, 200, 255, 0))

    def initialize
      super
      @help = Engine::Text.new('help.keys')
      add_node(Torch.new(x: 90, y: FLOOR_Y - 40))
      @bolt = add_node(Bolt.new(length: FLOOR_Y, x: 440))
      sparkle_node = add_node(Engine::Node2D.new(x: WIDTH / 2, y: FLOOR_Y - 80))
      @sparkles = sparkle_node.add_component(Engine::Components::Particles.new(
                                               limit: 48, lifetime: 0.4..0.8, speed: 40.0..120.0,
                                               spread: Math::PI, gravity: 120.0, size: 3, ramp: SPARK,
                                               blend: :add
                                             ))
      @glare = add_node(Engine::ScreenFade.new(color: GLARE))
      @curtain = add_node(Engine::ScreenFade.new(color: Color::BLACK))
      @curtain.on_finished { @curtain.reveal(0.6) if @curtain.covered? }
    end

    def _control(actions)
      @curtain.cover(0.6) if actions.pressed?(:fade) && !@curtain.running?
      @sparkles.burst(16) if actions.pressed?(:fire)
      strike if actions.pressed?(:strike)
    end

    def _draw(renderer, view)
      renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
      renderer.rect(0, FLOOR_Y, view.width, view.height - FLOOR_Y, color: FLOOR)
      renderer.rect(200, 140, 36, FLOOR_Y - 140, color: PILLAR)
      renderer.rect(520, 180, 36, FLOOR_Y - 180, color: PILLAR)
      renderer.text(@help, 12, 12)
    end

    private

    def strike
      @bolt.strike
      @glare.flash(0.3)
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Room.new,
      caption: 'Effects',
      width: WIDTH,
      height: HEIGHT,
      locales: LOCALES,
      seed: DEFAULT_SEED,
      # Space is `fire` in the default map, and nothing else here reads it. Enter
      # is also `ui_confirm` and L is free; there is no menu to confirm.
      input_map: Engine::InputMap.default.merge(
        fade: { buttons: [Controls::KEY_RETURN, Controls::PAD_B] },
        strike: { buttons: [Controls::KEY_L, Controls::PAD_Y] }
      )
    )

    game.start
  end
end

EffectsExample.start
