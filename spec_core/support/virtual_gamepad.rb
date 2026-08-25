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

  # dlopen must find the copy SDL *already loaded* rather than open a second
  # one, so the name has to match this platform's actual shared-library name.
  #
  # macOS is the exception, and it needs no name at all. dyld has nothing like
  # Linux's ldconfig cache, so a bare `libSDL2-2.0.0.dylib` is looked for only
  # in /usr/lib and the dyld shared cache — never in Homebrew's prefix, which
  # is where SDL2 actually lives and which differs between Apple Silicon
  # (/opt/homebrew) and Intel (/usr/local). Rather than guess a prefix,
  # `Fiddle::Handle::DEFAULT` searches the images already loaded into this
  # process, which is a *stronger* guarantee than any filename: the extension
  # links SDL2, so the only copy this can resolve is the one the engine is
  # already driving. It does mean the extension has to be loaded first —
  # core_spec_helper.rb requires `rgame/core` before this file, and getting
  # that wrong fails loudly here with an unknown-symbol DLError rather than
  # quietly opening a second SDL.
  #
  # Linux and Windows keep by-name dlopen, which is measured working on both.
  # A platform-specific problem gets a platform-specific fix — see
  # docs/plans/cross-platform-support.md, B9, for what generalising one costs.
  SDL =
    case RbConfig::CONFIG['host_os']
    when /darwin/ then Fiddle::Handle::DEFAULT
    when /mswin|mingw|cygwin/ then Fiddle.dlopen('SDL2.dll')
    else Fiddle.dlopen('libSDL2-2.0.so.0')
    end

  def self.fn(name, args, ret) = Fiddle::Function.new(SDL[name], args, ret)

  ATTACH = fn('SDL_JoystickAttachVirtual', [Fiddle::TYPE_INT] * 4, Fiddle::TYPE_INT)
  DETACH = fn('SDL_JoystickDetachVirtual', [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
  OPEN   = fn('SDL_JoystickOpen', [Fiddle::TYPE_INT], Fiddle::TYPE_VOIDP)
  CLOSE  = fn('SDL_JoystickClose', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
  SET_BUTTON = fn('SDL_JoystickSetVirtualButton',
                  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_CHAR], Fiddle::TYPE_INT)
  SET_AXIS = fn('SDL_JoystickSetVirtualAxis',
                [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_SHORT], Fiddle::TYPE_INT)

  # Diagnostics, not drivers. The engine reads a pad through
  # SDL_GameControllerGetButton, which is the *mapped* view: SDL turns a
  # joystick button number into a named controller button using a mapping it
  # synthesises for a virtual device. So "the press did not arrive" has two
  # very different causes, and these two tell them apart — which matters
  # because the failure only reproduces on a runner nobody can attach a
  # debugger to (see docs/plans/cross-platform-support.md, B15).
  #
  #   raw_down?       the *unmapped* joystick button. True here but false
  #                   through the engine means the mapping is wrong.
  #   game_controller? whether SDL will treat the device as a controller at
  #                   all. False means there is no mapping, so the engine
  #                   declines to seat it (see rgame_gamepads_add).
  GET_BUTTON = fn('SDL_JoystickGetButton',
                  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_CHAR)
  IS_GAMECONTROLLER = fn('SDL_IsGameController', [Fiddle::TYPE_INT], Fiddle::TYPE_INT)

  def initialize
    @index = ATTACH.call(TYPE_GAMECONTROLLER, AXIS_COUNT, BUTTON_COUNT, 0)
    raise 'SDL_JoystickAttachVirtual failed' if @index.negative?

    @joystick = OPEN.call(@index)
  end

  def press(button) = SET_BUTTON.call(@joystick, button, 1)
  def release(button) = SET_BUTTON.call(@joystick, button, 0)
  def move_axis(axis, value) = SET_AXIS.call(@joystick, axis, value)

  # See GET_BUTTON / IS_GAMECONTROLLER above for why these exist.
  def raw_down?(button) = GET_BUTTON.call(@joystick, button) == 1
  def game_controller? = IS_GAMECONTROLLER.call(@index) == 1

  # Unplugging the pad, as far as SDL and the engine are concerned.
  def detach
    return if @detached

    CLOSE.call(@joystick)
    DETACH.call(@index)
    @detached = true
  end
end
