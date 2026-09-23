# frozen_string_literal: true

RSpec.describe RGame::Engine::ActionMapper do
  let(:controls) { RGame::Util::Controls }

  # A stand-in for RGame::Core::Input: held ids and axis values, per device.
  # Two devices, because the point of the mapper is that it asks one of them.
  let(:backend) { FakeInputBackend.new }

  # The engine's fixed step, which is what Game polls with.
  let(:step) { 1.0 / 60 }

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
      expect(mapper.poll(backend, step).held?(:fire)).to be(true)
    end

    it 'reports an unheld button as false' do
      expect(mapper.poll(backend, step).held?(:fire)).to be(false)
    end

    it 'is held when any of the action\'s ids is down' do
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      expect(mapper(device: controls.gamepad(0)).poll(backend, step).held?(:fire)).to be(true)
    end
  end

  describe 'the device' do
    it 'asks the device it was built with, not the keyboard' do
      backend.hold(controls::PAD_A, device: controls.gamepad(1))
      expect(mapper(device: controls.gamepad(1)).poll(backend, step).held?(:fire)).to be(true)
    end

    it 'does not see input on another device' do
      backend.hold(controls::PAD_A, device: controls.gamepad(1))
      expect(mapper(device: controls.gamepad(0)).poll(backend, step).held?(:fire)).to be(false)
    end

    # Two players, one map, two controllers — the reason the device is per
    # mapper rather than per map.
    it 'lets two mappers over one map read two controllers independently' do
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      one = mapper(device: controls.gamepad(0)).poll(backend, step).held?(:fire)
      two = mapper(device: controls.gamepad(1)).poll(backend, step).held?(:fire)
      expect([one, two]).to eq([true, false])
    end

    it 'follows the device being reassigned, as a hot-plug does' do
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      subject = mapper
      subject.device = controls.gamepad(0)
      expect(subject.poll(backend, step).held?(:fire)).to be(true)
    end
  end

  describe 'a digital axis' do
    it 'yields +1.0 on the positive binding' do
      backend.hold(controls::KEY_RIGHT)
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(1.0)
    end

    it 'yields -1.0 on the negative binding' do
      backend.hold(controls::KEY_LEFT)
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(-1.0)
    end

    it 'cancels to 0.0 when both bindings are down' do
      backend.hold(controls::KEY_LEFT, controls::KEY_RIGHT)
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(0.0)
    end

    it 'is neutral (0.0) when nothing is down' do
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(0.0)
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
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(1.0)
    end

    it 'reads the second pair, on the device that has it' do
      pad = controls.gamepad(0)
      backend.hold(controls::PAD_DPAD_LEFT, device: pad)
      expect(mapper(device: pad).poll(backend, step).axis(:move_x)).to eq(-1.0)
    end

    it 'takes the largest deflection when two pairs disagree' do
      backend.hold(controls::KEY_RIGHT, controls::PAD_DPAD_LEFT)
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(1.0)
    end

    it 'is neutral when a pair cancels itself out' do
      backend.hold(controls::KEY_LEFT, controls::KEY_RIGHT)
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(0.0)
    end
  end

  describe 'an analog axis' do
    let(:pad) { RGame::Util::Controls.gamepad(0) }

    it 'reads the stick' do
      backend.set_axis(controls::AXIS_LEFT_X, 1.0, device: pad)
      expect(mapper(device: pad).poll(backend, step).axis(:move_x)).to eq(1.0)
    end

    it 'reads a negative deflection' do
      backend.set_axis(controls::AXIS_LEFT_X, -1.0, device: pad)
      expect(mapper(device: pad).poll(backend, step).axis(:move_x)).to eq(-1.0)
    end

    # The keyboard reads 0.0 for every axis, so a map that binds both sources
    # needs no per-device branching to work on either.
    it 'ignores the stick on a device that has none' do
      backend.hold(controls::KEY_RIGHT)
      expect(mapper.poll(backend, step).axis(:move_x)).to eq(1.0)
    end

    it 'lets the larger deflection win when both sources are active' do
      backend.hold(controls::KEY_RIGHT, device: pad)
      backend.set_axis(controls::AXIS_LEFT_X, -0.5, device: pad)
      expect(mapper(device: pad).poll(backend, step).axis(:move_x)).to eq(1.0)
    end
  end

  describe 'the dead zone' do
    let(:pad) { RGame::Util::Controls.gamepad(0) }

    it 'ignores a resting stick' do
      backend.set_axis(controls::AXIS_LEFT_X, 0.1, device: pad)
      expect(mapper(device: pad, dead_zone: 0.15).poll(backend, step).axis(:move_x)).to eq(0.0)
    end

    it 'ignores a resting stick in the negative direction too' do
      backend.set_axis(controls::AXIS_LEFT_X, -0.1, device: pad)
      expect(mapper(device: pad, dead_zone: 0.15).poll(backend, step).axis(:move_x)).to eq(0.0)
    end

    # Rescaled rather than cut off: a stick just past the threshold reads near
    # zero, not the threshold's own width.
    it 'ramps from zero rather than jumping to the threshold' do
      backend.set_axis(controls::AXIS_LEFT_X, 0.2, device: pad)
      value = mapper(device: pad, dead_zone: 0.15).poll(backend, step).axis(:move_x)
      expect(value).to be_within(0.001).of(0.0588)
    end

    it 'still reaches full deflection' do
      backend.set_axis(controls::AXIS_LEFT_X, 1.0, device: pad)
      expect(mapper(device: pad, dead_zone: 0.15).poll(backend, step).axis(:move_x)).to eq(1.0)
    end
  end

  # The mapper is the one place that sees every action once a tick, so counting
  # a press is its job rather than each caller's.
  describe '#held_for' do
    subject(:subject_mapper) { mapper }

    def poll_with(*ids)
      backend.clear
      backend.hold(*ids) unless ids.empty?
      subject_mapper.poll(backend, step)
    end

    it 'is 0.0 for an action nobody has touched' do
      expect(poll_with.held_for(:fire)).to eq(0.0)
    end

    it 'counts one step on the tick the button goes down' do
      expect(poll_with(controls::KEY_SPACE).held_for(:fire)).to be_within(0.0001).of(step)
    end

    it 'counts a step per tick the button stays down' do
      3.times { poll_with(controls::KEY_SPACE) }
      expect(poll_with(controls::KEY_SPACE).held_for(:fire)).to be_within(0.0001).of(step * 4)
    end

    # A caller asking "was that a long press" asks on the release, so the count
    # has to outlive the tick it ended on.
    it 'still reads the press on the tick of the release' do
      2.times { poll_with(controls::KEY_SPACE) }
      expect(poll_with.held_for(:fire)).to be_within(0.0001).of(step * 2)
    end

    it 'is 0.0 again the tick after the release' do
      2.times { poll_with(controls::KEY_SPACE) }
      poll_with
      expect(poll_with.held_for(:fire)).to eq(0.0)
    end

    it 'starts from zero on the next press' do
      2.times { poll_with(controls::KEY_SPACE) }
      2.times { poll_with }
      expect(poll_with(controls::KEY_SPACE).held_for(:fire)).to be_within(0.0001).of(step)
    end

    it 'counts nothing for an action bound to an axis alone' do
      expect(poll_with(controls::KEY_RIGHT).held_for(:move_x)).to eq(0.0)
    end

    # A seat with no device reads nothing at all, the count included.
    it 'is 0.0 while the device is nil' do
      backend.hold(controls::KEY_SPACE)
      2.times { subject_mapper.poll(backend, step) }
      subject_mapper.device = nil
      expect(subject_mapper.poll(backend, step).held_for(:fire)).to eq(0.0)
    end
  end

  describe '#poll_count' do
    it 'is 0 before the first poll' do
      expect(mapper.actions.poll_count).to eq(0)
    end

    it 'counts each poll' do
      subject_mapper = mapper
      3.times { subject_mapper.poll(backend, step) }
      expect(subject_mapper.actions.poll_count).to eq(3)
    end

    it 'counts a poll while the device is nil' do
      subject_mapper = mapper(device: nil)
      2.times { subject_mapper.poll(backend, step) }
      expect(subject_mapper.actions.poll_count).to eq(2)
    end
  end

  describe '#down_since' do
    subject(:subject_mapper) { mapper }

    def poll_with(*ids)
      backend.clear
      backend.hold(*ids) unless ids.empty?
      subject_mapper.poll(backend, step)
    end

    it 'is nil for an action nobody has touched' do
      expect(poll_with.down_since(:fire)).to be_nil
    end

    it 'is the poll the button went down on' do
      2.times { poll_with }
      expect(poll_with(controls::KEY_SPACE).down_since(:fire)).to eq(3)
    end

    it 'stays on that poll while the button is down' do
      poll_with
      3.times { poll_with(controls::KEY_SPACE) }
      expect(subject_mapper.actions.down_since(:fire)).to eq(2)
    end

    # `released?` reads on that tick, and asks when the press began.
    it 'still reads the press on the tick of the release' do
      2.times { poll_with(controls::KEY_SPACE) }
      expect(poll_with.down_since(:fire)).to eq(1)
    end

    it 'is nil the tick after the release' do
      2.times { poll_with(controls::KEY_SPACE) }
      poll_with
      expect(poll_with.down_since(:fire)).to be_nil
    end

    it 'starts again on the next press' do
      poll_with(controls::KEY_SPACE)
      2.times { poll_with }
      expect(poll_with(controls::KEY_SPACE).down_since(:fire)).to eq(4)
    end

    it 'is nil for an action bound to an axis alone' do
      expect(poll_with(controls::KEY_RIGHT).down_since(:move_x)).to be_nil
    end

    it 'is nil while the device is nil' do
      poll_with(controls::KEY_SPACE)
      subject_mapper.device = nil
      expect(poll_with(controls::KEY_SPACE).down_since(:fire)).to be_nil
    end
  end

  # E tapped opens the chest and E held searches it: one button, two actions, and
  # the mapper deciding which of them the press was.
  describe 'a hold and a tap on one button' do
    subject(:subject_mapper) { mapper }

    # A tenth of a second a tick, and thresholds that fall between two of them:
    # which tick a threshold lands on is then a fact about the rule rather than
    # about where a float accumulation happens to sit.
    let(:step) { 0.1 }

    let(:map) do
      RGame::Engine::InputMap.new(
        interact: { buttons: [RGame::Util::Controls::KEY_E], tap: 0.15 },
        search: { buttons: [RGame::Util::Controls::KEY_E], hold: 0.25 }
      )
    end

    def hold_for(ticks)
      backend.hold(controls::KEY_E)
      ticks.times { subject_mapper.poll(backend, step) }
    end

    def release
      backend.release(controls::KEY_E)
      subject_mapper.poll(backend, step)
    end

    describe 'the hold' do
      it 'is not held before its threshold' do
        hold_for(2)
        expect(subject_mapper.actions.held?(:search)).to be(false)
      end

      it 'presses on the tick its threshold passes' do
        hold_for(3)
        expect(subject_mapper.actions.pressed?(:search)).to be(true)
      end

      it 'presses once, however long the button stays down' do
        hold_for(3)
        presses = 20.times.count { subject_mapper.poll(backend, step).pressed?(:search) }
        expect(presses).to eq(0)
      end

      it 'stays held until the button comes up' do
        hold_for(10)
        expect(subject_mapper.actions.held?(:search)).to be(true)
      end

      it 'releases when the button comes up' do
        hold_for(3)
        expect(release.released?(:search)).to be(true)
      end
    end

    describe 'the tap' do
      it 'is not pressed while the button is down' do
        hold_for(1)
        expect(subject_mapper.actions.pressed?(:interact)).to be(false)
      end

      it 'presses on a release that came in time' do
        hold_for(1)
        expect(release.pressed?(:interact)).to be(true)
      end

      it 'is a single tick' do
        hold_for(1)
        release
        expect(subject_mapper.poll(backend, step).held?(:interact)).to be(false)
      end

      it 'presses nothing on a release that came too late' do
        hold_for(3)
        expect(release.pressed?(:interact)).to be(false)
      end
    end

    # The two never fire for one press, which is what makes a button safe to
    # declare twice.
    it 'answers a short press with the tap alone' do
      hold_for(1)
      released = release
      expect([released.pressed?(:interact), released.held?(:search)]).to eq([true, false])
    end

    it 'answers a long press with the hold alone' do
      hold_for(3)
      held = subject_mapper.actions.held?(:search)
      expect([release.pressed?(:interact), held]).to eq([false, true])
    end

    it 'counts the press for both, whichever of them fired' do
      hold_for(2)
      expect(subject_mapper.actions.held_for(:interact)).to be_within(0.0001).of(step * 2)
    end

    # A tap presses on the release and releases the tick after, and both edges
    # ask when the press began.
    describe 'when the press began' do
      it 'reads it on the tick the tap presses' do
        hold_for(1)
        expect(release.down_since(:interact)).to eq(1)
      end

      it 'reads it on the tick the tap releases' do
        hold_for(1)
        release
        released = subject_mapper.poll(backend, step)
        expect([released.released?(:interact), released.down_since(:interact)]).to eq([true, 1])
      end

      it 'forgets it once the tap has released' do
        hold_for(1)
        2.times { release }
        expect(subject_mapper.poll(backend, step).down_since(:interact)).to be_nil
      end

      it 'reads it for the hold, from the poll the button went down on' do
        subject_mapper.poll(backend, step)
        hold_for(3)
        expect(subject_mapper.actions.down_since(:search)).to eq(2)
      end
    end
  end

  # L alone blocks and L+R swaps: while the chord is held, the action on L reads
  # as not held, so a game writes neither a check for the other button nor an
  # order between the two.
  describe 'a chord' do
    subject(:subject_mapper) { mapper(device: pad) }

    let(:pad) { controls.gamepad(0) }

    let(:map) do
      RGame::Engine::InputMap.new(
        block: { buttons: [RGame::Util::Controls::PAD_LEFT_SHOULDER] },
        swap: { all: [RGame::Util::Controls::PAD_LEFT_SHOULDER,
                      RGame::Util::Controls::PAD_RIGHT_SHOULDER] }
      )
    end

    def poll_with(*ids)
      backend.clear
      backend.hold(*ids, device: pad) unless ids.empty?
      subject_mapper.poll(backend, step)
    end

    it 'is not held while only one of its buttons is down' do
      expect(poll_with(controls::PAD_LEFT_SHOULDER).held?(:swap)).to be(false)
    end

    it 'presses when the last of its buttons arrives' do
      poll_with(controls::PAD_LEFT_SHOULDER)
      expect(poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER).pressed?(:swap)).to be(true)
    end

    it 'stays held while every button is down' do
      poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER)
      expect(poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER).held?(:swap)).to be(true)
    end

    it 'releases when one of them comes up' do
      poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER)
      expect(poll_with(controls::PAD_LEFT_SHOULDER).released?(:swap)).to be(true)
    end

    it 'lets the plain action read while the chord is not held' do
      expect(poll_with(controls::PAD_LEFT_SHOULDER).held?(:block)).to be(true)
    end

    it 'silences the plain action on one of its buttons' do
      expect(poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER).held?(:block)).to be(false)
    end

    it 'releases the plain action as the chord takes over' do
      poll_with(controls::PAD_LEFT_SHOULDER)
      expect(poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER).released?(:block)).to be(true)
    end

    it 'gives the plain action back when the chord breaks' do
      poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER)
      expect(poll_with(controls::PAD_LEFT_SHOULDER).held?(:block)).to be(true)
    end

    it 'reads a chord declared for another device as its own' do
      two = RGame::Engine::InputMap.new(
        swap: { all: [[RGame::Util::Controls::KEY_Q, RGame::Util::Controls::KEY_E],
                      [RGame::Util::Controls::PAD_LEFT_SHOULDER,
                       RGame::Util::Controls::PAD_RIGHT_SHOULDER]] }
      )
      backend.hold(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER, device: pad)
      expect(described_class.new(two, device: pad).poll(backend, step).held?(:swap)).to be(true)
    end

    it 'counts the chord\'s own hold' do
      2.times { poll_with(controls::PAD_LEFT_SHOULDER, controls::PAD_RIGHT_SHOULDER) }
      expect(subject_mapper.actions.held_for(:swap)).to be_within(0.0001).of(step * 2)
    end
  end

  # Edge detection compares against the previous poll, so it needs one mapper
  # polled repeatedly rather than a fresh one per poll.
  describe 'edge detection' do
    let(:subject_mapper) { mapper }

    def poll_with(*ids)
      backend.clear
      backend.hold(*ids) unless ids.empty?
      subject_mapper.poll(backend, step)
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
      subject_mapper.poll(backend, step)
      subject_mapper.poll(backend, step) # now held, not pressed, for this one
      expect(other.poll(backend, step).pressed?(:fire)).to be(true)
    end
  end
end
