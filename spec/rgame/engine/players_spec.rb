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

    it 'gives a new controller to the first seat waiting for one' do
      expect(players.claim_gamepad(0)).to equal(waiting)
    end

    it 'seats them on that slot\'s device' do
      players.claim_gamepad(2)
      expect(waiting.device).to eq(controls.gamepad(2))
    end

    # A controller arriving must never take the game away from someone already
    # playing, which is why only empty seats are filled.
    it 'leaves a player who already has a device alone' do
      players.claim_gamepad(0)
      expect(seated.device).to eq(controls::KEYBOARD)
    end

    it 'reports nobody when every seat is taken' do
      expect(described_class.new([seated]).claim_gamepad(0)).to be_nil
    end

    it 'empties the seat when its controller leaves' do
      players.claim_gamepad(1)
      players.release_gamepad(1)
      expect(waiting).not_to be_active
    end

    # The player survives the unplug — same camera, same bindings, same UI — so
    # plugging back in resumes rather than restarts.
    it 'keeps the player and their camera across an unplug' do
      camera = waiting.camera
      players.claim_gamepad(1)
      players.release_gamepad(1)
      players.claim_gamepad(1)
      expect([players[1], players[1].camera]).to eq([waiting, camera])
    end

    it 'ignores a slot nobody was on' do
      expect(players.release_gamepad(3)).to be_nil
    end
  end
end
