# frozen_string_literal: true

# The room: the map, the world it makes solid, and one hero per player.
#
# It mounts a TileWorld over the town map, puts a WorldView under itself and
# lets TileMapLayer.mount lay the map's layers out around an `:actors` slot. The
# heroes go in that slot, so a tree's canopy draws in front of whoever walks
# under it. The coins, the chest, the lever and the crate go in the same slot,
# for the same reason, and so do the sparkles every coin bursts as it is taken.
#
# Each hero's Bag goes in a PlayerLayer of that hero's player, so it draws in
# their region, over the world, and reads their input.
#
# It also mounts a CollisionWorld. The map alone stops a hero, and that needed
# no broadphase — but a coin is a contact, a chest is a range query and a crate
# is a collider a step runs into, and all three read this one index.
#
# The room never counts players and never asks how the screen is divided. It
# spawns for whoever is already playing and listens for whoever joins; Viewports
# gives each active player a region, and one more player is one more region.
class Room < RGame::Engine::Node2D
  MAP = 'town.tmx'

  CELL_SIZE = 64

  STARTS = [[376.0, 262.0], [424.0, 262.0]].freeze

  COINS = [[341, 206], [314, 179], [288, 152], [468, 317], [256, 150]].freeze

  CHEST = [265, 115].freeze

  LEVER = [160, 96].freeze

  CRATE = [440, 304].freeze

  DEFAULT_SEED = 0xAD7E

  def _enter_tree
    map = root.context.assets.tilemap(MAP).map
    @players = root.system(RGame::Engine::Players)

    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: @players.map(&:camera)
                  ))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))

    @view = add_node(RGame::Engine::WorldView.new)
    @actors = RGame::Engine::TileMapLayer.mount(@view)[:actors]

    rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
    sparkles = @actors.add_node(Sparkles.new(rng: rng))
    COINS.each { |x, y| @actors.add_node(Coin.new(x: x, y: y, sparkles: sparkles)) }
    @actors.add_node(Chest.new(x: CHEST.first, y: CHEST.last))
    @actors.add_node(Lever.new(x: LEVER.first, y: LEVER.last))
    @actors.add_node(Crate.new(x: CRATE.first, y: CRATE.last))

    @players.each_active { |player| spawn(player) }
    @players.on_joined { |player| spawn(player) }
  end

  private

  def spawn(player)
    x, y = STARTS[player.id]
    hero = Hero.new(x: x, y: y, camera: player.camera)
    hero.input_owner = player
    @actors.add_node(hero)
    add_node(RGame::Engine::PlayerLayer.new(player: player)).add_node(Bag.new(hero: hero, x: 8, y: 8))
  end
end
