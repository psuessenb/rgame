# frozen_string_literal: true

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
    class MapTypes
      TILED = { string: 'string', symbol: 'string', integer: 'int', float: 'float', bool: 'bool',
                color: 'color' }.freeze
      EMPTY = { string: '', symbol: '', integer: 0, float: 0.0, bool: false, color: '' }.freeze
      WANTED = { string: 'a String or nil', symbol: 'a Symbol or nil', integer: 'an Integer', float: 'a Float',
                 bool: 'true or false', color: 'a Util::Color or nil' }.freeze

      # What Tiled gives a class it makes, and where a game's class may be used.
      COLOR = '#ffa0a0a4'
      USE_AS = %w[object tile].freeze
      private_constant :TILED, :EMPTY, :WANTED, :COLOR, :USE_AS

      # `scope` is the game's module.
      def initialize(scope)
        @scope = scope
      end

      # Each placeable class under `scope` as a Tiled class, and each enum its
      # members name, as Hashes in the shape of Tiled's project file, sorted by
      # name. A type has no `id` until it is written into a project.
      def types = placeable.flat_map { class_types(it) }.sort_by { it['name'] }

      private

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
