# frozen_string_literal: true

# Collision tiles — walking into a wall.
#
# Run it:
#
#   ruby examples/collision_tiles/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero. The trees and the
# fence are solid; hold a diagonal against the fence and watch what happens.
# East of the start is a spiky ball that stops the hero and costs a life. It
# exercises:
#   - Components::TileWorld — the scene-scoped system that owns the map, and
#     answers every question about what is solid;
#   - Components::CollisionWorld — the broadphase the ball's box lives in;
#   - Components::FeetCollider — the shape at the hero's feet, derived from the
#     sprite's size, and the one shape both of those stop;
#   - Components::CharacterBody with `blocked_by: %i[tiles spike]` — steps
#     resolved against the map *and* the ball, using that shape;
#   - CharacterBody's `on_blocked` — what stopped a step, as an event;
#   - Components::CameraFollow — a camera on the feet rather than on the head;
#   - Engine::CachedLabel — the life count as a string built only when it changes;
#   - the `:tilemap` asset loader and TileMapLayer, both from `examples/scroll_map`.
#
# ## Two indexes, one list of names
#
# The walls are not objects. A character against a grid of solid tiles is not a
# pairwise overlap problem, because there are no pairs to find — a tile map
# already knows what is where, so the wall a step would hit is arithmetic on the
# step: divide by the tile size and ask the grid. Bucketing forty thousand tiles
# into a spatial hash would be building a second index of something already
# indexed, and then paying for it every frame.
#
# The spiky ball is an object, and it is in one. The scene mounts a
# `CollisionWorld`, the ball wears a box on the `:spike` layer, and the hero
# names that layer beside `:tiles`. So a step here is resolved against a grid and
# against a broadphase at once, one axis at a time, stopping at whichever answer
# is nearer — and the only place in this file where that shows is the list of
# names in `blocked_by`.
#
# `examples/collision` is the third case, and the one neither of those is: shapes
# that are told when they start and stop *overlapping*, with nothing stopped.
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
# `FeetCollider` builds it from the node's own dimensions, which
# `AnimatedSprite` fills in from the sprite frame when it attaches. So the box
# follows the art: re-export the hero at a different size and the feet stay at
# the feet. Note what the `Hero` does *not* pass — a sprite size, an offset, or
# the box to anybody else. One component owns the shape and the body reads it.
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
# ## Being stopped is an event
#
# `on_blocked` fires on the step something starts stopping the body and
# `on_unblocked` on the step it stops, each once per blocker. That is what spends
# a life here: walk into the ball and lose one, keep pushing and lose no more,
# back off and walk in again and lose another.
#
# It has to be that signal rather than `on_hit`, and this is the part worth
# reading twice. Blocking leaves the two boxes exactly *touching*, and an overlap
# test is half-open, so a successfully blocked pair does not overlap and reports
# no contact at all. A ball that hurt through `on_hit` would have to be walked
# into — which is exactly what blocking it prevents.
#
# The handler is given whatever stopped the step, and reads `layer` and `node`
# off it the same way whichever kind it was. So the hero's one handler asks
# `by.layer == :spike` and ignores the fence, which arrives as `:tiles` with no
# node behind it.
#
# ## The system is not optional, and says so
#
# `blocked_by: [:tiles]` raises at attach when the scene has no `TileWorld`, and
# again when the node has no collider to resolve, rather than falling back to
# free movement. The fallback would look like a collision bug — an actor walking
# through walls — and the cause would be a scene three files away that never
# mounted the system.
#
# ## What this scene does not solve
#
# Nothing here moves but the hero. The ball is an ordinary actor with a box in
# the broadphase, so it could walk about and block just the same — which is what
# `test_projects/tiled_world` is, a crowd whose every walker declares
# `%i[tiles hero npc]` and shoulders past itself. A hazard that holds still is
# simply the smaller thing to read.
#
# Nor is anything here overlapping. Blocking and contact are reports of two
# different facts and a game usually wants both: a trigger walked through, a
# pickup that vanishes, a puddle that slows whoever stands in it. Every one of
# those is `on_hit` on a box nobody named in a `blocked_by`, which is
# `examples/collision`.

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

# The spiky ball: three tiles east of the hero, on the open ground between the
# trees, and low enough that its box sits across the hero's feet.
BALL_X = 434.0
BALL_Y = 284.0
BALL_SIZE = 12

LIVES = 3

