# frozen_string_literal: true

require_relative '../../util'
require_relative '../tiled'

module RGame
  module Engine
    module Tiled
      # Reads the attributes every Tiled element shares a form for: whole
      # numbers, decimals, colours and paths. A value that does not read raises a
      # `FormatError` naming the element, the attribute and the file, so each
      # parser states what it reads and none repeats how.
      module Attributes
        COLOR = /\A#(\h{2})?(\h{2})(\h{2})(\h{2})\z/
        private_constant :COLOR

        module_function

        # The attribute as an Integer, or `default` when the element has none.
        def integer(element, name, source_path, default: nil)
          value = element.attributes[name]
          return default if value.nil?

          Integer(value, 10)
        rescue ArgumentError
          refuse(element, name, source_path, 'is not a whole number')
        end

        # The attribute as an Integer, raising when the element has none.
        def integer!(element, name, source_path)
          integer(element, name, source_path) || refuse_element(element, source_path, "has no #{name}")
        end

        # The attribute as a Float, or `default` when the element has none.
        def float(element, name, source_path, default: nil)
          value = element.attributes[name]
          return default if value.nil?

          Float(value)
        rescue ArgumentError
          refuse(element, name, source_path, 'is not a number')
        end

        # The attribute as a `Util::Color`, or `nil` when the element has none.
        def color(element, name, source_path)
          value = element.attributes[name]
          return nil if value.nil? || value.empty?

          to_color(value) or refuse(element, name, source_path, 'is not a #AARRGGBB or #RRGGBB colour')
        end

        # `text`, in Tiled's `#AARRGGBB` or `#RRGGBB`, as a `Util::Color`, or
        # `nil` when it is in neither form.
        def to_color(text)
          match = COLOR.match(text) or return nil
          alpha, red, green, blue = match.captures
          Util::Color.new(red.hex, green.hex, blue.hex, alpha ? alpha.hex : 255)
        end

        # `path` as the file at `source_path` means it: relative to that file's
        # directory. An empty path, an absolute one, or one with no file to be
        # relative to stays as written.
        def path(path, source_path)
          return path if path.empty? || source_path.nil? || File.absolute_path?(path)

          File.join(File.dirname(source_path), path)
        end

        # Raises `FormatError` for the element as a whole.
        def refuse_element(element, source_path, problem)
          where = source_path ? " in #{source_path}" : ''
          raise FormatError, "<#{element.name}>#{where} #{problem}"
        end

        def refuse(element, name, source_path, problem)
          value = element.attributes[name]
          refuse_element(element, source_path, "has #{name}=#{value.inspect}, which #{problem}")
        end
      end
    end
  end
end
