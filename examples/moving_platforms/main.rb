# frozen_string_literal: true

# Moving platforms — a raft shuttling across a chasm, boarded with a timed hop.
#
# Run it:
#
#   ruby examples/moving_platforms/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero; Space or the pad's A
# button hops. It exercises:
#   - Components::Platform — the raft's box is floor over the chasm, and it
#     carries whoever stands on it;
#   - Components::PathFollow with `loop: true` — the raft going back and forth
#     along its route for good;
#   - TileMapLayer.mount — the raft built from the map, over the route a
#     designer draws, sized by its `deck_width` and `deck_height`;
#   - Components::Footing — boarding the raft, and the fall off it;
#   - Components::Respawn, Components::Hop and Components::CameraFollow — the way
#     back, the jump, and a camera that rides along;
#   - renderer.sprite over a sheet with no animations — the raft's planks, one
#     Tiny Town tile at a time.
#
# ## Floor that moves
#
# The raft never touches either bank. Each end of its route stops 12 px short,
# and a hop carries the hero 40 px, so boarding takes a hop timed for when the
# raft is close. A hop that lands on the raft stands the hero on it. One that
# lands in the chasm falls, and the hero comes back on the spot they started
# from. On board, the raft carries the hero whether they stand, walk or hop,
# and the camera goes with them. Walk off the raft's edge and the hero falls.
#
# Nothing here moves the hero with the raft. The raft's `PathFollow` hands each
# step to its `Platform`, the `Platform` carries every node standing on it, and
# the hero's `Footing` says which platform that is.
#
# ## What this does not solve
#
# **The raft never waits at a bank.** A raft that paused at a dock would be
# easier to board; this one turns round at once. **A hop off the raft keeps
# only the hero's own walk**, not the raft's speed. **The chasm's edges are
# drawn on its north side only**, as in `examples/pits`.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module MovingPlatformsExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  MAP   = 'platforms.tmx'
  TILES = 'tiles.json' # tileset.png cut into 16x16 frames
  SPEED = 80.0 # px/s

  # The raft's speed along its route, in px/s: 168 px there and 168 back.
  RAFT_SPEED = 40.0

  # The hop from `examples/pits`: 40 px at walking speed.
  HOP_PEAK = 18.0
  HOP_DURATION = 0.5

  FEET_WIDTH  = 12
  FEET_HEIGHT = 6

  # The feet sit at the bottom of the sprite, so look at the hero's middle.
  CAMERA_OFFSET_Y = -11

  Controls = Util::Controls

  # A walker that hops, falls and comes back, and rides what it stands on.
  class Hero < Engine::Node2D
    def initialize(camera:, **)
      super(**)
      add_component(Components::AnimatedSprite.new(sheet: 'hero.json'))
      add_component(Components::FeetCollider.new(width: FEET_WIDTH, height: FEET_HEIGHT))
      add_component(Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
      add_component(Components::PlayerController.new)
      add_component(Components::Hop.new(peak: HOP_PEAK, duration: HOP_DURATION))
      add_component(Components::Footing.new)
      add_component(Components::Respawn.new(flash: 1.0))
      add_component(Components::CameraFollow.new(camera: camera, offset_y: CAMERA_OFFSET_Y))
    end
  end

  # A raft of Tiny Town planks, centred on its node, that walks its route for good.
  # Its box is the floor, and its `PathFollow` is what carries its riders. The
  # map builds it from a polyline, the route its centre shuttles along, and the
  # node starts on the route's first point.
  class Raft < Engine::Node2D
    TILE = 16
    PLANK_ROW = 6
    LEFT = 0
    MIDDLE = 1
    RIGHT = 3

    # @param deck_width [Integer] the raft's width in pixels, a multiple of 16
    # @param deck_height [Integer] its height in pixels, a multiple of 16
    def initialize(route:, deck_width:, deck_height:, **)
      super(**)
      add_component(Components::BoxCollider.new(
                      width: deck_width, height: deck_height, offset_x: -deck_width / 2.0, offset_y: -deck_height / 2.0
                    ))
      add_component(Components::Platform.new)
      add_component(Components::PathFollow.new(speed: RAFT_SPEED, path: route, loop: true))
      @columns = deck_width / TILE
      @rows = deck_height / TILE
      @left = -deck_width / 2.0
      @top = -deck_height / 2.0
    end

    def _draw(renderer, _view)
      @rows.times do |row|
        @columns.times do |column|
          renderer.sprite(TILES, PLANK_ROW, plank(column), @left + (column * TILE), @top + (row * TILE))
        end
      end
    end

    private

    def plank(column)
      return LEFT if column.zero?

      column == @columns - 1 ? RIGHT : MIDDLE
    end
  end

  # The map, which builds the raft in its `platforms` layer, and the hero on its
  # `start` point. That layer draws under the actors', so the hero draws over
  # the raft. The help draws in the `:overlay` band, over the world.
  class Scene < Engine::Node2D
    def initialize
      super(band: :overlay)
      @help_walk = Engine::Text.new('help.walk')
      @help_board = Engine::Text.new('help.board')
    end

    def _enter_tree
      map = root.context.assets.tilemap(MAP).map
      players = root.system(Engine::Players)
      add_component(Components::TileWorld.new(
                      map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                    ))

      actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))[:actors]
      start = map.object_named('start')
      actors.add_node(Hero.new(camera: players.primary.camera, x: start.x, y: start.y))
    end

    def _draw(renderer, _view)
      renderer.text(@help_walk, 12, 12)
      renderer.text(@help_board, 12, 34)
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Moving platforms',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES,
      # :jump is this game's own action. Space is also in the default map as :fire
      # and :ui_confirm, which nothing here reads.
      input_map: Engine::InputMap.default.merge(
        jump: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
      )
    )

    game.start
  end
end

MovingPlatformsExample.start
