# frozen_string_literal: true

RSpec.describe RGame::Engine::Player do
  let(:controls) { RGame::Util::Controls }
  let(:backend)  { FakeInputBackend.new }

  describe 'what a player owns' do
    subject(:player) { described_class.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }

    it 'carries its id' do
      expect(player.id).to eq(1)
    end

    it 'has a camera of its own' do
      expect(player.camera).to be_a(RGame::Engine::Camera)
    end

    it 'has a screen-space UI root of its own' do
      expect(player.ui).to be_a(RGame::Engine::Node2D)
    end

    it 'does not share its camera with another player' do
      expect(player.camera).not_to equal(described_class.new(id: 2).camera)
    end

    it 'does not share its UI root with another player' do
      expect(player.ui).not_to equal(described_class.new(id: 2).ui)
    end
  end

  describe 'the device' do
    it 'defaults to the keyboard, which is what single player wants' do
      expect(described_class.new.device).to eq(controls::KEYBOARD)
    end

    it 'reports as active when something is driving it' do
      expect(described_class.new).to be_active
    end

    it 'is an empty seat when it has no device' do
      expect(described_class.new(device: nil)).not_to be_active
    end

    it 'follows a reassignment, which is how a hot-plug lands' do
      player = described_class.new(device: nil)
      player.device = controls.gamepad(2)
      expect(player.device).to eq(controls.gamepad(2))
    end
  end

  describe 'polling' do
    it 'reads its own device' do
      backend.hold(controls::KEY_SPACE)
      player = described_class.new(device: controls::KEYBOARD)
      player.poll(backend)
      expect(player.actions.held?(:fire)).to be(true)
    end

    it 'does not see input meant for another device' do
      backend.hold(controls::PAD_A, device: controls.gamepad(1))
      player = described_class.new(device: controls.gamepad(0))
      player.poll(backend)
      expect(player.actions.held?(:fire)).to be(false)
    end

    it 'reuses one Actions object rather than allocating per tick' do
      player = described_class.new
      expect(player.poll(backend)).to equal(player.poll(backend))
    end

    # An empty seat is polled like any other; it just reads as nothing held.
    # That is what lets a "press a button to join" screen exist with no special
    # case in the tick.
    it 'reads as nothing held when no device is driving it' do
      player = described_class.new(device: nil)
      player.poll(backend)
      expect(player.actions.held?(:fire)).to be(false)
    end

    it 'releases what was held when its device goes away mid-press' do
      backend.hold(controls::KEY_SPACE)
      player = described_class.new(device: controls::KEYBOARD)
      player.poll(backend)
      player.device = nil
      player.poll(backend)
      expect(player.actions.held?(:fire)).to be(false)
    end
  end

  describe 'bindings' do
    it 'takes a map of its own' do
      map = RGame::Engine::InputMap.new(fire: { buttons: [RGame::Util::Controls::KEY_RETURN] })
      expect(described_class.new(input_map: map).input_map).to equal(map)
    end

    # The requirement this whole design exists for: the action *names* are the
    # game's and shared, the physical inputs behind them are per player.
    it 'lets two players answer the same action from different buttons' do
      one = described_class.new(
        id: 0, device: controls::KEYBOARD,
        input_map: RGame::Engine::InputMap.new(fire: { buttons: [RGame::Util::Controls::KEY_SPACE] })
      )
      two = described_class.new(
        id: 1, device: controls.gamepad(0),
        input_map: RGame::Engine::InputMap.new(fire: { buttons: [RGame::Util::Controls::PAD_X] })
      )

      backend.hold(controls::KEY_SPACE)
      backend.hold(controls::PAD_X, device: controls.gamepad(0))
      [one, two].each { |player| player.poll(backend) }

      expect([one.actions.held?(:fire), two.actions.held?(:fire)]).to eq([true, true])
    end

    it 'keeps their edges independent, so one press cannot consume another' do
      one = described_class.new(id: 0)
      two = described_class.new(id: 1)
      backend.hold(controls::KEY_SPACE)

      one.poll(backend)
      one.poll(backend) # held now, not pressed, for this player only
      two.poll(backend)

      expect([one.actions.pressed?(:fire), two.actions.pressed?(:fire)]).to eq([false, true])
    end
  end
end
