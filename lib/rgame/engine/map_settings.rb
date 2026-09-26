# frozen_string_literal: true

module RGame
  module Engine
    # What a map may set on a node class: each keyword its `initialize`
    # documents with a YARD `@param` tag of a type Tiled can hold.
    #
    #   class Chest < Engine::Node2D
    #     # @param contents [String] the item inside
    #     # @param locked [Boolean] whether it takes a key to open
    #     def initialize(contents:, locked: false, **)
    #
    #   RGame::Engine::MapSettings.of(Chest)   # => { contents: :string, locked: :bool }
    #
    # The tags are the unbroken run of comment lines directly above the
    # `def initialize` the class uses. A blank line detaches them. A subclass with
    # no `initialize` of its own reads its parent's, and one with its own reads
    # only its own. The pre-commit hook keeps the block, as it keeps any comment
    # above a public method.
    #
    # | Tag | Type | A property arrives as |
    # |---|---|---|
    # | `[String]` | `:string` | a String |
    # | `[Integer]` | `:integer` | an Integer |
    # | `[Float]` | `:float` | a Float, from a float or an int property |
    # | `[Boolean]` | `:bool` | `true` or `false` |
    # | `[Symbol]` | `:symbol` | a Symbol, from a string property |
    # | `[:low, :high]` | `[:low, :high]` | one of the Symbols, from a string property |
    # | `[Util::Color]` | `:color` | a `Util::Color` |
    #
    # A keyword with no tag, or with a type outside the table such as `[Random]`,
    # stays out of every map's reach. Reading raises ArgumentError for a tag
    # naming no keyword of `initialize`, for a tag naming something the map or
    # the builder sets already, and for an `initialize` with no source file. A
    # class's tags are read once and cached.
    #
    # @api private
    module MapSettings
      TYPES = { 'String' => :string, 'Integer' => :integer, 'Float' => :float, 'Boolean' => :bool,
                'Symbol' => :symbol, 'Util::Color' => :color, 'RGame::Util::Color' => :color }.freeze

      # What a designer sets in Tiled for each type, for the messages that ask
      # them to change it.
      EXPECTED = { string: 'a string property', integer: 'an int property', float: 'a float or int property',
                   bool: 'a bool property', symbol: 'a string property', color: 'a color property' }.freeze

      COMMENT = /\A\s*#/
      TAG = /\A\s*#\s*@param\s+(\w+)(?:\s+\[([^\]]*)\])?/
      SYMBOL = /\A:\w+\z/
      private_constant :TYPES, :EXPECTED, :COMMENT, :TAG, :SYMBOL

      @cache = {}.compare_by_identity

      # The keywords a map may set on `node_class`, each with its type from the
      # table above, as a frozen Hash.
      def self.of(node_class)
        method = node_class.instance_method(:initialize)
        @cache[method.owner] ||= read(method).freeze
      end

      # `value` as a keyword of `type` receives it, or what the block returns
      # when it is not a value of that type.
      def self.cast(type, value)
        return yield unless fits?(type, value)

        case type
        when :float then value.to_f
        when :symbol, Array then value.to_sym
        else value
        end
      end

      # The property a designer sets in Tiled for a keyword of `type`, in words.
      def self.expected(type)
        return EXPECTED.fetch(type) unless type.is_a?(Array)

        "a string property holding #{type.join(', ')}"
      end

      def self.reserved = @reserved ||= [*Node2D.instance_method(:initialize).parameters.map(&:last), :fact].freeze

      def self.read(method)
        owner = method.owner
        file, line = method.source_location
        unless file && File.file?(file)
          raise ArgumentError, "#{owner}#initialize has no source file, so no @param tags say what a map may set; " \
                               'define the class in a .rb file to build it from a map'
        end

        keywords = method.parameters.filter_map { |kind, name| name if %i[key keyreq].include?(kind) }
        tags(file, line).each_with_object({}) do |(name, type), settings|
          check(owner, name, keywords)
          settings[name] = type if type
        end
      end

      def self.tags(file, line)
        comment = File.readlines(file, chomp: true).first(line - 1).reverse.take_while { it.match?(COMMENT) }
        comment.reverse.filter_map { TAG.match(it) }.map { [it[1].to_sym, type_of(it[2])] }
      end

      def self.type_of(text)
        return if text.nil?

        text = text.strip
        return TYPES[text] if TYPES.key?(text)

        symbols = text.split(',').map(&:strip)
        symbols.map { it.delete_prefix(':').to_sym }.freeze if !symbols.empty? && symbols.all? { it.match?(SYMBOL) }
      end

      def self.check(owner, name, keywords)
        if reserved.include?(name)
          raise ArgumentError, "#{owner}#initialize tags @param #{name}, a name no property may set: the object's " \
                               "box and the builder fill Node2D's own keywords, and 'fact' becomes fact_key " \
                               "(reserved: #{reserved.join(', ')})"
        end
        return if keywords.include?(name)

        taken = keywords.empty? ? 'none' : keywords.join(', ')
        raise ArgumentError, "#{owner}#initialize tags @param #{name}, and takes no keyword #{name} " \
                             "(takes: #{taken}); fix the tag or add the keyword"
      end

      def self.fits?(type, value)
        case type
        when :string, :symbol then value.is_a?(String)
        when :integer then value.is_a?(Integer)
        when :float then value.is_a?(Integer) || value.is_a?(Float)
        when :bool then [true, false].include?(value)
        when :color then value.is_a?(Util::Color)
        else value.is_a?(String) && type.include?(value.to_sym)
        end
      end
      private_class_method :reserved, :read, :tags, :type_of, :check, :fits?
    end
  end
end
