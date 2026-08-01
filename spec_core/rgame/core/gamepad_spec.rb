# frozen_string_literal: true

RSpec.describe RGame::Core::Gamepad do
  # Attaching and detaching a virtual pad only takes effect once the engine has
  # pumped events, so each example runs real frames and scripts one action per
  # frame. `results` is filled in the frame callback and asserted afterwards.
  #
  # `yield` inside define_method reaches run_frames' own block — legitimate
  # here because run_frames is still on the stack while the loop runs.
  def run_frames(&)
    Class.new(RGame::Core::App) do
      define_method(:initialize) do
        super(width: 200, height: 150, caption: 'gamepad-spec')
        @pads = RGame::Core::Gamepad.new(self)
        @frame = 0
      end

      define_method(:draw) do
        yield(@frame, @pads, self)
        @frame += 1
      end
    end.new.run
  end

  describe 'with nothing plugged in' do
    it 'reports an empty, but well-defined, set of slots' do
      results = {}

      run_frames do |frame, pads, app|
        if frame == 2
          results[:count] = pads.count
          results[:connected] = pads.connected?(0)
          results[:name] = pads.name(0)
          results[:each] = pads.each_connected.to_a
          results[:max_slots] = pads.max_slots
          app.close
        end
      end

      expect(results[:count]).to eq(0)
      expect(results[:connected]).to be(false)
      expect(results[:name]).to be_nil
      expect(results[:each]).to be_empty
      expect(results[:max_slots]).to eq(RGame::Util::Controls::MAX_GAMEPADS)
    end
  end

  describe 'with a controller plugged in' do
    it 'reports the slot, a name, and the device id Input needs' do
      results = {}
      pad = nil

      run_frames do |frame, pads, app|
        case frame
        when 0 then pad = VirtualGamepad.new
        when 3
          results[:count] = pads.count
          results[:connected] = pads.connected?(0)
          results[:name] = pads.name(0)
          results[:other_slot] = pads.connected?(1)
          results[:each] = pads.each_connected.to_a
          results[:device] = pads.device(0)
          app.close
        end
      end

      expect(results[:count]).to eq(1)
      expect(results[:connected]).to be(true)
      expect(results[:name]).to be_a(String)
      expect(results[:other_slot]).to be(false)
      expect(results[:each]).to eq([[0, results[:name]]])
      # The bridge to Input: a menu that found a pad can drive it without
      # knowing how devices are numbered.
      expect(results[:device]).to eq(RGame::Util::Controls.gamepad(0))
    end

    it 'goes back to empty after an unplug' do
      results = {}
      pad = nil

      run_frames do |frame, pads, app|
        case frame
        when 0 then pad = VirtualGamepad.new
        when 3
          results[:before] = pads.count
          pad.detach
        when 6
          results[:after] = pads.count
          results[:connected_after] = pads.connected?(0)
          results[:name_after] = pads.name(0)
          app.close
        end
      end

      expect(results[:before]).to eq(1)
      expect(results[:after]).to eq(0)
      expect(results[:connected_after]).to be(false)
      expect(results[:name_after]).to be_nil
    end
  end

  describe 'out-of-range slots' do
    it 'answers rather than raising, so UI loops need no bounds checks' do
      results = {}

      run_frames do |frame, pads, app|
        if frame == 2
          results[:negative] = pads.connected?(-1)
          results[:past_end] = pads.connected?(pads.max_slots)
          results[:name_past_end] = pads.name(pads.max_slots)
          app.close
        end
      end

      expect(results[:negative]).to be(false)
      expect(results[:past_end]).to be(false)
      expect(results[:name_past_end]).to be_nil
    end
  end
end
