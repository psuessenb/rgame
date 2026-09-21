# frozen_string_literal: true

require_relative 'child_ruby'

# A synthetic SDL game controller, for specs that need to exercise the real
# gamepad path without hardware.
#
# SDL can fabricate a whole controller in-process. A virtual pad reports
# SDL_IsGameController == 1 and raises genuine CONTROLLERDEVICEADDED/REMOVED
# events, so the engine's hot-plug path runs completely unmodified.
#
# The device itself is RGame::Core::VirtualGamepad, which is C inside the
# extension. That is what guarantees this drives the engine's own SDL state
# rather than a second copy: a helper that reached SDL through Fiddle had to
# find it by library name or exported symbol, and once SDL is linked into the
# extension statically neither finds the right copy everywhere — on Windows the
# extension exports no SDL symbol, and `SDL2.dll` names RubyInstaller's MSYS2
# copy instead. What stays here is spec machinery the gem has no business
# shipping: waiting for a press to land, and probing whether presses land on
# this machine at all.
#
# Unlike synthetic keystrokes (which need X11's XTEST), *attaching* a pad works
# on every platform SDL does, because it is an SDL feature rather than an OS
# one. Reading a *pressed button* back does not — see
# `button_state_supported?`.
class VirtualGamepad
  Device = RGame::Core::VirtualGamepad

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

  AXIS_MAX = 32_767
  AXIS_MIN = -32_768

  # How many passes a press gets before the harness stops waiting. Setting a
  # virtual button only queues it, and SDL applies it on a joystick update —
  # which the device runs itself, and which is enough wherever virtual button
  # state works at all. The remaining passes pump and update again, so that "SDL
  # has not applied it *yet*" and "SDL will never apply it" are distinguishable
  # rather than both reading as a bare false.
  #
  # Driving the update here, rather than relying on the engine's own
  # `SDL_PollEvent` loop to pump between a press and a read, keeps this
  # harness's synthetic input off the engine's frame schedule. It does not
  # weaken what the specs check: the engine still reads through
  # SDL_GameControllerGetButton, so seating and the controller mapping are
  # exercised exactly as before. *When* SDL applies pending virtual state is a
  # property of the fake device, and making that deterministic is the harness's
  # job.
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

      @button_state_supported = button_state_probe_passes?
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
    # this has to answer the same way everywhere.
    def button_state_probe_passes?
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
      # A probe that hangs raises instead, because a skip would hide the hang.
      ChildRuby.capture(script)[2].success?
    end
  end

  def initialize
    @device = Device.new
  end

  def press(button) = set_button(button, true)
  def release(button) = set_button(button, false)

  def move_axis(axis, value)
    @last_set_result = @device.set_axis(axis, value) ? 0 : -1
  end

  # Enough to tell apart the several ways a press can fail to arrive, which
  # matters because the interesting failure is the one where SDL reports success
  # at every step (see `button_state_supported?`):
  #
  #   raw_down?         the *unmapped* joystick button. True here while the
  #                     engine reads false would mean the mapping is wrong.
  #   game_controller?  whether SDL will treat the device as a controller at
  #                     all. False means there is no mapping, so the engine
  #                     declines to seat it (see rgame_gamepads_add).
  #   attached?         whether this handle is still a live device.
  #   sdl_error         what SDL says when it refuses something.
  def raw_down?(button) = @device.button_down?(button)
  def game_controller? = @device.game_controller?
  def attached? = @device.attached?
  def sdl_error = Device.sdl_error

  # Non-zero means SDL refused the last press/release/axis outright. Nil until
  # something has been set.
  attr_reader :last_set_result

  # How many passes the last button press or release needed before SDL applied
  # it, and whether it ever did. `nil` until a button has been set; `applied`
  # false means SDL accepted the call and never honoured it.
  attr_reader :apply_attempts, :applied

  # Unplugging the pad, as far as SDL and the engine are concerned.
  def detach = @device.detach

  private

  # Sets the button and then checks SDL actually applied it, rather than
  # trusting the call's return value — which can be a success for a press that
  # never takes effect. Deliberately does *not* raise on failure: this runs
  # inside the engine's draw callback, and an exception there unwinds through
  # the C frame loop, which is why input_spec.rb collects results and asserts
  # afterwards. A press that never lands is recorded and left for the example's
  # own expectations to report.
  def set_button(button, down)
    @last_set_result = @device.set_button(button, down) ? 0 : -1
    @apply_attempts = 0
    @applied = false
    APPLY_ATTEMPTS.times do
      @apply_attempts += 1
      if raw_down?(button) == down
        @applied = true
        break
      end
      Device.pump
    end
    @last_set_result
  end
end
