# frozen_string_literal: true

# Push and pull — walk crates around a room, and drag one back out of a corner.
#
# Run it:
#
#   ruby examples/push_pull/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk. Walk into a crate to push it.
# Hold Left Shift — or the pad's Y — beside a crate to take hold of it, and it
# comes with you whichever way you walk. F3 draws the collision boxes. It
# exercises:
#   - `pushes:` on Components::CharacterBody — what a step moves instead of
#     stopping at;
#   - Components::Pushable — a crate that moves only when pushed, and stops at
#     walls and other crates;
#   - Components::Grab — a crate held while a button is, pulled as well as
#     pushed;
#   - Engine::Text — whether the hero has hold of something, from a table.
#
# ## A crate is stopped by what stops it, and so is its pusher
#
# Each crate declares its own `blocked_by:` — the walls, the other crates and
# the hero — and a push is resolved against that list as any step is. A crate
# pushed into a wall moves nothing, and the hero stops flush against it. A crate
# pushed into another crate pushes that one too, because each crate declares
# `pushes: [:crate]`. The row of three along the bottom shows it.
#
# The hero's `blocked_by:` names `:crate` as well as its `pushes:`. A layer in
# `pushes:` must be in both, since a step walks through anything else.
#
# ## Pulling is Grab, and the hero's mover does the moving
#
# `Grab` picks the nearest crate in range, as a turret's Targeting picks what
# to shoot, and hands it to the hero's CharacterBody while the button is held.
# The body moves the crate first and follows it, or goes first and brings it,
# and neither moves when either is stopped. Let go, and the crate stays where
# it is.
#
# ## What this does not solve
#
# The hero is a square with no facing, so nothing turns them to face what they
# hold. A crate's speed is the hero's: there is no weight, no friction, and no
# sliding on after a push ends.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine` and `Util` inside it are short for
# `RGame::Engine` and `RGame::Util`, and every name the example defines stays off
# the top level. docs/api/README.md says why, under "A game's own module".
module PushPullExample
  Engine = RGame::Engine
  Util = RGame::Util

  WIDTH  = 640
  HEIGHT = 480
  LOCALES = File.expand_path('locales', __dir__)

  Color = Util::Color

  CELL_SIZE = 64
  SPEED = 90.0
  HERO_SIZE = 16
  CRATE_SIZE = 24
  WALL = 16
  REACH = 30.0

  BACKDROP = Color.new(34, 36, 44)
  WALLS    = Color.new(90, 94, 110)
  CRATE    = Color.new(176, 128, 72)
  HELD     = Color.new(226, 180, 96)
  HERO     = Color.new(110, 170, 240)
  HUD      = Color.new(220, 224, 236)

  # A wall: a box on the `:wall` layer, drawn as itself. Everything that moves in
  # this room declares `:wall` in `blocked_by:`.
  class Wall < Engine::Node2D
    def initialize(width:, height:, **)
      super(**)
      @width = width
      @height = height
      add_component(Engine::Components::BoxCollider.new(width:, height:, layer: :wall))
    end

    def _draw(renderer, _view) = renderer.rect(0, 0, @width, @height, color: WALLS)
  end

  # A crate: a box, and a Pushable that says what stops it. `held` is set by the
  # room so the crate in hand draws brighter.
  class Crate < Engine::Node2D
    attr_writer :held

    def initialize(**)
      super
      @held = false
      add_component(Engine::Components::BoxCollider.new(width: CRATE_SIZE, height: CRATE_SIZE,
                                                        layer: :crate))
      add_component(Engine::Components::Pushable.new(blocked_by: %i[wall crate hero],
                                                     pushes: [:crate]))
    end

    def _draw(renderer, _view) = renderer.rect(0, 0, CRATE_SIZE, CRATE_SIZE, color: @held ? HELD : CRATE)
  end

  # The hero: a square whose origin is its centre, so Grab's range — measured from
  # the node's origin — reaches as far on every side.
  class Hero < Engine::Node2D
    HALF = HERO_SIZE / 2

    def initialize(**)
      super
      add_component(Engine::Components::BoxCollider.new(width: HERO_SIZE, height: HERO_SIZE,
                                                        offset_x: -HALF, offset_y: -HALF,
                                                        layer: :hero))
      add_component(Engine::Components::CharacterBody.new(speed: SPEED, blocked_by: %i[wall crate],
                                                          pushes: [:crate]))
      add_component(Engine::Components::PlayerController.new)
      @grab = add_component(Engine::Components::Grab.new(layer: :crate, range: REACH))
    end

    # The crate in hand, or nil.
    def holding = @grab.holding

    def _draw(renderer, _view) = renderer.rect(-HALF, -HALF, HERO_SIZE, HERO_SIZE, color: HERO)
  end

  # The room: four walls and a pillar, six crates, the hero, and the line that
  # says what the hero is holding.
  class Room < Engine::Node2D
    WALLS = [
      [0, 64, WIDTH, WALL], [0, HEIGHT - WALL, WIDTH, WALL],
      [0, 64, WALL, HEIGHT - 64], [WIDTH - WALL, 64, WALL, HEIGHT - 64],
      [300, 200, 40, 120]
    ].freeze

    CRATES = [[200, 150], [440, 150], [120, 300], [200, 420], [224, 420], [248, 420]].freeze

    STATUS = {
      free: Engine::Text.new('hud.free'),
      holding: Engine::Text.new('hud.holding')
    }.freeze

    def initialize
      super
      add_component(Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))
      @help_walk = Engine::Text.new('help.walk')
      @help_grab = Engine::Text.new('help.grab')
      @held = nil
    end

    def _enter_tree
      WALLS.each { |x, y, width, height| add_node(Wall.new(x:, y:, width:, height:)) }
      @crates = CRATES.map { |x, y| add_node(Crate.new(x:, y:)) }
      @hero = add_node(Hero.new(x: 120, y: 160))
    end

    def _update(_dt)
      holding = @hero.holding
      return if holding.equal?(@held)

      @held&.held = false
      holding&.held = true
      @held = holding
    end

    def _draw(renderer, view)
      renderer.rect(0, 0, view.width, view.height, color: BACKDROP)
      renderer.text(@help_walk, 12, 10, color: HUD)
      renderer.text(@help_grab, 12, 30, color: HUD)
      renderer.text(STATUS.fetch(@held ? :holding : :free), 440, 30, color: HUD)
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Room.new,
      caption: 'Push and pull',
      width: WIDTH,
      height: HEIGHT,
      locales: LOCALES
    )

    game.start
  end
end

PushPullExample.start
