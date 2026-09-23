# frozen_string_literal: true

# One player's character: a sprite, a feet box, a body the map stops, and a
# camera that follows them.
#
# Nothing in it names a player. The room sets `input_owner` once, and
# PlayerController reads whatever that resolves to — which is what lets the same
# class serve both seats with nothing configured.
#
# `blocked_by: [:tiles]` is the whole collision setup for the map. The feet box
# is also what a coin waits for and what the room's broadphase indexes, so one
# shape serves being stopped, being seen and picking things up.
#
# ## A tap opens and a hold searches, on one button
#
# The Interactor reads `:interact`, which this project declares as a tap; the
# hold is `:search` on the same buttons, read here. Both act on the same
# `target`, so the hero asks "what is in reach" once and the input map decides
# which of the two a press meant — see main.rb for the two entries.
class Hero < RGame::Engine::Node2D
  SPEED = 80.0

  FEET_WIDTH  = 12
  FEET_HEIGHT = 6

  CAMERA_OFFSET_X = 8
  CAMERA_OFFSET_Y = 11

  REACH = 48.0

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
    @interactor = add_component(RGame::Engine::Components::Interactor.new(
                                  range: REACH, layer: :interactable
                                ))
    @interactor.on_interacted(&:open)
  end

  def _control(actions)
    @interactor.target&.search if actions.pressed?(:search)
  end
end
