# frozen_string_literal: true

# One player's character: a sprite, a feet box, a body the map stops, and a
# camera that follows them.
#
# Nothing in it names a player. The room sets `input_owner` once, and
# PlayerController reads whatever that resolves to — which is what lets the same
# class serve both seats with nothing configured.
#
# `blocked_by: [:tiles]` is the whole collision setup. The room mounts a
# TileWorld, the feet box is the shape that world stops, and there is no second
# index because nothing else here collides.
class Hero < RGame::Engine::Node2D
  SPEED = 80.0

  FEET_WIDTH  = 12
  FEET_HEIGHT = 6

  CAMERA_OFFSET_X = 8
  CAMERA_OFFSET_Y = 11

  def initialize(camera:, **)
    super(**)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::FeetCollider.new(
                    width: FEET_WIDTH, height: FEET_HEIGHT, layer: :hero
                  ))
    add_component(RGame::Engine::Components::CharacterBody.new(
                    speed: SPEED, blocked_by: [:tiles]
                  ))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: CAMERA_OFFSET_X, offset_y: CAMERA_OFFSET_Y
                  ))
  end
end
