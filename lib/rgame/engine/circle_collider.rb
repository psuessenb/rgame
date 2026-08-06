# frozen_string_literal: true

module RGame
  module Engine
    # A circular collision shape, the sibling of CollisionBox for entities that
    # rotate (rocks, ship): a circle is rotation-invariant, so a spinning rock needs
    # no per-frame box recompute. The collider owns only the radius; the entity owns
    # its centre position. Pure logic; no Gosu.
    class CircleCollider
      attr_reader :radius

      # Squared-distance overlap test (no sqrt): true when two circles touch.
      def self.overlap?(x1, y1, r1, x2, y2, r2)
        dx = x2 - x1
        dy = y2 - y1
        sum = r1 + r2
        (dx * dx) + (dy * dy) <= sum * sum
      end

      def initialize(radius:)
        @radius = radius
      end

      # Bounding AABB [x, y, w, h] for a circle centred at (cx, cy) — what the
      # spatial hash buckets on.
      def aabb(cx, cy)
        d = @radius * 2
        [cx - @radius, cy - @radius, d, d]
      end
    end
  end
end
