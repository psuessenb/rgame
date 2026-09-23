# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Collectable do
  # A collectable acts on a contact, so the arrangement is the one a game has: a
  # root carrying the AudioOut, a scene boundary carrying the broadphase, and
  # nodes whose colliders register with it. One update resolves the contacts.
  let(:audio) { FakeAudio.new }
  let(:root) { RGame::Engine::Node2D.new }
  let(:scene) { root.add_node(RGame::Engine::Node2D.new).tap { it.scene = it } }

  before do
    audio.register_sound(:blip, audio.sample('blip.ogg'))
    audio.clear
    root.add_component(RGame::Engine::AudioOut.new(audio))
    scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
    root.enter_tree
  end

  def tick = scene.update(1.0 / 60)

  # A taker: a node with a collider on `layer`, which is what a Collectable
  # names in `by:`.
  def hero(x, y, layer: :hero)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: layer))
    scene.add_node(node)
  end

  # A coin: round, because a coin is, which is also what pins that a Collectable
  # takes either shape.
  def coin(x, y, **)
    node = RGame::Engine::Node2D.new(x: x, y: y)
    node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 8, layer: :pickup))
    collectable = node.add_component(described_class.new(**))
    scene.add_node(node)
    [node, collectable]
  end

  describe 'the layer it names' do
    it 'fires on a collider of that layer' do
      seen = []
      _, collectable = coin(100, 100, by: :hero)
      collectable.on_collected { |other| seen << other.layer }
      hero(100, 100)

      tick

      expect(seen).to eq([:hero])
    end

    it 'ignores every other layer' do
      seen = []
      _, collectable = coin(100, 100, by: :hero)
      collectable.on_collected { |other| seen << other }
      hero(100, 100, layer: :enemy)

      tick

      expect(seen).to be_empty
    end

    it 'fires once, because a contact is an edge' do
      seen = []
      _, collectable = coin(100, 100, by: :hero, free: false)
      collectable.on_collected { |other| seen << other }
      hero(100, 100)

      3.times { tick }

      expect(seen.length).to eq(1)
    end

    it 'hands over the collider, so a listener can reach its node' do
      seen = nil
      _, collectable = coin(100, 100, by: :hero)
      collectable.on_collected { |other| seen = other.node }
      taker = hero(100, 100)

      tick

      expect(seen).to be(taker)
    end
  end

  describe 'what happens to the node' do
    it 'frees it by default' do
      node, = coin(100, 100, by: :hero)
      hero(100, 100)

      tick

      expect(node.freed?).to be(true)
    end

    it 'keeps it with free: false' do
      node, = coin(100, 100, by: :hero, free: false)
      hero(100, 100)

      tick

      expect(node.freed?).to be(false)
    end

    it 'emits before freeing, so a listener still has the node' do
      alive = nil
      node, collectable = coin(100, 100, by: :hero)
      collectable.on_collected { alive = !node.freed? }
      hero(100, 100)

      tick

      expect(alive).to be(true)
    end
  end

  describe 'the sound' do
    it 'plays it through the tree\'s AudioOut' do
      coin(100, 100, by: :hero, sound: :blip)
      hero(100, 100)

      tick

      expect(audio.played?('blip.ogg')).to be(true)
    end

    it 'plays nothing when given none' do
      coin(100, 100, by: :hero)
      hero(100, 100)

      tick

      expect(audio.played?).to be(false)
    end

    # `sound:` says this makes a noise, so a scene that cannot make one says so
    # rather than going quietly missing.
    it 'raises for a sound with no AudioOut above it' do
      bare = RGame::Engine::Node2D.new.tap { it.scene = it }
      bare.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
      bare.enter_tree
      [[:pickup, described_class.new(by: :hero, sound: :blip)], [:hero, nil]].each do |layer, collectable|
        node = RGame::Engine::Node2D.new(x: 100, y: 100)
        node.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: layer))
        node.add_component(collectable) if collectable
        bare.add_node(node)
      end

      expect { bare.update(1.0 / 60) }.to raise_error(KeyError, /no RGame::Engine::AudioOut system/)
    end
  end

  describe 'the collider it needs' do
    it 'takes a box as readily as a circle' do
      seen = []
      node = RGame::Engine::Node2D.new(x: 100, y: 100)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8, layer: :pickup))
      node.add_component(described_class.new(by: :hero)).on_collected { |other| seen << other }
      scene.add_node(node)
      hero(100, 100)

      tick

      expect(seen.length).to eq(1)
    end

    it 'raises for a node with no collider at all, naming what it needs' do
      node = RGame::Engine::Node2D.new
      node.add_component(described_class.new(by: :hero))

      expect { scene.add_node(node) }
        .to raise_error(/needs a RGame::Engine::Components::Collider on the same node/)
    end

    it 'raises for a node carrying both shapes, because either could be meant' do
      node = RGame::Engine::Node2D.new
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 8, height: 8))
      node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 4))
      node.add_component(described_class.new(by: :hero))

      expect { scene.add_node(node) }.to raise_error(ArgumentError, /and this node has 2/)
    end
  end

  # Rule 7. A pooled node leaves the tree and comes back, which attaches its
  # components again — so a Collectable that only ever connected would collect
  # one more listener each time round.
  describe 'a node that leaves the tree and returns' do
    it 'fires once per visit, not once per attach' do
      seen = []
      node, collectable = coin(100, 100, by: :hero, free: false)
      collectable.on_collected { |other| seen << other }
      taker = hero(100, 100)
      tick

      scene.remove_node(node)
      scene.add_node(node)
      taker.x = 400
      tick
      taker.x = 100
      tick

      expect(seen.length).to eq(2)
    end
  end

  # The caller CLAUDE.md asks for: the one that uses both of this step's
  # components at once. Nothing else in the suite mounts an Interactor and a
  # Collectable in one scene, and that is the case the two were designed for.
  # rubocop:disable RSpec/MultipleMemoizedHelpers -- the scene's audio, root and
  # broadphase, plus the two nodes and the input this case needs on top of them
  describe 'a hero who walks onto a chest and opens it' do
    let(:controls) { RGame::Util::Controls }
    let(:backend) { FakeInputBackend.new }
    let(:players) do
      RGame::Engine::Players.new([RGame::Engine::Player.new(id: 0, device: controls::KEYBOARD)])
    end

    let(:log) { [] }

    # A chest that reports being reached and stays put, with a coin inside that
    # is taken by touch.
    let(:chest) do
      node = RGame::Engine::Node2D.new(x: 160, y: 100)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 20, height: 20,
                                                                    layer: :interactable))
      node.add_component(described_class.new(by: :hero, free: false))
          .on_collected { log << :reached }
      scene.add_node(node)
    end

    let(:walker) do
      node = RGame::Engine::Node2D.new(x: 100, y: 100)
      node.add_component(RGame::Engine::Components::BoxCollider.new(width: 16, height: 16, layer: :hero))
      node.add_component(RGame::Engine::Components::Interactor.new(range: 56))
          .on_interacted { log << :opened }
      scene.add_node(node)
    end

    def step
      players.poll(backend, 1.0 / 60)
      scene.update(1.0 / 60)
      scene.control(players)
    end

    before do
      chest
      walker
    end

    it 'reaches it by touch and opens it with a press' do
      step
      walker.x = 160
      step
      backend.hold(controls::KEY_E)
      step

      expect(log).to eq(%i[reached opened])
    end

    it 'opens it again without reaching it again' do
      walker.x = 160
      step
      backend.hold(controls::KEY_E)
      step
      backend.release(controls::KEY_E)
      step
      backend.hold(controls::KEY_E)
      step

      expect(log).to eq(%i[reached opened opened])
    end

    it 'takes the coin inside it on touch, and frees only the coin' do
      taken = []
      node = RGame::Engine::Node2D.new(x: 160, y: 100)
      node.add_component(RGame::Engine::Components::CircleCollider.new(radius: 6, layer: :pickup))
      node.add_component(described_class.new(by: :hero, sound: :blip)).on_collected { taken << :coin }
      scene.add_node(node)

      walker.x = 160
      step

      expect([taken, node.freed?, chest.freed?]).to eq([[:coin], true, false])
    end
  end
  # rubocop:enable RSpec/MultipleMemoizedHelpers
end
