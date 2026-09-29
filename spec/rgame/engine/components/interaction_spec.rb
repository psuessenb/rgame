# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::Interaction do
  # A scene with the broadphase, and a chest class whose handlers record what
  # reached them. The numbered rules are the interaction-verbs plan's, which
  # `git show 6526120:docs/plans/interaction-verbs.md` keeps.
  let(:controls) { RGame::Util::Controls }
  let(:scene) { RGame::Engine::Node2D.new.tap { it.scene = it } }
  let(:actor) { RGame::Engine::Node2D.new }
  let(:chest_class) do
    Class.new(RGame::Engine::Node2D) do
      attr_reader :log

      def initialize(**)
        super
        @log = []
      end

      def open = @log << :opened
      def search(by:) = @log << [:searched, by]
      def peek(by: nil) = @log << [:peeked, by]
      def kick(target) = @log << target

      private

      def smash = @log << :smashed
    end
  end

  before do
    stub_const('Chest', chest_class)
    scene.add_component(RGame::Engine::Components::CollisionWorld.new(cell_size: 64))
    scene.enter_tree
  end

  def chest(collider: RGame::Engine::Components::BoxCollider.new(width: 20, height: 20, layer: :prop), **handlers)
    node = Chest.new(x: 100, y: 100)
    node.add_component(collider) if collider
    interaction = node.add_component(described_class.new(**handlers))
    scene.add_node(node)
    interaction
  end

  # Rule 1.
  describe 'what it answers' do
    let(:interaction) { chest(interact: :open, search: :search) }

    it 'answers the actions it was given' do
      expect([interaction.answers?(:interact), interaction.answers?(:search)]).to eq([true, true])
    end

    it 'answers no other action' do
      expect(interaction.answers?(:grab)).to be(false)
    end

    it 'lists them in the order given' do
      expect(interaction.actions).to eq(%i[interact search])
    end
  end

  # Rule 2.
  describe '#perform' do
    let(:interaction) { chest(interact: :open, search: :search, peek: :peek) }

    it 'calls the handler for the action' do
      interaction.perform(:interact, by: actor)

      expect(interaction.node.log).to eq([:opened])
    end

    it 'passes the actor to a handler that requires `by:`' do
      interaction.perform(:search, by: actor)

      expect(interaction.node.log).to eq([[:searched, actor]])
    end

    it 'passes the actor to a handler with an optional `by:`' do
      interaction.perform(:peek, by: actor)

      expect(interaction.node.log).to eq([[:peeked, actor]])
    end

    it 'raises for an action it does not answer' do
      expect { interaction.perform(:grab, by: actor) }.to raise_error(KeyError)
    end
  end

  # Rule 3.
  describe 'a handler the node cannot run' do
    it 'raises at attach for a method the node lacks, naming the class, action and method' do
      expect { chest(search: :serch) }
        .to raise_error(ArgumentError, 'Chest has no public method serch for the search action')
    end

    it 'raises at attach for a private method' do
      expect { chest(interact: :smash) }.to raise_error(ArgumentError, /no public method smash/)
    end

    it 'raises at attach for a method taking a positional parameter' do
      expect { chest(interact: :kick) }.to raise_error(ArgumentError, /Chest#kick handles the interact action/)
    end
  end

  # Rule 4.
  describe 'the collider' do
    it 'raises at attach without one' do
      expect { chest(collider: nil, interact: :open) }.to raise_error(/Interaction needs a .*Collider/)
    end

    it 'takes a circle as well as a box' do
      circle = RGame::Engine::Components::CircleCollider.new(radius: 10, layer: :prop)

      expect(chest(collider: circle, interact: :open).actions).to eq([:interact])
    end
  end

  # Rule 5.
  describe '.new' do
    it 'raises with no actions' do
      expect { described_class.new }.to raise_error(ArgumentError, /at least one action/)
    end

    it 'raises for a method name that is not a Symbol' do
      expect { described_class.new(interact: 'open') }.to raise_error(ArgumentError, /a Symbol, not "open"/)
    end
  end

  # Rule 6.
  describe 'a second Interaction on one node' do
    let(:node) do
      Chest.new.tap do |chest|
        chest.add_component(RGame::Engine::Components::CircleCollider.new(radius: 10))
        chest.add_component(described_class.new(interact: :open))
      end
    end

    it 'raises in the same slot' do
      expect { node.add_component(described_class.new(search: :search)) }
        .to raise_error(ArgumentError, /already has a component in slot/)
    end

    it 'raises at attach in a slot of its own' do
      node.add_component(described_class.new(search: :search), as: :search)

      expect { scene.add_node(node) }.to raise_error(ArgumentError, /Chest holds 2 Interactions/)
    end
  end

  # Rule 7, decision 7.
  describe 'an action no input map declares' do
    let(:map) { RGame::Engine::InputMap.default.merge(search: { buttons: [controls::KEY_E], hold: 0.3 }) }

    def seat(map)
      scene.add_component(RGame::Engine::Players.new([RGame::Engine::Player.new(input_map: map)]))
    end

    it 'raises at attach, naming the action' do
      seat(map)

      expect { chest(serach: :search) }.to raise_error(ArgumentError, /answers the serach action, and no player/)
    end

    it "passes an action one player's map declares" do
      seat(RGame::Engine::InputMap.default)
      scene.system(RGame::Engine::Players).add(RGame::Engine::Player.new(id: 1, input_map: map))

      expect(chest(interact: :open, search: :search).actions).to eq(%i[interact search])
    end

    it 'is not checked in a scene without Players' do
      expect(chest(serach: :search).actions).to eq([:serach])
    end
  end
end
