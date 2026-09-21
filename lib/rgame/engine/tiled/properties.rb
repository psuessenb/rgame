# frozen_string_literal: true

require_relative '../../util'
require_relative '../tiled'
require_relative 'attributes'

module RGame
  module Engine
    module Tiled
      # The custom properties Tiled attaches to a map, layer, tileset, tile or
      # object, cast to Ruby types when the file is parsed.
      #
      #   props['above']         # => true, a boolean rather than the String "true"
      #   props.fetch('damage')  # => 10, or KeyError naming the property
      #   props.fetch('speed', 1.0)
      #
      # | Tiled type | Ruby |
      # |---|---|
      # | `string` (the default) | `String` |
      # | `int` | `Integer` |
      # | `float` | `Float` |
      # | `bool` | `true` / `false` |
      # | `color` | `Util::Color`, or `nil` when Tiled has no colour to write |
      # | `file` | `String`, resolved relative to the file that named it |
      # | `object` | `Integer` — an object id, left unresolved |
      # | `class` | `Properties`, nested |
      #
      # Casting at parse time is what lets a caller use a value without
      # checking what it is: a `bool` read as a String would be truthy when it
      # is false.
      #
      # A class member left at its default value is absent. Tiled writes only
      # the members that differ, and keeps the defaults in the project file,
      # which rgame does not read — so a game reads such a member with
      # `fetch(name, default)`.
      #
      # A `Properties` is frozen, and a missing `<properties>` element parses to
      # `EMPTY`, never `nil`.
      class Properties
        include Enumerable

        COLOR = /\A#(\h{2})?(\h{2})(\h{2})(\h{2})\z/
        private_constant :COLOR

        # Builds the bag from a `<properties>` REXML element, or from `nil`.
        # `source_path` is the file the element came from; a `file` property
        # resolves against its directory, and stays as written without one.
        def self.parse(element, source_path: nil)
          return EMPTY unless element

          values = element.get_elements('property').to_h do |property|
            [property.attributes['name'], cast(property, source_path)]
          end
          new(values)
        end

        def self.cast(property, source_path)
          value = property.attributes['value']
          case property.attributes['type'] || 'string'
          when 'string' then value || property.text || ''
          when 'int', 'object' then number(property, source_path) { Integer(value, 10) }
          when 'float' then number(property, source_path) { Float(value) }
          when 'bool' then bool(property, source_path)
          when 'color' then color(property, source_path)
          when 'file' then Attributes.path(value.to_s, source_path)
          when 'class' then parse(property.elements['properties'], source_path: source_path)
          else refuse(property, source_path, "has type '#{property.attributes['type']}', which rgame does not read")
          end
        end

        def self.number(property, source_path)
          yield
        rescue ArgumentError, TypeError
          refuse(property, source_path, "is not a valid #{property.attributes['type']}")
        end

        def self.bool(property, source_path)
          case property.attributes['value']
          when 'true' then true
          when 'false' then false
          else refuse(property, source_path, 'is neither true nor false')
          end
        end

        def self.color(property, source_path)
          value = property.attributes['value'].to_s
          return nil if value.empty?

          match = COLOR.match(value) or refuse(property, source_path, 'is not a #AARRGGBB or #RRGGBB colour')
          alpha, red, green, blue = match.captures
          Util::Color.new(red.hex, green.hex, blue.hex, alpha ? alpha.hex : 255)
        end

        def self.refuse(property, source_path, problem)
          where = source_path ? " in #{source_path}" : ''
          value = property.attributes['value']
          raise FormatError, "property '#{property.attributes['name']}'#{where} (#{value.inspect}) #{problem}"
        end
        private_class_method :cast, :number, :bool, :color, :refuse

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

        def each(&) = @values.each(&)

        def to_h = @values

        def empty? = @values.empty?

        def ==(other) = other.is_a?(Properties) && to_h == other.to_h
        alias eql? ==

        def hash = @values.hash
      end
    end
  end
end
