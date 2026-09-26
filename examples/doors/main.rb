# frozen_string_literal: true

# Doors — a gate between two maps, and a pair of warp pads.
#
# Run it:
#
#   ruby examples/doors/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero. The brown square in
# the town is the gate to the garden, and the garden's brown square leads back.
# The two violet pads in the garden carry the hero from one to the other. It
# exercises:
#   - Scene::Rooms — the rooms of one world, each built as a player walks in and
#     freed once nobody is left in it;
#   - Scene::Room and its `_arrive` hook — placing whatever a move brings;
#   - Scene::Fade — the cover and reveal every move runs;
#   - TileMap#object_named — the entrance a door names, read off the map;
#   - TileMapLayer.mount — a Door or a Warp built from each object of that
#     class on the map, set up by the object's properties;
#   - Components::Collectable with `free: false` — a door touched and kept.
#
# ## The map says where the doors are
#
# Nothing in this file says where a door is. `town_with_gate.tmx` and
# `garden.tmx` each carry an object layer, `doors`, and every object in it has a
# class. An `entrance` is a point where a hero arrives. Its class starts with a
# lower-case letter, so it stays data. A `Door` is a box, and mounting the map
# builds a `Door` node over it. The object's properties `to`, `entrance` and
# `party` arrive as the keywords the `@param` tags above `Door#initialize` name.
# A `Warp` is a door into its own room, so it names only the entrance. Moving a
# door is a change in Tiled.
#
# ## One room class for both maps
#
# `Grounds` is every room here: a map, the world it makes solid, and its doors.
# `define` takes a block that builds a room each time one is needed, so the town
# and the garden are the same class built over two maps. A room is built anew
# each time it is entered, and nothing it held survives the trip. A game that
# must remember a taken coin keeps it in the `FactsDatabase`, where a loaded
# save puts it too.
#
# ## A warp and a door are the same call
#
# A door calls `rooms.move(hero, to: :garden, entrance: 'gate_in')`. A pad calls
# the same with the room the hero already stands in, and the rooms tell the two
# apart: moving into the room a node stands in only calls `_arrive` again, so
# nothing is built or freed, and the hero's components keep their systems.
#
# ## What this does not solve
#
# One player walks alone. Two players may stand in two rooms at once, each room
# drawn into its own player's region, and nothing here shows it. The garden's
# horn is a door marked `party`, which moves every hero the world holds; with
# one player, that is the one hero. A door draws a flat square rather than a
# picture.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

# The example's own module. `Engine`, `Util`, `UI` and `Components` inside it
# stand for rgame's namespaces of the same names, and every name the example
# defines stays off the top level. docs/api/README.md says why, under "A game's
# own module".
module DoorsExample
  Engine = RGame::Engine
  Util = RGame::Util
  UI = Engine::UI
  Components = Engine::Components

  WIDTH  = 640
  HEIGHT = 480
  ASSETS = File.expand_path('../assets', __dir__)
  LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

  SPEED = 80.0 # px/s

  # The feet: twelve wide and six tall, at the bottom of the 16x22 sprite.
  FEET_WIDTH  = 12
  FEET_HEIGHT = 6

  # A sprite, a feet box on the `:hero` layer, a body the map stops, and a camera.
  class Hero < Engine::Node2D
    def initialize(camera:, **)
      super(**)
      add_component(Components::AnimatedSprite.new(sheet: 'hero.json'))
      add_component(Components::FeetCollider.new(width: FEET_WIDTH, height: FEET_HEIGHT, layer: :hero))
      add_component(Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
      add_component(Components::PlayerController.new)
      add_component(Components::CameraFollow.new(camera: camera))
    end
  end

  # A door built from the map. A hero's feet box touching its box asks the
  # world's rooms for a move, and the door stays where it is. The box stands on
  # the node's origin, the bottom centre of the object Tiled shows.
  class Door < Engine::Node2D
    COLOR = Util::Color.new(150, 104, 56)

    # @param to [Symbol] the room the door leads to
    # @param entrance [String] the entrance in that room where the hero arrives
    # @param party [Boolean] whether it moves every hero the world holds, rather than the one who touched it
    def initialize(to:, entrance:, party: false, **)
      super(**)
      @to = to
      @entrance = entrance
      @party = party
      add_component(Components::BoxCollider.new(width:, height:, offset_x: -width / 2.0, offset_y: -height,
                                                layer: :door))
      add_component(Components::Collectable.new(by: :hero, free: false)).on_collected { move(it.node) }
    end

    def _enter_tree = @rooms = system!(Engine::Scene::Rooms)

    def _draw(renderer, _view) = renderer.rect(-width / 2.0, -height, width, height, color: self.class::COLOR)

    private

    def destination = @to

    def move(hero) = @rooms.move(@party ? @rooms.node.heroes : hero, to: destination, entrance: @entrance)
  end

  # A warp pad: a door into the room it stands in. A room is its own scene, so
  # the pad leads to the scene's name.
  class Warp < Door
    COLOR = Util::Color.new(150, 96, 210, 200)

    # @param entrance [String] the entrance in this room where the hero arrives
    def initialize(entrance:, **) = super(to: nil, entrance:, **)

    private

    def destination = scene.name
  end

  # One room: the map and the world it makes solid. Mounting the map builds its
  # doors, in its `doors` layer. That layer draws under the actors, so a hero
  # walks over a door rather than behind it.
  class Grounds < Engine::Scene::Room
    def initialize(map_id)
      super()
      @map_id = map_id
    end

    def _enter_tree
      @map = root.context.assets.tilemap(@map_id).map
      add_component(Components::TileWorld.new(map: @map, tilemap_id: @map_id))
      add_component(Components::CollisionWorld.new(cell_size: 32))
      @actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))[:actors]
    end

    # A hero arrives standing on the entrance the move named.
    def _arrive(node, entrance)
      spot = @map.object_named(entrance)
      node.x = spot.x
      node.y = spot.y
      @actors.add_node(node)
    end
  end

  # The root: the rooms, the heroes, and which room the player stands in, as a
  # line of text over everything.
  class World < Engine::Node2D
    FADE = Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)

    MAPS = { town: 'town_with_gate.tmx', garden: 'garden.tmx' }.freeze

    PLACES = {
      town: Engine::Text.new('place.town'),
      garden: Engine::Text.new('place.garden')
    }.freeze

    attr_reader :heroes

    def initialize
      super(band: :overlay)
      @rooms = add_component(Engine::Scene::Rooms.new)
      MAPS.each { |name, map_id| @rooms.define(name) { Grounds.new(map_id) } }
      @rooms.transition = FADE
      @heroes = []
      @help = Engine::Text.new('help.walk')
    end

    # Loads every room's map before anyone walks, so a door parses nothing: the
    # asset manager keeps a map once it is loaded, and a room built again reads
    # the one it kept.
    def _enter_tree
      MAPS.each_value { root.context.assets.tilemap(it) }
      @player = system!(Engine::Players).primary
      @heroes << Hero.new(camera: @player.camera)
      @rooms.move(@heroes.first, to: :town, entrance: 'start')
    end

    def _draw(renderer, _view)
      renderer.text(@help, 12, 12)
      room = @rooms.room_of(@player)
      renderer.text(PLACES.fetch(room.name), 12, 34) if room
    end
  end

  # Builds the game and runs it until the window closes.
  def self.start
    game = RGame::Game.new(
      root: World.new,
      caption: 'Doors',
      width: WIDTH,
      height: HEIGHT,
      media_root: ASSETS,
      locales: LOCALES
    )

    game.start
  end
end

DoorsExample.start
