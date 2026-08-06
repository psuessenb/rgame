# frozen_string_literal: true

module RGame
  module Engine
    # A node whose children live in *world* space and are drawn through a Camera: it
    # wraps their draw in renderer.translated(-camera.x, -camera.y), so the camera's
    # offset maps the world onto the screen. The children never know about the camera —
    # they draw at their own absolute (world) origin, and the view transform does the
    # rest. The owning scene drives the camera (e.g. centring it on the player); this
    # node only applies it.
    #
    # The offset is a draw-time transform, not a position baked into a node, so the same
    # world can later be drawn through several cameras (split-screen) by repeating the
    # pass under different offsets/clips.
    class CameraView < Node2D
      def initialize(camera:, **)
        super(**)
        @camera = camera
      end

      private

      def draw_children(renderer)
        renderer.translated(-@camera.x, -@camera.y) { super }
      end
    end
  end
end
