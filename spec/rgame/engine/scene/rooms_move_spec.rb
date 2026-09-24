# frozen_string_literal: true

# A tick is an eighth of a second, so a Fade of half a second covers in four
# ticks and reveals in four more, with no rounding. Each tick runs as
# RGame::Game runs one: a poll, a control of the whole tree, an update and a
# sweep.
# What a node reads of `:fire`: whether it is held, and how many presses of
# it reached the node.
class FireListener < RGame::Engine::Node2D
  attr_reader :held, :presses

  def initialize(**)
    super
    @held = false
    @presses = 0
  end

  def _control(actions)
    @held = actions.held?(:fire)
    @presses += 1 if actions.pressed?(:fire)
  end
end

# rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, their heroes, the screen and the tree every group shares
RSpec.describe RGame::Engine::Scene::Rooms do
  let(:fade) { RGame::Engine::Scene::Fade.new(cover: 0.5, reveal: 0.5) }
  let(:backend) { FakeInputBackend.new }
  let(:first) { RGame::Engine::Player.new(id: 0, device: RGame::Util::Controls::KEYBOARD) }
  let(:second) { RGame::Engine::Player.new(id: 1, device: RGame::Util::Controls.gamepad(0)) }
  let(:players) { RGame::Engine::Players.new([first, second]) }
  let(:viewports) { RGame::Engine::Viewports.new(players, width: 320, height: 240) }
  let(:root) do
    RGame::Engine::Node2D.new.tap do |root|
      root.add_component(players)
      root.add_component(viewports)
    end
  end
  let(:world) { root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it } }
  let(:rooms) { world.add_component(described_class.new) }
  let(:hero) { RGame::Engine::Node2D.new(input_owner: first) }
  let(:other_hero) { RGame::Engine::Node2D.new(input_owner: second) }

  def dt = 0.125

  def tick
    players.poll(backend, dt)
    root.control(players)
    root.update(dt)
    root.sweep_freed
  end

  # How opaque each player's cover draws: 0 when it draws nothing, and 1.0
  # when it draws with no `faded` around it.
  def covers
    renderer = FakeRenderer.new
    root.draw(renderer, RGame::Engine::View.new(width: 320, height: 240))
    [first, second].map do |player|
      region = viewports.screen_for(player)
      clip = [region.x, region.y, region.width, region.height]
      rect = renderer.calls_to(:rect).find do |call|
        call.transforms.any? { it.name == :clipped && it.args == clip }
      end
      rect ? rect.transforms.find { it.name == :faded }&.args&.first || 1.0 : 0
    end
  end

  # After each of `ticks` ticks: each player's cover, the room the first
  # player stands in, and whether the hero is paused. With a block, what the
  # block answers after each tick instead.
  def run(ticks)
    Array.new(ticks) do
      tick
      block_given? ? yield : [covers, rooms.room_of(first)&.name, hero.suspended?]
    end
  end

  before do
    rooms.define(:town) { SpecRoom.new }
    rooms.define(:garden) { SpecRoom.new }
    root.enter_tree
    rooms.move([hero, other_hero], to: :town, entrance: 'gate')
    tick
    rooms.transition = fade
  end

  # Rules 1 and 3.
  it 'covers the moving player\'s region alone, lands once it is covered, and reveals' do
    rooms.move(hero, to: :garden, entrance: 'well')
    expect(run(9)).to eq([[[0.25, 0], :town, true], [[0.5, 0], :town, true], [[0.75, 0], :town, true],
                          [[1.0, 0], :garden, true], [[0.75, 0], :garden, true], [[0.5, 0], :garden, true],
                          [[0.25, 0], :garden, true], [[0, 0], :garden, false], [[0, 0], :garden, false]])
  end

  # Rule 3.
  it 'stops the node with suspend, and leaves its own paused alone' do
    hero.paused = true
    rooms.move(hero, to: :garden, entrance: 'well')
    expect(run(9) { [hero.paused, hero.suspended?] }.uniq).to eq([[true, true], [true, false]])
  end

  it 'leaves a hold another owner keeps on the node, whichever ends first' do
    hero.suspend
    rooms.move(hero, to: :garden, entrance: 'well')
    run(2)
    hero.resume
    held = run(7) { hero.suspended? }
    rooms.move(hero, to: :town, entrance: 'gate')
    hero.suspend
    run(9)
    expect([held.uniq, hero.suspended?]).to eq([[true, false], true])
  end

  it 'leaves the other player\'s hero running' do
    rooms.move(hero, to: :garden, entrance: 'well')
    expect(run(9) { other_hero.suspended? }.uniq).to eq([false])
  end

  it 'covers both regions for a move of both heroes, and lands them together' do
    rooms.move([hero, other_hero], to: :garden, entrance: 'well')
    expect(run(5) { [covers, rooms.room_of(second)&.name] })
      .to eq([[[0.25, 0.25], :town], [[0.5, 0.5], :town], [[0.75, 0.75], :town], [[1.0, 1.0], :garden],
              [[0.75, 0.75], :garden]])
  end

  it 'starts covered for a player in no room, since there is nothing to cover' do
    lost = RGame::Engine::Player.new(id: 2, device: RGame::Util::Controls.gamepad(1))
    players.add(lost)
    newcomer = RGame::Engine::Node2D.new(input_owner: lost)
    rooms.move(newcomer, to: :garden, entrance: 'well')
    tick
    expect(rooms.room_of(lost)&.name).to eq(:garden)
  end

  it 'runs a move\'s own transition in place of the rooms\', and none for nil' do
    rooms.move(hero, to: :garden, entrance: 'well', transition: nil)
    expect(run(1)).to eq([[[0, 0], :garden, false]])
  end

  # Rule 10.
  it 'covers again from where the reveal got to, for a move asked during it' do
    rooms.move(hero, to: :garden, entrance: 'well')
    run(6)
    rooms.move(hero, to: :town, entrance: 'gate')
    expect(run(3).map { it.first.first }).to eq([0.625, 0.75, 0.875])
  end

  it 'keeps the cover under way for a second move asked during it, and lands only that one' do
    rooms.move(hero, to: :garden, entrance: 'well')
    run(2)
    rooms.move(hero, to: :town, entrance: 'well')
    expect(run(3).map { [it.first.first, it[1]] }).to eq([[0.75, :town], [1.0, :town], [0.75, :town]])
    expect(rooms[:garden]).to be_nil
  end

  it 'reports a transition under way' do
    rooms.move(hero, to: :garden, entrance: 'well')
    under_way = run(8) { rooms.transitioning? }
    expect(under_way).to eq([true] * 7 + [false])
  end

  describe 'the moving player\'s input' do
    # A node of the first player's outside the rooms, as a bag in the world is.
    let(:bag) { root.add_node(FireListener.new(input_owner: first)) }
    let(:other_bag) { root.add_node(FireListener.new(input_owner: second)) }

    it 'is suspended from the request until the reveal ends, and nobody else\'s is' do
      rooms.move(hero, to: :garden, entrance: 'well')
      suspended = [first.input_suspended?] + run(8) { first.input_suspended? }

      expect(suspended).to eq([true] * 8 + [false])
      expect(second.input_suspended?).to be(false)
    end

    it 'reaches no node of that player under the cover, while the other player\'s still reads theirs' do
      bag
      other_bag
      rooms.move(hero, to: :garden, entrance: 'well')
      tick
      backend.hold(RGame::Util::Controls::KEY_SPACE)
             .hold(RGame::Util::Controls::PAD_A, device: RGame::Util::Controls.gamepad(0))
      tick

      expect([bag.held, other_bag.held]).to eq([false, true])
    end

    it 'refuses, once the reveal ends, a press begun under the cover' do
      bag
      rooms.move(hero, to: :garden, entrance: 'well')
      tick
      backend.hold(RGame::Util::Controls::KEY_SPACE)
      run(8)
      under_cover = bag.presses
      backend.release(RGame::Util::Controls::KEY_SPACE)
      tick
      backend.hold(RGame::Util::Controls::KEY_SPACE)
      tick

      expect([under_cover, bag.presses]).to eq([0, 1])
    end

    it 'resumes as the rooms leave the tree mid-move' do
      rooms.move(hero, to: :garden, entrance: 'well')
      root.remove_node(world)

      expect(first.input_suspended?).to be(false)
    end
  end
end
# rubocop:enable RSpec/MultipleMemoizedHelpers
