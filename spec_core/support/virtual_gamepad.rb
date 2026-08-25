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

  # Setting a virtual button or axis only writes *pending* state: SDL applies it
  # to the device — and so makes it readable, mapped or unmapped — on the next
  # SDL_JoystickUpdate. Measured, because it is invisible until it bites: with
  # this call, 40 of 40 attach/press/read cycles read the press back; without
  # it, 0 of 40 did.
  #
  # Nothing here used to make that call, so every press depended on the
  # engine's own `SDL_PollEvent` loop pumping between the press and the read.
  # Driving the update here instead takes the harness's own synthetic input off
  # the engine's pump schedule, which it had no business depending on.
  #
  # **This is a real removed dependency, not a fix for the flake in B15.** Said
  # plainly because the two are easy to confuse: these examples still failed
  # once in roughly twenty full runs *after* this call was added, so whatever
  # makes them flaky is still open (docs/plans/cross-platform-support.md, B15).
  #
  # It is not a weakening of what these specs check: the engine still reads
  # through SDL_GameControllerGetButton, so seating and the controller mapping
  # are exercised exactly as before. *When SDL applies pending virtual state* is
  # a property of the fake device, and making that deterministic is the
  # harness's job either way.
  UPDATE = fn('SDL_JoystickUpdate', [], Fiddle::TYPE_VOID)

  # The three facts B15 still needs and nothing was keeping. All cheap, and
  # each one kills or confirms a specific surviving hypothesis:
  #
  #   GET_ATTACHED  is this handle still a live device? The main surviving
  #                 theory is a stale handle — an earlier example's pad not
  #                 detaching cleanly, so the press goes to a device SDL has
  #                 already dropped while the engine has a different one open.
  #   set result    SDL_JoystickSetVirtualButton returns non-zero on failure,
  #                 and every caller here has been throwing that away.
  #   GET_ERROR     what SDL says when it does refuse.
  GET_ATTACHED = fn('SDL_JoystickGetAttached', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  GET_ERROR = fn('SDL_GetError', [], Fiddle::TYPE_VOIDP)
  PUMP = fn('SDL_PumpEvents', [], Fiddle::TYPE_VOID)

  # How many update passes a press gets before the harness gives up on it. One
  # is enough on every machine measured; more exist because the macOS runner
  # reports a press SDL *accepted* (`SDL_JoystickSetVirtualButton` returned 0,
  # on a device `SDL_JoystickGetAttached` calls live) and then never applied,
  # and a bounded retry is the cheapest thing that distinguishes "slow" from
  # "never" — see docs/plans/cross-platform-support.md, B15.
  APPLY_ATTEMPTS = 10

  def initialize
    @index = ATTACH.call(TYPE_GAMECONTROLLER, AXIS_COUNT, BUTTON_COUNT, 0)
    raise 'SDL_JoystickAttachVirtual failed' if @index.negative?

    @joystick = OPEN.call(@index)
  end

  # Each of these applies its own change (see UPDATE above), so the state is
  # live by the time the call returns rather than whenever SDL is next pumped.
  def press(button) = set_button(button, 1)
  def release(button) = set_button(button, 0)

  def move_axis(axis, value)
    @last_set_result = SET_AXIS.call(@joystick, axis, value)
    UPDATE.call
    @last_set_result
  end

  # See GET_BUTTON / IS_GAMECONTROLLER / GET_ATTACHED above for why these exist.
  def raw_down?(button) = GET_BUTTON.call(@joystick, button) == 1
  def game_controller? = IS_GAMECONTROLLER.call(@index) == 1
  def attached? = GET_ATTACHED.call(@joystick) == 1
  def sdl_error = GET_ERROR.call.to_s

  # Non-zero means SDL refused the last press/release/axis outright. Nil until
  # something has been set.
  attr_reader :last_set_result

  # How many update passes the last button press or release needed before SDL
  # actually applied it, and whether it ever did. `nil` until a button has been
  # set; `applied` false means SDL accepted the call and never honoured it,
  # which is the state B15 is chasing.
  attr_reader :apply_attempts, :applied

  # Unplugging the pad, as far as SDL and the engine are concerned.
  def detach
    return if @detached

    CLOSE.call(@joystick)
    DETACH.call(@index)
    @detached = true
  end

  private

  # Sets the button and then makes sure SDL has actually applied it, rather than
  # trusting one update pass to be enough. Deliberately does *not* raise on
  # failure: this runs inside the engine's draw callback, and an exception there
  # unwinds through the C frame loop — which is why input_spec.rb collects
  # results and asserts afterwards. A press that never lands is recorded and
  # left for the example's own expectations to report.
  def set_button(button, value)
    @last_set_result = SET_BUTTON.call(@joystick, button, value)
    want = value == 1
    @apply_attempts = 0
    @applied = false
    APPLY_ATTEMPTS.times do
      @apply_attempts += 1
      UPDATE.call
      if raw_down?(button) == want
        @applied = true
        break
      end
      # A plain update is what should apply pending virtual state; pumping as
      # well covers the case where SDL only reconciles the device inside its own
      # event processing.
      PUMP.call
    end
    @last_set_result
  end
end
