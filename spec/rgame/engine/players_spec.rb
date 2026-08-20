# frozen_string_literal: true

RSpec.describe RGame::Engine::Players do
  let(:controls) { RGame::Util::Controls }
  let(:backend)  { FakeInputBackend.new }

  def player(id, device: RGame::Util::Controls::KEYBOARD)
    RGame::Engine::Player.new(id: id, device: device)
  end

  describe 'as a root-scoped system' do
    it 'is reachable from a node deep in the tree' do
      root = RGame::Engine::Node2D.new
      registry = root.add_component(described_class.new([player(0)]))
      leaf = RGame::Engine::Node2D.new
      root.add_node(RGame::Engine::Node2D.new).add_node(leaf)

      expect(leaf.system(described_class)).to equal(registry)
    end
  end

  describe '#primary' do
    it 'is the first player, which is what an unowned node reads from' do
      first = player(0)
      expect(described_class.new([first, player(1)]).primary).to equal(first)
    end
  end

  describe 'the list' do
    subject(:players) { described_class.new([player(0), player(1, device: nil)]) }

    it 'enumerates every player, seated or not' do
      expect(players.map(&:id)).to eq([0, 1])
    end

    it 'looks one up by id' do
      expect(players[1].id).to eq(1)
    end

    it 'counts only the ones a device is driving' do
      expect(players.active_count).to eq(1)
    end

    # A viewport loop walks this, so an empty seat gets no share of the screen.
    it 'skips empty seats when iterating the active ones' do
      expect(players.each_active.map(&:id)).to eq([0])
    end

    it 'takes a player added later' do
      players.add(player(2))
      expect(players.map(&:id)).to eq([0, 1, 2])
    end
  end

  describe '#poll' do
    it 'polls every player in one call' do
      players = described_class.new([player(0), player(1, device: controls.gamepad(0))])
      backend.hold(controls::KEY_SPACE)
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      players.poll(backend)

      expect(players.map { |p| p.actions.held?(:fire) }).to eq([true, true])
    end

    it 'gives each player only their own device\'s input' do
      players = described_class.new([player(0), player(1, device: controls.gamepad(0))])
      backend.hold(controls::KEY_SPACE) # keyboard only
      players.poll(backend)

      expect(players.map { |p| p.actions.held?(:fire) }).to eq([true, false])
    end
  end

  describe 'hot-plug' do
    subject(:players) { described_class.new([seated, waiting]) }

    let(:seated)  { player(0, device: RGame::Util::Controls::KEYBOARD) }
    let(:waiting) { player(1, device: nil) }

    # A connect says something about hardware. Seating a player creates a
    # camera, a viewport and a screen split, so it waits for someone to use the
    # thing.
    it 'does not seat anyone just because a controller arrived' do
      players.device_connected(0)
      expect(waiting).not_to be_active
    end

    it 'empties the seat when its controller leaves' do
      players.device_connected(0)
      players.seat(controls.gamepad(0))
      players.device_disconnected(0)
      expect(waiting).not_to be_active
    end

    # The player survives the unplug — same camera, same bindings, same UI — so
    # plugging back in resumes rather than restarts.
    it 'keeps the player and their camera across an unplug' do
      camera = waiting.camera
      players.device_connected(1)
      players.seat(controls.gamepad(1))
      players.device_disconnected(1)
      expect([players[1], players[1].camera]).to eq([waiting, camera])
    end

    it 'ignores a slot nobody was on' do
      expect(players.device_disconnected(3)).to be_nil
    end
  end

  describe 'joining' do
    subject(:players) { described_class.new([seated, waiting]) }

    let(:seated)  { player(0, device: RGame::Util::Controls::KEYBOARD) }
    let(:waiting) { player(1, device: nil) }

    let(:confirm) { RGame::Engine::InputMap.default[:ui_confirm].buttons.first }

    def press_on(slot)
      players.device_connected(slot)
      backend.hold(confirm, device: controls.gamepad(slot))
      players.poll(backend)
    end

    it 'defaults to :join when the game asked for more than one seat' do
      expect(players.on_unassigned_input).to eq(:join)
    end

    it 'seats the next free player when an unassigned pad is used' do
      press_on(0)
      expect(waiting.device).to eq(controls.gamepad(0))
    end

    it 'announces who joined, so a scene can spawn their avatar' do
      joined = nil
      players.on_joined { |player| joined = player }
      press_on(0)
      expect(joined).to equal(waiting)
    end

    it 'leaves a player who already has a device alone' do
      press_on(0)
      expect(seated.device).to eq(controls::KEYBOARD)
    end

    # A pad that is plugged in and left alone is somebody's spare, or a charging
    # cable. Nothing should happen.
    it 'seats nobody while the pad stays silent' do
      players.device_connected(0)
      players.poll(backend)
      expect(waiting).not_to be_active
    end

    it 'seats nobody while joining is closed' do
      players.accepting_joins = false
      press_on(0)
      expect(waiting).not_to be_active
    end

    it 'seats them once joining reopens' do
      players.accepting_joins = false
      press_on(0)
      players.accepting_joins = true
      backend.clear
      players.poll(backend) # release, so the next press is an edge
      press_on(0)
      expect(waiting).to be_active
    end

    # An edge, not a held button: one press does one thing.
    it 'does not seat a second player from one continuous press' do
      press_on(0)
      players.device_connected(1)
      backend.hold(confirm, device: controls.gamepad(1))
      players.poll(backend)
      expect(players.count(&:active?)).to eq(2) # the keyboard seat and pad 0
    end

    it 'stops looking once every seat is taken' do
      press_on(0)
      expect(players.seat(controls.gamepad(1))).to be_nil
    end

    it 'ignores an unassigned device entirely under :ignore' do
      players.on_unassigned_input = :ignore
      press_on(0)
      expect(waiting).not_to be_active
    end
  end

  describe 'taking over' do
    subject(:players) { described_class.new([solo]) }

    let(:solo) { player(0, device: RGame::Util::Controls::KEYBOARD) }
    let(:confirm) { RGame::Engine::InputMap.default[:ui_confirm].buttons.first }

    it 'is the default when there is one seat' do
      expect(players.on_unassigned_input).to eq(:takeover)
    end

    # The scenario connect-to-join could not express at all: one person, already
    # playing, picks up a controller. That is not a second player arriving.
    it 'moves the only player onto a pad they start using' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend)

      expect(solo.device).to eq(controls.gamepad(0))
    end

    it 'adds no second player' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend)

      expect(players.list.size).to eq(1)
    end

    # Once they are on the pad the keyboard is unassigned, so using it takes
    # them back — last device used wins, which is what one player expects.
    it 'moves them back to the keyboard when they use it again' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend)

      backend.clear
      backend.hold(confirm, device: controls::KEYBOARD)
      players.poll(backend)

      expect(solo.device).to eq(controls::KEYBOARD)
    end

    # Emptying the seat would leave the game dead in their hands: there is no
    # second player for them to become.
    it 'falls back to the keyboard when their pad is unplugged' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend)
      players.device_disconnected(0)

      expect(solo.device).to eq(controls::KEYBOARD)
    end
  end

  # It runs every tick for every unassigned device, and a steady drip is exactly
  # what the debug overlay's Δ/f exists to catch.
  it 'scans for joiners without allocating' do
    players = described_class.new([player(0), player(1, device: nil)])
    players.device_connected(0)
    players.poll(backend)
    expect { players.poll(backend) }.to allocate_nothing
  end
end
