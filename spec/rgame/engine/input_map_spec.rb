# frozen_string_literal: true

RSpec.describe RGame::Engine::InputMap do
  let(:controls) { RGame::Util::Controls }

  describe 'the universal UI set' do
    it 'is present in a map that declares nothing' do
      expect(described_class.new.actions).to include(:ui_up, :ui_down, :ui_left, :ui_right,
                                                     :ui_confirm, :ui_cancel)
    end

    it 'is still present alongside a game\'s own actions' do
      map = described_class.new(fire: { buttons: [controls::KEY_SPACE] })
      expect(map.actions).to include(:fire, :ui_confirm)
    end

    it 'binds ui_cancel to Escape, which is why Game quits on F2' do
      expect(described_class.new[:ui_cancel].buttons).to include(controls::KEY_ESCAPE)
    end

    it 'lets a game override one of them' do
      map = described_class.new(ui_confirm: { buttons: [controls::PAD_X] })
      expect(map[:ui_confirm].buttons).to eq([controls::PAD_X])
    end
  end

  describe 'one table for every device' do
    it 'lists a key and a pad button for the same action' do
      binding = described_class.default[:fire]
      expect(binding.buttons).to include(controls::KEY_SPACE, controls::PAD_A)
    end
  end

  describe 'sources' do
    it 'resolves a button list' do
      map = described_class.new(fire: { buttons: [controls::KEY_SPACE, controls::PAD_A] })
      expect(map[:fire].buttons).to eq([controls::KEY_SPACE, controls::PAD_A])
    end

    it 'resolves a two-button axis into a negative/positive pair' do
      map = described_class.new(turn: { axis: [controls::KEY_LEFT, controls::KEY_RIGHT] })
      expect(map[:turn].pairs).to eq([[controls::KEY_LEFT, controls::KEY_RIGHT]])
    end

    # Several pairs is how the arrows, WASD and a d-pad all drive one action —
    # the same thing `buttons:` does for a button, which an axis needed too.
    it 'resolves a list of pairs' do
      map = described_class.new(
        move: { axis: [[controls::KEY_LEFT, controls::KEY_RIGHT],
                       [controls::PAD_DPAD_LEFT, controls::PAD_DPAD_RIGHT]] }
      )
      expect(map[:move].pairs)
        .to eq([[controls::KEY_LEFT, controls::KEY_RIGHT],
                [controls::PAD_DPAD_LEFT, controls::PAD_DPAD_RIGHT]])
    end

    it 'resolves an analog stick' do
      map = described_class.new(turn: { stick: controls::AXIS_LEFT_X })
      expect(map[:turn].stick).to eq(controls::AXIS_LEFT_X)
    end

    it 'lets one action carry buttons and a stick at once' do
      map = described_class.new(move: { axis: [controls::KEY_LEFT, controls::KEY_RIGHT],
                                        stick: controls::AXIS_LEFT_X })
      expect([map[:move].pairs.first.last, map[:move].stick])
        .to eq([controls::KEY_RIGHT, controls::AXIS_LEFT_X])
    end
  end

  # A map that reads as "nothing is ever pressed" is the failure this catches:
  # without it a typo surfaces as a frame nobody can move in, far from its cause.
  describe 'entries it refuses' do
    it 'names the action when a source is unknown' do
      expect { described_class.new(fire: { button: [controls::KEY_SPACE] }) }
        .to raise_error(ArgumentError, /fire.*:button/)
    end

    it 'refuses an entry with no source at all' do
      expect { described_class.new(fire: {}) }
        .to raise_error(ArgumentError, /fire.*no buttons, axis or stick/)
    end

    it 'refuses an empty button list' do
      expect { described_class.new(fire: { buttons: [] }) }
        .to raise_error(ArgumentError, /fire.*list of ids/)
    end

    it 'refuses a single id where a button list belongs' do
      expect { described_class.new(fire: { buttons: controls::KEY_SPACE }) }
        .to raise_error(ArgumentError, /fire.*list of ids/)
    end

    it 'refuses an axis that is not a pair' do
      expect { described_class.new(turn: { axis: [controls::KEY_LEFT] }) }
        .to raise_error(ArgumentError, /turn.*negative_id, positive_id/)
    end
  end

  describe '#merge' do
    it 'overrides one action and keeps the rest' do
      map = described_class.default.merge(fire: { buttons: [controls::KEY_RETURN] })
      expect(map[:fire].buttons).to eq([controls::KEY_RETURN])
    end

    it 'keeps the actions it did not touch' do
      map = described_class.default.merge(fire: { buttons: [controls::KEY_RETURN] })
      expect(map[:move_x].stick).to eq(controls::AXIS_LEFT_X)
    end

    it 'leaves the map it was called on alone' do
      original = described_class.default
      original.merge(fire: { buttons: [controls::KEY_RETURN] })
      expect(original[:fire].buttons).to include(controls::KEY_SPACE)
    end
  end

  describe 'the defaults' do
    it 'binds move_x to the arrows, WASD, the d-pad and the left stick together' do
      binding = described_class.default[:move_x]
      expect([binding.pairs, binding.stick])
        .to eq([[[controls::KEY_LEFT, controls::KEY_RIGHT],
                 [controls::KEY_A, controls::KEY_D],
                 [controls::PAD_DPAD_LEFT, controls::PAD_DPAD_RIGHT]],
                controls::AXIS_LEFT_X])
    end

    # Without a d-pad pair a controller cannot drive movement at all, because
    # the same action already needed the arrow keys and an axis took one pair.
    it 'lets a controller walk on its d-pad' do
      expect(described_class.default[:move_x].pairs)
        .to include([controls::PAD_DPAD_LEFT, controls::PAD_DPAD_RIGHT])
    end

    # Screen y is positive downwards and so is the stick, so "up" is the
    # negative half. Getting this backwards inverts every game built on it.
    it 'binds move_y with up as the negative half of every pair' do
      expect(described_class.default[:move_y].pairs.map(&:first))
        .to eq([controls::KEY_UP, controls::KEY_W, controls::PAD_DPAD_UP])
    end
  end
end
