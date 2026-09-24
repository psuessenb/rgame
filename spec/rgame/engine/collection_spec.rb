# frozen_string_literal: true

RSpec.describe RGame::Engine::Collection do
  let(:roster_class) do
    Class.new do
      include RGame::Engine::Collection.of(:@members)

      def initialize(members) = @members = members
      def each(&) = @members.each(&)
    end
  end

  let(:roster) { roster_class.new([1, 2, 3]) }

  it 'answers Enumerable queries the way the Array does' do
    expect([roster.any? { it > 2 }, roster.find(&:even?), roster.count(&:odd?), roster.map { it * 2 }])
      .to eq([true, 2, 2, [2, 4, 6]])
  end

  it 'is still an Enumerable' do
    expect(roster).to be_a(Enumerable)
  end

  it 'answers a query without allocating' do
    expect { roster.any? { it > 2 } || roster.find(&:even?) || roster.count(&:odd?) }.to allocate_nothing
  end

  # Array#to_a is the Array itself, which would let a caller change the list.
  it 'hands out a copy of its members, not the list it keeps' do
    list = roster.to_a
    list << 4

    expect(roster.count).to eq(3)
  end

  it 'shares one module between the classes naming the same variable' do
    expect(described_class.of(:@members)).to equal(described_class.of(:@members))
  end

  it 'refuses a name that is not an instance variable' do
    expect { described_class.of(:members) }.to raise_error(ArgumentError, /instance variable, not :members/)
  end

  # Every class in RGame with an `each` of its own. Enumerable's queries over
  # that `each` allocate on every call, so each one forwards to its Array.
  describe 'the collections in RGame' do
    # A Hash answers `find`, `count` and most other queries through Enumerable
    # as well, so forwarding to one saves nothing and changes what `select`
    # and `include?` return. Properties are read while a map loads.
    let(:hash_backed) { [RGame::Engine::Properties] }

    let(:collections) do
      ObjectSpace.each_object(Class).select do |klass|
        Module.instance_method(:name).bind_call(klass)&.start_with?('RGame::') &&
          klass.include?(Enumerable) && klass.instance_method(:each).owner == klass
      end
    end

    it 'finds the ones it guards' do
      expect(collections).to include(RGame::Engine::Players, RGame::Engine::Dialogue::Transcript)
    end

    it 'answers every query through the Array it keeps' do
      through_each = (collections - hash_backed).select { it.instance_method(:any?).owner == Enumerable }

      expect(through_each).to be_empty, "include RGame::Engine::Collection.of(...) in #{through_each.join(', ')}"
    end
  end
end
