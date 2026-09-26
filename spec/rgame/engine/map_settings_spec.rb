# frozen_string_literal: true

# MapSettings reads the comment above a class's `initialize` from its source
# file, so the classes it reads are defined here, where each example can see
# the tags it is about. The classes exist for their signatures and their tags,
# so none of them reads a keyword it takes.

# rubocop:disable Lint/UnusedMethodArgument -- a signature is what MapSettings reads

# A tag of every type a map can hold, and a keyword for each way to stay out of
# a map's reach: a type Tiled cannot hold, and no tag at all.
class SpecMapChest < RGame::Engine::Node2D
  # A chest with one keyword of every kind.
  #
  # @param contents [String] the item inside
  # @param count [Integer] how many of it
  # @param weight [Float] in kilograms
  # @param locked [Boolean] whether it takes a key to open
  # @param wood [Symbol] what it is made of
  # @param lid [:flat, :round] the shape of its lid
  # @param tint [Util::Color] the colour it is painted
  # @param glow [RGame::Util::Color] the colour it shines
  # @param rng [Random] where its loot rolls come from,
  #   in a description running onto a second line
  def initialize(contents: '', count: 1, weight: 1.0, locked: false, wood: :oak, lid: :flat, tint: nil,
                 glow: nil, rng: nil, secret: nil, **)
    super(**)
  end
end

# Takes its parent's initialize, comment and all.
class SpecMapLockedChest < SpecMapChest; end

# Has an initialize of its own, and so only its own tags.
class SpecMapTrappedChest < SpecMapChest
  # @param trap [String] what springs when it opens
  def initialize(trap: 'dart', **)
    super(**)
  end
end

# The blank line detaches the comment.
class SpecMapDetachedChest < RGame::Engine::Node2D
  # @param contents [String] the item inside

  def initialize(contents: '', **)
    super(**)
  end
end

# Tags a keyword its initialize does not take: a typo of `contents`.
class SpecMapMistaggedChest < RGame::Engine::Node2D
  # @param contnets [String] the item inside
  def initialize(contents: '', **)
    super(**)
  end
end

# Tags a keyword Node2D takes, which the object's box sets.
class SpecMapWideChest < RGame::Engine::Node2D
  # @param width [Float] the chest's width
  def initialize(width: 16.0, **)
    super
  end
end

# Tags `fact`, which becomes the node's fact_key.
class SpecMapFactChest < RGame::Engine::Node2D
  # @param fact [String] where it keeps its state
  def initialize(fact: nil, **)
    super(**)
  end
end

# rubocop:enable Lint/UnusedMethodArgument

RSpec.describe RGame::Engine::MapSettings do
  def descendants(klass) = klass.subclasses.flat_map { [it, *descendants(it)] }

  describe '.of' do
    it 'makes each keyword whose tag gives a type from the table settable, with that type' do
      expect(described_class.of(SpecMapChest))
        .to eq(contents: :string, count: :integer, weight: :float, locked: :bool, wood: :symbol,
               lid: %i[flat round], tint: :color, glow: :color)
    end

    it 'leaves out a keyword tagged with another type, and one with no tag' do
      expect(described_class.of(SpecMapChest).keys).not_to include(:rng, :secret)
    end

    it 'reads nothing above a blank line' do
      expect(described_class.of(SpecMapDetachedChest)).to eq({})
    end

    it "reads a subclass's parent's tags when the subclass takes the parent's initialize" do
      expect(described_class.of(SpecMapLockedChest)).to eq(described_class.of(SpecMapChest))
    end

    it 'reads only its own tags for a subclass with an initialize of its own' do
      expect(described_class.of(SpecMapTrappedChest)).to eq(trap: :string)
    end

    it 'reads a class once, and keeps what it read frozen' do
      settings = described_class.of(SpecMapChest)

      expect([described_class.of(SpecMapChest).equal?(settings), settings.frozen?]).to eq([true, true])
    end

    it 'reads a node class with no tags as nothing settable' do
      expect(described_class.of(RGame::Engine::Node2D)).to eq({})
    end

    it 'refuses a tag naming a keyword initialize does not take, naming the class, the tag and the keywords' do
      expect { described_class.of(SpecMapMistaggedChest) }
        .to raise_error(ArgumentError, /SpecMapMistaggedChest#initialize tags @param contnets.*takes: contents/)
    end

    it "refuses a tag naming one of Node2D's own keywords" do
      expect { described_class.of(SpecMapWideChest) }
        .to raise_error(ArgumentError, /SpecMapWideChest#initialize tags @param width, a name no property may set/)
    end

    it 'refuses a tag naming fact, which becomes the fact_key' do
      expect { described_class.of(SpecMapFactChest) }
        .to raise_error(ArgumentError, /@param fact, a name no property may set.*reserved: x, y, .*, fact\)/)
    end

    it 'refuses a class whose initialize was defined from a String, naming it' do
      # Ruby gives code evaluated from a String a location no file is at.
      built = stub_const('SpecMapBuiltChest', Class.new(RGame::Engine::Node2D))
      built.class_eval('def initialize(**) = super') # rubocop:disable Style/EvalWithLocation -- a location would give it a file

      expect { described_class.of(SpecMapBuiltChest) }
        .to raise_error(ArgumentError, /SpecMapBuiltChest#initialize has no source file/)
    end

    it 'refuses a class whose initialize is written in C' do
      expect { described_class.of(Class.new) }
        .to raise_error(ArgumentError, /BasicObject#initialize has no source file/)
    end

    it 'reads every engine node class, so no engine comment drifts from its constructor' do
      classes = descendants(RGame::Engine::Node2D).select { it.name&.start_with?('RGame::Engine::') }

      expect { classes.each { described_class.of(it) } }.not_to raise_error
    end
  end
end
