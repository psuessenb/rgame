# frozen_string_literal: true

# Quick wheel — a radial menu held open by a button, and chosen by letting go.
#
# Run it:
#
#   ruby examples/quick_wheel/main.rb
#
# Hold Tab (or the left shoulder button), point with the arrow keys (or the left
# stick), and let go of Tab to choose. Let go with nothing pointed at to choose
# nothing. It exercises:
#   - UI::RadialMenu with `trigger:` — the wheel is closed until the trigger goes
#     down and chooses what is focused when it comes up;
#   - UI::Pointing's grace window — a stick that springs back a moment before
#     the trigger still chooses what it pointed at;
#   - UI::Menu#on_opened / #on_closed — what the game does while the wheel is
#     open, here slowing the world to a quarter of its speed;
#   - InputMap.default.merge — declaring the trigger on Tab and the left shoulder.
#
# ## Letting go is the choice
#
# There is no confirm button here, and pressing one does nothing: the player's
# thumb is on the stick and a finger is on the shoulder, and releasing the
# shoulder is the only thing left to do. `examples/radial_menu` is the other
# style of the same wheel — always open, point, then press A — and is the same
# classes without `trigger:`.
#
# ## The stick springs back first
#
# Letting go of a stick and a shoulder button at once is not at once: the stick
# is back in the middle a frame or two before the button comes up. With nothing
# to account for that, the release would find the stick at rest and choose
# nothing almost every time. So focus survives the dead zone for
# `Pointing::GRACE`, 0.15 s, which a wheel with a trigger gets without asking.
# On a keyboard the same thing happens between letting go of an arrow key and
# letting go of Tab. Hold the arrow at rest for longer than that, and the
# release chooses nothing — which is how a player changes their mind.
#
# ## The world is the game's business
#
# The wheel says when it opens and closes. Whether the world pauses, slows or
# carries on is a decision about the game, not about menus, so it is made here:
# the dots drift at a quarter speed while the wheel is open.
#
# ## What this example does not solve
#
# Captions on the wheel, and a wheel centred on the view — see
# `examples/radial_menu`. A stick that overshoots the middle as it springs back
# can briefly point at the opposite icon, which the grace window does not
# cover.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`, and every name the example defines stays off
# the top level. docs/api/README.md says why, under "A game's own module".
module QuickWheelExample
  Engine = RGame::Engine
  Util = RGame::Util

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml
  Controls = Util::Controls

  # The part of the scene the wheel slows down. A time scale applied to `dt` on
  # the way in is the whole of slow motion, because time only enters through
  # `update`.
  class World < Engine::Node2D
    SLOWED = 0.25

    attr_accessor :time_scale

    def initialize(**)
      super
      @time_scale = 1.0
    end

    def update(dt) = super(dt * @time_scale)
  end

  # A square that drifts and bounces off the window's edges.
  class Dot < Engine::Node2D
    SIZE = 12
    COLOR = Util::Color.new(120, 180, 150)

    def initialize(speed_x:, speed_y:, **)
      super(**)
      @speed_x = speed_x
      @speed_y = speed_y
    end

    def _update(dt)
      self.x += @speed_x * dt
      self.y += @speed_y * dt
      @speed_x = -@speed_x unless x.between?(0, WIDTH - SIZE)
      @speed_y = -@speed_y unless y.between?(0, HEIGHT - SIZE)
    end

    def _draw(renderer, _view) = renderer.rect(0, 0, SIZE, SIZE, color: COLOR)
  end

  # The wheel, held open by `:quick_menu`, and what it last chose.
  class QuickWheel < Engine::Node2D
    UI = Engine::UI

    RADIUS = 150
    SLOT = 64

    # Clockwise from the top. Each image names an entry of icons.json's `images`.
    ICONS = [
      %i[home home],
      %i[settings gear],
      %i[save save],
      %i[favourite star],
      %i[trophies trophy],
      %i[sound audio_on],
      %i[music music_on],
      %i[locked locked]
    ].freeze

    DISC = UI::ShapeStyle.new(shape: :disc)

    attr_reader :chosen

    def initialize(world:, **)
      super(**)
      @chosen = nil
      @menu = add_node(UI::RadialMenu.new(radius: RADIUS, button_width: SLOT, trigger: :quick_menu))
      ICONS.each { |key, image| add_icon(key, image) }
      @menu.on_opened { world.time_scale = World::SLOWED }
      @menu.on_closed { world.time_scale = 1.0 }
    end

    private

    def add_icon(key, image)
      button = @menu.add(UI::IconButton.new(image: image, style: DISC, enabled: image != :locked))
      button.on_activated { @chosen = key }
    end
  end

  # The captions. Added last, so its final line is the last text of every frame —
  # which is what the drive script reads.
  class Caption < Engine::Node2D
    NAMES = QuickWheel::ICONS.to_h { |key, _| [key, Engine::Text.new(key, scope: 'items')] }.freeze

    def initialize(wheel:, **)
      super(**)
      @wheel = wheel
      @help = Engine::Text.new('help.wheel')
      @nothing = Engine::Text.new('status.nothing')
      @chosen = Engine::Text.new('status.chosen', :item)
    end

    def _draw(renderer, _view)
      renderer.text(@help, 12, 12)
      chosen = @wheel.chosen
      renderer.text(chosen ? @chosen.with(item: NAMES.fetch(chosen).to_s) : @nothing, 12, HEIGHT - 30)
    end
  end

  class Scene < Engine::Node2D
    DOTS = [[60, 80, 90, 40], [400, 120, -70, 60], [200, 360, 50, -80], [520, 300, -100, -30]].freeze

    def _enter_tree
      world = add_node(World.new)
      DOTS.each { |x, y, speed_x, speed_y| world.add_node(Dot.new(x: x, y: y, speed_x: speed_x, speed_y: speed_y)) }
      wheel = add_node(QuickWheel.new(world: world, x: WIDTH / 2, y: (HEIGHT / 2) + 6))
      add_node(Caption.new(wheel: wheel))
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Quick wheel',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES,
      input_map: Engine::InputMap.default.merge(
        quick_menu: { buttons: [Controls::KEY_TAB, Controls::PAD_LEFT_SHOULDER] }
      )
    )

    # The icons are registered by name, once: the atlas cuts each from the strip.
    game.renderer.register_ui_atlas(game.assets.ui_atlas('icons.json'))

    game.start
  end
end

QuickWheelExample.start