# A sprite, a feet box, a body that knows about walls, and a camera. The only
# thing this class writes itself is the drawing of that box, so what collides is
# visible.
class Hero < RGame::Engine::Node2D
  FEET = RGame::Util::Color.rgba(255, 110, 110, 120)

  attr_reader :lives

  def initialize(camera:, **)
    super(**)
    @lives = LIVES
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    # The two lines that differ from `examples/walk`: a shape, and a body told
    # what that shape may not pass through. Everything about the intent — the
    # controller writing it, the sprite reading it back as a facing, the speed it
    # is scaled by — is the same CharacterBody as there.
    @collider = add_component(RGame::Engine::Components::FeetCollider.new(
                                width: FEET_WIDTH, height: FEET_HEIGHT
                              ))
    body = add_component(RGame::Engine::Components::CharacterBody.new(
                           speed: SPEED, blocked_by: %i[tiles spike]
                         ))
    # One handler for everything that can stop a step, because everything that
    # can stop a step reports the same two things. The fence arrives here too, as
    # :tiles with no node behind it, and is ignored.
    body.on_blocked { |by| @lives = [@lives - 1, 0].max if by.layer == :spike }
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: CAMERA_OFFSET_X, offset_y: CAMERA_OFFSET_Y
                  ))
  end

  # Components draw first, so this lands over the sprite. The box's offsets are
  # relative to the node's origin, which is exactly where the renderer already
  # is — a collision box and local space agree about what (0, 0) means.
  def on_draw(renderer, _view)
    box = @collider.box
    renderer.rect(box.offset_x, box.offset_y, box.width, box.height, color: FEET)
  end
end

# The hazard: a box on the `:spike` layer, and a drawing of a ball with spikes on
# it. It has no body and no controller — it never moves — so the only thing it
# contributes to a step is its rectangle, sitting in the broadphase waiting to be
# found.
class SpikyBall < RGame::Engine::Node2D
  BODY = RGame::Util::Color.rgba(190, 90, 210, 255)
  SPIKE = RGame::Util::Color.rgba(120, 40, 140, 255)
  RADIUS = BALL_SIZE / 2.0
  SPIKE_LENGTH = 5

  def initialize(**)
    super
    add_component(RGame::Engine::Components::BoxCollider.new(
                    width: BALL_SIZE, height: BALL_SIZE, layer: :spike
                  ))
  end

  # Local space, like every other on_draw: the node's transform is already
  # pushed, so the ball is drawn around its own origin and lands wherever the
  # node is.
  def on_draw(renderer, _view)
    renderer.line(RADIUS, -SPIKE_LENGTH, RADIUS, BALL_SIZE + SPIKE_LENGTH, thickness: 2.0, color: SPIKE)
    renderer.line(-SPIKE_LENGTH, RADIUS, BALL_SIZE + SPIKE_LENGTH, RADIUS, thickness: 2.0, color: SPIKE)
    renderer.circle(RADIUS, RADIUS, RADIUS, color: BODY)
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
    # The second index, for the things the map knows nothing about. Its cells are
    # sized to the actors rather than to the 16px tiles: a broadphase cell wants
    # to hold a handful of the things it buckets, and these are a dozen pixels
    # across.
    add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 32))

    view = add_node(RGame::Engine::WorldView.new)
    # The node handed back is the gap between the ground layers and anything
    # Tiled flags `above` — where things that walk around belong.
    actors = RGame::Engine::TileMapLayer.mount(view)
    actors.add_node(SpikyBall.new(x: BALL_X, y: BALL_Y))
    @hero = actors.add_node(Hero.new(camera: players.primary.camera, x: START_X, y: START_Y))
    # Built here rather than in on_draw: the interpolation runs once per change of
    # the count, and the frames in between read the string it kept.
    @lives_label = RGame::Engine::CachedLabel.new { |lives| "Lives: #{lives}" }
  end

  # Screen space: outside the WorldView, so it stays put while the map scrolls.
  def on_draw(renderer, _view)
    renderer.text('Arrows / WASD / gamepad to walk — trees and the fence are solid', 12, 12)
    renderer.text('Hold down and left against the fence: you slide to its one gap', 12, 34)
    renderer.text('The red box is what collides. The rest of the sprite is a picture', 12, 56)
    renderer.text('Walk east into the spiky ball: it stops you, and it costs a life', 12, 78)
    renderer.text(@lives_label[@hero.lives], 12, 100)
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
