# frozen_string_literal: true

RSpec.describe RGame::Engine::ActionMapper do
  let(:controls) { RGame::Util::Controls }

  # A stand-in for RGame::Core::Input: held ids and axis values, per device.
  # Two devices, because the point of the mapper is that it asks one of them.
  let(:backend) { FakeInputBackend.new }

  let(:map) do
    RGame::Engine::InputMap.new(
      move_x: { axis: [RGame::Util::Controls::KEY_LEFT, RGame::Util::Controls::KEY_RIGHT],
                stick: RGame::Util::Controls::AXIS_LEFT_X },
      fire: { buttons: [RGame::Util::Controls::KEY_SPACE, RGame::Util::Controls::PAD_A] }
    )
  end

  def mapper(**) = described_class.new(map, **)

  describe 'buttons' do
    it 'reports a held button' do
      backend.hold(controls::KEY_SPACE)
      expect(mapper.poll(backend).held?(:fire)).to be(true)
    end

    it 'reports an unheld button as false' do
      expect(mapper.poll(backend).held?(:fire)).to be(false)
    end

    it 'is held when any of the action\'s ids is down' do
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      expect(mapper(device: controls.gamepad(0)).poll(backend).held?(:fire)).to be(true)
    end
  end

  describe 'the device' do
    it 'asks the device it was built with, not the keyboard' do
      backend.hold(controls::PAD_A, device: controls.gamepad(1))
      expect(mapper(device: controls.gamepad(1)).poll(backend).held?(:fire)).to be(true)
    end

    it 'does not see input on another device' do
      backend.hold(controls::PAD_A, device: controls.gamepad(1))
      expect(mapper(device: controls.gamepad(0)).poll(backend).held?(:fire)).to be(false)
    end

    # Two players, one map, two controllers — the reason the device is per
    # mapper rather than per map.
    it 'lets two mappers over one map read two controllers independently' do
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      one = mapper(device: controls.gamepad(0)).poll(backend).held?(:fire)
      two = mapper(device: controls.gamepad(1)).poll(backend).held?(:fire)
      expect([one, two]).to eq([true, false])
    end

    it 'follows the device being reassigned, as a hot-plug does' do
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      subject = mapper
      subject.device = controls.gamepad(0)
      expect(subject.poll(backend).held?(:fire)).to be(true)
    end
  end

  describe 'a digital axis' do
    it 'yields +1.0 on the positive binding' do
      backend.hold(controls::KEY_RIGHT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(1.0)
    end

    it 'yields -1.0 on the negative binding' do
      backend.hold(controls::KEY_LEFT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(-1.0)
    end

    it 'cancels to 0.0 when both bindings are down' do
      backend.hold(controls::KEY_LEFT, controls::KEY_RIGHT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(0.0)
    end

    it 'is neutral (0.0) when nothing is down' do
      expect(mapper.poll(backend).axis(:move_x)).to eq(0.0)
    end
  end

  # Several pairs on one axis: the arrows, WASD and a d-pad all walking. A
  # device with only one of them reads 0.0 for the rest, so binding all three
  # costs a pad player nothing.
  describe 'an axis with several button pairs' do
    let(:map) do
      RGame::Engine::InputMap.new(
        move_x: { axis: [[RGame::Util::Controls::KEY_LEFT, RGame::Util::Controls::KEY_RIGHT],
                         [RGame::Util::Controls::PAD_DPAD_LEFT,
                          RGame::Util::Controls::PAD_DPAD_RIGHT]] }
      )
    end

    it 'reads the first pair' do
      backend.hold(controls::KEY_RIGHT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(1.0)
    end

    it 'reads the second pair, on the device that has it' do
      pad = controls.gamepad(0)
      backend.hold(controls::PAD_DPAD_LEFT, device: pad)
      expect(mapper(device: pad).poll(backend).axis(:move_x)).to eq(-1.0)
    end

    it 'takes the largest deflection when two pairs disagree' do
      backend.hold(controls::KEY_RIGHT, controls::PAD_DPAD_LEFT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(1.0)
    end

    it 'is neutral when a pair cancels itself out' do
      backend.hold(controls::KEY_LEFT, controls::KEY_RIGHT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(0.0)
    end
  end

  describe 'an analog axis' do
    let(:pad) { RGame::Util::Controls.gamepad(0) }

    it 'reads the stick' do
      backend.set_axis(controls::AXIS_LEFT_X, 1.0, device: pad)
      expect(mapper(device: pad).poll(backend).axis(:move_x)).to eq(1.0)
    end

    it 'reads a negative deflection' do
      backend.set_axis(controls::AXIS_LEFT_X, -1.0, device: pad)
      expect(mapper(device: pad).poll(backend).axis(:move_x)).to eq(-1.0)
    end

    # The keyboard reads 0.0 for every axis, so a map that binds both sources
    # needs no per-device branching to work on either.
    it 'ignores the stick on a device that has none' do
      backend.hold(controls::KEY_RIGHT)
      expect(mapper.poll(backend).axis(:move_x)).to eq(1.0)
    end

    it 'lets the larger deflection win when both sources are active' do
      backend.hold(controls::KEY_RIGHT, device: pad)
      backend.set_axis(controls::AXIS_LEFT_X, -0.5, device: pad)
      expect(mapper(device: pad).poll(backend).axis(:move_x)).to eq(1.0)
    end
  end

  describe 'the dead zone' do
    let(:pad) { RGame::Util::Controls.gamepad(0) }

    it 'ignores a resting stick' do
      backend.set_axis(controls::AXIS_LEFT_X, 0.1, device: pad)
      expect(mapper(device: pad, dead_zone: 0.15).poll(backend).axis(:move_x)).to eq(0.0)
    end

    it 'ignores a resting stick in the negative direction too' do
      backend.set_axis(controls::AXIS_LEFT_X, -0.1, device: pad)
      expect(mapper(device: pad, dead_zone: 0.15).poll(backend).axis(:move_x)).to eq(0.0)
    end

    # Rescaled rather than cut off: a stick just past the threshold reads near
    # zero, not the threshold's own width.
    it 'ramps from zero rather than jumping to the threshold' do
      backend.set_axis(controls::AXIS_LEFT_X, 0.2, device: pad)
      value = mapper(device: pad, dead_zone: 0.15).poll(backend).axis(:move_x)
      expect(value).to be_within(0.001).of(0.0588)
    end

    it 'still reaches full deflection' do
      backend.set_axis(controls::AXIS_LEFT_X, 1.0, device: pad)
      expect(mapper(device: pad, dead_zone: 0.15).poll(backend).axis(:move_x)).to eq(1.0)
    end
  end

  # Edge detection compares against the previous poll, so it needs one mapper
  # polled repeatedly rather than a fresh one per poll.
  describe 'edge detection' do
    let(:subject_mapper) { mapper }

    def poll_with(*ids)
      backend.clear
      backend.hold(*ids) unless ids.empty?
      subject_mapper.poll(backend)
    end

    it 'pressed? is true only on the frame the button goes down' do
      expect(poll_with.pressed?(:fire)).to be(false)
      expect(poll_with(controls::KEY_SPACE).pressed?(:fire)).to be(true)
      expect(poll_with(controls::KEY_SPACE).pressed?(:fire)).to be(false)
    end

    it 'released? is true only on the frame the button goes up' do
      poll_with(controls::KEY_SPACE)
      expect(poll_with(controls::KEY_SPACE).released?(:fire)).to be(false)
      expect(poll_with.released?(:fire)).to be(true)
      expect(poll_with.released?(:fire)).to be(false)
    end

    # Each player's mapper carries its own previous frame, so one player's
    # press cannot consume another's edge.
    it 'is independent between two mappers' do
      other = mapper
      backend.hold(controls::KEY_SPACE)
      subject_mapper.poll(backend)
      subject_mapper.poll(backend) # now held, not pressed, for this one
      expect(other.poll(backend).pressed?(:fire)).to be(true)
    end
  end
end
