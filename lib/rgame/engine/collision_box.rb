# frozen_string_literal: true

module RGame
  module Engine
    # A character's collision rectangle, expressed as an offset + size relative to
    # the actor's top-left origin (the sprite's top-left). Decoupled from sprite
    # size: a 32x32 sprite can have a small 16x16 box at its feet.
    #
    # It is also where rectangle geometry lives, the way CircleCollider owns circle
    # geometry: the overlap tests below are class methods over plain numbers, so the
    # per-frame collision path can call them without building a box first.
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

      # Rect-vs-rect: true when two world-space AABBs overlap in *area*. A shape spans
      # the half-open box [x, x + w), so shapes that merely share an edge are apart —
      # the same convention SDL_HasIntersection uses, and the one thing that makes a
      # grid work: pieces on neighbouring squares border each other constantly, and an
      # inclusive test would report every one of those as a contact.
      def self.overlap?(x1, y1, w1, h1, x2, y2, w2, h2)
        x1 < x2 + w2 && x2 < x1 + w1 && y1 < y2 + h2 && y2 < y1 + h1
      end

      # Rect-vs-circle: true when the circle at (cx, cy) overlaps the rect. Clamping
      # the centre into the rect gives the rect's nearest point to it, so the corner
      # case and the edge case are the same two lines — no per-region analysis, and
      # no sqrt (compare squared distances). Grazing is not overlapping, as above.
      def self.overlap_circle?(x, y, w, h, cx, cy, r)
        nx = cx.clamp(x, x + w)
        ny = cy.clamp(y, y + h)
        dx = cx - nx
        dy = cy - ny
        (dx * dx) + (dy * dy) < r * r
      end

      def initialize(width:, height:, offset_x: 0, offset_y: 0)
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
end
