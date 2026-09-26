# frozen_string_literal: true

require 'tmpdir'

RSpec.describe RGame::Engine::Components::FactsDatabase do
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

  describe 'records' do
    it 'holds a Hash of fields written whole, and hands out a frozen copy' do
      facts[:crate] = { x: 3, way: 'east' }

      expect([facts[:crate], facts[:crate].frozen?]).to eq([{ x: 3, way: 'east' }, true])
    end

    it 'writes one field, making the record when the key has none' do
      facts[:crate, :x] = 3
      facts[:crate, :y] = 4

      expect([facts[:crate, :x], facts[:crate]]).to eq([3, { x: 3, y: 4 }])
    end

    it 'reads nil for a field never set, and for a key never set' do
      facts[:crate, :x] = 3

      expect([facts[:crate, :y], facts[:never, :x], facts.key?(:crate, :y), facts.key?(:crate, :x)])
        .to eq([nil, nil, false, true])
    end

    it 'keeps a copy of a record written whole, so changing the Hash afterwards changes nothing' do
      record = { x: 3, name: +'crate' }
      facts[:crate] = record
      record[:x] = 9
      record[:name] << 's'

      expect([facts[:crate, :x], facts[:crate, :name]]).to eq([3, 'crate'])
    end

    it 'holds a record inside a field, frozen' do
      facts[:oasis, :chest] = { state: 'open' }

      expect([facts[:oasis], facts[:oasis, :chest].frozen?]).to eq([{ chest: { state: 'open' } }, true])
    end

    it "refuses a field write or read on a key that holds no record, naming the key's value" do
      facts[:chest] = 'open'

      expect { facts[:chest, :state] = 'shut' }.to raise_error(TypeError, /facts\[:chest\] holds "open", not a record/)
      expect { facts[:chest, :state] }.to raise_error(TypeError, /not a record of fields/)
    end

    it 'refuses a field that is not a Symbol, in a write and in a record' do
      expect { facts[:crate, 'x'] = 3 }.to raise_error(TypeError, /field is a Symbol, got "x" \(String\)/)
      expect { facts[:crate] = { 'x' => 3 } }
        .to raise_error(TypeError, /facts\[:crate\] is a record, whose fields are Symbols, got "x"/)
    end

    it 'refuses a value inside a record as it would refuse it alone, naming where it sits' do
      expect { facts[:crate] = { way: :east } }
        .to raise_error(TypeError, /facts\[:crate\]\[:way\] cannot hold the Symbol :east/)
      expect { facts[:crate, :spot] = [1, 2] }.to raise_error(TypeError, /facts\[:crate, :spot\].*Array/)
    end

    it 'deletes a field and returns its value, and deletes the key with its last field' do
      facts[:crate] = { x: 3, y: 4 }
      removed = [facts.delete(:crate, :x), facts[:crate]]

      expect([removed, facts.delete(:crate, :y), facts.key?(:crate)]).to eq([[3, { y: 4 }], 4, false])
    end

    it 'reports a field write with the key, the value and the field, and not a value already held' do
      heard = []
      facts.on_changed { |key, value, field| heard << [key, value, field] }
      facts[:crate, :x] = 3
      facts[:crate, :x] = 3
      facts[:wolves] = 1

      expect(heard).to eq([[:crate, 3, :x], [:wolves, 1, nil]])
    end

    it "calls a key's watchers with the record when one of its fields changes" do
      heard = []
      facts.watch(:crate) { heard << it }
      facts[:crate, :x] = 3

      expect(heard).to eq([nil, { x: 3 }])
    end

    it 'survives a save file, fields and nested records included' do
      facts[:crate] = { x: 3, way: 'east', lid: { open: true } }
      other = described_class.new
      other.restore(round_trip(facts.to_h))

      expect([other[:crate], other[:crate, :x]]).to eq([{ x: 3, way: 'east', lid: { open: true } }, 3])
    end

    it 'reads and writes a field without allocating' do
      facts[:crate, :x] = 0
      i = 0

      expect do
        facts[:crate, :x]
        facts[:crate, :x] = (i += 1)
      end.to allocate_nothing
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
