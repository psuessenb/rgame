# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws a sprite-sheet animation for a walking actor, picking the animation from its
      # Mover sibling's heading: walk_left/right/up/down while moving, stand when still. The
      # larger axis of the heading picks the direction and a tie goes horizontal, so a
      # keyboard diagonal walks sideways and a route running mostly downhill walks down.
      # Any mover will do — a CharacterBody faces its intent, a PathFollow the road it is
      # on — and a node with two movers raises at attach, since there would be no telling
      # which way it faces. Owns its Animator + the pure AnimationSet built from the sheet's
      # animation table.
      #
      # Like Sprite, it places its frame against the node's origin by `anchor:` (see
      # Engine::Anchor). The default, `:bottom`, stands the character on the origin,
      # which is where a FeetCollider puts its box. It passes NO angle and NO
      # position of its own: (0, 0) is what
      # Node2D#draw has already made mean "at this node, correctly rotated", and a
      # WorldView ancestor has already made mean "through the camera". `z` is the
      # render layer (kept as @rgame_layer, distinct from the node's transform z); it must
      # sit between the tile map's ground and canopy z bands, so canopies draw in
      # front.
      #
      # `sheet` is the asset's relative path. The component resolves it from the game's
      # asset manager on attach — via node.root.context.assets (the platform seam) — to
      # build its animation table and to size the node to the sprite's frame, which the
      # anchor and culling measure from. The renderer resolves the same
      # symbol when drawing, so nothing is registered or passed in by hand.
      class AnimatedSprite < Engine::Component
        include Engine::Culling

        def initialize(sheet:, z: 0, anchor: :bottom)
          super()
          @rgame_sheet = sheet
          @rgame_layer = z
          @rgame_anchor = Engine::Anchor.check!(anchor)
        end

        def _attach
          sheet = context.assets.sheet(@rgame_sheet)
          @rgame_animator = Engine::Animator.new(Engine::AnimationSet.new(sheet.animations))
          node.width = sheet.frame_width
          node.height = sheet.frame_height
          @rgame_mover = require_sibling(Mover)
        end

        def _update(dt)
          @rgame_animator.play(walk_animation(@rgame_mover.heading_x, @rgame_mover.heading_y))
          @rgame_animator.update(dt)
        end

        # Placed by the anchor, sized by the sheet's frame and lifted by the node's
        # elevation — so the footprint to cull against is the node's box, moved and
        # raised the same way the picture is.
        def _draw(renderer, view)
          left = Engine::Anchor.left(@rgame_anchor, node.width)
          top = Engine::Anchor.top(@rgame_anchor, node.height) - node.elevation
          return if culled?(view, node.world_x + left, node.world_y + top, node.width, node.height)

          renderer.sprite(@rgame_sheet, @rgame_animator.row, @rgame_animator.col, left, top,
                          flip_x: @rgame_animator.flip_x, z: @rgame_layer)
        end

        private

        def walk_animation(heading_x, heading_y)
          if heading_x.zero? && heading_y.zero? then :stand
          elsif heading_x.abs >= heading_y.abs then heading_x.negative? ? :walk_left : :walk_right
          else heading_y.negative? ? :walk_up : :walk_down
          end
        end
      end
    end
  end
end
