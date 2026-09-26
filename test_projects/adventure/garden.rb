# frozen_string_literal: true

module Adventure
  # The garden: a second map, the gate back to the town, a pair of warp pads, and
  # the horn.
  #
  # It is built as the first hero walks through the town's gate and freed once
  # nobody is left in it. The first hero ever to arrive reads its Sign, a scene
  # for that player alone, and the facts database remembers it was read.
  #
  # The map builds its doors. The gate leads back to the town. A pad is a Warp,
  # a door into this same room: stepping on one only places the hero again,
  # beside the other pad, and nothing is built or freed. The horn is a Door
  # marked `party`, which moves every hero the world holds to the town square,
  # from whichever room they stand in.
  #
  # ## Its song, when there is one
  #
  # `SONG` is `media/music/garden.ogg` when that file exists, and nil otherwise.
  # `media/` is never committed or shipped, so a checkout without it runs the
  # garden in silence, and CI drives the game all the same. The world defines the
  # garden with it at priority 2, over the town's 1, so the song plays while
  # anybody stands in the garden or is on the way there.
  class Garden < Engine::Scene::Room
    MAP = 'garden.tmx'

    SONG_FILE = File.expand_path('../../media/music/garden.ogg', __dir__)

    SONG = (SONG_FILE if File.exist?(SONG_FILE))

    CELL_SIZE = 64

    def _enter_tree
      @map = root.context.assets.tilemap(MAP).map
      add_component(Components::TileWorld.new(map: @map, tilemap_id: MAP))
      add_component(Components::CollisionWorld.new(cell_size: CELL_SIZE))

      @actors = Engine::TileMapLayer.mount(add_node(Engine::WorldView.new))[:actors]
    end

    def _arrive(hero, entrance)
      spot = @map.object_named(entrance)
      hero.x = spot.x + (Town::SPACING * hero.input_owner.id)
      hero.y = spot.y
      @actors.add_node(hero)
      read_the_sign(hero)
    end

    private

    def read_the_sign(hero)
      facts = system!(Components::FactsDatabase)
      return if facts[:sign_read]

      facts[:sign_read] = true
      @actors.add_node(Sign.new(hero:))
    end
  end
end
