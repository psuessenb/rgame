# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RGame::Engine::Components::Facts do
  subject(:facts) { described_class.new }

  def round_trip(state)
    Dir.mktmpdir do |dir|
      save = RGame::Util::SaveFile.new('slot.json', dir:)
      save.write(world: state)
      save.read[:world]
    end
  end

  describe 'values' do
    it 'holds nil, true, false, an Integer, a Float and a String' do
      values = [nil, true, false, 3, 2.5, 'north']
      values.each_with_index { |value, i| facts[:"k#{i}"] = value }
      expect(values.each_index.map { facts[:"k#{it}"] }).to eq(values)
    end

    it 'refuses anything else, naming the key and the class' do
      expect { facts[:where] = [1, 2] }.to raise_error(TypeError, /facts\[:where\].*Array/)
    end

    it 'refuses a Symbol, saying a save would bring it back a String' do
      expect { facts[:door] = :open }.to raise_error(TypeError, /save brings it back as the String "open"/)
    end

    it 'keeps a frozen copy of a String' do
      name = +'Bram'
      facts[:smith] = name
      name << 'well'
      expect([facts[:smith], facts[:smith]]).to all(eq('Bram').and(be_frozen))
    end
  end

  describe 'keys' do
    it 'refuses a String key on every read and write' do
      facts[:met_smith] = true
      [-> { facts['met_smith'] }, -> { facts['met_smith'] = true }, -> { facts.fetch('met_smith') },
       -> { facts.key?('met_smith') }, -> { facts.delete('met_smith') }, -> { facts.watch('met_smith') { nil } }]
        .each { expect(&it).to raise_error(TypeError, /"met_smith" \(String\)/) }
    end

    it 'reads nil for a key never set, and fetches as a Hash does' do
      expect([facts[:never], facts.key?(:never), facts.fetch(:never, 0)]).to eq([nil, false, 0])
      expect { facts.fetch(:never) }.to raise_error(KeyError)
    end

    it 'deletes a key and returns its value' do
      facts[:wolves] = 2
      expect([facts.delete(:wolves), facts.key?(:wolves)]).to eq([2, false])
    end
  end

  describe '#on_changed' do
    it 'fires once per change, not for a value already held' do
      heard = []
      facts.on_changed { |key, value| heard << [key, value] }
      facts[:wolves] = 1
      facts[:wolves] = 1
      facts[:wolves] = 2
      facts.delete(:wolves)
      facts.delete(:wolves)
      expect(heard).to eq([[:wolves, 1], [:wolves, 2], [:wolves, nil]])
    end

    it 'counts an Integer and a Float of the same size as different' do
      facts[:gold] = 1
      heard = []
      facts.on_changed { |_, value| heard << value }
      facts[:gold] = 1.0
      expect(heard).to eq([1.0])
    end
  end

  describe '#watch' do
    it 'calls now with the value, nil for a key never set, then on every change' do
      heard = []
      facts.watch(:bridge_down) { heard << it }
      facts[:bridge_down] = true
      facts[:bridge_down] = true
      facts[:bridge_down] = false
      expect(heard).to eq([nil, true, false])
    end

    it 'stops calling a block after unwatch' do
      heard = []
      handle = facts.watch(:bridge_down) { heard << it }
      facts.unwatch(handle)
      facts[:bridge_down] = true
      expect(heard).to eq([nil])
    end
  end

  describe '#to_h' do
    it 'is frozen, and a copy' do
      facts[:wolves] = 1
      saved = facts.to_h
      facts[:wolves] = 2
      expect(saved).to eq(values: { wolves: 1 }, machines: {})
      expect([saved, saved[:values], saved[:machines]]).to all(be_frozen)
    end
  end

  describe '#restore' do
    before do
      facts[:met_smith] = true
      facts[:wolves] = 10
    end

    it 'puts back what to_h saved, through a SaveFile' do
      saved = round_trip(facts.to_h)
      other = described_class.new
      other.restore(saved)
      expect(other.to_h).to eq(facts.to_h)
    end

    it 'fires no on_changed, and calls the watchers of each key that differs' do
      changed = []
      watched = []
      facts.on_changed { |key, _| changed << key }
      %i[met_smith wolves bridge_down].each { |key| facts.watch(key) { watched << [key, it] } }
      watched.clear
      facts.restore(values: { wolves: 10, bridge_down: true })
      expect([changed, watched]).to eq([[], [[:met_smith, nil], [:bridge_down, true]]])
    end

    it 'clears everything from nil' do
      facts.restore(nil)
      expect(facts.to_h).to eq(values: {}, machines: {})
    end

    it 'changes nothing when a value is refused' do
      before = facts.to_h
      expect { facts.restore(values: { wolves: 3, where: [1, 2] }) }.to raise_error(TypeError, /:where/)
      expect(facts.to_h).to eq(before)
    end

    it 'keeps machine entries it was handed, and saves them again' do
      entry = { state: 'searching', visits: { not_started: 1, searching: 1 } }
      facts.restore(values: {}, machines: { hammer: entry })
      expect(round_trip(facts.to_h)[:machines]).to eq(hammer: entry)
    end
  end

  it 'is found with node.system from a descendant' do
    root = RGame::Engine::Node2D.new
    root.add_component(facts)
    child = RGame::Engine::Node2D.new
    root.add_node(child)
    grandchild = RGame::Engine::Node2D.new
    child.add_node(grandchild)
    expect(grandchild.system(described_class)).to be(facts)
  end

  it 'reads a value without allocating' do
    facts[:wolves] = 3
    expect { facts[:wolves] }.to allocate_nothing
  end
end
