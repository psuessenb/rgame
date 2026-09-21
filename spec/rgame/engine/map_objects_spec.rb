# frozen_string_literal: true

# The records come from TileMap#objects of a parsed `.tmx` string rather than from
# MapObject.new, so the registry is tested against the producer it will meet.
RSpec.describe RGame::Engine::MapObjects do
  subject(:factory) { described_class.new }

  # Two chests, one of them hidden, a trap, and a spawn point of a class nobody
  # defines, in that order in one object layer.
  let(:objects) do
    tmx = <<~TMX
      <map orientation="orthogonal" width="4" height="4" tilewidth="16" tileheight="16">
        <objectgroup name="things">
          <object id="1" class="chest" x="32" y="16" width="16" height="16">
            <properties><property name="contents" value="key"/></properties>
          </object>
          <object id="2" class="trap" x="48" y="0" width="16" height="16"/>
          <object id="3" class="spawn" x="0" y="0"><point/></object>
          <object id="4" class="chest" x="0" y="48" width="16" height="16" visible="0">
            <properties><property name="contents" value="coin"/></properties>
          </object>
        </objectgroup>
      </map>
    TMX
    RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.parse(tmx)).objects
  end

  # A node that says what built it.
  let(:tagged) { Class.new(RGame::Engine::Node2D) { attr_accessor :tag } }

  def node_for(object, tag) = tagged.new(x: object.x, y: object.y).tap { it.tag = tag }

  def define_chest = factory.define('chest') { node_for(it, it.properties.fetch('contents')) }

  describe '#build' do
    it 'returns what the block for the object’s class returns' do
      define_chest
      expect(factory.build(objects.first)).to have_attributes(x: 32, y: 16, tag: 'key')
    end

    it 'returns nil for an object of a class nobody defined' do
      define_chest
      expect(factory.build(objects[2])).to be_nil
    end

    it 'hands the block the record untouched, and places nothing itself' do
      seen = nil
      factory.define('trap') { seen = it }
      factory.build(objects[1])
      expect(seen).to equal(objects[1])
    end
  end

  describe '#define' do
    it 'raises for a class defined twice, naming it' do
      define_chest
      expect { factory.define('chest') { nil } }.to raise_error(ArgumentError, /'chest' is already defined/)
    end

    it 'raises for a Symbol, which no Tiled class would ever match' do
      expect { factory.define(:chest) { nil } }.to raise_error(ArgumentError, /:chest is not a String/)
    end

    it 'raises without a block' do
      expect { factory.define('chest') }.to raise_error(ArgumentError, /needs a block/)
    end
  end

  describe '#spawn_into' do
    let(:parent) { RGame::Engine::Node2D.new }

    before do
      define_chest
      factory.define('trap') { node_for(it, 'trap') }
    end

    it 'adds every node built under the parent, in the map’s order, hidden objects included' do
      factory.spawn_into(parent, objects)
      expect(parent.children.map(&:tag)).to eq(%w[key trap coin])
    end

    it 'returns the nodes it added' do
      added = factory.spawn_into(parent, objects)
      expect(added).to eq(parent.children)
    end

    it 'adds nothing for a map with no objects of a defined class' do
      expect(factory.spawn_into(parent, [objects[2]])).to be_empty
    end
  end
end
