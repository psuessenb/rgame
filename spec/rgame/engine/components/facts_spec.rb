# frozen_string_literal: true

# A game whose chest keeps whether it is open, under the key its map or its
# code gives it. MapBuilder resolves `Chest` in `Room`, and reads the chest's
# tags from this file.
module SpecFactsGame
  # The scene class a map's names resolve in.
  class Room < RGame::Engine::Node2D; end

  # A chest the hero opens once.
  class Chest < RGame::Engine::Node2D
    def initialize(key: nil, **)
      super(**)
      @facts = add_component(RGame::Engine::Components::Facts.new(key:, state: 'closed'))
    end

    def state = @facts[:state]

    def open = @facts[:state] = 'open'
  end
end

RSpec.describe RGame::Engine::Components::Facts do
  let(:database) { RGame::Engine::Components::FactsDatabase.new }
  let(:root) { RGame::Engine::Node2D.new.tap { it.add_component(database) }.tap(&:enter_tree) }

  # A room built over a map: a scene whose TileWorld names the map.
  def room(tilemap_id = 'map/town.tmx')
    world = RGame::Engine::Components::TileWorld.new(map: StubTileMap.new(layers: [[1, 0, 0, 0]]), tilemap_id:)
    scene = RGame::Engine::Node2D.new.tap { it.scene = it }
    scene.add_component(world)
    root.add_node(scene)
  end

  def kept(facts = described_class.new(state: 'closed'), map_object_id: nil, under: room)
    under.add_node(RGame::Engine::Node2D.new(map_object_id:)).add_component(facts)
  end

  describe '#key' do
    it 'is the key: the node passes' do
      expect(kept(described_class.new(key: :chest, state: 'closed')).key).to eq(:chest)
    end

    it "is the map's id and the object's id for a node a map built" do
      expect(kept(map_object_id: 7).key).to eq(:'map/town.tmx#7')
    end

    it "takes the key: the node passes over the object's id" do
      expect(kept(described_class.new(key: :chest, state: 'closed'), map_object_id: 7).key).to eq(:chest)
    end

    it "raises as its node enters a tree with neither, naming the node's class" do
      expect { kept }
        .to raise_error(ArgumentError, /RGame::Engine::Node2D has a Components::Facts with no key: pass key:/)
    end

    it 'is made once, so a node moved into another room keeps it' do
      facts = kept(map_object_id: 7)
      node = facts.node
      node.parent.remove_node(node)
      room('map/garden.tmx').add_node(node)

      expect(facts.key).to eq(:'map/town.tmx#7')
    end
  end

  describe 'the fields' do
    let(:facts) { kept(described_class.new(key: :crate, x: 16, y: 32, way: 'still')) }

    it 'reads each default while the field was never set' do
      expect([facts[:x], facts[:y], facts[:way]]).to eq([16, 32, 'still'])
    end

    it 'writes each field into the record under its key' do
      facts[:x] = 48
      facts[:way] = 'east'

      expect([facts[:x], database[:crate]]).to eq([48, { x: 48, way: 'east' }])
    end

    it 'reads a record the database already held' do
      database[:crate] = { y: 64 }

      expect([facts[:x], facts[:y]]).to eq([16, 64])
    end

    it 'reports a write as the database reports any field write' do
      heard = []
      facts
      database.on_changed { |key, value, field| heard << [key, value, field] }
      facts[:way] = 'east'

      expect(heard).to eq([[:crate, 'east', :way]])
    end

    it 'refuses a field the node did not name, listing those it did' do
      expect { facts[:wya] }.to raise_error(KeyError, /has no field :wya \(fields: x, y, way\)/)
      expect { facts[:wya] = 'east' }.to raise_error(KeyError, /has no field :wya/)
    end

    it 'reads and writes a field without allocating' do
      facts[:x] = 0
      i = 0

      expect do
        facts[:x]
        facts[:x] = (i += 1)
      end.to allocate_nothing
    end
  end

  describe 'before its node enters a tree' do
    let(:facts) { RGame::Engine::Node2D.new.add_component(described_class.new(key: :chest, state: 'closed')) }

    it 'raises for the key, saying when it can be read' do
      expect { facts.key }.to raise_error(RuntimeError, /found as its node enters the tree.*_enter_tree on/)
    end

    it 'raises for a field' do
      expect { facts[:state] }.to raise_error(RuntimeError, /keeps its record in the root's FactsDatabase/)
    end

    it 'raises for a write' do
      expect { facts[:state] = 'open' }.to raise_error(RuntimeError, /keeps its record/)
    end
  end

  describe 'what it refuses as it is built' do
    it 'no fields' do
      expect { described_class.new(key: :chest) }.to raise_error(ArgumentError, /pass each with its default/)
    end

    it 'a default the database cannot hold, naming the field' do
      expect { described_class.new(state: :closed) }
        .to raise_error(TypeError, /the default of state cannot hold the Symbol :closed/)
    end

    it 'a key that is not a Symbol' do
      expect { described_class.new(key: 'chest', state: 'closed') }
        .to raise_error(TypeError, /key: is a Symbol, got "chest"/)
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
      builder = RGame::Engine::MapBuilder.new(tilemap_id: 'map/town.tmx', scope: SpecFactsGame::Room)
      [scene, scene.add_node(builder.build(object)), scene.add_node(SpecFactsGame::Chest.new(key: :chest))]
    end

    it 'keeps each record under its own key: the map object, and what the code passed' do
      _, from_map, in_code = town
      from_map.open
      in_code.open

      expect(database.to_h[:values]).to eq('map/town.tmx#7': { state: 'open' }, chest: { state: 'open' })
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
