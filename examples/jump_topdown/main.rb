# frozen_string_literal: true

# Jump top-down — a hop that leaves the ground without leaving its spot on it.
#
# Run it:
#
#   ruby examples/jump_topdown/main.rb
#
# Arrow keys, WASD, a d-pad or a left stick walk the hero; Space or the pad's A
# button hops. The trees and the fence are solid. It exercises:
#   - Components::Hop — a parabola in time, written to the node's elevation;
#   - Node2D#elevation — how far a node's picture is drawn above where it stands;
#   - Components::AnimatedSprite — the picture that rises with it;
#   - Components::FeetCollider and Components::CharacterBody — the shape and the
#     steps that stay on the ground, from `examples/collision_tiles`;
#   - Components::TileWorld and Components::CameraFollow — the map and a camera
#     that does not bob;
#   - InputMap.default.merge — the :jump action this game declares.
#
# ## A jump is a drawing offset
#
# In a top-down view, "up" on the screen is *north*. So a jump cannot move the
# node up the screen: that would be walking north, and the feet box would go with
# it, into whatever is north of the hero. What leaves the ground is the picture.
#
# `Hop` writes its height to `node.elevation`, and `elevation` is not part of the
# transform: `y` does not change, `world_y` does not change, the feet box does not
# move, and neither does the camera following them. `AnimatedSprite` is the one
# thing that reads it, and draws the sprite that far above the spot. Watch the red
# box during a hop — it never leaves the floor, and the shadow sits on it, getting
# smaller as the hero gets further away from it.
#
# ## So a hop does not clear a fence
#
# Walk up to the fence and hop over it. The sprite rises well above it, and the
# hero stops exactly where walking stopped them, because what collides never
# left the ground. That is correct for a hop and would be wrong for a vault, and
# the difference is a decision about the map rather than about the jump.
#
# ## What this does not solve
#
# **Crossing anything.** `hop.airborne?` is the seam for that: a game whose
# chasm tiles should be passable in the air reads it where it decides what is
# solid. `TileWorld` does not consult it, and `Hop` knows nothing about tiles.
# Which tiles a jump clears, and what happens to a hero who lands on one, are
# rules of a particular game, and a jump component that had an opinion about
# them would be wrong for the next game.
#
# **Height against the scenery.** The lifted sprite keeps the draw order it has
# on the ground, so a hop next to a tree still passes behind the canopy that
# would hide the hero walking there. A game with tall jumps would sort by the
# feet and draw the lifted part over the scenery.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/game'

WIDTH  = 640
HEIGHT = 480
ASSETS = File.expand_path('../assets', __dir__)

MAP   = 'town.tmx'
SPEED = 80.0 # px/s

# A hop about as tall as the hero's head, over half a second: enough to read as a
# jump at this sprite size, short enough that it is over before the next press.
HOP_PEAK = 18.0
HOP_DURATION = 0.5

FEET_WIDTH  = 12
FEET_HEIGHT = 6

CAMERA_OFFSET_X = 8
CAMERA_OFFSET_Y = 19

# North of the fence, two tiles above it: one walk down reaches it.
START_X = 384.0
START_Y = 264.0

Controls = RGame::Util::Controls

# A walker from `examples/collision_tiles` with one more component. The only
# drawing it does itself is what stays on the ground: the shadow and the feet box.
class Hero < RGame::Engine::Node2D
  FEET = RGame::Util::Color.rgba(255, 110, 110, 120)
  SHADOW = RGame::Util::Color.rgba(0, 0, 0, 90)

  # The shadow on the ground is an ellipse this wide and tall, and shrinks to half
  # its size once the hero is this far above it.
  SHADOW_RADIUS_X = 7.0
  SHADOW_RADIUS_Y = 3.0
  SHADOW_HALF_AT = 18.0

  attr_reader :hop

  def initialize(camera:, **)
    super(**)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    @collider = add_component(RGame::Engine::Components::FeetCollider.new(
                                width: FEET_WIDTH, height: FEET_HEIGHT
                              ))
    add_component(RGame::Engine::Components::CharacterBody.new(speed: SPEED, blocked_by: [:tiles]))
    add_component(RGame::Engine::Components::PlayerController.new)
    # The one line that differs from `examples/collision_tiles`. It needs nothing
    # from its siblings and none of them know it is here: it writes the node's
    # elevation, and the sprite already draws lifted by whatever that is.
    @hop = add_component(RGame::Engine::Components::Hop.new(peak: HOP_PEAK, duration: HOP_DURATION))
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: CAMERA_OFFSET_X, offset_y: CAMERA_OFFSET_Y
                  ))
  end

  # Both drawn at the feet, and neither reads the node's elevation: this is the
  # part of the hero that is on the ground. The shadow is a circle squashed into an
  # ellipse, so it is placed first and squashed second — squashing first would
  # squash the placement too. It shrinks through the circle's radius rather than
  # the squash, which keeps the ellipse's proportions. `z: -1` puts it under the
  # sprite, which draws at 0.
  def on_draw(renderer, _view)
    box = @collider.box
    shrink = 1.0 / (1.0 + (@hop.height / SHADOW_HALF_AT))
    renderer.translated(box.offset_x + (box.width / 2.0), box.offset_y + (box.height / 2.0)) do
      renderer.scaled(SHADOW_RADIUS_X, SHADOW_RADIUS_Y) do
        renderer.circle(0, 0, shrink, color: SHADOW, z: -1)
      end
    end
    renderer.rect(box.offset_x, box.offset_y, box.width, box.height, color: FEET)
  end
end

# The scene from `examples/collision_tiles`, less the spiky ball.
class Scene < RGame::Engine::Node2D
  STATE = { true => 'In the air', false => 'On the ground' }.freeze

  def on_add
    map = root.context.assets.tilemap(MAP).map
    players = root.system(RGame::Engine::Players)

    add_component(RGame::Engine::Components::TileWorld.new(
                    map: map, tilemap_id: MAP, cameras: players.map(&:camera)
                  ))

    view = add_node(RGame::Engine::WorldView.new)
    actors = RGame::Engine::TileMapLayer.mount(view)
    @hero = actors.add_node(Hero.new(camera: players.primary.camera, x: START_X, y: START_Y))
  end

  def on_draw(renderer, _view)
    renderer.text('Arrows / WASD / gamepad to walk, Space / A to hop', 12, 12)
    renderer.text('The red box stays on the ground. So does everything it collides with', 12, 34)
    renderer.text('Walk south into the fence and hop: the picture clears it, the feet do not', 12, 56)
    renderer.text(STATE[@hero.hop.airborne?], 12, 78)
  end
end

game = RGame::Game.new(
  root: Scene.new,
  caption: 'Jump top-down',
  width: WIDTH,
  height: HEIGHT,
  media_root: ASSETS,
  # :jump is this game's own action. Space is also in the default map as :fire and
  # :ui_confirm, which nothing in this scene reads.
  input_map: RGame::Engine::InputMap.default.merge(
    jump: { buttons: [Controls::KEY_SPACE, Controls::PAD_A] }
  )
)

game.start
