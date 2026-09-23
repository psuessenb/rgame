# frozen_string_literal: true

# A node that remembers whether fire was held when it was last controlled.
class SpecFireReadingNode < RGame::Engine::Node2D
  attr_reader :fire_held

  def _control(actions) = @fire_held = actions.held?(:fire)
end

# rubocop:disable RSpec/MultipleMemoizedHelpers -- every group reads the file's controls, backend and step
RSpec.describe RGame::Engine::Players do
  let(:controls) { RGame::Util::Controls }
  let(:backend)  { FakeInputBackend.new }
  let(:step)     { 1.0 / 60 }

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
      players.poll(backend, step)

      expect(players.map { |p| p.actions.held?(:fire) }).to eq([true, true])
    end

    it 'gives each player only their own device\'s input' do
      players = described_class.new([player(0), player(1, device: controls.gamepad(0))])
      backend.hold(controls::KEY_SPACE) # keyboard only
      players.poll(backend, step)

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
      players.poll(backend, step)
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
      players.poll(backend, step)
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
      players.poll(backend, step) # release, so the next press is an edge
      press_on(0)
      expect(waiting).to be_active
    end

    # An edge, not a held button: one press does one thing.
    it 'does not seat a second player from one continuous press' do
      press_on(0)
      players.device_connected(1)
      backend.hold(confirm, device: controls.gamepad(1))
      players.poll(backend, step)
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
      players.poll(backend, step)

      expect(solo.device).to eq(controls.gamepad(0))
    end

    it 'adds no second player' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend, step)

      expect(players.list.size).to eq(1)
    end

    # Once they are on the pad the keyboard is unassigned, so using it takes
    # them back — last device used wins, which is what one player expects.
    it 'moves them back to the keyboard when they use it again' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend, step)

      backend.clear
      backend.hold(confirm, device: controls::KEYBOARD)
      players.poll(backend, step)

      expect(solo.device).to eq(controls::KEYBOARD)
    end

    # Emptying the seat would leave the game dead in their hands: there is no
    # second player for them to become.
    it 'falls back to the keyboard when their pad is unplugged' do
      players.device_connected(0)
      backend.hold(confirm, device: controls.gamepad(0))
      players.poll(backend, step)
      players.device_disconnected(0)

      expect(solo.device).to eq(controls::KEYBOARD)
    end
  end

  describe '#everyone' do
    subject(:players) { described_class.new([one, two]) }

    let(:one) { player(0) }
    let(:two) { player(1, device: controls.gamepad(0)) }
    let(:pad) { controls.gamepad(0) }

    def everyone_after_poll
      players.poll(backend, step)
      players.everyone.actions
    end

    it 'is held while either player holds the action' do
      backend.hold(controls::PAD_A, device: pad)
      expect(everyone_after_poll.held?(:fire)).to be(true)
    end

    it 'is not held while nobody holds it' do
      expect(everyone_after_poll.held?(:fire)).to be(false)
    end

    it 'is pressed on the tick one player presses' do
      everyone_after_poll
      backend.hold(controls::KEY_SPACE)
      expect(everyone_after_poll.pressed?(:fire)).to be(true)
    end

    # One press does one thing: the union is already down, so the second
    # player's press is no edge of it.
    it 'is not pressed when a second player presses while the first holds' do
      backend.hold(controls::KEY_SPACE)
      everyone_after_poll
      backend.hold(controls::PAD_A, device: pad)
      expect(everyone_after_poll.pressed?(:fire)).to be(false)
    end

    it 'is not released while the second player still holds' do
      backend.hold(controls::KEY_SPACE)
      backend.hold(controls::PAD_A, device: pad)
      everyone_after_poll
      backend.release(controls::KEY_SPACE)
      expect(everyone_after_poll.released?(:fire)).to be(false)
    end

    it 'is released when the last holder lets go' do
      backend.hold(controls::KEY_SPACE)
      everyone_after_poll
      backend.release(controls::KEY_SPACE)
      expect(everyone_after_poll.released?(:fire)).to be(true)
    end

    it 'reads the axis of largest magnitude' do
      backend.hold(controls::KEY_LEFT)
      backend.set_axis(controls::AXIS_LEFT_X, 0.6, device: pad)
      expect(everyone_after_poll.axis(:move_x)).to eq(-1.0)
    end

    it 'reads a positive axis over a smaller negative one' do
      backend.set_axis(controls::AXIS_LEFT_X, -0.3, device: pad)
      backend.hold(controls::KEY_RIGHT)
      expect(everyone_after_poll.axis(:move_x)).to eq(1.0)
    end

    # The longest hold wins, as the largest axis does: one player holding a door
    # open is the door being held open.
    it 'reads the longest of the players\' holds' do
      backend.hold(controls::KEY_SPACE)
      3.times { everyone_after_poll }
      backend.hold(controls::PAD_A, device: pad)
      expect(everyone_after_poll.held_for(:fire)).to be_within(0.0001).of(step * 4)
    end

    it 'reads nothing while nobody holds the action' do
      expect(everyone_after_poll.held_for(:fire)).to eq(0.0)
    end

    it 'forgets the hold once every player has let go' do
      backend.hold(controls::KEY_SPACE)
      2.times { everyone_after_poll }
      backend.release(controls::KEY_SPACE)
      2.times { everyone_after_poll }
      expect(everyone_after_poll.held_for(:fire)).to eq(0.0)
    end

    it 'raises for an action no active player declares' do
      expect { everyone_after_poll.held?(:fyre) }.to raise_error(KeyError, /:fyre/)
    end

    it 'counts its own polls' do
      2.times { everyone_after_poll }
      expect(everyone_after_poll.poll_count).to eq(3)
    end

    describe '#down_since' do
      it 'is the poll one player pressed on' do
        everyone_after_poll
        backend.hold(controls::KEY_SPACE)
        expect(everyone_after_poll.down_since(:fire)).to eq(2)
      end

      # The union went down with the first press, so a second player joining in
      # starts nothing.
      it 'keeps the first press while a second player joins it' do
        backend.hold(controls::KEY_SPACE)
        everyone_after_poll
        backend.hold(controls::PAD_A, device: pad)
        expect(everyone_after_poll.down_since(:fire)).to eq(1)
      end

      it 'keeps the first press while its player lets go and another still holds' do
        backend.hold(controls::KEY_SPACE)
        everyone_after_poll
        backend.hold(controls::PAD_A, device: pad)
        everyone_after_poll
        backend.release(controls::KEY_SPACE)
        2.times { everyone_after_poll }
        expect(everyone_after_poll.down_since(:fire)).to eq(1)
      end

      it 'is nil once every player has let go' do
        backend.hold(controls::KEY_SPACE)
        everyone_after_poll
        backend.release(controls::KEY_SPACE)
        2.times { everyone_after_poll }
        expect(everyone_after_poll.down_since(:fire)).to be_nil
      end

      it 'starts again on the next press' do
        backend.hold(controls::KEY_SPACE)
        everyone_after_poll
        backend.release(controls::KEY_SPACE)
        2.times { everyone_after_poll }
        backend.hold(controls::PAD_A, device: pad)
        expect(everyone_after_poll.down_since(:fire)).to eq(4)
      end
    end

    context 'when only one player declares an action' do
      let(:two) do
        map = RGame::Engine::InputMap.default.merge(dash: { buttons: [controls::PAD_B] })
        RGame::Engine::Player.new(id: 1, device: pad, input_map: map)
      end

      it 'reads it from that player' do
        backend.hold(controls::PAD_B, device: pad)
        expect(everyone_after_poll.held?(:dash)).to be(true)
      end

      it 'raises for it once that player has left' do
        players.device_disconnected(0)
        expect { everyone_after_poll.held?(:dash) }.to raise_error(KeyError)
      end
    end

    it 'leaves out a seat nobody is in' do
      players.device_disconnected(0)
      backend.hold(controls::PAD_A, device: pad)
      expect(everyone_after_poll.held?(:fire)).to be(false)
    end

    it 'takes in a player who joins' do
      players.device_disconnected(0)
      everyone_after_poll
      players.device_connected(0)
      players.seat(pad)
      backend.hold(controls::PAD_A, device: pad)
      expect(everyone_after_poll.held?(:fire)).to be(true)
    end

    context 'with no active player' do
      let(:two) { player(1, device: nil) }

      let(:one) do
        map = RGame::Engine::InputMap.default.merge(dash: { buttons: [controls::PAD_B] })
        RGame::Engine::Player.new(id: 0, device: nil, input_map: map)
      end

      it 'reads the primary player' do
        expect { everyone_after_poll.held?(:dash) }.not_to raise_error
      end
    end

    it 'is the same object before the first poll as after it' do
      held = players.everyone.actions
      expect(everyone_after_poll).to equal(held)
    end

    it 'is what a node owned by it reads' do
      root = RGame::Engine::Node2D.new
      root.add_component(players)
      node = root.add_node(SpecFireReadingNode.new(input_owner: players.everyone))
      backend.hold(controls::PAD_A, device: pad)
      players.poll(backend, step)
      root.control(players)

      expect(node.fire_held).to be(true)
    end

    it 'polls and reads without allocating' do
      backend.hold(controls::KEY_SPACE)
      backend.set_axis(controls::AXIS_LEFT_X, 0.6, device: pad)
      players.poll(backend, step)
      actions = players.everyone.actions
      expect do
        players.poll(backend, step)
        actions.held?(:fire)
        actions.pressed?(:fire)
        actions.axis(:move_x)
      end.to allocate_nothing
    end
  end

  # It runs every tick for every unassigned device, and a steady drip is exactly
  # what the debug overlay's Δ/f exists to catch.
  it 'scans for joiners without allocating' do
    players = described_class.new([player(0), player(1, device: nil)])
    players.device_connected(0)
    players.poll(backend, step)
    expect { players.poll(backend, step) }.to allocate_nothing
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
