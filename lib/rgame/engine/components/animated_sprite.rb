# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws a sprite-sheet animation for a walking actor, picking the animation from a
      # CharacterBody sibling's movement intent: walk_left/right/up/down while moving
      # (horizontal wins on a diagonal), stand when still. Owns its Animator + the pure
      # AnimationSet built from the sheet's animation table.
      #
      # Like Sprite, it passes NO angle and draws at the node's *world* origin
      # (node.abs_x/abs_y): a WorldView ancestor wraps the draw in renderer.translated to
      # map world → screen, so this component never touches the camera. `z` is the render
      # layer (kept as @layer, distinct from the node's transform z); it must sit between
      # the tile map's ground and canopy z bands, so canopies draw in front.
      #
      # `sheet` is the asset's relative path. The component resolves it from the game's
      # asset manager on attach — via node.root.context.assets (the platform seam) — to
      # build its animation table and to size the node to the sprite's frame, so siblings
      # like CharacterBody can read node.width/height. The renderer resolves the same
      # symbol when drawing, so nothing is registered or passed in by hand.
      class AnimatedSprite < Engine::Component
        include Engine::Culling

        def initialize(sheet:, z: 0)
          super()
          @sheet = sheet
          @layer = z
        end

        def on_attach
          sheet = context.assets.sheet(@sheet)
          @animator = Engine::Animator.new(Engine::AnimationSet.new(sheet.animations))
          node.width = sheet.frame_width
          node.height = sheet.frame_height
          @body = require_sibling(CharacterBody)
        end

        def update(dt)
          @animator.play(walk_animation(@body.move_x, @body.move_y))
          @animator.update(dt)
        end

        # Top-left anchored, and sized by the sheet's frame — so the footprint
        # to cull against is exactly the node's box.
        def draw(renderer, view)
          return if culled?(view, node.abs_x, node.abs_y, node.width, node.height)

          # Read row/col/flip_x separately (not @animator.frame, which allocates an Array
          # every call) to keep the draw path allocation-free.
          renderer.sprite(@sheet, @animator.row, @animator.col, node.abs_x, node.abs_y,
                          flip_x: @animator.flip_x, z: @layer)
        end

        private

        # Horizontal movement wins over vertical, so a diagonal walk faces left/right.
        def walk_animation(move_x, move_y)
          if move_x.negative? then :walk_left
          elsif move_x.positive? then :walk_right
          elsif move_y.negative? then :walk_up
          elsif move_y.positive? then :walk_down
          else :stand
          end
        end
      end
    end
  end
end
