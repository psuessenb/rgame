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
#   - MapObjects — a door built from each door object on the map;
#   - Components::Collectable with `free: false` — a door touched and kept.
#
# ## The map says where the doors are
#
# Nothing in this file says where a door is. `town.tmx` and `garden.tmx` each
# carry an object layer, `doors`, and every object in it has a class. An
# `entrance` is a point where a hero arrives. A `door` is a box whose
# properties say which room it leads to and at which entrance. A `warp` is a
# door into its own room, so it names only the entrance. Moving a door is a
# change in Tiled.
#
# ## One room class for both maps
#
# `Grounds` is every room here: a map, the world it makes solid, and its doors.
# `define` takes a block that builds a room each time one is needed, so the
# town and the garden are the same class built over two maps. A room is built
# anew each time it is entered, and nothing it held survives the trip. A game
# that must remember a taken coin keeps it in `Facts`, where a loaded save puts
# it too.
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

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)
LOCALES = File.expand_path('locales', __dir__) # the text on screen: locales/en.yml

SPEED = 80.0 # px/s

# The feet: twelve wide and six tall, at the bottom of the 16x22 sprite.
FEET_WIDTH  = 12
FEET_HEIGHT = 6

# A sprite, a feet box on the `:hero` layer, a body the map stops, and a camera.
class Hero < RGame::Engine::Node2D
  def initialize(camera:, **)
    super(**)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::FeetCollider.new(width: FEET_WIDTH, height: FEET_HEIGHT, layer: :hero))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(camera: camera))
  end
end

# A door or a warp pad, built from one object on the map. A hero's feet box
# touching its box asks the rooms for a move, and the door stays where it is.
#
# `to` is the room the object's properties name, or the room the pad stands in
# for a warp, which the room hands over. A door marked `party` moves every hero
# the world holds, and any other door moves the one who touched it.
class Door < RGame::Engine::Node2D
  COLORS = {
    'door' => RGame::Util::Color.new(150, 104, 56),
    'warp' => RGame::Util::Color.new(150, 96, 210, 200)
  }.freeze

  def initialize(object:, world:, to: object.properties.fetch('to').to_sym)
    super(x: object.x, y: object.y, width: object.width, height: object.height)
    @color = COLORS.fetch(object.class_name)
    entrance = object.properties.fetch('entrance')
    party = object.properties.fetch('party', false)
    add_component(RGame::Engine::Components::BoxCollider.new(width: object.width, height: object.height,
                                                             layer: :door))
    add_component(RGame::Engine::Components::Collectable.new(by: :hero, free: false)).on_collected do |other|
      world.rooms.move(party ? world.heroes : other.node, to:, entrance:)
    end
  end

  def _draw(renderer, _view) = renderer.rect(0, 0, width, height, color: @color)
end

# One room: the map, the world it makes solid, and a door for each door object
# on it. The doors go in a slot of their own, under the actors, so a hero walks
# over them rather than behind them.
class Grounds < RGame::Engine::Scene::Room
  def initialize(map_id)
    super()
    @map_id = map_id
  end

  def _enter_tree
    @map = root.context.assets.tilemap(@map_id).map
    add_component(RGame::Engine::Components::TileWorld.new(map: @map, tilemap_id: @map_id))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 32))
    slots = RGame::Engine::TileMapLayer.mount(add_node(RGame::Engine::WorldView.new),
                                              gaps: { doors: nil, actors: nil })
    @actors = slots[:actors]

    doors = RGame::Engine::MapObjects.new
    doors.define('door') { |o| Door.new(object: o, world: parent) }
    doors.define('warp') { |o| Door.new(object: o, world: parent, to: name) }
    doors.spawn_into(slots[:doors], @map.objects)
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
class World < RGame::Engine::Node2D
  FADE = RGame::Engine::Scene::Fade.new(cover: 0.25, reveal: 0.25)

  MAPS = { town: 'town.tmx', garden: 'garden.tmx' }.freeze

  PLACES = {
    town: RGame::Engine::Text.new('place.town'),
    garden: RGame::Engine::Text.new('place.garden')
  }.freeze

  attr_reader :rooms, :heroes

  def initialize
    super(band: :overlay)
    @rooms = add_component(RGame::Engine::Scene::Rooms.new)
    MAPS.each { |name, map_id| @rooms.define(name) { Grounds.new(map_id) } }
    @rooms.transition = FADE
    @heroes = []
    @help = RGame::Engine::Text.new('help.walk')
  end

  # Loads every room's map before anyone walks, so a door parses nothing: the
  # asset manager keeps a map once it is loaded, and a room built again reads
  # the one it kept.
  def _enter_tree
    MAPS.each_value { root.context.assets.tilemap(it) }
    @player = system!(RGame::Engine::Players).primary
    @heroes << Hero.new(camera: @player.camera)
    @rooms.move(@heroes.first, to: :town, entrance: 'start')
  end

  def _draw(renderer, _view)
    renderer.text(@help, 12, 12)
    room = @rooms.room_of(@player)
    renderer.text(PLACES.fetch(room.name), 12, 34) if room
  end
end

game = RGame::Game.new(
  root: World.new,
  caption: 'Doors',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  locales: LOCALES
)

game.start
