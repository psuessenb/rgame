# frozen_string_literal: true

module TopDownPlatformer
  # One player's character: a walker that hops, falls, comes back and rides what it
  # stands on, and pushes the crate by walking into it.
  #
  # It keeps two status lines for its player's Hud: how often it has fallen, and
  # the last checkpoint it reached. Each is built again as it changes, never while
  # drawing. A Flag calls #reach with its name, after the hero's Respawn has the
  # flag's point.
  class Hero < Engine::Node2D
    SPEED = 80.0

    # A hop from `examples/pits`: 40 px at walking speed.
    HOP_PEAK = 18.0
    HOP_DURATION = 0.5

    FEET_WIDTH  = 12
    FEET_HEIGHT = 6

    # The feet sit at the bottom of the sprite, so the camera looks at its middle.
    CAMERA_OFFSET_Y = -11

    attr_reader :falls_line, :checkpoint_line

    def initialize(camera:, **)
      super(**)
      add_component(Components::AnimatedSprite.new(sheet: 'hero.json'))
      add_component(Components::FeetCollider.new(width: FEET_WIDTH, height: FEET_HEIGHT,
                                                 layer: :hero))
      add_component(Components::CharacterBody.new(speed: SPEED, blocked_by: %i[tiles crate npc],
                                                  pushes: [:crate]))
      add_component(Components::PlayerController.new)
      add_component(Components::Hop.new(peak: HOP_PEAK, duration: HOP_DURATION))
      add_component(Components::Footing.new).on_fell { fell }
      add_component(Components::Respawn.new(flash: 1.0))
      add_component(Components::CameraFollow.new(camera: camera, offset_y: CAMERA_OFFSET_Y))
      @falls = 0
      @falls_line = 'Falls: 0'
      @checkpoint_line = 'Checkpoint: start'
    end

    def reach(name)
      @checkpoint_line = "Checkpoint: #{name}"
    end

    private

    def fell
      @falls += 1
      @falls_line = "Falls: #{@falls}"
    end
  end
end
