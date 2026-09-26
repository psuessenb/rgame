# frozen_string_literal: true

# The one scene: a course crossed west to east over trenches and two chasms, for
# two players. It mounts the map and both worlds, builds the platforms, the
# checkpoints, the crate and the walker from the map's objects, and a hero for
# each player.
#
# The map lives beside this file rather than in `examples/assets`, and names that
# directory's tilesets by relative path. The asset manager takes its absolute path
# as it is, while every other asset resolves against `media_root`.
#
# ## Where a hero stands
#
# The primary player's hero stands on `start`, which its Respawn takes as its
# first point. A player who joins later stands on the primary hero's respawn
# point: the last checkpoint that hero reached. That point is ground, since a
# Respawn refuses any other, so a join never puts a hero over a gap.
#
# The platforms have a slot of their own under the actors', so a hero draws over
# the raft they ride. The course listens to `Players#on_joined` for as long as it
# is in the tree, and ends that as it leaves.
class Course < RGame::Engine::Node2D
  MAP = File.expand_path('course.tmx', __dir__)

  CELL_SIZE = 64

  def _enter_tree
    @map = root.context.assets.tilemap(MAP).map
    @players = system!(RGame::Engine::Players)
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: @map, tilemap_id: MAP, cameras: @players.map(&:camera)
                  ))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))
    slots = RGame::Engine::TileMapLayer.mount(add_node(RGame::Engine::WorldView.new),
                                              slots: { platforms: nil, actors: nil })
    @actors = slots[:actors]
    rafts.spawn_into(slots[:platforms], @map.objects)
    things.spawn_into(@actors, @map.objects)
    @heroes = {}
    @players.each_active { spawn(it) }
    @joining = @players.on_joined { spawn(it) }
  end

  def _exit_tree = @players.disconnect_joined(@joining)

  private

  def rafts
    RGame::Engine::MapObjects.new.define('platform') do |object|
      Raft.new(route: RGame::Engine::Path.from_object(object),
               width: object.properties.fetch('width'), height: object.properties.fetch('height'))
    end
  end

  def things
    RGame::Engine::MapObjects.new
                             .define('checkpoint') { Flag.new(name: it.name, x: it.x, y: it.y) }
                             .define('crate') { Crate.new(x: it.x, y: it.y) }
                             .define('walker') { Walker.new(x: it.x, y: it.y) }
  end

  def spawn(player)
    point = @heroes[@players.primary]&.get_component(RGame::Engine::Components::Respawn)
    start = @map.object_named('start')
    hero = Hero.new(camera: player.camera, x: point ? point.point_x : start.x, y: point ? point.point_y : start.y)
    hero.input_owner = player
    @heroes[player] = @actors.add_node(hero)
    add_node(RGame::Engine::PlayerLayer.new(player:)).add_node(Hud.new(hero:))
  end
end
