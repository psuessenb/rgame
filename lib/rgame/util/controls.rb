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

      KEY_RETURN = 40
      KEY_ESCAPE = 41
      KEY_BACKSPACE = 42
      KEY_TAB = 43
      KEY_SPACE = 44

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

      KEY_INSERT = 73
      KEY_HOME = 74
      KEY_PAGEUP = 75
      KEY_DELETE = 76
      KEY_END = 77
      KEY_PAGEDOWN = 78

      KEY_RIGHT = 79
      KEY_LEFT = 80
      KEY_DOWN = 81
      KEY_UP = 82

      KEY_LCTRL = 224
      KEY_LSHIFT = 225
      KEY_LALT = 226
      KEY_RCTRL = 228
      KEY_RSHIFT = 229
      KEY_RALT = 230

      BUTTON_GAMEPAD_FIRST = 0x1000

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

      AXIS_LEFT_X = 0
      AXIS_LEFT_Y = 1
      AXIS_RIGHT_X = 2
      AXIS_RIGHT_Y = 3
      AXIS_TRIGGER_LEFT = 4
      AXIS_TRIGGER_RIGHT = 5

      KEYBOARD = 0
      GAMEPAD_FIRST = 1
      MAX_GAMEPADS = 4

      # The device id for a player slot: gamepad(0) is the first controller.
      def self.gamepad(slot) = GAMEPAD_FIRST + slot

      # Is this *device* a controller rather than the keyboard? What a game asks
      # when the answer changes what it shows the player — the prompt for an
      # action is a key cap or a face button depending on what they last used.
      def self.gamepad?(device) = device >= GAMEPAD_FIRST

      # Is this *button* one a controller has rather than one a keyboard has?
      # The mirror of the question above, on the other id space, and the pair is
      # what lets a caller keep the two apart: an action bound to both lists its
      # keys and its pad buttons together, and only a device can say which half
      # of that list applies right now.
      def self.pad_button?(id) = id >= BUTTON_GAMEPAD_FIRST
    end
  end
end
