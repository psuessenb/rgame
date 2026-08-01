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
  # The script is called, not instance_exec'd: rebinding self to the App would
  # put the example group's own helpers out of reach inside the block, for no
  # gain. It receives the app instead, so `app.close` ends the run.
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

  describe 'the binding table' do
    it 'maps the same action to a different physical input per device class' do
      expect(described_class::KEYBOARD_BINDINGS[:fire]).to eq(described_class::KEY_SPACE)
      expect(described_class::PAD_BINDINGS[:fire]).to eq(described_class::PAD_A)
    end

    it 'numbers the keyboard first so single-player callers can omit the device' do
      expect(described_class::KEYBOARD).to eq(0)
      expect(described_class.gamepad(0)).to be > described_class::KEYBOARD
    end

    it 'raises for an action nothing is bound to' do
      expect { described_class.new(nil).down?(:teleport) }.to raise_error(KeyError)
    end

    it 'has no pointer binding — mouse input is deliberately absent' do
      expect(described_class::KEYBOARD_BINDINGS).not_to have_key(:pointer)
      expect(described_class).not_to be_method_defined(:pointer_x)
    end
  end

  def pad_device(slot) = RGame::Core::Input.gamepad(slot)

  describe 'reading the keyboard', :needs_key_injection do
    it 'reports a held key while it is down and not after' do
      results = {}
      keys = XKeys.new(ENV.fetch('DISPLAY', nil))

      run_frames do |frame, input, app|
        case frame
        when 2 then keys.press('Left')
        when 5 then results[:while_held] = input.down?(:left)
        when 6 then keys.release('Left')
        when 9
          results[:after_release] = input.down?(:left)
          results[:other_key] = input.down?(:right)
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
          results[:keyboard] = input.down?(:left)
          results[:pad] = input.down?(:left, device: pad_device(0))
          keys.release('Left')
          app.close
        end
      end

      expect(results[:keyboard]).to be(true)
      expect(results[:pad]).to be(false)
    end
  end

  describe 'reading a gamepad' do
    # Portable: SDL fabricates the pad, so this needs no hardware and no X11.
    it 'reports buttons and axes for the slot the pad was seated in, and no other' do
      results = {}
      pad = nil

      run_frames do |frame, input, app|
        case frame
        when 0 then pad = VirtualGamepad.new
        when 2 then pad.press(VirtualGamepad::BUTTON_A)
        when 4
          results[:fire] = input.down?(:fire, device: pad_device(0))
          results[:other_slot] = input.down?(:fire, device: pad_device(1))
          results[:keyboard] = input.down?(:fire)
          pad.release(VirtualGamepad::BUTTON_A)
          pad.press(VirtualGamepad::BUTTON_DPAD_RIGHT)
          pad.move_axis(VirtualGamepad::AXIS_LEFT_X, VirtualGamepad::AXIS_MIN)
        when 6
          results[:released] = input.down?(:fire, device: pad_device(0))
          results[:dpad_right] = input.down?(:right, device: pad_device(0))
          results[:axis_x] = input.axis(:move_x, device: pad_device(0))
          results[:axis_y] = input.axis(:move_y, device: pad_device(0))
          results[:keyboard_axis] = input.axis(:move_x)
          app.close
        end
      end

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

    it 'clears the slot on unplug so a button held at that moment is not stuck' do
      results = {}
      pad = nil

      run_frames do |frame, input, app|
        case frame
        when 0 then pad = VirtualGamepad.new
        when 2
          pad.press(VirtualGamepad::BUTTON_A)
          pad.move_axis(VirtualGamepad::AXIS_LEFT_X, VirtualGamepad::AXIS_MAX)
        when 4
          results[:before] = input.down?(:fire, device: pad_device(0))
          pad.detach
        when 7
          results[:after] = input.down?(:fire, device: pad_device(0))
          results[:axis_after] = input.axis(:move_x, device: pad_device(0))
          app.close
        end
      end

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
