# frozen_string_literal: true

module Engine
  module UI
    # A static 9-slice background — a modal/menu frame. Not focusable; it just
    # draws its texture filling its rect.
    class Panel < Control
      def initialize(parent, x:, y:, width:, height:, texture: :panel, z: 0)
        super(parent, x: x, y: y, width: width, height: height, z: z)
        @texture = texture
      end

      def focusable? = false

      def draw(renderer)
        renderer.nine_slice(@texture, @abs_x, @abs_y, @width, @height, z: @abs_z)
      end
    end
  end
end
