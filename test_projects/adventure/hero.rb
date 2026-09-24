# frozen_string_literal: true

# One player's character: a sprite, a feet box, a body the map stops, and a
# camera that follows them.
#
# Nothing in it names a player. The room sets `input_owner` once, and
# PlayerController reads whatever that resolves to — which is what lets the same
# class serve both seats with nothing configured.
#
# `blocked_by: %i[tiles crate]` is the whole collision setup, and `pushes:
# [:crate]` turns the crates from walls into things that move. The feet box is
# also what a coin waits for and what the room's broadphase indexes, so one shape
# serves being stopped, pushing, being seen and picking things up.
#
# A Grab on the default `:grab` action, Left Shift or the pad's Y, drags a crate
# the other way. It is a Targeting, as the Interactor is, so the hero holds each
# by name rather than asking for a Targeting.
#
# ## A tap opens and a hold searches, on one button
#
# The Interactor reads `:interact`, which this project declares as a tap; the
# hold is `:search` on the same buttons, read here. Both act on the same
# `target`, so the hero asks "what is in reach" once and the input map decides
# which of the two a press meant — see main.rb for the two entries.
#
# ## What it carries and wears
#
# The hero owns both lists, and `carry` is the one way in: a coin calls it on
# whoever touched it, and a search carries what the chest gave. The player's Bag
# reads `carried` and `worn` and calls `wear` and `take_off`. The hero draws
# what it wears over its sprite, and names it in words above its head, as the
# chest and the crate draw their state.
class Hero < RGame::Engine::Node2D
  SLOTS = %i[head].freeze

  SPEED = 80.0

  FEET_WIDTH  = 12
  FEET_HEIGHT = 6

  CAMERA_OFFSET_X = 8
  CAMERA_OFFSET_Y = 11

  REACH = 48.0
  GRIP = 32.0

  HAT_WIDTH = 14
  HAT_HEIGHT = 4

  def initialize(camera:, **)
    super(**)
    add_component(RGame::Engine::Components::AnimatedSprite.new(sheet: 'hero.json'))
    add_component(RGame::Engine::Components::FeetCollider.new(
                    width: FEET_WIDTH, height: FEET_HEIGHT, layer: :hero
                  ))
    add_component(RGame::Engine::Components::CharacterBody.new(
                    speed: SPEED, blocked_by: %i[tiles crate], pushes: [:crate]
                  ))
    add_component(RGame::Engine::Components::PlayerController.new)
    add_component(RGame::Engine::Components::CameraFollow.new(
                    camera: camera, offset_x: CAMERA_OFFSET_X, offset_y: CAMERA_OFFSET_Y
                  ))
    @interactor = add_component(RGame::Engine::Components::Interactor.new(
                                  range: REACH, layer: :interactable
                                ))
    @interactor.on_interacted(&:open)
    add_component(RGame::Engine::Components::Grab.new(range: GRIP, layer: :crate))
    @carried = []
    @worn = {}
    @revision = 0
  end

  # `carried` is every Item held and not worn, in the order it came. `worn`
  # maps a slot to the Item it wears. `revision` counts the changes to either,
  # so a reader can tell whether what it last read is still true.
  attr_reader :carried, :worn, :revision

  def carry(item)
    @carried << item
    @revision += 1
  end

  # Wears `item` from what is carried, and carries whatever its slot wore.
  def wear(item)
    @carried.delete_at(@carried.index(item))
    take_off(item.slot)
    @worn[item.slot] = item
    @revision += 1
  end

  def take_off(slot)
    item = @worn.delete(slot)
    carry(item) if item
  end

  def _control(actions)
    return unless actions.pressed?(:search)

    found = @interactor.target&.search
    carry(found) if found
  end

  def _draw(renderer, _view)
    hat = @worn[:head]
    return unless hat

    renderer.rect(1, 0, HAT_WIDTH, HAT_HEIGHT, z: 1, color: hat.color)
    renderer.text(hat.name, 0, -12)
  end
end
