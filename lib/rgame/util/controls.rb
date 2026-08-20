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
    #   controls = RGame::Util::Controls
    #   map = RGame::Engine::InputMap.default.merge(
    #     fire: { buttons: [controls::KEY_SPACE, controls::PAD_A] }
    #   )
    #
    # This module is the **vocabulary** only. What an id *means* to a game — the
    # binding table — is RGame::Engine::InputMap, one per player, because two
    # players share a game's actions but not the buttons that trigger them.
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
      KEY_F2 = 59
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
    end
  end
end
