# frozen_string_literal: true

module Engine
  # A character's collision rectangle, expressed as an offset + size relative to
  # the actor's top-left origin (the sprite's top-left). Decoupled from sprite
  # size: a 32x32 sprite can have a small 16x16 box at its feet.
  class CollisionBox
    attr_reader :offset_x, :offset_y, :width, :height

    # Centre the box horizontally and anchor it to the bottom of the sprite (feet).
    def self.bottom_anchored(sprite_width:, sprite_height:, width:, height:)
      new(
        offset_x: (sprite_width - width) / 2,
        offset_y: sprite_height - height,
        width: width,
        height: height
      )
    end

    def initialize(offset_x:, offset_y:, width:, height:)
      @offset_x = offset_x
      @offset_y = offset_y
      @width = width
      @height = height
    end

    # World-space AABB [x, y, w, h] for an actor whose origin is at (x, y).
    def aabb(x, y)
      [x + @offset_x, y + @offset_y, @width, @height]
    end
  end
end
