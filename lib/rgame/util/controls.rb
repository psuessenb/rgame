# frozen_string_literal: true

module RGame
  module Util
    # The vocabulary of physical inputs: which integer means "the left arrow
    # key", "the A button", "the left stick's X axis", "player 2's controller".
    #
    # These are values — plain integers with no window, GPU or OS handle behind
    # them — so they live in Util rather than Core. That is what lets the engine
    # layer and a game's own configuration name a physical input without
    # touching RGame::Core, which they may not do:
    #
    #   bindings = Controls::DEFAULT_KEYBOARD.merge(fire: Controls::KEY_J)
    #   RGame::Core::Input.new(app, bindings: bindings)
    #
    # The same numbers exist as `#define`s in
    # ext/rgame_core/include/rgame/core.h, because the C engine and the
    # standalone binary need them too and cannot see Ruby. Two definitions means
    # a drift risk, so it is checked: the C side is tied to SDL's own scancodes
    # by _Static_assert at compile time, and spec/rgame/util/controls_spec.rb
    # parses that header and compares every value here against it.
    module Controls
      # --- Keyboard. Values are SDL scancodes. ---
      KEY_RETURN = 40
      KEY_ESCAPE = 41
      KEY_SPACE = 44
      KEY_F1 = 58
      KEY_RIGHT = 79
      KEY_LEFT = 80
      KEY_DOWN = 81
      KEY_UP = 82

      # --- Gamepad buttons. The gamepad range plus SDL's controller button. ---
      PAD_A = 4096
      PAD_B = 4097
      PAD_X = 4098
      PAD_Y = 4099
      PAD_BACK = 4100
      PAD_GUIDE = 4101
      PAD_START = 4102
      PAD_LEFT_STICK = 4103
      PAD_RIGHT_STICK = 4104
      PAD_LEFT_SHOULDER = 4105
      PAD_RIGHT_SHOULDER = 4106
      PAD_DPAD_UP = 4107
      PAD_DPAD_DOWN = 4108
      PAD_DPAD_LEFT = 4109
      PAD_DPAD_RIGHT = 4110

      # --- Analog axes. Their own small space: they are float-valued and read
      # through a different call, so folding them into the button space would
      # only invite asking for an axis as if it were a button. ---
      AXIS_LEFT_X = 0
      AXIS_LEFT_Y = 1
      AXIS_RIGHT_X = 2
      AXIS_RIGHT_Y = 3
      AXIS_TRIGGER_LEFT = 4
      AXIS_TRIGGER_RIGHT = 5

      # --- Devices. The keyboard is 0 so single-player code can leave it out;
      # gamepads follow, one per player slot. ---
      KEYBOARD = 0
      GAMEPAD_FIRST = 1
      MAX_GAMEPADS = 4

      # The device id for a player slot: gamepad(0) is the first controller.
      def self.gamepad(slot) = GAMEPAD_FIRST + slot

      # --- Default bindings ---
      #
      # Symbolic action => physical input. Games override these to rebind; they
      # are values, so a config screen can build its own table from the
      # constants above and hand it to the input layer.
      #
      # Two button tables rather than one, because the same action is a
      # different physical input per device class: :fire is the space bar on a
      # keyboard and the A button on a pad.
      DEFAULT_KEYBOARD = {
        left: KEY_LEFT,
        right: KEY_RIGHT,
        up: KEY_UP,
        down: KEY_DOWN,
        confirm: KEY_RETURN,
        fire: KEY_SPACE
      }.freeze

      DEFAULT_PAD = {
        left: PAD_DPAD_LEFT,
        right: PAD_DPAD_RIGHT,
        up: PAD_DPAD_UP,
        down: PAD_DPAD_DOWN,
        confirm: PAD_A,
        fire: PAD_A
      }.freeze

      # Analog axes exist only on pads, so there is one table.
      DEFAULT_AXES = {
        move_x: AXIS_LEFT_X,
        move_y: AXIS_LEFT_Y,
        aim_x: AXIS_RIGHT_X,
        aim_y: AXIS_RIGHT_Y,
        trigger_left: AXIS_TRIGGER_LEFT,
        trigger_right: AXIS_TRIGGER_RIGHT
      }.freeze
    end
  end
end
