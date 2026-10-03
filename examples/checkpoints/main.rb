# frozen_string_literal: true

# Checkpoints — flags that move where a hero comes back after a fall.
#
# Run it:
#
#   ruby examples/checkpoints/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero; Space or the pad's A
# button hops. It exercises:
#   - Components::Checkpoint — the flag a hero touches, which moves the hero's
#     Respawn point to the flag and then says so in `on_reached`;
#   - Components::Respawn — where a hero comes back after a fall, which only
#     the checkpoints move;
#   - Engine::MapBuilder — the map builds each flag from a point object of
#     class `Flag`, and hands it the point's name;
#   - Components::CollisionWorld — the index in which the hero's feet box
#     touches a flag's box;
#   - Components::Footing, Components::Fall, Components::Hop,
#     Components::Shrink and Components::Blink — the hops and falls
#     `examples/pits` shows.
#
# ## The last flag touched is where the hero comes back
#
# Hop the first trench and walk on to the flag beyond it. The flag raises its
# banner, and the line at the top says where the hero comes back now. Walk into
# the next trench: the hero falls, and comes back at that flag rather than at
# the start. Hop it instead, and the next flag takes over.
#
# The flag's Checkpoint does the work. It listens to the flag's box, and when the
# hero's feet box starts touching it, it sets the hero's Respawn point to the
# flag. Fall and Respawn bring the hero back there, as they bring the hero back
# to the start in `examples/pits`. The flag itself only raises its banner and
# names its place for the status line.
#
# ## A checkpoint names its place
#
# The map builds each Flag and passes the point's name to `initialize`, and the
# flag passes it on as the Checkpoint's `location:`. Here the name changes
# nothing about the respawn. In a `Scene::Room` a checkpoint needs one: a hero
# who falls in another room comes back to this room, at the place the name
# finds. `docs/api/components.md` has that case. Each flag also builds the key
# of its place's name, `places.<name>`, so a flag a designer adds without a line
# in `locales/en.yml` fails a driven run.
#
# A flag the map places over a gap raises as the map loads, since a hero brought
# back there would only fall again.
#
# ## What this does not solve
#
# **The last flag touched wins, not the furthest.** Hop back across a trench to
# an earlier flag, and the hero comes back there again. A course that only moves
# forward compares the flags in `on_reached`. **Nothing is saved.** A Respawn
# point lives as long as its hero; `examples/save_load` keeps state across runs.
# **One hero.** A Checkpoint moves only the point of the node that touched it, so
# two heroes would each come back at the last flag they touched.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module CheckpointsExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  MAP   = 'checkpoints.tmx'
  SPEED = 80.0 # px/s

  # The hop from `examples/jump_topdown`: half a second at walking speed carries the
  # hero 40px, across a one-tile trench from anywhere near its edge.
  HOP_PEAK = 18.0
  HOP_DURATION = 0.5

  FEET_WIDTH  = 12
  FEET_HEIGHT = 6

  Controls = Util::Controls

  # A walker that hops, falls and comes back, as in `examples/pits`. It keeps the
  # name of the place it comes back to, which a Flag hands it.
  class Hero < Engine::Node2D
    attr_reader :place

    def initialize(**)
      super
      add_component(Components::WalkingSprite.new(sheet: 'hero.json'))
      add_component(Components::FeetCollider.new(width: FEET_WIDTH, height: FEET_HEIGHT, layer: :hero))
      add_component(Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
      add_component(Components::PlayerController.new)
      add_component(Components::Hop.new(peak: HOP_PEAK, duration: HOP_DURATION))
      add_component(Components::Footing.new)
      add_component(Components::Fall.new)
      add_component(Components::Shrink.new)
      blink = add_component(Components::Blink.new)
      add_component(Components::Respawn.new).on_respawned { blink.start(1.0) }
      @place = Engine::Text.new('places.start')
    end

    # Called by the Flag the hero touched, after its Checkpoint moved the point.
    def reach(place)
      @place = place
    end
  end

  # A checkpoint: a signpost until a hero reaches it, and a banner after. It
  # stands on its node's origin, which is where the hero comes back.
  class Flag < Engine::Node2D
    TILES = 'tiles.json'
    SIZE = 16
    POST = 6 # the row of tiles.json, in column 11
    BANNER = 7
    COLUMN = 11

    # @placeable
    def initialize(name:, **)
      super(**)
      add_component(Components::BoxCollider.new(width: SIZE, height: SIZE, offset_x: -SIZE / 2,
                                                offset_y: -SIZE, layer: :checkpoint))
      place = Engine::Text.new("places.#{name}")
      add_component(Components::Checkpoint.new(by: :hero, location: name)).on_reached do |other|
        @row = BANNER
        other.node.reach(place)
      end
      @row = POST
    end

    def _draw(renderer, _view) = renderer.sprite(TILES, @row, COLUMN, -SIZE / 2, -SIZE)
  end

  # The map, which builds the flags in its `actors` layer, and the hero on its
  # `start` point among them. It draws the help and the status line itself, in
  # the `:overlay` band, once across the window over everything else.
  class Scene < Engine::Node2D
    CELL_SIZE = 64

    def initialize
      super(band: :overlay)
      @help_walk = Engine::Text.new('help.walk')
      @help_flags = Engine::Text.new('help.flags')
      @back_at = Engine::Text.new('status.back_at', :place)
    end

    def _enter_tree
      map = root.context.assets.tilemap(MAP).map
      players = root.system(Engine::Players)
      add_component(Components::TileWorld.new(
                      map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                    ))
      add_component(Components::CollisionWorld.new(cell_size: CELL_SIZE))

      start = map.object_named('start')
      actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))['actors']
      @hero = actors.add_node(Hero.new(x: start.x, y: start.y))
    end

    def _draw(renderer, _view)
      renderer.text(@help_walk, 12, 12)
      renderer.text(@help_flags, 12, 34)
      renderer.text(@back_at.with(place: @hero.place), 12, 56)
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: Scene.new,
      caption: 'Checkpoints',
      configuration: RGame::Game::Configuration.new(
        width: WIDTH,
        height: HEIGHT,
        media_root: ASSETS,
        locales: LOCALES,
        # :jump is this game's own action. Space is also in the default map as
        # :fire and :ui_confirm, which nothing here reads.
        input_map: Engine::InputMap.default.merge(
          jump: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
        )
      )
    )

    game.start
  end
end

CheckpointsExample.start
