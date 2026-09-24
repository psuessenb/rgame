# frozen_string_literal: true

# The garden: a second map, and the gate back to the town.
#
# It is built as the first hero walks through the town's gate and freed once
# nobody is left in it. Nothing in it changes, so it keeps nothing in Facts.
class Garden < RGame::Engine::Scene::Room
  MAP = 'garden.tmx'

  CELL_SIZE = 64

  def _enter_tree
    @map = root.context.assets.tilemap(MAP).map
    add_component(RGame::Engine::Components::TileWorld.new(map: @map, tilemap_id: MAP))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))

    slots = RGame::Engine::TileMapLayer.mount(add_node(RGame::Engine::WorldView.new),
                                              gaps: { doors: nil, actors: nil })
    @actors = slots[:actors]

    doors = RGame::Engine::MapObjects.new
    doors.define('door') { |o| Door.new(object: o, world: parent) }
    doors.spawn_into(slots[:doors], @map.objects)
  end

  def _arrive(hero, entrance)
    spot = @map.object_named(entrance)
    hero.x = spot.x + (Town::SPACING * hero.input_owner.id)
    hero.y = spot.y
    @actors.add_node(hero)
  end
end
