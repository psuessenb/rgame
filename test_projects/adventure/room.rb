# frozen_string_literal: true

# The room: the map, the world it makes solid, and one hero per player.
#
# It mounts a TileWorld over the town map, puts a WorldView under itself and
# lets TileMapLayer.mount lay the map's layers out around an `:actors` slot. The
# heroes go in that slot, so a tree's canopy draws in front of whoever walks
# under it. The coins and the chest go in the same slot, for the same reason.
#
# It also mounts a CollisionWorld. The map alone stops a hero, and that needed
# no broadphase — but a coin is a contact and a chest is a range query, and both
# read this one index.
#
# The room never counts players and never asks how the screen is divided. It
# spawns for whoever is already playing and listens for whoever joins; Viewports
# gives each active player a region, and one more player is one more region.
class Room < RGame::Engine::Node2D
  MAP = 'town.tmx'

  CELL_SIZE = 64

  STARTS = [[368.0, 240.0], [416.0, 240.0]].freeze

  COINS = [[341, 206], [314, 179], [288, 152], [468, 317]].freeze

  CHEST = [265, 115].freeze

  def _enter_tree
    map = root.context.assets.tilemap(MAP).map
    @players = root.system(RGame::Engine::Players)

    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: @players.map(&:camera)
                  ))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))

    @view = add_node(RGame::Engine::WorldView.new)
    @actors = RGame::Engine::TileMapLayer.mount(@view)[:actors]

    COINS.each { |x, y| @actors.add_node(Coin.new(x: x, y: y)) }
    @actors.add_node(Chest.new(x: CHEST.first, y: CHEST.last))

    @players.each_active { |player| spawn(player) }
    @players.on_joined { |player| spawn(player) }
  end

  private

  def spawn(player)
    x, y = STARTS[player.id]
    hero = Hero.new(x: x, y: y, camera: player.camera)
    hero.input_owner = player
    @actors.add_node(hero)
  end
end
