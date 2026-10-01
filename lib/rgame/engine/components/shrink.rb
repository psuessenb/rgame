# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A fall that looks like the node dropping out of sight: it shrinks the node
      # through Node2D#scale from the scale it found toward 0, easing in, then gives
      # that scale back. The shrink runs toward the node's origin, where a character
      # stands, so it drops into the ground at its feet.
      #
      #   hero.add_component(Fall.new)
      #   hero.add_component(Shrink.new)
      #
      # The node's Fall runs it, as a Components::FallLook. It gives the scale back
      # as the fall ends, and as it leaves its node mid-fall.
      class Shrink < FallLook
        def initialize
          super
          @rgame_found = nil
        end

        def start
          @rgame_found = node.scale
        end

        # hot-path
        def show(progress)
          node.scale = @rgame_found * (1 - (progress * progress))
        end

        def finish
          return unless @rgame_found

          node.scale = @rgame_found
          @rgame_found = nil
        end

        def _detach = finish
      end
    end
  end
end
