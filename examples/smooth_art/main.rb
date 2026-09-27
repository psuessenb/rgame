# frozen_string_literal: true

# Smooth art — anti-aliased art, sampled with `texture_filter: :linear`.
#
# Run it, then run it unfiltered to compare:
#
#   ruby examples/smooth_art/main.rb
#   RGAME_FILTER=nearest ruby examples/smooth_art/main.rb
#
# **F** (or Y on a pad) switches fullscreen. It exercises:
#   - Game::Configuration's `texture_filter` — how every image the game loads is
#     sampled;
#   - Game::Configuration's `scale_mode` — `:letterbox`, which scales the whole
#     1280x720 scene to the window;
#   - Components::Sprite — each figure, standing on its node's origin;
#   - Node2D#angle=, #x= and #opacity= — the tilt, the glide and the fade.
#
# ## What to watch
#
# **Anti-aliased art needs `:linear` wherever it is drawn at other than its own
# pixels.** The two figures were drawn with soft edges, and this scene resamples
# them four ways:
#
#   as drawn           only the window scales it: 1.5 times fullscreen on a
#                      1920x1080 screen, and not at all in a 1280x720 window
#   2.5 times          a scale in the scene, at any window size
#   turned             a rotation
#   moving and fading  a position between two pixels, and an opacity
#
# Under `:nearest` each screen pixel takes the one texel nearest it. At 1.5
# times, one outline row covers two screen pixels and the next covers one, so a
# line's thickness changes along its length. A turned edge becomes a staircase,
# and a slow glide jumps a whole pixel every few frames. Under `:linear` a
# screen pixel blends the four texels around it, so outlines keep their weight
# and the glide moves smoothly.
#
# **No exporter step is needed for the edges.** The pixels around each figure
# are transparent black, and blending an edge with them would draw a dark
# fringe. The engine premultiplies every image as it loads, so a transparent
# texel adds nothing, whatever colour it stored.
#
# ## What it does not solve
#
# **The filter is fixed for the game's life.** Every image the game loads takes
# it, which is why comparing the two means running the file twice. Pixel art
# wants `:nearest`, which is the default.
#
# **Art is drawn at its own size or larger.** Shrinking it below half its size
# needs mipmaps, which rgame does not build. A game that targets a larger
# screen draws its art for that screen, and lets `:letterbox` scale it down no
# further than that.
#
# Text looks the same under either filter: glyphs are always sampled linearly.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module SmoothArtExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  Controls = Util::Controls

  WIDTH = 1280
  HEIGHT = 720
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  # :linear, or :nearest to compare. A game chooses once, in its configuration.
  TEXTURE_FILTER = ENV.fetch('RGAME_FILTER', 'linear').to_sym

  MAN = 'older-man@1x.png'
  MAN_WIDTH = 64
  MAN_HEIGHT = 150
  WOMAN = 'woman@1x.png'
  WOMAN_WIDTH = 56
  WOMAN_HEIGHT = 132

  # A figure standing on its node's origin. The node's size is the image's,
  # which is what Components::Sprite's anchor measures from.
  class Figure < Engine::Node2D
    def initialize(image, width:, height:, scale: 1.0, **)
      super(width:, height:, **)
      add_component(Components::Sprite.new(id: image, scale:))
    end
  end

  # Rocks about its feet, as far as TILT either way.
  class Tilting < Figure
    TILT = 0.25 # radians
    PERIOD = 5.0 # seconds, there and back

    def initialize(...)
      super
      @elapsed = 0.0
    end

    def _update(dt)
      @elapsed += dt
      self.angle = TILT * Math.sin(@elapsed * 2 * Math::PI / PERIOD)
    end
  end

  # Glides to and fro about where it was placed, never faster than a third of a
  # pixel a frame, and fades while it goes.
  class Gliding < Figure
    REACH = 60.0 # pixels either way
    GLIDE_PERIOD = 20.0 # seconds, there and back
    FADE = 0.8 # how far the opacity falls, from 1
    FADE_PERIOD = 6.0

    def initialize(...)
      super
      @home = x
      @elapsed = 0.0
    end

    def _update(dt)
      @elapsed += dt
      self.x = @home + (REACH * Math.sin(@elapsed * 2 * Math::PI / GLIDE_PERIOD))
      self.opacity = 1.0 - (FADE * (1.0 - Math.cos(@elapsed * 2 * Math::PI / FADE_PERIOD)) / 2)
    end
  end

  class Scene < Engine::Node2D
    BACKDROP = Util::Color.new(236, 230, 218)
    FLOOR = Util::Color.new(206, 196, 178)
    INK = Util::Color.new(52, 48, 44)

    GROUND = 560 # where every figure stands
    CAPTION_Y = GROUND + 20
    MARGIN = 24

    # Which filter the game samples with. The game reports it, rather than this
    # file's constant, so the line is true however the game was configured.
    STATUS = { linear: Engine::Text.new('status.linear'),
               nearest: Engine::Text.new('status.nearest') }.freeze

    # Each figure, and the caption under it, by the left edge of its column.
    AS_DRAWN = 120
    SCALED = 400
    TURNED = 720
    MOVING = 960

    def initialize
      super
      @help = Engine::Text.new('help.keys')
      @as_drawn = Engine::Text.new('captions.as_drawn')
      @scaled = Engine::Text.new('captions.scaled')
      @turned = Engine::Text.new('captions.turned')
      @moving = Engine::Text.new('captions.moving')
    end

    def _enter_tree
      add_node(Figure.new(MAN, width: MAN_WIDTH, height: MAN_HEIGHT, x: AS_DRAWN + 40, y: GROUND))
      add_node(Figure.new(WOMAN, width: WOMAN_WIDTH, height: WOMAN_HEIGHT, x: AS_DRAWN + 130, y: GROUND))
      add_node(Figure.new(WOMAN, width: WOMAN_WIDTH, height: WOMAN_HEIGHT, scale: 2.5, x: SCALED + 90, y: GROUND))
      add_node(Tilting.new(MAN, width: MAN_WIDTH, height: MAN_HEIGHT, x: TURNED + 60, y: GROUND))
      add_node(Gliding.new(WOMAN, width: WOMAN_WIDTH, height: WOMAN_HEIGHT, x: MOVING + 120, y: GROUND))
    end

    def _control(actions)
      # `context` is the Game, which is an App. A node may not *name*
      # RGame::Core, but it may call methods on an object it is handed.
      return unless actions.pressed?(:fullscreen)

      app = root.context
      app.fullscreen = !app.fullscreen?
    end

    def _draw(renderer, view)
      renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
      renderer.rect(0, GROUND, view.width, view.height - GROUND, color: FLOOR)

      renderer.text(STATUS.fetch(root.context.texture_filter), MARGIN, MARGIN, color: INK)
      renderer.text(@help, MARGIN, MARGIN + 28, color: INK)

      renderer.text(@as_drawn, AS_DRAWN, CAPTION_Y, color: INK)
      renderer.text(@scaled, SCALED, CAPTION_Y, color: INK)
      renderer.text(@turned, TURNED, CAPTION_Y, color: INK)
      renderer.text(@moving, MOVING, CAPTION_Y, color: INK)
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Smooth art',
      configuration: RGame::Game::Configuration.new(
        width: WIDTH,
        height: HEIGHT,
        scale_mode: :letterbox,
        texture_filter: TEXTURE_FILTER,
        media_root: ASSETS,
        locales: LOCALES,
        # :fullscreen is this game's own action; everything else comes from the
        # default map.
        input_map: Engine::InputMap.default.merge(
          fullscreen: { buttons: [Controls::KEY_F, Controls::PAD_Y] }
        )
      )
    )

    game.start
  end
end

SmoothArtExample.start
