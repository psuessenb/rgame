# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws a sprite-sheet animation: the one it is given, until `play` names
      # another. It needs no sibling, so a spinning coin is this and a collider.
      #
      # **A subclass chooses through `_choose_animation`**, which `_update`
      # calls before it advances the frame. The choice and its first frame then
      # land on the same tick, whatever order the node's components were added
      # in. WalkingSprite chooses a walk from its node's Mover this way.
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

        hook :_choose_animation

        # `animation` is the one it plays first. Attach raises ArgumentError when
        # the sheet has no animation of that name, listing the ones it has.
        def initialize(sheet:, animation:, z: 0, anchor: :bottom)
          super()
          @rgame_sheet = sheet
          @rgame_animation = animation
          @rgame_layer = z
          @rgame_anchor = Engine::Anchor.check!(anchor)
        end

        # The animation playing now.
        sealed_reader :animation

        # Plays `name` from its first frame, or carries on when `name` is already
        # playing. Once attached, raises ArgumentError for a name the sheet lacks.
        def play(name)
          return if name == @rgame_animation

          check_animation(name) if @rgame_animator
          @rgame_animation = name
          @rgame_animator&.play(name)
        end

        def _attach
          sheet = context.assets.sheet(@rgame_sheet)
          @rgame_animations = Engine::AnimationSet.new(sheet.animations)
          check_animation(@rgame_animation)
          @rgame_animator = Engine::Animator.new(@rgame_animations, initial: @rgame_animation)
          node.width = sheet.frame_width
          node.height = sheet.frame_height
        end

        def _update(dt)
          chosen = _choose_animation
          play(chosen) if chosen
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

        # The animation to play this update, or nil to carry on. A subclass
        # answers from its node's state, and the frame it picks draws on the
        # same tick.
        def _choose_animation = nil

        private

        def check_animation(name)
          return if @rgame_animations.include?(name)

          raise ArgumentError, "#{self.class}: the sheet #{@rgame_sheet.inspect} has no animation " \
                               "#{name.inspect}. It has #{@rgame_animations.names.map(&:inspect).join(', ')}."
        end
      end
    end
  end
end
