# frozen_string_literal: true

module TopDownPlatformer
  # The one scene: a course crossed west to east over trenches and two chasms, for
  # two players. It mounts both worlds and the map, which builds the rafts, the
  # flags, the crate and the walker, and it spawns a hero for each player.
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
  # The map marks its `spawns` layer `actors`, so the heroes go there and sort
  # against the flags, the crate and the walker. The rafts are in the
  # `platforms` layer under it, so a hero draws over the raft they ride. The
  # course listens to `Players#on_joined` for as long as it is in the tree, and
  # ends that as it leaves.
  class Course < Engine::Node2D
    MAP = File.expand_path('course.tmx', __dir__)

    CELL_SIZE = 64

    def _enter_tree
      @map = root.context.assets.tilemap(MAP).map
      @players = system!(Engine::Players)
      add_component(Components::TileWorld.new(
                      map: @map, tilemap_id: MAP, cameras: @players.map(&:camera)
                    ))
      add_component(Components::CollisionWorld.new(cell_size: CELL_SIZE))
      @actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))[:actors]
      @heroes = {}
      @players.each_active { spawn(it) }
      @joining = @players.on_joined { spawn(it) }
    end

    def _exit_tree = @players.disconnect_joined(@joining)

    private

    def spawn(player)
      point = @heroes[@players.primary]&.get_component(Components::Respawn)
      start = @map.object_named('start')
      hero = Hero.new(camera: player.camera, x: point ? point.point_x : start.x, y: point ? point.point_y : start.y)
      hero.input_owner = player
      @heroes[player] = @actors.add_node(hero)
      add_node(Engine::PlayerLayer.new(player:)).add_node(Hud.new(hero:))
    end
  end
end
