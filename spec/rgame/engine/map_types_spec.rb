# frozen_string_literal: true

require 'json'
require 'open3'
require 'tmpdir'

# MapTypes reads the comments above each class's `initialize`, and Prism reads
# its defaults, both from the source file. So each game's module it exports is
# defined here, where each example can see what it is about. A module the
# export refuses holds one class, since the export stops at the first refusal.

# rubocop:disable Lint/UnusedMethodArgument -- a signature is what MapTypes reads

# A module defined outside the game, which the game names with a constant.
module SpecTypesElsewhere
  # A class the game's constant reaches, and no class of the game's.
  class Barrel < RGame::Engine::Node2D
    # @placeable
    def initialize(**) = super # rubocop:disable Lint/UselessMethodDefinition -- it carries the comment above it
  end
end

# A game with a placeable class of every tag type, a nested one, a subclass with
# and without an initialize of its own, and a class without the tag.
module SpecTypesGame
  Engine = RGame::Engine
  Util = RGame::Util
  Elsewhere = SpecTypesElsewhere

  TINT = Util::Color.new(150, 104, 56)

  # A default of every kind a member shows.
  class Chest < Engine::Node2D
    WEIGHT = 2.5

    # A chest the hero opens.
    #
    # @placeable
    # @param contents [String] the item inside
    # @param count [Integer] how many of it
    # @param weight [Float] in kilograms
    # @param locked [Boolean] whether it takes a key to open
    # @param wood [Symbol] what it is made of
    # @param lid [:flat, :round] the shape of its lid
    # @param tint [Util::Color] the colour it is painted
    # @param glow [Util::Color] the colour it shines
    def initialize(contents:, count: 3, weight: WEIGHT, locked: false, wood: :oak, lid: :round, tint: TINT,
                   glow: nil, rng: Random.new(1), **)
      super(**)
    end
  end

  # Placeable through the initialize it takes from Chest.
  class LockedChest < Chest; end

  # Has an initialize of its own, without the tag.
  class TrappedChest < Chest
    # @param trap [String] what springs when it opens
    def initialize(trap: 'dart', **) = super(**)
  end

  # A scene, which no map places.
  class Town < Engine::Node2D
    # A chest of the town's own, whose every setting is required.
    class Chest < Engine::Node2D
      # @placeable
      # @param label [String] what its sign says
      # @param count [Integer] how many of it
      # @param weight [Float] in kilograms
      # @param locked [Boolean] whether it takes a key to open
      # @param wood [Symbol] what it is made of
      # @param lid [:flat, :round] the shape of its lid
      # @param tint [Util::Color] the colour it is painted
      def initialize(label:, count:, weight:, locked:, wood:, lid:, tint:, **)
        super(**)
      end
    end
  end

  # A flag with nothing a map sets but its name, which the builder gives it.
  class Flag < Engine::Node2D
    # @placeable
    def initialize(name:, **)
      super(**)
    end
  end
end

# A game whose node class carries no @placeable.
module SpecTypesUntagged
  # A crate a map builds all the same.
  class Crate < RGame::Engine::Node2D
    # @param size [Float] its side, in pixels
    def initialize(size: 16.0, **)
      super(**)
    end
  end
end

# A default of another type than the tag's.
module SpecTypesWordCount
  # Counts in words.
  class Crate < RGame::Engine::Node2D
    # @placeable
    # @param count [Integer] how many of it
    def initialize(count: 'three', **)
      super(**)
    end
  end
end

# `nil` for an Integer, which Tiled has no empty value for.
module SpecTypesNilCount
  # Counts nothing.
  class Crate < RGame::Engine::Node2D
    # @placeable
    # @param count [Integer] how many of it
    def initialize(count: nil, **)
      super(**)
    end
  end
end

# A default outside its tag's list.
module SpecTypesSquareLid
  # A lid no list holds.
  class Crate < RGame::Engine::Node2D
    # @placeable
    # @param lid [:flat, :round] the shape of its lid
    def initialize(lid: :square, **)
      super(**)
    end
  end
end

# A default no one can read without running it.
module SpecTypesTurned
  # Turned a quarter.
  class Crate < RGame::Engine::Node2D
    # @placeable
    # @param spin [Float] how far it is turned, in radians
    def initialize(spin: -Math::PI / 2, **)
      super(**)
    end
  end
end

# A placeable class that requires what no map sets.
module SpecTypesCamera
  # A hero, which the scene builds with its camera.
  class Hero < RGame::Engine::Node2D
    # @placeable
    def initialize(camera:, **)
      super(**)
    end
  end
end

