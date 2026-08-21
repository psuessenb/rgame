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
      # --- Keyboard. Values are SDL scancodes, which name a physical *position*
      # rather than a letter: KEY_A is the key marked A on a QWERTY board and Q
      # on AZERTY. A game rebinding controls shows the player what their layout
      # calls it; the engine only ever compares numbers. ---
      #
      # The set is what a Western keyboard can be relied on to have. No numpad
      # (most laptops have none), no GUI/Windows/Command key, no print-screen
      # cluster, and nothing whose position depends on the layout.

      # Letters. Scancodes are physical *positions*, so KEY_A is the key marked A on
      # a QWERTY board and Q on AZERTY.
      KEY_A = 4
      KEY_B = 5
      KEY_C = 6
      KEY_D = 7
      KEY_E = 8
      KEY_F = 9
      KEY_G = 10
      KEY_H = 11
      KEY_I = 12
      KEY_J = 13
      KEY_K = 14
      KEY_L = 15
      KEY_M = 16
      KEY_N = 17
      KEY_O = 18
      KEY_P = 19
      KEY_Q = 20
      KEY_R = 21
      KEY_S = 22
      KEY_T = 23
      KEY_U = 24
      KEY_V = 25
      KEY_W = 26
      KEY_X = 27
      KEY_Y = 28
      KEY_Z = 29

      # Digits along the top row.
      KEY_1 = 30
      KEY_2 = 31
      KEY_3 = 32
      KEY_4 = 33
      KEY_5 = 34
      KEY_6 = 35
      KEY_7 = 36
      KEY_8 = 37
      KEY_9 = 38
      KEY_0 = 39

      # Editing and whitespace.
      KEY_RETURN = 40
      KEY_ESCAPE = 41
      KEY_BACKSPACE = 42
      KEY_TAB = 43
      KEY_SPACE = 44

      # Punctuation, by position on a US board.
      KEY_MINUS = 45
      KEY_EQUALS = 46
      KEY_LEFTBRACKET = 47
      KEY_RIGHTBRACKET = 48
      KEY_BACKSLASH = 49
      KEY_SEMICOLON = 51
      KEY_APOSTROPHE = 52
      KEY_GRAVE = 53
      KEY_COMMA = 54
      KEY_PERIOD = 55
      KEY_SLASH = 56

      # Function row and caps lock.
      KEY_CAPSLOCK = 57
      KEY_F1 = 58
      KEY_F2 = 59
      KEY_F3 = 60
      KEY_F4 = 61
      KEY_F5 = 62
      KEY_F6 = 63
      KEY_F7 = 64
      KEY_F8 = 65
      KEY_F9 = 66
      KEY_F10 = 67
      KEY_F11 = 68
      KEY_F12 = 69

      # The navigation cluster.
      KEY_INSERT = 73
      KEY_HOME = 74
      KEY_PAGEUP = 75
      KEY_DELETE = 76
      KEY_END = 77
      KEY_PAGEDOWN = 78

      # Arrows.
      KEY_RIGHT = 79
      KEY_LEFT = 80
      KEY_DOWN = 81
      KEY_UP = 82

      # Modifiers. No GUI key: that is Windows on a PC and Command on a Mac, which
      # is exactly the platform-specific territory this list stays out of.
      KEY_LCTRL = 224
      KEY_LSHIFT = 225
      KEY_LALT = 226
      KEY_RCTRL = 228
      KEY_RSHIFT = 229
      KEY_RALT = 230

      # --- Gamepad buttons. The gamepad range plus SDL's own controller button
      # number. The first fifteen are on every controller; MISC1, the paddles
      # and TOUCHPAD are hardware the id space describes but most pads do not
      # have, and read as never pressed on one that does not. ---
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
      PAD_MISC1 = 4111
      PAD_PADDLE1 = 4112
      PAD_PADDLE2 = 4113
      PAD_PADDLE3 = 4114
      PAD_PADDLE4 = 4115
      PAD_TOUCHPAD = 4116

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
