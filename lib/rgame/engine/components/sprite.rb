# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Draws a single registered image centered on the node's absolute origin. It
      # passes NO angle to the renderer: Node2D#draw already wraps a node's own draws
      # in renderer.rotated(abs_angle, abs_x, abs_y), so the node's rotation orients
      # the sprite — passing an angle here too would rotate it twice.
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
        def draw(renderer, view)
          width = node.width * @scale
          height = node.height * @scale
          return if culled?(view, node.abs_x - (width / 2.0), node.abs_y - (height / 2.0),
                            width, height)

          renderer.image(@id, node.abs_x, node.abs_y, scale: @scale, z: @layer)
        end
      end
    end
  end
end
