# frozen_string_literal: true

module Adventure
  # The course: a third map, crossed west to east over trenches and two chasms,
  # where the heroes hop, fall and come back, and ride rafts across.
  #
  # It is built as the first hero walks through the town's east gate, and freed
  # once nobody is left in it. Its map lives beside this file rather than in
  # `examples/assets`, and names that directory's tilesets by relative path. The
  # asset manager takes its absolute path as it is, while every other asset
  # resolves against `media_root`.
  #
  # The map builds the gate back to the town, the rafts, the flags, the crate
  # and the walker. The rafts are in the `platforms` layer under `actors`, so a
  # hero draws over the raft they ride, and sorts against everything else.
  #
  # ## Where a hero comes back
  #
  # `_arrive` sets the arriving hero's Respawn point to the place they arrive
  # at, a RoomPoint in this room. So a fall before the first flag brings a hero
  # back to the course's start, not to the town where their point began. A
  # Flag's Checkpoint moves the point on to the flag. A fall brings the hero
  # back through `_arrive` again, at the flag, and the point stays there.
  class Course < Engine::Scene::Room
    MAP = File.expand_path('course.tmx', __dir__)

    CELL_SIZE = 64

    def _enter_tree
      map = root.context.assets.tilemap(MAP).map
      add_component(Components::TileWorld.new(map:, tilemap_id: MAP))
      add_component(Components::CollisionWorld.new(cell_size: CELL_SIZE))

      @actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))['actors']
    end

    def _arrive(hero, location)
      spot = get_component(Components::TileWorld).location(location)
      hero.x = spot.x + (Town::SPACING * hero.input_owner.id)
      hero.y = spot.y
      hero.get_component(Components::Respawn).set_point(Components::Respawn::RoomPoint.new(room: name, location:))
      hero.reach(location)
      @actors.add_node(hero)
    end
  end
end
