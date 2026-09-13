# frozen_string_literal: true

# The one scene: it owns the camera, mounts the TileWorld system, and builds the
# player + NPCs under a WorldView (so they draw in world space and the camera maps
# them to the screen). It resolves everything it needs from the game's asset manager
# (node.root.context.assets) by relative path — nothing is passed into its constructor.
#
# Actors live in the node TileMapLayer.mount hands back, which sits between the
# map's ground layers and the layers Tiled flags `above` — so palm canopies
# render in front of a walker and trunks behind. No z is picked anywhere here.
#
# It mounts both collision systems, which is the case a game usually wants and this
# project is the acceptance test for: TileWorld for the map's walls, CollisionWorld for
# the actors. Each walker carries one feet box and one body declaring both.
class BeachScene < RGame::Engine::Node2D
  MAP_KEY      = 'map/beach_large.tmx'
  PLAYER_SHEET = 'player.json'
  NPC_SHEET    = 'Male 01-1.json'
  PLAYER_SPEED = 120.0
  NPC_SPEED    = 70.0
  NPC_OFFSETS  = [[-80, -48], [96, -32], [-64, 64], [120, 48], [40, -96], [-112, 16]].freeze
  BLOCKED_BY   = %i[tiles hero npc].freeze
  ACTOR_CELL     = 32
  WALKER_SPACING = 48
  UI_MARGIN      = 20

  DEFAULT_SEED = 0xBEAC4

  def initialize
    super
    @rng = Random.new(ENV.fetch('RGAME_SEED', DEFAULT_SEED).to_i)
    @walkers = {}
  end

  def on_add
    @map = node_context.assets.tilemap(MAP_KEY).map
    @players = root.system(RGame::Engine::Players)
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: @map, tilemap_id: MAP_KEY, cameras: @players.map(&:camera)
                  ))
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: ACTOR_CELL))

    @view = add_node(RGame::Engine::WorldView.new)
    @actors = RGame::Engine::TileMapLayer.mount(@view)

    @players.each_active { |player| spawn_walker(player) }
    @players.on_joined { |player| spawn_walker(player) }

    npc_spawns.each { |x, y| @actors.add_node(build_npc(x, y)) }

    add_node(Cutscene.new(world_view: @view))
  end

  private

  def node_context = root.context

  def spawn_walker(player)
    walker = build_player
    walker.input_owner = player
    walker.x += WALKER_SPACING * player.id
    @actors.add_node(walker)
    follow_camera(walker, player.camera)
    @walkers[player.id] = walker
    spawn_ui(player, walker)
  end

  def spawn_ui(player, walker)
    layer = add_node(RGame::Engine::PlayerLayer.new(player: player))
    layer.add_node(Inventory.new(walker: walker, x: UI_MARGIN, y: UI_MARGIN))
  end

  def follow_camera(node, camera)
    box = node.get_component(RGame::Engine::Components::BoxCollider).box
    node.add_component(RGame::Engine::Components::CameraFollow.new(
                         camera: camera,
                         offset_x: box.offset_x + (box.width / 2.0),
                         offset_y: box.offset_y + (box.height / 2.0)
                       ))
  end

  def build_player
    node = RGame::Engine::Node2D.new(x: @map.pixel_width / 2.0, y: @map.pixel_height / 2.0)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: PLAYER_SHEET))
    node.add_component(RGame::Engine::Components::FeetCollider.new(width: 10, height: 8, layer: :hero))
    node.add_component(RGame::Engine::Components::CharacterBody.new(speed: PLAYER_SPEED,
                                                                    blocked_by: BLOCKED_BY))
    node.add_component(RGame::Engine::Components::PlayerController.new)
    node
  end

  def build_npc(x, y)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: NPC_SHEET))
    node.add_component(RGame::Engine::Components::FeetCollider.new(width: 14, height: 10, layer: :npc))
    node.add_component(RGame::Engine::Components::CharacterBody.new(speed: NPC_SPEED,
                                                                    blocked_by: BLOCKED_BY))
    node.add_component(RGame::Engine::Components::WanderController.new(rng: @rng))
    node
  end

  def npc_spawns
    cx = @map.pixel_width / 2.0
    cy = @map.pixel_height / 2.0
    NPC_OFFSETS.map { |dx, dy| [cx + dx, cy + dy] }.reject { |x, y| @map.solid_at?(x, y) }
  end
end
