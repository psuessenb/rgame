# frozen_string_literal: true

require_relative '../tiled'
require_relative 'attributes'
require_relative '../properties'

module RGame
  module Engine
    module Tiled
      # Reads a `<properties>` element into an `Engine::Properties`, casting
      # each value by the type Tiled gives it.
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
      # | `class` | `Engine::Properties`, nested, answering `class_name` |
      #
      # Casting at parse time is what lets a caller use a value without
      # checking what it is: a `bool` read as a String would be truthy when it
      # is false.
      #
      # A class member left at its default value is absent. Tiled writes only
      # the members that differ, and keeps the defaults in the project file,
      # which rgame does not read.
      module Properties
        # Builds the bag from a `<properties>` REXML element, or from `nil`.
        # `source_path` is the file the element came from; a `file` property
        # resolves against its directory, and stays as written without one.
        # `class_name` is the custom class the bag is a value of, if any.
        def self.parse(element, source_path: nil, class_name: nil)
          return Engine::Properties::EMPTY unless element || class_name

          values = (element&.get_elements('property') || []).to_h do |property|
            [property.attributes['name'], cast(property, source_path)]
          end
          Engine::Properties.new(values, class_name: class_name)
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
          when 'class'
            parse(property.elements['properties'], source_path: source_path,
                                                   class_name: property.attributes['propertytype'])
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

          Attributes.to_color(value) or refuse(property, source_path, 'is not a #AARRGGBB or #RRGGBB colour')
        end

        def self.refuse(property, source_path, problem)
          where = source_path ? " in #{source_path}" : ''
          value = property.attributes['value']
          raise FormatError, "property '#{property.attributes['name']}'#{where} (#{value.inspect}) #{problem}"
        end
        private_class_method :cast, :number, :bool, :color, :refuse
      end
    end
  end
end
