# frozen_string_literal: true

module Engine
  module UI
    # Base for interactive UI widgets: a rectangle that can be hit-tested, enabled
    # or disabled, and focused. Pure logic — it draws through the renderer interface
    # and reads input from the Actions snapshot, never touching Gosu. Concrete
    # widgets (Button, Panel) add their own look and behaviour.
    class Control < Engine::Node
      attr_writer :enabled
      attr_accessor :focused

      def initialize(parent, x:, y:, width:, height:, z: 0, enabled: true)
        super(parent, x: x, y: y, z: z, width: width, height: height)
        @enabled = enabled
        @focused = false
      end

      def enabled? = @enabled
      def focused? = @focused

      # Only enabled controls take focus, so navigation skips disabled ones.
      def focusable? = @enabled

      # Hit-tests against the resolved absolute rect (the parent traversal sets
      # @abs_x/@abs_y before #update runs), since the pointer is in absolute coords.
      def contains?(px, py)
        px >= @abs_x && px < @abs_x + @width && py >= @abs_y && py < @abs_y + @height
      end
    end
  end
end
