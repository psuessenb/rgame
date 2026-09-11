# frozen_string_literal: true

# Collision tiles — walking into a wall.
#
# Run it:
#
#   ruby examples/collision_tiles/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero. The trees and the
# fence are solid; hold a diagonal against the fence and watch what happens. It
# exercises:
#   - Components::TileWorld — the scene-scoped system that owns the map, and
#     answers every question about what is solid;
#   - Components::TileCharacterBody — a CharacterBody whose steps are resolved
#     against that map;
#   - Engine::CollisionBox — the feet box, bottom-anchored to the sprite;
#   - Components::CameraFollow — a camera on the feet rather than on the head;
#   - the `:tilemap` asset loader and TileMapLayer, both from `examples/scroll_map`.
#
# ## This is the other collision problem, and it shares no code with the first
#
# `examples/collision` is a world of shapes that are told when they overlap.
# There is none of that here: no `CollisionWorld`, no collider component, no
# `on_hit`. Nothing in this file registers a shape, and the walls are not
# objects at all.
#
# That is the point of the pair. A character against a grid of solid tiles is
# not a pairwise overlap problem, because there are no pairs to find — a tile map
# already knows what is where, so the wall a step would hit is arithmetic on the
# step: divide by the tile size and ask the grid. Bucketing forty thousand tiles
# into a spatial hash would be building a second index of something already
# indexed, and then paying for it every frame.
#
# So the two examples answer the same English word with different machinery, and
# a game normally wants both: `examples/collision` for the things that move, this
# for the ground they move over.
#
# ## What is solid is decided in Tiled, not in code
#
# A tile is solid because it carries a collision shape in the tileset — an
# `<objectgroup>` on that tile in `tileset.tsx` — and `Engine::Tileset` reads
# that. Nothing in this file lists tile ids, and adding a solid tile to the map
# means drawing it in Tiled.
#
# ## A feet box, not the sprite's box
#
# The translucent rectangle drawn over the hero is the thing that actually
# collides. It is twelve by six at the bottom of a sixteen by twenty-two sprite,
# and everything above it is a picture that nothing tests.
#
# A top-down view needs that. The sprite is drawn as though seen from in front,
# so its upper half is *height* rather than floor, and a character whose whole
# frame collided could not stand with their head overlapping the fence behind
# them — which is what standing close to it looks like from this angle.
#
# `Engine::CollisionBox.bottom_anchored` builds it from the node's own
# dimensions, which `AnimatedSprite` fills in from the sprite frame when it
# attaches. So the box follows the art: re-export the hero at a different size
# and the feet stay at the feet.
#
# ## Sliding is the whole feel
#
# Walk diagonally into the fence and the hero keeps moving. The step is resolved
# one axis at a time, so the blocked half is dropped and the free half is kept,
# and a player pressing down-left against a wall travels left along it.
#
# It is worth doing deliberately: put the hero against the fence, hold down and
# left together, and you arrive at the one gap in it without ever steering. A
# version that stopped dead on contact would be correct by the letter — you did
# walk into a wall — and would feel broken in a way a player cannot articulate.
#
# ## The system is not optional, and says so
#
# `TileCharacterBody#on_attach` raises when the scene has no `TileWorld`, rather
# than falling back to free movement. The fallback would look like a collision
# bug — an actor walking through walls — and the cause would be a scene three
# files away that never mounted the system.
#
# ## What it does not solve
#
# Anything that is not the map. The hero here would walk straight through
# another character, because `TileWorld` answers questions about tiles and knows
# nothing about the actors standing on them. Things that bump into each other
# want the shapes and the system in `examples/collision`, and a game with both
# runs both.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

MAP   = 'town.tmx'
SPEED = 80.0 # px/s

# The feet: twelve wide and six tall, centred at the bottom of the 16x22 sprite.
FEET_WIDTH  = 12
FEET_HEIGHT = 6

# Where the camera looks: the middle of that box rather than the node's origin,
# which is the sprite's top-left corner. Without it the hero drifts below the
# centre of the screen by half a sprite, which reads as the camera lagging.
CAMERA_OFFSET_X = 8
CAMERA_OFFSET_Y = 19

# North of the fence and a few tiles east of its gap, so that holding a diagonal
# into it arrives there.
START_X = 384.0
START_Y = 272.0

# A sprite, a body that knows about walls, and a camera. The only thing this
# class writes itself is the box, drawn so that what collides is visible.
class Hero < RGame::Engine::Node2D
  FEET = RGame::Util::Color.rgba(255, 110, 110, 120)

  def initialize(camera:, **)
    super(**)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    # The one line that differs from `examples/walk`. Everything about the
    # intent — the controller writing it, the sprite reading it back as a
    # facing, the speed it is scaled by — is inherited from CharacterBody; this
    # subclass only changes where a step is allowed to land.
    @body = add_component(RGame::Engine::Components::TileCharacterBody.new(
                            feet_width: FEET_WIDTH, feet_height: FEET_HEIGHT, speed: SPEED
                          ))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: CAMERA_OFFSET_X, offset_y: CAMERA_OFFSET_Y
                  ))
  end

  # Components draw first, so this lands over the sprite. The box's offsets are
  # relative to the node's origin, which is exactly where the renderer already
  # is — a collision box and local space agree about what (0, 0) means.
  def on_draw(renderer, _view)
    box = @body.collision_box
    renderer.rect(box.offset_x, box.offset_y, box.width, box.height, color: FEET)
  end
end

# The scene: mount the map, mount the world, put the hero in it. The same three
# steps as `examples/scroll_map`, with an actor that collides instead of a rig
# that does not.
class Scene < RGame::Engine::Node2D
  def on_add
    map = root.context.assets.tilemap(MAP).map
    players = root.system(RGame::Engine::Players)

    # Solidity and the world's size come from the same system, because they are
    # the same fact about the same map. Handing it the cameras bounds them to
    # the map's edges.
    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                  ))

    view = add_node(RGame::Engine::WorldView.new)
    # The node handed back is the gap between the ground layers and anything
    # Tiled flags `above` — where things that walk around belong.
    actors = RGame::Engine::TileMapLayer.mount(view)
    actors.add_node(Hero.new(camera: players.primary.camera, x: START_X, y: START_Y))
  end

  # Screen space: outside the WorldView, so it stays put while the map scrolls.
  def on_draw(renderer, _view)
    renderer.text('Arrows / WASD / gamepad to walk — trees and the fence are solid', 12, 12)
    renderer.text('Hold down and left against the fence: you slide to its one gap', 12, 34)
    renderer.text('The red box is what collides. The rest of the sprite is a picture', 12, 56)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Collision tiles',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS
)

game.start
