# frozen_string_literal: true

module RGame
  module Engine
    # Where a picture sits against its node's origin. `Components::Sprite` and
    # `Components::AnimatedSprite` both take one of three anchors, and both put
    # the picture in the same place for the same anchor and size:
    #
    # - `:center` puts the picture's centre on the origin, so a rotating ship
    #   spins in place.
    # - `:bottom` puts its bottom centre on the origin, so a character's origin
    #   is where they stand.
    # - `:top_left` puts its top-left corner on the origin.
    #
    # `left` and `top` measure the picture's edges from the origin. Both return
    # the Integer `0` for a size of zero, since `-0.0` allocates on every call.
    #
    # @api private
    module Anchor
      NAMES = %i[center bottom top_left].freeze

      # Returns the anchor, or raises ArgumentError naming the three.
      def self.check!(anchor)
        return anchor if NAMES.include?(anchor)

        raise ArgumentError, "anchor: must be one of #{NAMES.inspect}, not #{anchor.inspect}"
      end

      # The picture's left edge, measured from the origin.
      # hot-path
      def self.left(anchor, width)
        return 0 if anchor == :top_left || width.zero?

        -width / 2.0
      end

      # The picture's top edge, measured from the origin.
      # hot-path
      def self.top(anchor, height)
        return 0 if anchor == :top_left || height.zero?

        anchor == :bottom ? -height : -height / 2.0
      end
    end
  end
end
