# frozen_string_literal: true

module Platform
  # InputBackend implementation: translates symbolic physical ids (used by the
  # engine's InputMap) into Gosu key constants and queries the window.
  class GosuInput
    BINDINGS = {
      left: Gosu::KB_LEFT,
      right: Gosu::KB_RIGHT,
      up: Gosu::KB_UP,
      down: Gosu::KB_DOWN,
      confirm: Gosu::KB_RETURN,
      fire: Gosu::KB_SPACE,
      pointer: Gosu::MS_LEFT # the click button rides the normal button path
    }.freeze

    def initialize(window)
      @window = window
    end

    # Use the Gosu *module* method, not Window#button_down?: the latter is a deprecated
    # backwards-compat shim (gosu/compat.rb) defined as `|*args, &block|`, whose splat
    # allocates an Array on every call — once per polled key, every frame. The module
    # method is what the shim forwards to anyway, so this is equivalent for our single
    # window but allocation-free.
    def down?(physical_id)
      Gosu.button_down?(BINDINGS.fetch(physical_id))
    end

    # Cursor position, read straight off the window each poll.
    def pointer_x = @window.mouse_x
    def pointer_y = @window.mouse_y
  end
end
