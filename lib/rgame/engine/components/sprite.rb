# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws a single registered image centred on the node's own origin. It passes
      # NO angle and NO position to the renderer: Node2D#draw has already pushed the
      # node's transform, so drawing at (0, 0) *is* drawing at the node, correctly
      # rotated. Passing either would apply it a second time.
      #
      # `scale` is writable so a pooled entity (e.g. a multi-tier rock) can retune it on
      # reset. `z` is the render layer (NOT the node's transform z / abs_z) — kept under
      # @layer to say so. For an animated sprite (sheet + frame index driving
      # renderer.sprite), add a sibling AnimatedSprite component later.
      class Sprite < Engine::Component
        include Engine::Culling

        attr_accessor :scale

        def initialize(id:, scale: 1.0, z: 0)
          super()
          @id = id
          @scale = scale
          @layer = z
        end

        # Centred on the node's origin and scaled, so the footprint to cull
        # against is the node's box scaled and offset back by half of itself. A
        # node that never set a size is never culled — see Culling.
        #
        # Culling is the one thing here still stated in **world** coordinates:
        # it compares against the camera, which is nowhere near this node's
        # local space. Drawing is local, culling is world, and the two are
        # deliberately different arguments.
        def draw(renderer, view)
          width = node.width * @scale
          height = node.height * @scale
          return if culled?(view, node.world_x - (width / 2.0), node.world_y - (height / 2.0),
                            width, height)

          renderer.image(@id, 0, 0, scale: @scale, z: @layer)
        end
      end
    end
  end
end