# A placeable class that takes none of the keywords a map passes every node.
module SpecTypesClosed
  # Takes only what it names.
  class Sign < RGame::Engine::Node2D
    # @placeable
    # @param text [String] what it says
    def initialize(text: '')
      super()
    end
  end
end

# A placeable class that requires an argument.
module SpecTypesPositional
  # A room of the map it is given.
  class Room < RGame::Engine::Node2D
    # @placeable
    def initialize(map_id, **)
      super(**)
    end
  end
end

# A Float of each form Tiled writes otherwise than Ruby.
module SpecTypesFloats
  # A gauge with a Float default of each form.
  class Gauge < RGame::Engine::Node2D
    # @placeable
    # @param whole [Float] a whole number
    # @param huge [Float] beyond 2**64
    # @param tenth [Float] a fraction
    # @param tiny [Float] below 1e-4
    # @param below [Float] a whole negative number
    # @param long [Float] whole, below 2**64, with more digits than a Float keeps
    def initialize(whole: 100.0, huge: 1e20, tenth: 0.1, tiny: 0.00001, below: -3.0,
                   long: 12_345_678_901_234_567_890.0, **)
      super(**)
    end
  end
end

# rubocop:enable Lint/UnusedMethodArgument

RSpec.describe RGame::Engine::MapTypes do
  def types_of(scope) = described_class.new(scope).types

  def named(name) = types_of(SpecTypesGame).find { it['name'] == name }

  describe '#types' do
    it 'writes each placeable class and each enum its members name, sorted by name' do
      expect(types_of(SpecTypesGame).map { it['name'] })
        .to eq(%w[Chest Chest.lid Flag LockedChest LockedChest.lid Town::Chest Town::Chest.lid])
    end

    it 'follows no constant naming a module defined elsewhere' do
      expect(types_of(SpecTypesGame).map { it['name'] }).not_to include('Elsewhere::Barrel', 'Barrel')
    end

    it 'writes a class Tiled uses for an object and a tile, with its members sorted by name' do
      expect(named('Chest')).to include('type' => 'class', 'useAs' => %w[object tile], 'color' => '#ffa0a0a4',
                                        'drawFill' => true)
      expect(named('Chest')['members'].map { it['name'] })
        .to eq(%w[contents count glow lid locked tint weight wood])
    end

    it "shows each keyword's default, in the member of its tag's type" do
      expect(named('Chest')['members']).to eq(
        [
          { 'name' => 'contents', 'type' => 'string', 'value' => '' },
          { 'name' => 'count', 'type' => 'int', 'value' => 3 },
          { 'name' => 'glow', 'type' => 'color', 'value' => '' },
          { 'name' => 'lid', 'propertyType' => 'Chest.lid', 'type' => 'string', 'value' => 'round' },
          { 'name' => 'locked', 'type' => 'bool', 'value' => false },
          { 'name' => 'tint', 'type' => 'color', 'value' => '#ff966838' },
          { 'name' => 'weight', 'type' => 'float', 'value' => 2.5 },
          { 'name' => 'wood', 'type' => 'string', 'value' => 'oak' }
        ]
      )
    end

    it 'writes a list of Symbols as a string enum named after the class and the keyword' do
      expect(named('Chest.lid')).to eq('name' => 'Chest.lid', 'storageType' => 'string', 'type' => 'enum',
                                       'values' => %w[flat round], 'valuesAsFlags' => false)
    end

    it "shows Tiled's empty value for each required keyword" do
      expect(named('Town::Chest')['members'].to_h { [it['name'], it['value']] })
        .to eq('count' => 0, 'label' => '', 'lid' => '', 'locked' => false, 'tint' => '', 'weight' => 0.0,
               'wood' => '')
    end

    it 'writes a subclass that takes its parent initialize with its own name, and enum' do
      expect(named('LockedChest')['members'].find { it['name'] == 'lid' })
        .to include('propertyType' => 'LockedChest.lid')
    end

    it 'gives name: and route: no member, since the builder fills them from the object' do
      expect(named('Flag')['members']).to eq([])
    end

    it 'refuses a default of another type than its tag, naming the class, the keyword and the type to write' do
      expect { types_of(SpecTypesWordCount) }
        .to raise_error(ArgumentError, /SpecTypesWordCount::Crate#initialize defaults count to "three".*an Integer/)
    end

    it 'refuses nil for a type Tiled has no empty value for' do
      expect { types_of(SpecTypesNilCount) }
        .to raise_error(ArgumentError, /defaults count to nil.*make the default an Integer/)
    end

    it "refuses a Symbol outside its tag's list, listing the list" do
      expect { types_of(SpecTypesSquareLid) }
        .to raise_error(ArgumentError, /defaults lid to :square.*one of :flat, :round/)
    end

    it 'refuses a default it cannot read' do
      expect { types_of(SpecTypesTurned) }
        .to raise_error(ArgumentError, %r{SpecTypesTurned::Crate#initialize defaults spin to `-Math::PI / 2`})
    end

    it 'refuses a placeable class that requires a keyword no map sets' do
      expect { types_of(SpecTypesCamera) }
        .to raise_error(ArgumentError, /SpecTypesCamera::Hero carries @placeable, and no map could build it: .*camera/)
    end

    it 'refuses a placeable class that takes none of the keywords a map passes every node' do
      expect { types_of(SpecTypesClosed) }
        .to raise_error(ArgumentError, /SpecTypesClosed::Sign carries @placeable.*takes no \*\*/)
    end

    it 'refuses a placeable class that requires an argument' do
      expect { types_of(SpecTypesPositional) }
        .to raise_error(ArgumentError, /SpecTypesPositional::Room carries @placeable.*the argument map_id/)
    end

    it 'writes nothing for a module with no placeable class' do
      expect(types_of(SpecTypesUntagged)).to eq([])
    end
  end

  # The fixture is Tiled 1.12.2's own writing. MapTypes wrote SpecTypesGame's
  # types into a new project, and this script, run as
  # `tiled --project saved.tiled-project --evaluate saved.js`, added a
  # project property, a lower-case enum and a lower-case class. Adding a type
  # makes Tiled save the project, and it wrote every byte of the export back
  # as it was.
  #
  #   var project = tiled.project;
  #   project.setProperty("author", "rgame");
  #   var facing = project.addEnumType("facing");
  #   facing.addValue("north");
  #   facing.addValue("south");
  #   var entrance = project.addClassType("entrance");
  #   entrance.setMember("facing", tiled.propertyValue("facing", "south"));
  #   entrance.setMember("rise", 0.5);
  describe 'a project' do
    let(:dir) { Dir.mktmpdir('rgame-map-types') }
    let(:saved) { File.read(File.expand_path('../../fixtures/saved.tiled-project', __dir__)) }
    let(:path) { File.join(dir, 'game.tiled-project') }
    let(:exporter) { described_class.new(SpecTypesGame) }

    # The fixture with Chest's count at 4 rather than its default of 3, so a
    # write has something to change.
    let(:stale) { saved.sub('"value": 3', '"value": 4') }

    after { FileUtils.remove_entry(dir) }

    def project = JSON.parse(File.read(path))

    def held = project['propertyTypes']

    # The fixture changed by the block, written by Ruby's own JSON, so what a
    # write leaves reads as MapTypes wrote it rather than as it came in.
    def edited
      parsed = JSON.parse(saved)
      yield parsed['propertyTypes']
      File.write(path, JSON.pretty_generate(parsed))
    end

    def type(name) = held.find { it['name'] == name }

    describe '#write' do
      it "creates a missing project, holding what Tiled's own new project holds" do
        exporter.write(path)

        expect(project.except('propertyTypes'))
          .to eq('automappingRulesFile' => '', 'commands' => [], 'compatibilityVersion' => 1100,
                 'extensionsPath' => 'extensions', 'folders' => ['.'], 'properties' => [])
        expect(held.map { [it['id'], it['name']] }).to eq(exporter.types.each_with_index.map { |t, i|
          [i + 1, t['name']]
        })
      end

      it 'creates one for a game with no placeable class, holding no type' do
        described_class.new(SpecTypesUntagged).write(path)

        expect(held).to eq([])
      end

      it 'writes the file as Tiled does, so a project Tiled saved changes only where a type did' do
        File.write(path, stale)
        exporter.write(path)

        expect(File.read(path)).to eq(saved)
      end

      # Tiled 1.12.2 wrote each value back this way, where Ruby writes -3.0,
      # 1.0e+20, 1.2345678901234567e+19, 1.0e-05 and 100.0.
      it 'writes a Float as Tiled writes it' do
        described_class.new(SpecTypesFloats).write(path)

        expect(File.read(path).scan(/"value": (.*)$/).flatten)
          .to eq(%w[-3 1e+20 12345678901234567000 0.1 1e-05 100])
      end

      it 'leaves a project that holds the types untouched, however it is formatted' do
        compact = JSON.generate(JSON.parse(saved))
        File.write(path, compact)
        exporter.write(path)

        expect(File.read(path)).to eq(compact)
      end

      it 'replaces a type the game defines in its place, keeping the id, colour and fill Tiled holds' do
        edited do |types|
          chest = types.find { it['name'] == 'Chest' }
          chest.merge!('color' => '#ff112233', 'drawFill' => false, 'members' => [])
        end
        exporter.write(path)

        expect(held.first).to include('id' => 1, 'name' => 'Chest', 'color' => '#ff112233', 'drawFill' => false,
                                      'members' => exporter.types.first['members'])
      end

      it 'removes a type starting with a capital letter that the game does not define' do
        edited { it << { 'id' => 20, 'name' => 'Barrel', 'type' => 'class', 'members' => [], 'useAs' => [] } }
        exporter.write(path)

        expect(type('Barrel')).to be_nil
      end

      it 'keeps every type starting with a lower-case letter, and every other key of the project' do
        edited { it.reject! { it['name'] == 'Flag' } }
        exporter.write(path)

        expect([type('entrance')['id'], type('facing')['id'], project['properties'].first['name']])
          .to eq([9, 8, 'author'])
      end

      it 'adds a type the project lacks after the rest, with an id above the highest' do
        edited { it.reject! { it['name'] == 'Flag' } }
        exporter.write(path)

        expect(held.last).to include('id' => 10, 'name' => 'Flag')
      end
    end

    describe '#changes' do
      it 'reports what write would, and writes nothing' do
        File.write(path, stale)

        expect([exporter.changes(path).changed.map { it['name'] }, File.read(path)]).to eq([['Chest'], stale])
      end

      it 'is current for a project holding the types, whatever id, colour or fill Tiled gave them' do
        edited do |types|
          types.each do |type|
            type['id'] += 100
            type['color'] = '#ff000000' if type['type'] == 'class'
          end
          types.first['drawFill'] = false
        end

        expect(exporter.changes(path)).to be_current
      end

      it 'counts a class changed when only an enum of its members did' do
        edited { |types| types.find { it['name'] == 'Chest.lid' }['values'] = %w[flat] }

        expect(exporter.changes(path).changed.map { it['name'] }).to eq(['Chest'])
      end

      it 'is not current for a missing project, even with no class to write' do
        expect(described_class.new(SpecTypesUntagged).changes(path)).not_to be_current
      end
    end

    describe 'the report' do
      it 'lists every class, with its members and what the write did, then every type removed' do
        edited do |types|
          types.reject! { it['name'] == 'Flag' }
          types.find { it['name'] == 'Chest' }['members'] = []
          types << { 'id' => 20, 'name' => 'Barrel', 'type' => 'class', 'members' => [], 'useAs' => [] }
        end

        expect(exporter.write(path).to_s).to eq(<<~REPORT.chomp)
          #{path}
            changed    Chest        contents, count, glow, lid, locked, tint, weight, wood
            added      Flag
            unchanged  LockedChest  contents, count, glow, lid, locked, tint, weight, wood
            unchanged  Town::Chest  count, label, lid, locked, tint, weight, wood
            removed    Barrel
          Tiled shows the change once the project is reopened.
          A class is written when the comment above its initialize carries @placeable.
        REPORT
      end

      it 'says only which classes are written, for a current project' do
        File.write(path, saved)

        expect(exporter.write(path).to_s.lines.last(2).map(&:chomp))
          .to eq(['  unchanged  Town::Chest  count, label, lid, locked, tint, weight, wood',
                  'A class is written when the comment above its initialize carries @placeable.'])
      end

      it 'says a project was created, and that a missing one would be' do
        expect([exporter.changes(path).to_s.lines.first, exporter.write(path).to_s.lines.first])
          .to eq(["#{path}, missing\n", "#{path}, created\n"])
      end

      it 'says only the rule, for a game with no placeable class' do
        File.write(path, JSON.generate('propertyTypes' => []))

        expect(described_class.new(SpecTypesUntagged).write(path).to_s)
          .to eq("#{path}\nA class is written when the comment above its initialize carries @placeable.")
      end
    end
  end

  # Prism takes about a third as long to load as rgame itself, so a game that
  # never exports its types never pays for it.
  describe 'loading Prism' do
    def loaded_after(script)
      program = "require 'rgame'; #{script}; print defined?(Prism).inspect"
      root = File.expand_path('../../..', __dir__)
      output, status = Open3.capture2e(RbConfig.ruby, '-Ilib', '-e', program, chdir: root)
      raise output unless status.success?

      output
    end

    it "is left to the first default read, not done by require 'rgame'" do
      expect(loaded_after('nil')).to eq('nil')
    end

    it 'happens when a default is read' do
      expect(loaded_after('RGame::Engine::MapSettings.defaults(RGame::Engine::Node2D)')).to eq('"constant"')
    end
  end
end
