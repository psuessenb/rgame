# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Interactor do
  # The same arrangement a game has: a scene boundary carrying the broadphase,
  # targets whose Interactions answer actions, and a hero carrying the component
  # under test. A tick rebuilds the index (update) and then reads the press
  # (control), in that order, because a press acts on the target the last update
  # chose. The numbered rules are the interaction-verbs plan's, which
  # `git show 6526120:docs/plans/interaction-verbs.md` keeps.
  let(:controls) { RGame::Util::Controls }
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:backend) { FakeInputBackend.new }
  # One player, so `actions_for(nil)` resolves to them and no node needs an owner.
  # `search` is on its own key, so a spec can press it apart from `interact`.
  let(:players) do
    map = RGame::Engine::InputMap.default.merge(search: { buttons: [controls::KEY_F] })
    RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD, input_map: map)])
  end
  let(:log) { [] }

  before do
    record = log
    stub_const('Target', Class.new(RGame::Engine::Node2D) do
      define_method(:open) { record << [:opened, self] }
      define_method(:search) { |by:| record << [:searched, self, by] }
      define_method(:pull) { |by:| record << [:pulled, self, by] }
    end)
    scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  def target(x, y, **handlers)
    node = Target.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 10, layer: :prop))
    node.add_component(RGame::Engine::Components::Interaction.new(**handlers)) unless handlers.empty?
    scene.add_node(node)
  end

  def chest(x, y) = target(x, y, interact: :open, search: :search)
  def lever(x, y) = target(x, y, interact: :open)

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

  describe '.new' do
    it 'reads `interact` by default' do
      expect(hero(100, 100).actions).to eq([:interact])
    end

    it 'raises for an empty list, a name that is not a Symbol, or a name given twice' do
      [[], ['interact'], %i[interact interact], :interact].each do |actions|
        expect { described_class.new(range: 56, actions:) }.to raise_error(ArgumentError, /distinct action names/)
      end
    end
  end

  # Rule 1.
  describe '#target' do
    it 'is the nearest node in range whose Interaction answers one of its actions' do
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

    it 'is never a collider without an Interaction' do
      target(120, 100)
      interactor = hero(100, 100)

      tick

      expect(interactor.target).to be_nil
    end

    it 'is never a node whose Interaction answers none of its actions' do
      target(120, 100, search: :search)
      interactor = hero(100, 100)

      tick

      expect(interactor.target).to be_nil
    end

    it 'clears on the update after the target leaves range' do
      box = chest(140, 100)
      interactor = hero(100, 100)
      tick

      box.x = 300
      tick

      expect(interactor.target).to be_nil
    end

    # Rule 4.
    it 'is never its own node' do
      interactor = hero(100, 100)
      interactor.node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 10, layer: :hero))
      interactor.node.add_component(RGame::Engine::Components::Interaction.new(interact: :to_s))

      tick

      expect(interactor.target).to be_nil
    end
  end

  # Rule 2.
  describe '#target_for' do
    def searcher = hero(100, 100, actions: %i[interact search])

    it 'is the nearest node that answers the action' do
      box = chest(150, 100)
      interactor = searcher
      tick

      expect(interactor.target_for(:search)).to be(box)
    end

    it 'passes over a nearer node that does not answer it' do
      box = chest(150, 100)
      pull = lever(120, 100)
      interactor = searcher
      tick

      expect([interactor.target, interactor.target_for(:interact), interactor.target_for(:search)])
        .to eq([pull, pull, box])
    end

    it 'raises for an action it does not read' do
      expect { searcher.target_for(:grab) }.to raise_error(ArgumentError, /reads \[:interact, :search\], not :grab/)
    end
  end

  # Rule 3. The hero is controlled once before anything is pressed: a node reads
  # only the presses it saw start, and a press on its first tick is not one.
  describe 'the press' do
    def interactor_at(x, y, **)
      hero(x, y, **).tap { tick }
    end

    it 'calls the handler once per press' do
      box = chest(140, 100)
      interactor_at(100, 100)

      backend.hold(controls::KEY_E)
      tick
      tick

      expect(log).to eq([[:opened, box]])
    end

    it 'calls it again on a second press' do
      chest(140, 100)
      interactor_at(100, 100)

      backend.hold(controls::KEY_E)
      tick
      backend.release(controls::KEY_E)
      tick
      backend.hold(controls::KEY_E)
      tick

      expect(log.length).to eq(2)
    end

    it 'calls nothing while nothing is in range' do
      chest(300, 100)
      interactor_at(100, 100)

      backend.hold(controls::KEY_E)
      tick

      expect(log).to be_empty
    end

    it 'calls nothing on a target that has left range' do
      box = chest(140, 100)
      interactor_at(100, 100)
      tick

      box.x = 300
      backend.hold(controls::KEY_E)
      tick

      expect(log).to be_empty
    end

    it 'passes its own node as `by:`' do
      box = chest(140, 100)
      interactor = interactor_at(100, 100, actions: %i[interact search])

      backend.hold(controls::KEY_F)
      tick

      expect(log).to eq([[:searched, box, interactor.node]])
    end

    it 'sends each action to its own answerer' do
      box = chest(150, 100)
      pull = lever(120, 100)
      interactor_at(100, 100, actions: %i[interact search])

      backend.hold(controls::KEY_E)
      backend.hold(controls::KEY_F)
      tick

      expect(log.map { it.take(2) }).to eq([[:opened, pull], [:searched, box]])
    end
  end

  describe 'policy: :facing' do
    # A hero at (100, 100) that headed (x, y) for a tick and then stood still. Its body
    # has no speed, so it turns on the spot.
    def facing_hero(x, y, **)
      body = RGame::Engine::Components::CharacterBody.new(speed: 0.0)
      node = RGame::Engine::Node2D.new(x: 100, y: 100)
      node.add_component(body)
      node.add_component(RGame::Engine::Components::Facing.new)
      interactor = node.add_component(described_class.new(range: 56, policy: :facing, **))
      scene.add_node(node)
      body.set_intent(x, y)
      tick
      body.set_intent(0.0, 0.0)
      tick
      interactor
    end

    it 'reaches for the nearest node in front, over a nearer one behind' do
      lever(80, 100)
      box = chest(140, 100)
      expect(facing_hero(1.0, 0.0).target).to be(box)
    end

    it 'passes over a nearer node to the side for each action' do
      lever(100, 90)
      chest(100, 80)
      box = chest(140, 100)
      interactor = facing_hero(1.0, 0.0, actions: %i[interact search])

      expect([interactor.target_for(:interact), interactor.target_for(:search)]).to eq([box, box])
    end

    it 'presses nothing behind it' do
      chest(80, 100)
      facing_hero(1.0, 0.0)

      backend.hold(controls::KEY_E)
      tick

      expect(log).to be_empty
    end

    it 'presses what it turned to' do
      box = chest(80, 100)
      facing_hero(-1.0, 0.0)

      backend.hold(controls::KEY_E)
      tick

      expect(log).to eq([[:opened, box]])
    end

    it 'raises at attach for a node with no Facing' do
      node = RGame::Engine::Node2D.new(x: 100, y: 100)
      node.add_component(RGame::Engine::Components::CharacterBody.new(speed: 0.0))
      node.add_component(described_class.new(range: 56, policy: :facing))

      expect { scene.add_node(node) }
        .to raise_error(RuntimeError, /Interactor needs a .*Facing on the same node, and there is none/)
    end

    it 'allocates nothing to find the targets' do
      lever(80, 100)
      chest(100, 80)
      chest(140, 100)
      interactor = facing_hero(1.0, 0.0, actions: %i[interact search])

      expect { interactor._update(1.0 / 60) }.to allocate_nothing
    end
  end

  # Rule 5. Actions answers only for what its map declares, so a misspelled action
  # raises rather than reading as never pressed, with or without a target.
  describe 'an action the map does not declare' do
    it 'raises on the first control with nothing in reach' do
      hero(100, 100, actions: %i[interact serach])

      expect { tick }.to raise_error(KeyError, /serach/)
    end
  end

  # Rule 6. An Interactor reads the actions of whoever owns its node, which the
  # control traversal resolves, so two heroes either side of one chest press
  # their own button and reach their own target.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- two players, the registry, the
  # chest and what was seen: a two-player example needs both seats named
  describe 'two players, one chest between them' do
    let(:one) { RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD) }
    let(:two) { RGame::Engine::Player.new(id: 1, device: controls.gamepad(0)) }
    let(:players) { RGame::Engine::Players.new([one, two]) }

    let(:box) { target(200, 100, interact: :pull) }
    let(:heroes) { [owned_hero(160, one), owned_hero(240, two)] }

    def owned_hero(x, player)
      hero(x, 100).tap { it.node.input_owner = player }.node
    end

    before do
      box
      heroes
      tick
    end

    it 'lets each player reach it with their own button, as themselves' do
      backend.hold(controls::KEY_E)
      backend.hold(controls::PAD_X, device: controls.gamepad(0))

      tick

      expect(log).to eq([[:pulled, box, heroes.first], [:pulled, box, heroes.last]])
    end

    it "does not let one player's press act for the other" do
      backend.hold(controls::PAD_X, device: controls.gamepad(0))

      tick

      expect(log).to eq([[:pulled, box, heroes.last]])
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers

  # Rule 7.
  describe 'what a tick allocates' do
    it 'allocates nothing to find the targets' do
      chest(150, 100)
      lever(120, 100)
      interactor = hero(100, 100, actions: %i[interact search])
      tick

      expect { interactor._update(1.0 / 60) }.to allocate_nothing
    end

    it 'allocates nothing to control without a press' do
      chest(150, 100)
      interactor = hero(100, 100, actions: %i[interact search])
      tick
      actions = players.primary.actions

      expect { interactor._control(actions) }.to allocate_nothing
    end
  end
end
