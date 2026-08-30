# frozen_string_literal: true

# Scroll map — a Tiled map, larger than the window, that a player scrolls.
#
# Run it:
#
#   ruby examples/scroll_map/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick pan the view; the map stops at its
# own edges. It exercises:
#   - the `:tilemap` asset loader — a .tmx becomes a parsed map plus a renderer;
#   - Components::TileWorld — the scene-scoped system that owns the map and the
#     world's size;
#   - TileMapLayer.mount — one node per Tiled layer, drawn as world content;
#   - WorldView — where world space begins, and where the camera is applied;
#   - Camera — clamped to the world, so the view never shows past the edge;
#   - Components::CameraFollow — what points a camera at something.
#
# ## Moving a camera means moving a node
#
# There is no "pan the camera" call, and the absence is the design. A camera is
# owned by a *player* — a scene may have any number of viewers, so it cannot own
# one — and where it points is decided by a CameraFollow component on some node
# in the world. Scrolling is therefore the same thing as walking: build a node,
# drive it with the usual controller, and hang a camera off it.
#
# That node is the Rig below. It is `examples/walk`'s hero with the sprite left
# off — same CharacterBody, same PlayerController — which is the point worth
# taking away: the camera is not a special case, and a game that follows its
# player is this file with a sprite added back.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

MAP   = 'town.tmx'
SPEED = 220.0 # px/s — a camera pans faster than a character walks

# The node the camera follows: no sprite, no collision, just a position that
# input moves and a camera that trails it.
#
# It draws a crosshair so the centre of the view is visible, which is the only
# reason it is a class rather than a bare Node2D with three components on it.
class Rig < RGame::Engine::Node2D
  ARM = 7
  # A Color rather than an array literal, and a constant rather than either: a
  # drawing call coerces `nil`, `[r, g, b]` or a Color, and building the array
  # inline would allocate one every frame. RGame::Util::Color is a value type —
  # frozen, comparable, and safe to share.
  TINT = RGame::Util::Color.new(250, 250, 255)

  def initialize(world_width:, world_height:, **)
    super(**)
    @world_width = world_width
    @world_height = world_height
  end

  # Keep the rig on the map. The camera already refuses to show past the world's
  # edges, but the rig is not the camera: without this it walks off into
  # nothing, the view stays pinned to the edge, and the player is left pushing a
  # key that does nothing visible. Clamping both to the same bounds keeps the
  # crosshair and the view agreeing.
  def on_update(_dt)
    self.x = x.clamp(0, @world_width)
    self.y = y.clamp(0, @world_height)
  end

  # (0, 0) is this node: Node2D#draw has already pushed its transform, and the
  # WorldView above has already applied the camera. Reading `x` or `world_x`
  # here would apply one of those a second time.
  def on_draw(renderer, _view)
    renderer.line(-ARM, 0, ARM, 0, color: TINT)
    renderer.line(0, -ARM, 0, ARM, color: TINT)
  end
end

# The scene: mount the map, mount the world, put the rig in it.
class Scene < RGame::Engine::Node2D
  def on_add
    # `.tilemap` is a loader RGame::Game installs, because building one needs
    # both layers at once: Engine::TileMap reads the .tmx, and the renderer that
    # draws it is Core. What comes back holds both; `.map` is the grid half.
    map = root.context.assets.tilemap(MAP).map
    players = root.system(RGame::Engine::Players)

    # The system every actor asks about the world: how big it is, what is solid.
    # Handing it the cameras is what bounds them — a camera left unbounded
    # follows its target exactly and will happily show the void past the edge.
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                  ))

    # World space begins here. Everything under it is drawn in world
    # coordinates, once per viewport, through that viewport's camera.
    view = add_node(RGame::Engine::WorldView.new)
    # One node per Tiled layer. The node handed back is the gap between the
    # ground layers and any layer Tiled flags `above`, which is where things
    # that walk around go — the rig included, so a canopy layer would pass over
    # it without this file choosing a single z.
    actors = RGame::Engine::TileMapLayer.mount(view)
    actors.add_node(build_rig(map, players.primary.camera))
  end

  def on_draw(renderer, _view)
    # Outside the WorldView, so this is screen space: it stays put while the
    # world scrolls under it.
    renderer.text('Arrow keys / WASD / gamepad to scroll', 12, 12)
  end

  private

  def build_rig(map, camera)
    rig = Rig.new(x: map.pixel_width / 2.0, y: map.pixel_height / 2.0,
                  world_width: map.pixel_width, world_height: map.pixel_height)
    rig.add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED))
    rig.add_component(RGame::Engine::Components::PlayerController.new)
    rig.add_component(RGame::Engine::Components::CameraFollow.new(camera: camera))
    rig
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Scroll map',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
