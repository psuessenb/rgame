# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A BoxCollider whose rectangle is the node's *feet*: horizontally centred in the
      # node's dimensions and anchored to their bottom. That is the shape a top-down
      # character collides with — a 16x22 hero standing on a floor occupies the 12x6
      # patch under them, not the whole sprite, which is what stops their head from
      # bumping into a wall a tile away.
      #
      # It is an ordinary BoxCollider in every other respect, so it registers with the
      # scene's CollisionWorld, collides with circles and boxes alike, and
      # `get_component(BoxCollider)` finds it. See docs/api/components.md.
      #
      # The box is derived from `node.width`/`node.height`, which AnimatedSprite sets
      # from the sprite frame, rather than from a sprite size passed in — so the caller
      # gives the feet box and nothing else, and the two can never disagree.
      class FeetCollider < BoxCollider
        def initialize(width:, height:, layer: :default)
          super
          @feet_width = width
          @feet_height = height
          @box = nil
        end

        # The feet box, derived from the node's sprite size and memoised.
        #
        # **Only valid once the node is in the tree**, and it says so rather than letting
        # you find out later. The size comes from AnimatedSprite#on_attach, so a read from
        # a constructor sees a 0x0 node and bakes a box anchored to nothing — permanently,
        # because this memoises. The symptom is an actor that walks through walls it
        # should not, a long way from the call that caused it. Guarding costs one
        # comparison, once.
        #
        # Building it here rather than in on_attach is what makes the order components
        # were added in irrelevant: the first read is a frame later, by which time every
        # sibling has attached. Assigning `box =` still wins, since that leaves nothing
        # to memoise.
        def box
          @box ||= build_box
        end

        private

        def build_box
          if node.width.zero? || node.height.zero?
            raise "FeetCollider needs the node's sprite size, but it is " \
                  "#{node.width}x#{node.height}. AnimatedSprite sets that when it attaches, so " \
                  'read this after the node is in the tree, not while building it.'
          end

          Engine::CollisionBox.bottom_anchored(
            sprite_width: node.width, sprite_height: node.height,
            width: @feet_width, height: @feet_height
          )
        end
      end
    end
  end
end
