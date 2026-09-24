# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A BoxCollider whose rectangle is the node's *feet*: centred across the node's
      # origin, with its bottom edge on it. That is the shape a top-down character
      # collides with — a hero standing on a floor occupies the 12x6 patch under them,
      # not the whole sprite, which is what stops their head from bumping into a wall a
      # tile away.
      #
      # The node's origin is where it stands, because Sprite and AnimatedSprite draw
      # anchored at `:bottom` by default. So the box needs nothing but its own size, and
      # it is right from construction, before the node has a size or a parent.
      #
      # It is an ordinary BoxCollider in every other respect, so it registers with the
      # scene's CollisionWorld, collides with circles and boxes alike, and
      # `get_component(BoxCollider)` finds it. See docs/api/components.md.
      class FeetCollider < BoxCollider
        def initialize(width:, height:, layer: :default)
          super(width:, height:, offset_x: -width / 2.0, offset_y: -height, layer:)
        end
      end
    end
  end
end
