# frozen_string_literal: true

# The room: the map, the world it makes solid, and one hero per player.
#
# It mounts a TileWorld over the town map, puts a WorldView under itself and
# lets TileMapLayer.mount lay the map's layers out around an `:actors` slot. The
# heroes go in that slot, so a tree's canopy draws in front of whoever walks
# under it.
#
# The room never counts players and never asks how the screen is divided. It
# spawns for whoever is already playing and listens for whoever joins; Viewports
# gives each active player a region, and one more player is one more region.
class Room < RGame::Engine::Node2D
  MAP = 'town.tmx'

  STARTS = [[368.0, 240.0], [416.0, 240.0]].freeze

  def _enter_tree
    map = root.context.assets.tilemap(MAP).map
    @players = root.system(RGame::Engine::Players)

    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: @players.map(&:camera)
                  ))

    @view = add_node(RGame::Engine::WorldView.new)
    @actors = RGame::Engine::TileMapLayer.mount(@view)[:actors]

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
