# frozen_string_literal: true

require 'fileutils'
require 'json'

module RGame
  module Engine
    # Tiled's custom types for a game's node classes, so a designer picks a
    # class from a list and fills in its members rather than typing both.
    #
    #   module MyGame
    #     class Chest < Engine::Node2D
    #       # A chest the hero opens once.
    #       #
    #       # @placeable
    #       # @param contents [String] the item inside
    #       # @param lid [:flat, :round] the shape of its lid
    #       def initialize(contents:, lid: :flat, **)
    #
    #   RGame::Engine::MapTypes.new(MyGame).types
    #   # => the class Chest, with the members contents and lid, and the enum Chest.lid
    #
    # **A class is written when the comment above its `initialize` carries
    # `@placeable`.** The export walks `scope`, and every module and class
    # defined under it, and follows no constant that names a module defined
    # elsewhere, such as a game's `Engine = RGame::Engine`. A map builds a class
    # without the tag all the same: the tag only puts it in the designer's list.
    #
    # **Each placeable class becomes a Tiled class named by its path under
    # `scope`**, such as `Chest` or `Town::Chest`, which is what a map names to
    # build it from any scene in the game. It is used as an object's class and
    # a tile's. Its members are the keywords its `@param` tags let a map set,
    # sorted by name:
    #
    # | Tag | Member |
    # |---|---|
    # | `[String]`, `[Symbol]` | `string` |
    # | `[Integer]` | `int` |
    # | `[Float]` | `float` |
    # | `[Boolean]` | `bool` |
    # | `[Util::Color]` | `color` |
    # | `[:flat, :round]` | `string`, of a string enum `Chest.lid` holding `flat` and `round` |
    #
    # **A member shows its keyword's default**, since Tiled saves no member
    # the designer leaves at its default and the game then takes Ruby's. A
    # literal shows itself, and a constant its value. A required keyword shows
    # Tiled's empty value, and `nil` shows as empty for a String, a Symbol and
    # a colour. Any other default raises ArgumentError, naming the class and
    # the keyword, and so does a placeable class no map could build.
    #
    #   puts RGame::Engine::MapTypes.new(MyGame).write('assets/my_game.tiled-project')
    #
    # **`write` owns every type whose name starts with a capital letter**, as a
    # capital letter in a map's class is the code's. It replaces those the game
    # defines, keeping the id, colour and fill Tiled holds for each, removes
    # the others, and adds new ones after the rest. The designer's lower-case
    # types, and every other key of the project, stay as they are. It writes
    # the file as Tiled does, so a project Tiled saved changes only where the
    # types did, and a project that holds the types already is not written.
    #
    # Nothing at load reads the project. A map builds the same with it, with a
    # stale one, and with none: the project only helps a designer pick.
    class MapTypes
      # What a write changed, or would change, in one project. `added`,
      # `changed` and `unchanged` hold classes as `types` gives them, each
      # changed when an enum of its members changed, and `removed` holds the
      # names of the types taken out. `missing` says the project did not exist,
      # and `written` that this report's write changed the file.
      Report = Data.define(:path, :missing, :added, :changed, :unchanged, :removed, :written) do
        # Whether the project exists and holds every type already.
        def current? = !missing && added.empty? && changed.empty? && removed.empty?

        # A line per class written, with its members, a line per type removed,
        # and the rule that decides which classes are written.
        def to_s
          lines = [heading, *class_lines, *removed.map { "  removed    #{it}" }]
          lines << 'Tiled shows the change once the project is reopened.' if written && !missing
          lines << 'A class is written when the comment above its initialize carries @placeable.'
          lines.join("\n")
        end

        private

        def heading
          return path unless missing

          written ? "#{path}, created" : "#{path}, missing"
        end

        def class_lines
          classes = added.map { [it, 'added'] } + changed.map { [it, 'changed'] } + unchanged.map { [it, 'unchanged'] }
          classes.sort_by! { |type, _status| type['name'] }
          width = classes.map { |type, _status| type['name'].size }.max
          classes.map do |type, status|
            members = type['members'].map { it['name'] }.join(', ')
            "  #{status.ljust(9)}  #{type['name'].ljust(width)}  #{members}".rstrip
          end
        end
      end

      TILED = { string: 'string', symbol: 'string', integer: 'int', float: 'float', bool: 'bool',
                color: 'color' }.freeze
      EMPTY = { string: '', symbol: '', integer: 0, float: 0.0, bool: false, color: '' }.freeze
      WANTED = { string: 'a String or nil', symbol: 'a Symbol or nil', integer: 'an Integer', float: 'a Float',
                 bool: 'true or false', color: 'a Util::Color or nil' }.freeze

      # What Tiled gives a class it makes, and where a game's class may be used.
      COLOR = '#ffa0a0a4'
      USE_AS = %w[object tile].freeze

      OWNED = /\A[[:upper:]]/
      KEPT = %w[color drawFill].freeze
      INDENT = '    '
      private_constant :TILED, :EMPTY, :WANTED, :COLOR, :USE_AS, :OWNED, :KEPT, :INDENT

      # `scope` is the game's module.
      def initialize(scope)
        @scope = scope
      end

      # Each placeable class under `scope` as a Tiled class, and each enum its
      # members name, as Hashes in the shape of Tiled's project file, sorted by
      # name. A type has no `id` until it is written into a project.
      def types = placeable.flat_map { class_types(it) }.sort_by { it['name'] }

      # Writes the types into the Tiled project at `path`, creating the project
      # when it is missing, and returns the Report. A project that holds the
      # types already stays untouched, whatever id, colour, fill or formatting
      # Tiled gave them.
      def write(path)
        report, project = merged(path)
        return report if report.current?

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{json(project, '')}\n")
        report.with(written: true)
      end

      # The Report `write` would return, writing nothing.
      def changes(path) = merged(path).first

      private

      def merged(path)
        missing = !File.exist?(path)
        project = missing ? new_project : JSON.parse(File.read(path))
        held = project.fetch('propertyTypes', [])
        written = types
        wanted = written.to_h { [it['name'], it] }
        statuses = {}
        removed = []
        kept = []
        held.each do |type|
          name = type['name']
          if !name.match?(OWNED) then kept << type
          elsif (replacement = wanted.delete(name)) then kept << replaced(type, replacement, statuses)
          else removed << name
          end
        end
        next_id = held.filter_map { it['id'] }.max.to_i
        wanted.each_value do |type|
          statuses[type['name']] = :added
          kept << type.merge('id' => next_id += 1)
        end
        project['propertyTypes'] = kept
        [report(path, missing, written, statuses, removed), project]
      end

      def new_project
        { 'automappingRulesFile' => '', 'commands' => [], 'compatibilityVersion' => 1100,
          'extensionsPath' => 'extensions', 'folders' => ['.'], 'properties' => [], 'propertyTypes' => [] }
      end

      def replaced(held, type, statuses)
        statuses[type['name']] = held.except('id', *KEPT) == type.except(*KEPT) ? :unchanged : :changed
        type.merge(held.slice('id', *(KEPT & type.keys)))
      end

      def report(path, missing, written, statuses, removed)
        grouped = written.select { it['type'] == 'class' }.group_by { class_status(it, statuses) }
        Report.new(path:, missing:, added: grouped.fetch(:added, []), changed: grouped.fetch(:changed, []),
                   unchanged: grouped.fetch(:unchanged, []), removed:, written: false)
      end

      def class_status(type, statuses)
        return :added if statuses[type['name']] == :added

        same = statuses[type['name']] == :unchanged &&
               type['members'].all? { !it['propertyType'] || statuses[it['propertyType']] == :unchanged }
        same ? :unchanged : :changed
      end

      def json(value, indent)
        inner = indent + INDENT
        case value
        when Hash then block('{', '}', value.sort.map { |key, item| "#{JSON.generate(key)}: #{json(item, inner)}" },
                             indent)
        when Array then block('[', ']', value.map { json(it, inner) }, indent)
        when Float then number(value)
        else JSON.generate(value)
        end
      end

      def block(open, close, entries, indent)
        return "#{open}\n#{indent}#{close}" if entries.empty?

        "#{open}\n#{entries.map { "#{indent}#{INDENT}#{it}" }.join(",\n")}\n#{indent}#{close}"
      end

      def number(value)
        mantissa, exponent = value.to_s.split('e')
        mantissa = mantissa.delete_suffix('.0')
        return mantissa unless exponent
        return "#{mantissa}e#{exponent}" unless value == value.round && value.abs < 2**64

        integer, fraction = mantissa.split('.')
        "#{integer}#{fraction}#{'0' * (exponent.to_i - fraction.to_s.size)}"
      end

      def placeable
        found = []
        walk(@scope, found)
        found
      end

      def walk(space, found)
        space.constants(false).each do |constant|
          value = space.const_get(constant, false)
          next unless value.is_a?(Module) && value.name == "#{space.name}::#{constant}"

          found << value if value.is_a?(Class) && value < Node2D && MapSettings.placeable?(value)
          walk(value, found)
        end
      end

      def class_types(node_class)
        refusal = MapBuilder.refusal(node_class)
        if refusal
          raise ArgumentError, "#{node_class} carries @placeable, and no map could build it: #{refusal}. Take " \
                               '@placeable out of the comment above its initialize, or let a map give it what it needs'
        end

        name = node_class.name.delete_prefix("#{@scope.name}::")
        settings = MapSettings.of(node_class)
        defaults = MapSettings.defaults(node_class)
        members = settings.keys.sort.map { member(node_class, name, it, settings[it], defaults) }
        enums = settings.filter_map { |keyword, type| enum(name, keyword, type) if type.is_a?(Array) }
        [{ 'color' => COLOR, 'drawFill' => true, 'members' => members, 'name' => name, 'type' => 'class',
           'useAs' => USE_AS.dup }, *enums]
      end

      def member(node_class, name, keyword, type, defaults)
        value = defaults.key?(keyword) ? shown(node_class, keyword, type, defaults[keyword]) : EMPTY.fetch(type, '')
        member = { 'name' => keyword.to_s, 'type' => TILED.fetch(type, 'string'), 'value' => value }
        member['propertyType'] = "#{name}.#{keyword}" if type.is_a?(Array)
        member
      end

      def enum(name, keyword, type)
        { 'name' => "#{name}.#{keyword}", 'storageType' => 'string', 'type' => 'enum', 'values' => type.map(&:to_s),
          'valuesAsFlags' => false }
      end

      def shown(node_class, keyword, type, default)
        value = tiled_value(type, default)
        return value unless value.nil?

        owner = node_class.instance_method(:initialize).owner
        wanted = type.is_a?(Array) ? "one of #{type.map(&:inspect).join(', ')}" : WANTED.fetch(type)
        raise ArgumentError, "#{owner}#initialize defaults #{keyword} to #{default.inspect}, which Tiled cannot show " \
                             "for its @param tag; make the default #{wanted}, or leave it out to require the keyword"
      end

      def tiled_value(type, value)
        case type
        when :string then value.nil? ? '' : (value if value.is_a?(String))
        when :symbol then value.nil? ? '' : (value.to_s if value.is_a?(Symbol))
        when :integer then value if value.is_a?(Integer)
        when :float then value.to_f if (value.is_a?(Integer) || value.is_a?(Float)) && value.finite?
        when :bool then value if [true, false].include?(value)
        when :color then value.nil? ? '' : (color(value) if value.is_a?(Util::Color))
        else value.to_s if type.include?(value)
        end
      end

      def color(value) = format('#%<a>02x%<r>02x%<g>02x%<b>02x', a: value.a, r: value.r, g: value.g, b: value.b)
    end
  end
end
