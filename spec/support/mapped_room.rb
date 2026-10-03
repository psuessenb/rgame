# frozen_string_literal: true

# A Scene::Room over a WalledTileMap, built as a game's room over its Tiled map
# is. It places each node a move brings at the location its TileWorld names, so
# an entrance and a respawn point are found the same way.
#
#   MappedRoom.new(['....', '.~~.'], objects: [['gate', 8, 8]])
#
# The node it places becomes a child of the room itself. A CollisionWorld
# beside the TileWorld lets colliders in the room meet, such as a hero's and a
# checkpoint's.
class MappedRoom < RGame::Engine::Scene::Room
  def initialize(rows, objects:)
    super()
    map = WalledTileMap.build(rows, objects:)
    add_component(RGame::Engine::Components::TileWorld.new(map:, tilemap_id: :map))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
  end

  def world = get_component(RGame::Engine::Components::TileWorld)

  def _arrive(node, location)
    place = world.location(location)
    node.x = place.x
    node.y = place.y
    add_node(node)
  end
end
