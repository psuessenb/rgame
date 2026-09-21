# frozen_string_literal: true

module RGame
  module Engine
    # The custom properties a designer attached to a map, a layer, a tile or an
    # object in Tiled, already cast to Ruby types.
    #
    #   props['speed']            # => 2.5, or nil when there is none
    #   props.fetch('damage')     # => 10, or KeyError naming the property
    #   props.fetch('speed', 1.0) # => a default for a member left unset
    #
    # A value is a String, Integer, Float, `true` or `false`, a `Util::Color`,
    # or a nested `Properties` for a property of a custom class. A `file`
    # property is a path resolved against the file that states it.
    #
    # A class member left at its default is absent, because Tiled writes only
    # the members that differ from the class's defaults. Read one with
    # `fetch(name, default)`.
    #
    # A `Properties` is frozen, and "no properties" is `EMPTY`, never `nil`.
    class Properties
      include Enumerable

      # Wraps `values`, a Hash from name to value.
      def initialize(values)
        @values = values.dup.freeze
        freeze
      end

      EMPTY = new({})

      def [](name) = @values[name]

      # The value of `name`, or `default` when there is none. With no default,
      # a missing property raises `KeyError` naming it.
      def fetch(name, *default)
        @values.fetch(name, *default)
      rescue KeyError
        names = @values.empty? ? 'none' : @values.keys.join(', ')
        raise KeyError.new("no custom property '#{name}' (has: #{names})", receiver: self, key: name)
      end

      def key?(name) = @values.key?(name)

      # Yields each name and value.
      def each(&) = @values.each(&)

      def to_h = @values

      def empty? = @values.empty?

      # Equal when both hold the same names and values.
      def ==(other) = other.is_a?(Properties) && to_h == other.to_h
      alias eql? ==

      def hash = @values.hash
    end
  end
end
