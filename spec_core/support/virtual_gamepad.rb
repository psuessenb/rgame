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
# Unlike synthetic keystrokes (which need X11's XTEST), *attaching* a pad works
# on every platform SDL does, because it is an SDL feature rather than an OS
# one. Reading a *pressed button* back does not — see
# `button_state_supported?`.
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

  # Setting a virtual button or axis writes only *pending* state: SDL applies it
  # to the device — and so makes it readable, mapped or unmapped — on the next
  # SDL_JoystickUpdate. Measured, because it is invisible until it bites: with
  # this call, 40 of 40 attach/press/read cycles read the press back; without
  # it, 0 of 40 did.
  #
  # Driving the update here, rather than relying on the engine's own
  # `SDL_PollEvent` loop to pump between a press and a read, keeps this
  # harness's synthetic input off the engine's frame schedule. It does not
  # weaken what the specs check: the engine still reads through
  # SDL_GameControllerGetButton, so seating and the controller mapping are
  # exercised exactly as before. *When* SDL applies pending virtual state is a
  # property of the fake device, and making that deterministic is the harness's
  # job.
  UPDATE = fn('SDL_JoystickUpdate', [], Fiddle::TYPE_VOID)

  # Enough SDL to tell apart the several ways a press can fail to arrive, which
  # matters because the interesting failure is the one where SDL reports success
  # at every step (see `button_state_supported?`):
  #
  #   GET_BUTTON        the *unmapped* joystick button. True here while the
  #                     engine reads false would mean the mapping is wrong.
  #   IS_GAMECONTROLLER whether SDL will treat the device as a controller at
  #                     all. False means there is no mapping, so the engine
  #                     declines to seat it (see rgame_gamepads_add).
  #   GET_ATTACHED      whether this handle is still a live device.
  #   GET_ERROR         what SDL says when it refuses something.
  GET_BUTTON = fn('SDL_JoystickGetButton',
                  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT], Fiddle::TYPE_CHAR)
  IS_GAMECONTROLLER = fn('SDL_IsGameController', [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
  GET_ATTACHED = fn('SDL_JoystickGetAttached', [Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  GET_ERROR = fn('SDL_GetError', [], Fiddle::TYPE_VOIDP)
  PUMP = fn('SDL_PumpEvents', [], Fiddle::TYPE_VOID)

  # How many update passes a press gets before the harness stops waiting. One is
  # enough wherever virtual button state works at all; the rest exist so that
  # "SDL has not applied it *yet*" and "SDL will never apply it" are
  # distinguishable rather than both reading as a bare false.
  APPLY_ATTEMPTS = 10

  class << self
    # Whether SDL actually applies virtual *button state* on this machine.
    #
    # Attaching a virtual pad and reading a pressed button back are two
    # separate capabilities, and the second is not available everywhere. On
    # GitHub's macOS runners SDL reports success at every observable step —
    # `SDL_JoystickAttachVirtual` yields a device, `SDL_IsGameController` says
    # it is a controller, the engine seats it and raises its hot-plug
    # callbacks, `SDL_JoystickGetAttached` calls it live, and
    # `SDL_JoystickSetVirtualButton` returns 0 — and then the button never
    # reads back, through ten update-and-pump passes. Nothing in SDL's API
    # reports a problem; the state simply never appears.
    #
    # It is not a library or OS version difference. That was measured, with SDL
    # and macOS pinned identical to a machine where the same specs pass
    # (sdl2-compat 2.32.70, SDL3 3.4.14, macOS 26). What is left is the runner
    # environment itself — a CI session with no real display or input devices —
    # and no spec can install its way out of that.
    #
    # So it is treated the way `HeadlessDisplay.can_inject_keys?` treats XTEST:
    # a capability probed rather than assumed, with the specs that need it
    # skipping themselves where it is absent. Probed rather than branched on
    # `host_os` deliberately — that keeps the examples running on every machine
    # where the capability *does* work, including every developer Mac, instead
    # of switching them off for a whole platform because one environment cannot
    # manage it.
    #
    # Answered once and memoised: it spawns a process, so it is not free, and
    # the answer cannot change within a process.
    def button_state_supported?
      return @button_state_supported unless @button_state_supported.nil?

      @button_state_supported = probe_button_state
    end

    private

    # Probes in a **child process**, and that isolation is the whole point
    # rather than tidiness.
    #
    # The probe has to do the real thing to be worth anything: open an App,
    # attach a pad, press a button, see whether it reads back. Doing that
    # in-process poisons the suite that follows it. Measured, on the machine
    # this was written on: with an in-process probe the two gamepad examples
    # failed on 4 of 4 full `spec:core` runs; with the probe isolated they pass,
    # as they did before any probe existed. Attaching and detaching a virtual
    # joystick evidently leaves SDL in a state where later virtual pads do not
    # work, so a probe that runs first would be measuring one thing and breaking
    # another.
    #
    # A subprocess rather than a fork, because Windows has no usable fork and
    # this has to answer the same way everywhere. The child inherits bundler's
    # environment, which is what makes `fiddle` resolvable there.
    def probe_button_state
      lib = File.expand_path('../../lib', __dir__)
      script = <<~RUBY
        require 'rgame/core'
        require #{File.expand_path(__FILE__).inspect}
        app = RGame::Core::App.new(width: 64, height: 48, caption: 'virtual pad probe')
        pad = VirtualGamepad.new
        pad.press(VirtualGamepad::BUTTON_A)
        applied = pad.applied
        pad.detach
        app.close
        exit(applied ? 0 : 1)
      RUBY

      # Any non-zero exit — a false answer, a crash, a missing library — counts
      # as unsupported: if the harness cannot get a press to read back here, the
      # examples needing one cannot pass either.
      system(RbConfig.ruby, '-I', lib, '-e', script, out: File::NULL, err: File::NULL) || false
    end
  end

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
  # applied it, and whether it ever did. `nil` until a button has been set;
  # `applied` false means SDL accepted the call and never honoured it.
  attr_reader :apply_attempts, :applied

  # Unplugging the pad, as far as SDL and the engine are concerned.
  def detach
    return if @detached

    CLOSE.call(@joystick)
    DETACH.call(@index)
    @detached = true
  end

  private

  # Sets the button and then checks SDL actually applied it, rather than
  # trusting the call's return value — which can be a successful 0 for a press
  # that never takes effect. Deliberately does *not* raise on failure: this runs
  # inside the engine's draw callback, and an exception there unwinds through
  # the C frame loop, which is why input_spec.rb collects results and asserts
  # afterwards. A press that never lands is recorded and left for the example's
  # own expectations to report.
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
