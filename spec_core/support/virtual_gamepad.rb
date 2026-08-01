# frozen_string_literal: true

require 'fiddle'

# A synthetic SDL game controller, for specs that need to exercise the real
# gamepad path without hardware.
#
# SDL can fabricate a whole controller in-process. A virtual pad reports
# SDL_IsGameController == 1 and raises genuine CONTROLLERDEVICEADDED/REMOVED
# events, so the engine's hot-plug path runs completely unmodified.
#
# This reaches SDL through Fiddle rather than through the extension, and
# deliberately opens the same libSDL2 the extension already loaded — so it is
# driving the engine's own SDL state, not a second copy.
#
# Unlike synthetic keystrokes (which need X11's XTEST), this works on every
# platform SDL does, because it is an SDL feature rather than an OS one.
class VirtualGamepad
  TYPE_GAMECONTROLLER = 1

  # SDL_CONTROLLER_BUTTON_* / SDL_CONTROLLER_AXIS_* values. The engine asserts
  # its own ids against these at compile time (see gamepad.c), so a mismatch
  # would fail the C build rather than silently confuse a spec.
  BUTTON_A = 0
  BUTTON_DPAD_UP = 11
  BUTTON_DPAD_DOWN = 12
  BUTTON_DPAD_LEFT = 13
  BUTTON_DPAD_RIGHT = 14
  AXIS_LEFT_X = 0
  AXIS_LEFT_Y = 1

  AXIS_COUNT = 6
  BUTTON_COUNT = 21
  AXIS_MAX = 32_767
  AXIS_MIN = -32_768

  SDL = Fiddle.dlopen('libSDL2-2.0.so.0')

  def self.fn(name, args, ret) = Fiddle::Function.new(SDL[name], args, ret)

  ATTACH = fn('SDL_JoystickAttachVirtual', [Fiddle::TYPE_INT] * 4, Fiddle::TYPE_INT)
  DETACH = fn('SDL_JoystickDetachVirtual', [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
  OPEN   = fn('SDL_JoystickOpen', [Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
  CLOSE  = fn('SDL_JoystickClose', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
  SET_BUTTON = fn('SDL_JoystickSetVirtualButton',
                  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], Fiddle::TYPE_INT)
  SET_AXIS = fn('SDL_JoystickSetVirtualAxis',
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_SHORT], Fiddle::TYPE_INT)

  def initialize
    @index = ATTACH.call(TYPE_GAMECONTROLLER, AXIS_COUNT, BUTTON_COUNT, 0)
    raise 'SDL_JoystickAttachVirtual failed' if @index.negative?

    @joystick = OPEN.call(@index)
  end

  def press(button) = SET_BUTTON.call(@joystick, button, 1)
  def release(button) = SET_BUTTON.call(@joystick, button, 0)
  def move_axis(axis, value) = SET_AXIS.call(@joystick, axis, value)

  # Unplugging the pad, as far as SDL and the engine are concerned.
  def detach
    return if @detached

    CLOSE.call(@joystick)
    DETACH.call(@index)
    @detached = true
  end
end
