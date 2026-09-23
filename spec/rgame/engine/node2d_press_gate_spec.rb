# frozen_string_literal: true

# A node that logs the edges of fire it reads, and whether fire was held.
class SpecEdgeReader < RGame::Engine::Node2D
  attr_reader :log

  def initialize(**)
    super
    @log = []
  end

  def _control(actions)
    @log << :pressed if actions.pressed?(:fire)
    @log << :released if actions.released?(:fire)
    @log << :held if actions.held?(:fire)
  end
end

# A node reads the edges of a press only if it saw the press start. Each example
# ticks as RGame::Game does, a poll and then a control of the whole tree, and
# the reader is controlled on the ticks before anything is pressed unless the
# example says otherwise.
# rubocop:disable RSpec/MultipleMemoizedHelpers -- the players, backend, root and reader every group shares
RSpec.describe RGame::Engine::Node2D do
  let(:controls) { RGame::Util::Controls }
  let(:backend) { FakeInputBackend.new }
  let(:one) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD) }
  let(:players) { RGame::Engine::Players.new([one]) }
  let(:root) { described_class.new }
  let(:reader) { SpecEdgeReader.new }

  def tick(times = 1)
    times.times do
      players.poll(backend, 1.0 / 60)
      root.control(players)
    end
  end

  def press = backend.hold(controls::KEY_SPACE)
  def release = backend.release(controls::KEY_SPACE)

  describe 'a node controlled on every tick' do
    before do
      root.add_node(reader)
      tick
    end

    it 'reads the press and the release' do
      press
      tick(2)
      release
      tick
      expect(reader.log).to eq(%i[pressed held held released])
    end
  end

  # Rule 1: a press begun before the node resumed reaches it as a held button
  # with no edges.
  describe 'a node under a paused parent' do
    let(:parent) { root.add_node(described_class.new) }

    before do
      parent.add_node(reader)
      tick
      parent.paused = true
    end

    it 'reads no edge of a press begun while it was paused' do
      press
      tick
      parent.paused = false
      tick
      release
      tick
      expect(reader.log).to eq(%i[held])
    end

    # Rule 3: the level passes through, so a direction held across the pause
    # still walks the hero.
    it 'still reads the press as held' do
      press
      tick
      parent.paused = false
      tick(2)
      expect(reader.log).to eq(%i[held held])
    end

    # Rule 4.
    it 'reads the next press as usual' do
      press
      tick
      parent.paused = false
      tick
      release
      tick
      press
      tick
      expect(reader.log.last(2)).to eq(%i[pressed held])
    end

    # Rule 2, as Menu refuses a confirm already down when it opens.
    it 'refuses a press begun on the tick it resumed' do
      tick
      parent.paused = false
      press
      tick
      release
      tick
      expect(reader.log).to eq(%i[held])
    end
  end

  describe 'a scene popped back to' do
    let(:stack) { RGame::Engine::Scene::SceneStack.new }
    let(:host) { root.add_node(described_class.new) }
    let(:above) { described_class.new }

    before do
      root.add_component(players)
      host.add_component(stack)
      root.enter_tree
      stack.push(reader)
      tick
      stack.push(above)
    end

    it 'reads no edge of a press begun while a scene was above it' do
      press
      tick
      stack.pop
      tick
      release
      tick
      expect(reader.log).to eq(%i[held])
    end
  end

  describe 'a node added while a press is held' do
    it 'reads no edge of that press' do
      press
      tick
      root.add_node(reader)
      tick
      release
      tick
      expect(reader.log).to eq(%i[held])
    end

    # Rule 2 again: its first control is the tick it resumed on.
    it 'refuses a press begun on its first tick' do
      root.add_node(reader)
      press
      tick
      release
      tick
      expect(reader.log).to eq(%i[held])
    end
  end

  # Rule 5: from the change on, the node reads another player's presses, and
  # it saw none of them start.
  describe 'a node whose owner changes' do
    let(:two) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
    let(:players) { RGame::Engine::Players.new([one, two]) }

    def press_two = backend.hold(controls::PAD_A, device: controls.gamepad(0))
    def release_two = backend.release(controls::PAD_A, device: controls.gamepad(0))

    before do
      root.add_node(reader)
      reader.input_owner = one
      tick
    end

    it 'reads no edge of the new owner\'s press under way' do
      press_two
      tick
      reader.input_owner = two
      tick
      release_two
      tick
      expect(reader.log).to eq(%i[held])
    end

    it 'reads the new owner\'s next press' do
      reader.input_owner = two
      tick
      press_two
      tick
      expect(reader.log).to eq(%i[pressed held])
    end
  end

  # Rule 6: a press of everyone began with its first member's.
  describe 'a node everyone owns' do
    let(:two) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
    let(:players) { RGame::Engine::Players.new([one, two]) }

    before do
      root.add_node(reader)
      reader.input_owner = players.everyone
    end

    it 'reads no edge of a press the first player began before it resumed' do
      # The second player joins the press after the node resumed, and starts
      # nothing: the union went down with the first.
      tick
      reader.paused = true
      press
      tick
      reader.paused = false
      backend.hold(controls::PAD_A, device: controls.gamepad(0))
      tick
      release
      backend.release(controls::PAD_A, device: controls.gamepad(0))
      tick
      expect(reader.log).to eq(%i[held])
    end
  end

  # Rule 7: a spec passing a snapshot of its own reads what it passed.
  describe 'a snapshot built by hand' do
    let(:snapshot) { RGame::Engine::Actions.new(held: { fire: true }, prev_held: { fire: false }) }

    it 'is handed on as it is' do
      root.add_node(reader)
      root.control(snapshot)
      expect(reader.log).to eq(%i[pressed held])
    end
  end

  # The caller the gate exists for. The bag pauses the hero, and E is a tap:
  # begun in the bag and ended after it closes, it would press on the release
  # and open the chest in reach.
  describe 'a hero paused by a bag' do
    let(:map) { RGame::Engine::InputMap.default.merge(interact: { buttons: [controls::KEY_E], tap: 0.3 }) }
    let(:one) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD, input_map: map) }
    let(:opened) { [] }
    let(:hero) do
      described_class.new(x: 100, y: 100).tap do |node|
        node.add_component(RGame::Engine::Components::Interactor.new(range: 56))
            .on_interacted { |chest| opened << chest }
      end
    end
    let(:chest) do
      described_class.new(x: 140, y: 100).tap do |node|
        node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 10, layer: :interactable))
      end
    end

    def step(times = 1)
      times.times do
        players.poll(backend, 1.0 / 60)
        root.update(1.0 / 60)
        root.control(players)
      end
    end

    def tap_e(across: nil)
      backend.hold(controls::KEY_E)
      step(2)
      across&.call
      backend.release(controls::KEY_E)
      step
    end

    before do
      root.scene = root
      root.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      root.add_node(chest)
      root.add_node(hero)
      root.enter_tree
      step
    end

    it 'opens the chest on a tap' do
      tap_e
      expect(opened).to eq([chest])
    end

    it 'opens nothing on a tap begun in the bag' do
      hero.paused = true
      tap_e(across: -> { hero.paused = false })
      expect(opened).to be_empty
    end

    it 'opens the chest on the next tap' do
      hero.paused = true
      tap_e(across: -> { hero.paused = false })
      tap_e
      expect(opened).to eq([chest])
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
