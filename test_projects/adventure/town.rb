# frozen_string_literal: true

# The town: the map, the world it makes solid, the things to take and press, and
# the gate to the garden.
#
# It mounts a TileWorld over the town map, puts a WorldView under itself and
# lets TileMapLayer.mount lay the map's layers out around two slots. The heroes
# go in `:actors`, so a tree's canopy draws in front of whoever walks under it.
# The coins, the chest, the lever and the crate go there too, for the same
# reason, and so do the sparkles every coin bursts as it is taken. The gate goes
# in `:doors`, under them, so a hero walks over it.
#
# It also mounts a CollisionWorld. The map alone stops a hero, and that needed
# no broadphase — but a coin is a contact, a chest is a range query, a crate is a
# collider a step runs into and the gate is a box a hero touches, and all four
# read this one index.
#
# ## The town that was left
#
# The rooms build the town anew each time a hero walks into it, so nothing it
# holds survives the garden. What changes in it is kept in Facts: each coin
# taken, the chest's state, the lever's, and where the crate stands. A town
# built again reads them back, so it is the town that was left — as a loaded
# save's town would be.
#
# The heroes are not the town's. The world spawns them and the rooms move them
# in, and `_arrive` stands each one on the entrance the move named, a second
# player's hero a step to the east of the first's.
#
# ## The opening
#
# The first time the town is built, it plays a cutscene everybody watches: a
# caption, the view carried from the start to the square, a second caption, and
# a press. The cutscene has a camera of its own, which follows a lookout walked
# along that line, so the window shows one view of the town, and it pauses every
# hero and stops joins until it ends. Holding `skip` ends it at once, and the
# town is left the same. Facts remember it was played, so a town built again on
# the way back from the garden plays nothing.
class Town < RGame::Engine::Scene::Room
  MAP = 'town.tmx'

  CELL_SIZE = 64

  SPACING = 48

  COINS = [[341, 206], [314, 179], [288, 152], [468, 317], [256, 150]].freeze

  CHEST = [265, 115].freeze

  LEVER = [160, 96].freeze

  CRATE = [440, 304].freeze

  OPENING = RGame::Engine::Cutscene::Script.build do
    run { it.caption.text = 'Morning in the town' }
    wait 1.0
    hold(&:look_at_square)
    run { it.caption.text = 'The gate to the garden stands open' }
    press
    run { it.caption.text = nil }
  end

  attr_reader :caption

  def _enter_tree
    @map = root.context.assets.tilemap(MAP).map
    facts = system!(RGame::Engine::Components::Facts)

    add_component(RGame::Engine::Components::TileWorld.new(map: @map, tilemap_id: MAP))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))

    slots = RGame::Engine::TileMapLayer.mount(add_node(RGame::Engine::WorldView.new),
                                              slots: { doors: nil, actors: nil })
    @actors = slots[:actors]

    sparkles = @actors.add_node(Sparkles.new)
    COINS.each_with_index do |(x, y), index|
      taken = :"coin_#{index}"
      next if facts[taken]

      @actors.add_node(Coin.new(x: x, y: y, sparkles: sparkles)).collectable.on_collected { facts[taken] = true }
    end
    @actors.add_node(Chest.new(x: CHEST.first, y: CHEST.last, facts: facts, key: :chest))
    @actors.add_node(Lever.new(x: LEVER.first, y: LEVER.last, facts: facts, key: :lever))
    @actors.add_node(Crate.new(x: CRATE.first, y: CRATE.last, facts: facts, key: :crate))

    doors = RGame::Engine::MapObjects.new
    doors.define('door') { |o| Door.new(object: o, world: parent) }
    doors.spawn_into(slots[:doors], @map.objects)

    open_the_town(facts) unless facts[:opened]
  end

  # Walks the lookout from the start to the square, and hands the walk to the
  # step that waits on it.
  def look_at_square
    from = @map.object_named('start')
    to = @map.object_named('square')
    @look.tap { it.follow(RGame::Engine::Path.new([[from.x, from.y], [to.x, to.y]])) }
  end

  def _arrive(hero, entrance)
    spot = @map.object_named(entrance)
    hero.x = spot.x + (SPACING * hero.input_owner.id)
    hero.y = spot.y
    @actors.add_node(hero)
  end

  private

  def open_the_town(facts)
    facts[:opened] = true
    @caption = add_node(Caption.new)
    camera = RGame::Engine::Camera.new
    get_component(RGame::Engine::Components::TileWorld).bound(camera)
    start = @map.object_named('start')
    lookout = @actors.add_node(RGame::Engine::Node2D.new(x: start.x, y: start.y))
    lookout.add_component(RGame::Engine::Components::CameraFollow.new(camera:))
    @look = lookout.add_component(RGame::Engine::Components::PathFollow.new(speed: 60.0))
    add_component(RGame::Engine::Components::Cutscene.new(OPENING, context: self, camera:, pause: parent.heroes,
                                                                   skip: :skip))
  end
end
