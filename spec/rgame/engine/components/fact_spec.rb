# frozen_string_literal: true

# A game whose chest keeps whether it is open, under the key its map or its
# code gives it. MapBuilder resolves `Chest` in `Room`, and reads the chest's
# tags from this file.
module SpecFactGame
  # The scene class a map's names resolve in.
  class Room < RGame::Engine::Node2D; end

  # A chest the hero opens once.
  class Chest < RGame::Engine::Node2D
    def initialize(key: nil, **)
      super(**)
      @kept = add_component(RGame::Engine::Components::Fact.new(key:, default: 'closed'))
    end

    def state = @kept.value

    def open = @kept.value = 'open'
  end
end

RSpec.describe RGame::Engine::Components::Fact do
  let(:facts) { RGame::Engine::Components::Facts.new }
  let(:root) { RGame::Engine::Node2D.new.tap { it.add_component(facts) }.tap(&:enter_tree) }

  # A room built over a map: a scene whose TileWorld names the map.
  def room(tilemap_id = 'map/town.tmx')
    world = RGame::Engine::Components::TileWorld.new(map: StubTileMap.new(layers: [[1, 0, 0, 0]]), tilemap_id:)
    scene = RGame::Engine::Node2D.new.tap { it.scene = it }
    scene.add_component(world)
    root.add_node(scene)
  end

  def kept(fact = described_class.new, map_object_id: nil, under: room)
    under.add_node(RGame::Engine::Node2D.new(map_object_id:)).add_component(fact)
  end

  describe '#key' do
    it 'is the key: the node passes' do
      expect(kept(described_class.new(key: :chest)).key).to eq(:chest)
    end

    it 'joins a part to that key, after a dot' do
      expect(kept(described_class.new(key: :crate, part: :x)).key).to eq(:'crate.x')
    end

    it "is the map's id and the object's id for a node a map built" do
      expect(kept(map_object_id: 7).key).to eq(:'map/town.tmx#7')
    end

    it 'joins a part to that key too' do
      expect(kept(described_class.new(part: :x), map_object_id: 7).key).to eq(:'map/town.tmx#7.x')
    end

    it "takes the key: the node passes over the object's id" do
      expect(kept(described_class.new(key: :chest), map_object_id: 7).key).to eq(:chest)
    end

    it "raises as its node enters a tree with neither, naming the node's class" do
      expect { kept }
        .to raise_error(ArgumentError, /RGame::Engine::Node2D has a Components::Fact with no key: pass key:/)
    end

    it 'is made once, so a node moved into another room keeps it' do
      fact = kept(map_object_id: 7)
      node = fact.node
      node.parent.remove_node(node)
      room('map/garden.tmx').add_node(node)

      expect(fact.key).to eq(:'map/town.tmx#7')
    end
  end

  describe '#value' do
    let(:fact) { kept(described_class.new(key: :chest, default: 'closed')) }

    it 'is the default for a fact never set' do
      expect(fact.value).to eq('closed')
    end

    it 'is the fact once one is set' do
      facts[:chest] = 'open'

      expect(fact.value).to eq('open')
    end

    it "writes the fact to the root's Facts" do
      fact.value = 'open'

      expect(facts[:chest]).to eq('open')
    end

    it 'reports a write as Facts reports any write' do
      heard = []
      fact
      facts.on_changed { |key, value| heard << [key, value] }
      fact.value = 'open'

      expect(heard).to eq([[:chest, 'open']])
    end

    it 'keeps one value for each part on one node, each in a slot of its own' do
      node = room.add_node(RGame::Engine::Node2D.new)
      x = node.add_component(described_class.new(key: :crate, part: :x), as: :x)
      y = node.add_component(described_class.new(key: :crate, part: :y), as: :y)
      x.value = 3
      y.value = 4

      expect(facts.to_h[:values]).to eq('crate.x': 3, 'crate.y': 4)
    end

    it 'reads and writes the value it holds without allocating' do
      fact.value = 'open'

      expect do
        fact.value
        fact.value = 'open'
      end.to allocate_nothing
    end
  end

  describe 'before its node enters a tree' do
    let(:fact) { RGame::Engine::Node2D.new.add_component(described_class.new(key: :chest)) }

    it 'raises for the key, saying when it can be read' do
      expect { fact.key }.to raise_error(RuntimeError, /found as its node enters the tree.*_enter_tree on/)
    end

    it 'raises for the value' do
      expect { fact.value }.to raise_error(RuntimeError, /Components::Fact keeps its value in the root's Facts/)
    end

    it 'raises for a write' do
      expect { fact.value = 'open' }.to raise_error(RuntimeError, /Components::Fact keeps its value/)
    end
  end

  describe 'what it refuses as it is built' do
    it 'a default a fact cannot hold' do
      expect { described_class.new(default: :closed) }
        .to raise_error(TypeError, /a Fact default cannot hold the Symbol :closed/)
    end

    it 'a key that is not a Symbol' do
      expect { described_class.new(key: 'chest') }.to raise_error(TypeError, /key: is a Symbol, got "chest"/)
    end

    it 'a part that is not a Symbol' do
      expect { described_class.new(key: :crate, part: 1) }.to raise_error(TypeError, /part: is a Symbol, got 1/)
    end
  end

  # The caller that uses both: one chest built from a map and one built in
  # code, in a room that is left and built again.
  describe 'a chest from a map beside a chest from code' do
    let(:object) do
      map = '<map orientation="orthogonal" width="4" height="4" tilewidth="16" tileheight="16">' \
            '<objectgroup name="things"><object id="7" type="Chest" x="0" y="0" width="16" height="16"/>' \
            '</objectgroup></map>'
      RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.parse(map)).objects.first
    end

    def town
      scene = room
      builder = RGame::Engine::MapBuilder.new(tilemap_id: 'map/town.tmx', scope: SpecFactGame::Room)
      [scene, scene.add_node(builder.build(object)), scene.add_node(SpecFactGame::Chest.new(key: :chest))]
    end

    it 'keeps each under its own key: the map object, and what the code passed' do
      _, from_map, in_code = town
      from_map.open
      in_code.open

      expect(facts.to_h[:values]).to eq('map/town.tmx#7': 'open', chest: 'open')
    end

    it 'finds both open when the room is built again' do
      scene, from_map, in_code = town
      from_map.open
      in_code.open
      root.remove_node(scene)
      _, again_from_map, again_in_code = town

      expect([again_from_map.state, again_in_code.state]).to eq(%w[open open])
    end
  end
end
