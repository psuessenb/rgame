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

# Tags `fact`, which is a property like any other.
class SpecMapFactChest < RGame::Engine::Node2D
  # @param fact [String] where it keeps its state
  def initialize(fact: nil, **)
    super(**)
  end
end

# Tags `route`, which the builder sets from the object's shape.
class SpecMapRoutedChest < RGame::Engine::Node2D
  # @param route [String] where it floats
  def initialize(route: nil, **)
    super(**)
  end
end

# A game's module, for the defaults a constant gives and the nesting a name
# resolves in.
module SpecMapDefaultsGame
  SIZE = 24.0

  # A room of the game, and a module inside it.
  class Room < RGame::Engine::Node2D
    # A module of the room's own.
    module Parts; end
  end

  # Defaults of every kind a map can show.
  class Chest < RGame::Engine::Node2D
    WOOD = :pine

    # A chest a designer may place.
    #
    # @placeable
    # @param key [String] the fact it keeps its state under
    # @param wood [Symbol] what it is made of
    # @param size [Float] its side, in pixels
    # @param tint [Util::Color] the colour it is painted
    # @param spin [Float] how fast it turns
    # @param glow [Util::Color] the colour it shines
    def initialize(key:, wood: WOOD, size: SIZE, tint: RGame::Util::Color::BROWN, spin: -1.5, glow: ::RGame::Util::Color::RED,
                   rng: Random.new(4), **)
      super(**)
    end
  end

  # Takes its parent's initialize, @placeable and all.
  class SmallChest < Chest; end

  # Has an initialize of its own, and no @placeable.
  class LidlessChest < Chest
    # @param key [String] the fact it keeps its state under
    def initialize(key: 'lidless', **)
      super
    end
  end

  # @placeable, detached from initialize by a blank line.
  class DetachedChest < RGame::Engine::Node2D
    # @placeable

    def initialize(**) = super # rubocop:disable Lint/UselessMethodDefinition -- it carries the comment above it
  end

  # A default no one can read without running it.
  class TurnedChest < RGame::Engine::Node2D
    # @param angle_offset [Float] how far it is turned, in radians
    def initialize(angle_offset: -Math::PI / 2, **)
      super(**)
    end
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

    it 'refuses a tag naming route or name, which the builder sets, listing every reserved name' do
      expect { described_class.of(SpecMapRoutedChest) }
        .to raise_error(ArgumentError, /@param route, a name no property may set.*map_object_id, route, name\)/)
    end

    it 'reads a tag naming fact, which is a property like any other' do
      expect(described_class.of(SpecMapFactChest)).to eq(fact: :string)
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

    # The first room to build a class reads its tags, and a game may enter that
    # room long after it started. Splitting the file into lines cost a String
    # for every line above the class, in the middle of play.
    it 'allocates for the comment above initialize, not for each line of the file above it' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'far_down_chest.rb')
        File.write(path, "# filler\n\n" * 150 + <<~RUBY)
          class SpecMapFarDownChest < RGame::Engine::Node2D
            # @param contents [String] the item inside
            def initialize(contents: '', **) = super(**)
          end
        RUBY
        load path
        described_class.of(SpecMapChest)
        before = GC.stat(:total_allocated_objects)
        settings = described_class.of(SpecMapFarDownChest)
        allocated = GC.stat(:total_allocated_objects) - before

        expect([settings, allocated]).to match([{ contents: :string }, be < 40])
      end
    end

    it 'reads every engine node class, so no engine comment drifts from its constructor' do
      classes = descendants(RGame::Engine::Node2D).select { it.name&.start_with?('RGame::Engine::') }

      expect { classes.each { described_class.of(it) } }.not_to raise_error
    end
  end

  describe '.placeable?' do
    it 'is true when the comment above initialize carries @placeable' do
      expect(described_class.placeable?(SpecMapDefaultsGame::Chest)).to be(true)
    end

    it 'is false for a comment without it' do
      expect(described_class.placeable?(SpecMapChest)).to be(false)
    end

    it "follows a subclass that takes its parent's initialize" do
      expect(described_class.placeable?(SpecMapDefaultsGame::SmallChest)).to be(true)
    end

    it 'reads only its own comment for a subclass with an initialize of its own' do
      expect(described_class.placeable?(SpecMapDefaultsGame::LidlessChest)).to be(false)
    end

    it 'reads nothing above a blank line' do
      expect(described_class.placeable?(SpecMapDefaultsGame::DetachedChest)).to be(false)
    end
  end

  describe '.defaults' do
    it 'reads a literal of each kind, and leaves out every keyword a map cannot set' do
      expect(described_class.defaults(SpecMapChest))
        .to eq(contents: '', count: 1, weight: 1.0, locked: false, wood: :oak, lid: :flat, tint: nil, glow: nil)
    end

    it 'leaves out a required keyword' do
      expect(described_class.defaults(SpecMapDefaultsGame::Chest).keys).not_to include(:key)
    end

    it "looks a constant up in the class, then outward through its module, as a map's class name is" do
      expect(described_class.defaults(SpecMapDefaultsGame::Chest))
        .to include(wood: :pine, size: 24.0, tint: RGame::Util::Color::BROWN, glow: RGame::Util::Color::RED)
    end

    it 'reads a negative number as the number' do
      expect(described_class.defaults(SpecMapDefaultsGame::Chest)).to include(spin: -1.5)
    end

    it "reads a subclass's defaults from the initialize it takes" do
      expect(described_class.defaults(SpecMapDefaultsGame::SmallChest))
        .to eq(described_class.defaults(SpecMapDefaultsGame::Chest))
    end

    it 'refuses a default it cannot read without running it, naming the keyword and a constant to write' do
      expect { described_class.defaults(SpecMapDefaultsGame::TurnedChest) }
        .to raise_error(ArgumentError, %r{TurnedChest#initialize defaults angle_offset to `-Math::PI / 2`.*ANGLE_OFF})
    end

    it 'reads a class once, and keeps what it read frozen' do
      defaults = described_class.defaults(SpecMapChest)

      expect([described_class.defaults(SpecMapChest).equal?(defaults), defaults.frozen?]).to eq([true, true])
    end
  end

  describe '.nesting' do
    it 'lists the class, then each module its name passes through' do
      expect(described_class.nesting(SpecMapDefaultsGame::Room::Parts))
        .to eq([SpecMapDefaultsGame::Room::Parts, SpecMapDefaultsGame::Room, SpecMapDefaultsGame])
    end

    it 'lists only an anonymous class itself' do
      anonymous = Class.new

      expect(described_class.nesting(anonymous)).to eq([anonymous])
    end
  end

  describe '.resolve' do
    let(:nesting) { described_class.nesting(SpecMapDefaultsGame::Room) }

    it 'finds a name in the innermost module that defines it' do
      expect(described_class.resolve('SIZE', nesting)).to eq(24.0)
    end

    it 'resolves a path the same way' do
      expect(described_class.resolve('Chest::WOOD', nesting)).to eq(:pine)
    end

    it 'falls back on what the first module inherits, then the top level' do
      expect(described_class.resolve('Comparable', nesting)).to be(Comparable)
    end

    it 'raises NameError for a name nothing defines' do
      expect { described_class.resolve('Chset', nesting) }.to raise_error(NameError)
    end
  end
end
