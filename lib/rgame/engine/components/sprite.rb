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
        attr_accessor :scale

        def initialize(id:, scale: 1.0, z: 0)
          super()
          @id = id
          @scale = scale
          @layer = z
        end

        def draw(renderer, _view)
          renderer.image(@id, node.abs_x, node.abs_y, scale: @scale, z: @layer)
        end
      end
    end
  end
end
