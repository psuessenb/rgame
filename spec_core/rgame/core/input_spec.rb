# frozen_string_literal: true

RSpec.describe RGame::Core::Input do
  # Input reads the engine's per-frame snapshot, so exercising it means running
  # real frames. Each example subclasses App, scripts one action per frame (so
  # every change is visible to the *next* frame's snapshot) and records what
  # Input reported.
  #
  # `results` is a plain Hash the example fills in and then asserts on, which
  # keeps the assertions out of the frame callbacks where a failure would
  # unwind through the C loop.
  # The script is yielded to, not instance_exec'd: rebinding self to the App
  # would put the example group's own helpers out of reach inside the block, for
  # no gain. It receives the app instead, so `app.close` ends the run.
  #
  # `yield` inside define_method reaches run_frames' own block — legitimate
  # here because run_frames is still on the stack while the loop runs.
  def run_frames(&)
    Class.new(RGame::Core::App) do
      define_method(:initialize) do
        super(width: 200, height: 150, caption: 'input-spec')
        @input = RGame::Core::Input.new(self)
        @frame = 0
      end

      define_method(:draw) do
        yield(@frame, @input, self)
        @frame += 1
      end
    end.new.run
  end

  # Input is the raw query and nothing more. It used to carry three binding
  # tables and take `down?(:fire)`; binding now lives in the engine layer, one
  # table per player, so what is left here is "is this physical id active on
  # this device".
  describe 'the raw query' do
    it 'has no binding tables to configure' do
      expect(described_class.instance_method(:initialize).parameters).to eq([%i[req app]])
    end

    it 'has no pointer query — mouse input is deliberately absent' do
      expect(described_class).not_to be_method_defined(:pointer_x)
    end

    # The ids cross into C through NUM2INT, so anything that is not a number
    # fails loudly here. spec/support/fake_input_backend.rb refuses the same
    # thing with the same class — see CLAUDE.md, "A fake must refuse what the
    # real thing refuses". A Symbol is the case that matters: it is what the
    # binding tables used to hold, so code written against the old shape breaks
    # rather than reading false forever.
    it 'refuses an id that is not a number' do
      error = nil
      run_frames do |_frame, input, app|
        begin
          input.down?(:teleport)
        rescue TypeError => e
          error = e
        end
        app.close
      end

      expect(error).to be_a(TypeError)
    end

    it 'refuses a non-numeric axis id the same way' do
      error = nil
      run_frames do |_frame, input, app|
        begin
          input.axis(:move_x)
        rescue TypeError => e
          error = e
        end
        app.close
      end

      expect(error).to be_a(TypeError)
    end
  end

  def pad_device(slot) = RGame::Util::Controls.gamepad(slot)

  describe 'reading the keyboard', :needs_key_injection do
    it 'reports a held key while it is down and not after' do
      results = {}
      keys = XKeys.new(ENV.fetch('DISPLAY', nil))

      run_frames do |frame, input, app|
        case frame
        when 2 then keys.press('Left')
        when 5 then results[:while_held] = input.down?(RGame::Util::Controls::KEY_LEFT)
        when 6 then keys.release('Left')
        when 9
          results[:after_release] = input.down?(RGame::Util::Controls::KEY_LEFT)
          results[:other_key] = input.down?(RGame::Util::Controls::KEY_RIGHT)
          app.close
        end
      end

      expect(results[:while_held]).to be(true)
      expect(results[:after_release]).to be(false)
      expect(results[:other_key]).to be(false)
    end

    it 'does not let a gamepad device answer for a keyboard key' do
      results = {}
      keys = XKeys.new(ENV.fetch('DISPLAY', nil))

      run_frames do |frame, input, app|
        case frame
        when 2 then keys.press('Left')
        when 5
          results[:keyboard] = input.down?(RGame::Util::Controls::KEY_LEFT)
          results[:pad] = input.down?(RGame::Util::Controls::KEY_LEFT, device: pad_device(0))
          keys.release('Left')
          app.close
        end
      end

      expect(results[:keyboard]).to be(true)
      expect(results[:pad]).to be(false)
    end
  end

  describe 'reading a gamepad' do
    # The facts that tell a failure here apart, captured rather than assumed. A
    # press that does not arrive can mean the pad was never seated, that SDL has
    # no controller mapping for it, that the mapping is wrong, or that SDL
    # accepted the press and never applied it — and the button assertion alone
    # cannot say which. `:aggregate_failures` is what makes them useful: without
    # it the run stops at the first expectation and reports one bare `false`,
    # which says nothing about the cause.
    #
    # The two examples that press a button are tagged `:needs_virtual_pad_state`,
    # because the last of those causes is an environment limitation rather than a
    # bug — see VirtualGamepad.button_state_supported?. The hot-plug examples
    # below are not tagged: they only attach and detach, which works everywhere.
    def pad_diagnostics(results, pad, app)
      results[:seated] = app.gamepad_present?(0)
      results[:pad_count] = app.gamepad_count
      results[:mapped] = pad.game_controller?
      results[:attached] = pad.attached?
      results[:set_rc] = pad.last_set_result
      results[:applied] = pad.applied
      results[:apply_attempts] = pad.apply_attempts
      results[:raw_a] = pad.raw_down?(VirtualGamepad::BUTTON_A)
      # Only meaningful when a set actually failed; harmless noise otherwise.
      results[:sdl_error] = pad.sdl_error unless pad.last_set_result.zero?
    end

    # Portable: SDL fabricates the pad, so this needs no hardware and no X11.
    it 'reports buttons and axes for the slot the pad was seated in, and no other',
       :aggregate_failures, :needs_virtual_pad_state do
      results = {}
      pad = nil

      run_frames do |frame, input, app|
        case frame
        when 0 then pad = VirtualGamepad.new
        when 2 then pad.press(VirtualGamepad::BUTTON_A)
        when 4
          pad_diagnostics(results, pad, app)
          results[:fire] = input.down?(RGame::Util::Controls::PAD_A, device: pad_device(0))
          results[:other_slot] = input.down?(RGame::Util::Controls::PAD_A, device: pad_device(1))
          results[:keyboard] = input.down?(RGame::Util::Controls::PAD_A)
          pad.release(VirtualGamepad::BUTTON_A)
          pad.press(VirtualGamepad::BUTTON_DPAD_RIGHT)
          pad.move_axis(VirtualGamepad::AXIS_LEFT_X, VirtualGamepad::AXIS_MIN)
        when 6
          results[:released] = input.down?(RGame::Util::Controls::PAD_A, device: pad_device(0))
          results[:dpad_right] = input.down?(RGame::Util::Controls::PAD_DPAD_RIGHT, device: pad_device(0))
          results[:axis_x] = input.axis(RGame::Util::Controls::AXIS_LEFT_X, device: pad_device(0))
          results[:axis_y] = input.axis(RGame::Util::Controls::AXIS_LEFT_Y, device: pad_device(0))
          results[:keyboard_axis] = input.axis(RGame::Util::Controls::AXIS_LEFT_X)
          app.close
        end
      end

      # Asserted before the button, so a failure names the cause rather than
      # only the symptom.
      expect(results[:seated]).to be(true)
      expect(results[:pad_count]).to eq(1)
      expect(results[:mapped]).to be(true)
      expect(results[:attached]).to be(true)
      expect(results[:set_rc]).to eq(0)
      # How many update passes the press needed. Reported rather than bounded
      # to 1 on purpose: if this ever comes back above 1 on a machine that
      # passes, that is the timing story in B15 confirmed.
      expect(results[:applied]).to be(true)
      expect(results[:raw_a]).to be(true)

      expect(results[:fire]).to be(true)
      expect(results[:other_slot]).to be(false)
      expect(results[:keyboard]).to be(false)
      expect(results[:released]).to be(false)
      expect(results[:dpad_right]).to be(true)
      # SDL's axis range is asymmetric, so full-left must clamp to exactly -1.0.
      expect(results[:axis_x]).to be_within(0.02).of(-1.0)
      expect(results[:axis_y]).to be_within(0.02).of(0.0)
      expect(results[:keyboard_axis]).to eq(0.0)
    end

    it 'clears the slot on unplug so a button held at that moment is not stuck',
       :aggregate_failures, :needs_virtual_pad_state do
      results = {}
      pad = nil

      run_frames do |frame, input, app|
        case frame
        when 0 then pad = VirtualGamepad.new
        when 2
          pad.press(VirtualGamepad::BUTTON_A)
          pad.move_axis(VirtualGamepad::AXIS_LEFT_X, VirtualGamepad::AXIS_MAX)
        when 4
          pad_diagnostics(results, pad, app)
          results[:before] = input.down?(RGame::Util::Controls::PAD_A, device: pad_device(0))
          pad.detach
        when 7
          results[:after] = input.down?(RGame::Util::Controls::PAD_A, device: pad_device(0))
          results[:axis_after] = input.axis(RGame::Util::Controls::AXIS_LEFT_X, device: pad_device(0))
          app.close
        end
      end

      expect(results[:seated]).to be(true)
      expect(results[:mapped]).to be(true)
      expect(results[:attached]).to be(true)
      expect(results[:set_rc]).to eq(0)
      # How many update passes the press needed. Reported rather than bounded
      # to 1 on purpose: if this ever comes back above 1 on a machine that
      # passes, that is the timing story in B15 confirmed.
      expect(results[:applied]).to be(true)
      expect(results[:raw_a]).to be(true)

      expect(results[:before]).to be(true)
      expect(results[:after]).to be(false)
      expect(results[:axis_after]).to eq(0.0)
    end
  end

  describe 'hot-plug callbacks' do
    it 'reports the slot on connect and again on disconnect' do
      pad = nil

      probe = Class.new(RGame::Core::App) do
        attr_reader :events

        define_method(:initialize) do
          super(width: 200, height: 150, caption: 'hotplug')
          @events = []
          @frame = 0
        end

        define_method(:gamepad_connected) { |slot| @events << [:connected, slot] }
        define_method(:gamepad_disconnected) { |slot| @events << [:disconnected, slot] }

        define_method(:draw) do
          case @frame
          when 0 then pad = VirtualGamepad.new
          when 3 then pad.detach
          when 6 then close
          end
          @frame += 1
        end
      end.new

      probe.run

      expect(probe.events).to eq([[:connected, 0], [:disconnected, 0]])
    end
  end
end
