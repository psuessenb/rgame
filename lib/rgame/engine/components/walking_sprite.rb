# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # An AnimatedSprite that walks. It plays walk_left, walk_right, walk_up or
      # walk_down while its node's Mover heads somewhere, and stand while it does
      # not. The larger axis of the heading picks the direction and a tie goes
      # horizontal, so a keyboard diagonal walks sideways and a route running
      # mostly downhill walks down.
      #
      # Any mover will do: a CharacterBody faces its intent, a PathFollow the road
      # it is on. Attach raises for a node with no mover, and for one with two,
      # since there would be no telling which way it faces. It raises too for a
      # sheet missing one of the five animations, rather than on the first step
      # that way.
      class WalkingSprite < AnimatedSprite
        WALKS = %i[stand walk_left walk_right walk_up walk_down].freeze
        private_constant :WALKS

        def initialize(sheet:, z: 0, anchor: :bottom)
          super(sheet:, animation: :stand, z:, anchor:)
        end

        def _attach
          super
          @rgame_mover = require_sibling(Mover)
          WALKS.each { check_animation(it) }
        end

        def _choose_animation
          heading_x = @rgame_mover.heading_x
          heading_y = @rgame_mover.heading_y
          if heading_x.zero? && heading_y.zero? then :stand
          elsif heading_x.abs >= heading_y.abs then heading_x.negative? ? :walk_left : :walk_right
          else heading_y.negative? ? :walk_up : :walk_down
          end
        end
      end
    end
  end
end
