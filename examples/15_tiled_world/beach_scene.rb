# frozen_string_literal: true

# The one scene: it owns the camera, mounts the TileWorld system, and builds the
# player + NPCs under a CameraView (so they draw in world space and the camera maps
# them to the screen). It resolves everything it needs from the game's asset manager
# (node.root.context.assets) by relative path — nothing is passed into its constructor.
#
# Actors draw at ACTOR_Z, between the tile world's ground band (0) and overlay band
# (TileWorld::OVERLAY_Z), so palm canopies render in front and trunks behind.
class BeachScene < Engine::Node2D
  MAP_KEY      = 'map/beach_large.tmx'
  PLAYER_SHEET = 'player.json'
  NPC_SHEET    = 'Male 01-1.json'
  ACTOR_Z      = 10
  PLAYER_SPEED = 120.0
  NPC_SPEED    = 70.0
  NPC_OFFSETS  = [[-80, -48], [96, -32], [-64, 64], [120, 48], [40, -96], [-112, 16]].freeze

  def initialize
    super
    @rng = Random.new(0xBEAC4)
  end

  def on_add
    game = node_context
    @map = game.assets.tilemap(MAP_KEY).map
    @camera = Engine::Camera.new(
      viewport_width: game.width, viewport_height: game.height,
      world_width: @map.pixel_width, world_height: @map.pixel_height
    )
    add_component(Engine::Components::TileWorld.new(map: @map, tilemap_id: MAP_KEY, camera: @camera))

    view = add_node(Engine::CameraView.new(camera: @camera))
    @player = build_player
    view.add_node(@player)
    npc_spawns.each { |x, y| view.add_node(build_npc(x, y)) }
  end

  # Follow the player, centred on its feet box. Runs before the player's own update,
  # so the view trails by one step (~2 px) — uniform and imperceptible, and the tile
  # map and the actors read this one camera, so they never drift apart on screen.
  def on_update(_dt)
    box = @player.get_component(Engine::Components::CharacterBody).collision_box
    # Compute the feet-box centre inline; box.aabb would allocate an Array every frame.
    @camera.center_on(@player.x + box.offset_x + (box.width / 2.0),
                      @player.y + box.offset_y + (box.height / 2.0))
  end

  private

  def node_context = root.context

  def build_player
    node = Engine::Node2D.new(x: @map.pixel_width / 2.0, y: @map.pixel_height / 2.0)
    node.add_component(Engine::Components::AnimatedSprite.new(sheet: PLAYER_SHEET, z: ACTOR_Z))
    node.add_component(Engine::Components::CharacterBody.new(feet_width: 10, feet_height: 8, speed: PLAYER_SPEED))
    node.add_component(Engine::Components::PlayerController.new)
    node
  end

  def build_npc(x, y)
    node = Engine::Node2D.new(x: x, y: y)
    node.add_component(Engine::Components::AnimatedSprite.new(sheet: NPC_SHEET, z: ACTOR_Z))
    node.add_component(Engine::Components::CharacterBody.new(feet_width: 14, feet_height: 10, speed: NPC_SPEED))
    node.add_component(Engine::Components::WanderController.new(rng: @rng))
    node
  end

  # Spread NPCs around the (sandy) map centre, dropping any that land on a solid tile.
  def npc_spawns
    cx = @map.pixel_width / 2.0
    cy = @map.pixel_height / 2.0
    NPC_OFFSETS.map { |dx, dy| [cx + dx, cy + dy] }.reject { |x, y| @map.solid_at?(x, y) }
  end
end
