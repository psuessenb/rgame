# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws a single registered image at its node's origin, placed by `anchor:`
      # (see Engine::Anchor). The default, `:bottom`, puts the image's bottom centre
      # on the origin, where a character stands. A node that rotates passes
      # `anchor: :center`, so it spins in place.
      #
      # It passes NO angle and NO position of its own to the renderer: Node2D#draw
      # has already pushed the node's transform, so drawing against (0, 0) *is*
      # drawing at the node, correctly rotated. Passing either would apply it a
      # second time. The anchor measures from the node's size, which the game sets
      # to the image's.
      #
      # `scale` is writable so a pooled entity (e.g. a multi-tier rock) can retune it on
      # reset, and it scales about the anchor. `z` is the render layer (NOT the node's
      # transform z / abs_z) — kept under @rgame_layer to say so.
      class Sprite < Engine::Component
        include Engine::Culling

        sealed_accessor :scale

        def initialize(id:, scale: 1.0, z: 0, anchor: :bottom)
          super()
          @rgame_id = id
          @rgame_scale = scale
          @rgame_layer = z
          @rgame_anchor = Engine::Anchor.check!(anchor)
        end

        # Placed by the anchor and scaled, so the footprint to cull against is the
        # node's box scaled and moved to where the anchor put it. A node that never
        # set a size is never culled — see Culling.
        #
        # Culling is the one thing here still stated in **world** coordinates:
        # it compares against the camera, which is nowhere near this node's
        # local space. Drawing is local, culling is world, and the two are
        # deliberately different arguments.
        def _draw(renderer, view)
          width = node.width * @rgame_scale
          height = node.height * @rgame_scale
          left = Engine::Anchor.left(@rgame_anchor, width)
          top = Engine::Anchor.top(@rgame_anchor, height) - node.elevation
          return if culled?(view, node.world_x + left, node.world_y + top, width, height)

          renderer.image(@rgame_id, left + (width / 2.0), top + (height / 2.0), scale: @rgame_scale, z: @rgame_layer)
        end
      end
    end
  end
end
