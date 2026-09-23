# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Interactor do
  # The same arrangement a game has: a scene boundary carrying the broadphase,
  # interactable nodes whose colliders register with it, and a hero carrying the
  # component under test. A tick rebuilds the index (update) and then reads the
  # press (control) — in that order, because a press acts on the target the last
  # update chose.
  let(:controls) { RGame::Util::Controls }
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:backend) { FakeInputBackend.new }
  # One player, so `actions_for(nil)` resolves to them and no node needs an owner.
  let(:players) do
    RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD)])
  end

  before do
    scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  def chest(x, y, layer: :interactable)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 10, layer: layer))
    scene.add_node(node)
    node
  end

  def hero(x, y, range: 56, **)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    interactor = node.add_component(described_class.new(range: range, **))
    scene.add_node(node)
    interactor
  end

  def tick
    players.poll(backend, 1.0 / 60)
    scene.update(1.0 / 60)
    scene.control(players)
  end

  describe '#target' do
    it 'is the nearest node in range on its layer' do
      chest(200, 100)
      near = chest(140, 100)
      interactor = hero(100, 100)

      tick

      expect(interactor.target).to be(near)
    end

    it 'is nil when nothing is in range' do
      chest(300, 100)
      interactor = hero(100, 100)

      tick

      expect(interactor.target).to be_nil
    end

    it 'ignores a node on another layer' do
      chest(120, 100, layer: :wall)
      interactor = hero(100, 100)

      tick

      expect(interactor.target).to be_nil
    end

    # Rule 3's second half: the target is refreshed every update rather than
    # held until something replaces it, so walking away clears it.
    it 'clears on the update after the target leaves range' do
      box = chest(140, 100)
      interactor = hero(100, 100)
      tick

      box.x = 300
      tick

      expect(interactor.target).to be_nil
    end
  end

  describe 'the press' do
    let(:seen) { [] }

    def interactor_at(x, y, **)
      hero(x, y, **).tap { it.on_interacted { |target| seen << target } }
    end

    it 'emits the target once per press' do
      box = chest(140, 100)
      interactor_at(100, 100)

      backend.hold(controls::KEY_E)
      tick
      tick

      expect(seen).to eq([box])
    end

    it 'emits again on a second press' do
      chest(140, 100)
      interactor_at(100, 100)

      backend.hold(controls::KEY_E)
      tick
      backend.release(controls::KEY_E)
      tick
      backend.hold(controls::KEY_E)
      tick

      expect(seen.length).to eq(2)
    end

    it 'emits nothing while nothing is in range' do
      chest(300, 100)
      interactor_at(100, 100)

      backend.hold(controls::KEY_E)
      tick

      expect(seen).to be_empty
    end

    it 'emits nothing on a target that has left range' do
      box = chest(140, 100)
      interactor_at(100, 100)
      tick

      box.x = 300
      backend.hold(controls::KEY_E)
      tick

      expect(seen).to be_empty
    end

    it 'emits nothing while the action is held rather than pressed' do
      chest(140, 100)
      interactor_at(100, 100)
      backend.hold(controls::KEY_E)

      5.times { tick }

      expect(seen.length).to eq(1)
    end

    # An action of the game's own, which its map has to declare: Actions answers
    # only for what it was given, so a typo here raises rather than reading as
    # never pressed.
    describe 'an action the game named itself' do
      let(:players) do
        map = RGame::Engine::InputMap.default.merge(use: { buttons: [controls::KEY_F] })
        RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD,
                                                              input_map: map)])
      end

      it 'reads that action rather than the default' do
        box = chest(140, 100)
        interactor_at(100, 100, action: :use)

        backend.hold(controls::KEY_F)
        tick

        expect(seen).to eq([box])
      end

      it 'ignores the default action' do
        chest(140, 100)
        interactor_at(100, 100, action: :use)

        backend.hold(controls::KEY_E)
        tick

        expect(seen).to be_empty
      end
    end
  end

  # Rule 8. An Interactor reads the actions of whoever owns its node, which the
  # control traversal resolves — so two heroes either side of one chest press
  # their own button and reach their own target, with nothing per-player in the
  # component itself.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, the registry, the
  # chest and what was seen: a two-player example needs both seats named
  describe 'two players, one chest between them' do
    let(:one) { RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD) }
    let(:two) { RGame::Engine::Player.new(id: 1, device: controls.gamepad(0)) }
    let(:players) { RGame::Engine::Players.new([one, two]) }

    let(:box) { chest(200, 100) }
    let(:seen) { [] }

    def owned_hero(x, player)
      interactor = hero(x, 100)
      interactor.node.input_owner = player
      interactor.on_interacted { |target| seen << [player.id, target] }
      interactor
    end

    before do
      box
      owned_hero(160, one)
      owned_hero(240, two)
    end

    it 'lets each player reach it with their own button' do
      backend.hold(controls::KEY_E)
      backend.hold(controls::PAD_X, device: controls.gamepad(0))

      tick

      expect(seen).to eq([[0, box], [1, box]])
    end

    it 'does not let one player\'s press act for the other' do
      backend.hold(controls::KEY_E)

      tick

      expect(seen).to eq([[0, box]])
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
