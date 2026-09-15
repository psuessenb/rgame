# frozen_string_literal: true

require 'rgame/core_ext'

module RGame
  module Core
    # A synthetic game controller, for tests that need the real gamepad path
    # with no hardware. It is C (`ext/rgame_core/input/virtual_gamepad.c`, bound
    # in `ruby/virtual_gamepad_ext.c`), and it serves tests, not gameplay.
    #
    #   pad = RGame::Core::VirtualGamepad.new   # an App must be open
    #   pad.set_button(0, true)                  # SDL_CONTROLLER_BUTTON_A
    #   pad.set_axis(0, -32_768)                 # left stick fully left
    #   pad.detach                               # the App sees it unplugged
    #
    # SDL fabricates the device in-process, so the App seats it and raises its
    # `gamepad_connected` and `gamepad_disconnected` callbacks as it would for a
    # real pad. Buttons and axes take SDL's own numbers.
    #
    # It is part of the extension rather than a spec helper because only the
    # extension is guaranteed to reach the SDL the App runs on, whether SDL is
    # linked statically or dynamically.
    class VirtualGamepad
    end
  end
end
