# frozen_string_literal: true

# The one scene: it owns the camera, mounts the TileWorld system, and builds the
# player + NPCs under a WorldView (so they draw in world space and the camera maps
# them to the screen). It resolves everything it needs from the game's asset manager
# (node.root.context.assets) by relative path — nothing is passed into its constructor.
#
# Actors draw at ACTOR_Z, between the tile world's ground band (0) and overlay band
# (TileWorld::CANOPY_Z), so palm canopies render in front and trunks behind.
class BeachScene < RGame::Engine::Node2D
  MAP_KEY      = 'map/beach_large.tmx'
  PLAYER_SHEET = 'player.json'
  NPC_SHEET    = 'Male 01-1.json'
  ACTOR_Z      = 10
  PLAYER_SPEED = 120.0
  NPC_SPEED    = 70.0
  NPC_OFFSETS  = [[-80, -48], [96, -32], [-64, 64], [120, 48], [40, -96], [-112, 16]].freeze
  WALKER_SPACING = 48 # so a second player starts beside the first, not inside them

  def initialize
    super
    @rng = Random.new(0xBEAC4)
    @walkers = {}
  end

  def on_add
    @map = node_context.assets.tilemap(MAP_KEY).map
    # Cameras belong to players, not to this scene: a scene may have any number
    # of viewers. All the scene does is tell them how big the world is.
    @players = root.system(RGame::Engine::Players)
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: @map, tilemap_id: MAP_KEY, cameras: @players.map(&:camera)
                  ))

    # World space begins here: everything under it draws at its own world
    # coordinates and is drawn once per viewport, through that viewport's camera.
    @view = add_node(RGame::Engine::WorldView.new)
    # The map is world content, so it is drawn inside the band like everything
    # else — once per viewport, culled to what that viewport can see.
    @view.add_node(RGame::Engine::TileMapLayer.new)

    # One walker per player who is already playing, and one more whenever
    # somebody picks up a controller. The scene never polls for that — the
    # registry says so.
    @players.each_active { |player| spawn_walker(player) }
    @players.on_joined { |player| spawn_walker(player) }

    npc_spawns.each { |x, y| @view.add_node(build_npc(x, y)) }

    # Outside the WorldView, so it draws once across the whole window and keeps
    # ticking while the world it covers is frozen.
    add_node(Cutscene.new(world_view: @view))
  end

  private

  def node_context = root.context

  # A player's own walker: their input drives it, their camera follows it.
  #
  # `input_owner` is what makes the second one answer to the second player —
  # it is inherited down the subtree, so everything under this node reads that
  # player and nothing else has to be told.
  def spawn_walker(player)
    walker = build_player
    walker.input_owner = player
    walker.x += WALKER_SPACING * player.id
    @view.add_node(walker)
    # After add_node, deliberately: the camera offset is read off the walker's
    # feet box, and that box is sized from the sprite, which AnimatedSprite only
    # knows once it has attached. See #follow_camera.
    follow_camera(walker, player.camera)
    @walkers[player.id] = walker
  end

  # Point the camera at the player's feet box rather than the sprite's origin,
  # which is its top-left. Following is a CameraFollow component on the player
  # itself: the player owns the camera, and a component in the world moves it —
  # so "player two's camera follows player two" is the same line with their
  # camera in it.
  #
  # **Only valid once the node is in the tree.** `collision_box` is derived from
  # the sprite's frame size and memoised on first read, and the sprite size is
  # set by AnimatedSprite#on_attach — so reading it from `build_player` bakes a
  # box computed from a 0x0 sprite, for the collision system as well as for this.
  def follow_camera(node, camera)
    box = node.get_component(RGame::Engine::Components::CharacterBody).collision_box
    node.add_component(RGame::Engine::Components::CameraFollow.new(
                         camera: camera,
                         offset_x: box.offset_x + (box.width / 2.0),
                         offset_y: box.offset_y + (box.height / 2.0)
                       ))
  end

  def build_player
    node = RGame::Engine::Node2D.new(x: @map.pixel_width / 2.0, y: @map.pixel_height / 2.0)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: PLAYER_SHEET, z: ACTOR_Z))
    node.add_component(RGame::Engine::Components::CharacterBody.new(feet_width: 10, feet_height: 8,
                                                                    speed: PLAYER_SPEED))
    node.add_component(RGame::Engine::Components::PlayerController.new)
    node
  end

  def build_npc(x, y)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: NPC_SHEET, z: ACTOR_Z))
    node.add_component(RGame::Engine::Components::CharacterBody.new(feet_width: 14, feet_height: 10, speed: NPC_SPEED))
    node.add_component(RGame::Engine::Components::WanderController.new(rng: @rng))
    node
  end

  # Spread NPCs around the (sandy) map centre, dropping any that land on a solid tile.
  def npc_spawns
    cx = @map.pixel_width / 2.0
    cy = @map.pixel_height / 2.0
    NPC_OFFSETS.map { |dx, dy| [cx + dx, cy + dy] }.reject { |x, y| @map.solid_at?(x, y) }
  end
end
