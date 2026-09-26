# frozen_string_literal: true

require_relative 'properties'

module RGame
  module Engine
    module Tiled
      SHAPES = %w[capsule ellipse point polygon polyline text].freeze
      private_constant :SHAPES

      # One `<object>`, as the file states it: a tile's collision shape, or an
      # entry in a map's object layer.
      #
      # Coordinates are in pixels, as Floats, and mean what Tiled means by them.
      # A tile object's `(x, y)` is its bottom-left corner, `rotation` is in
      # degrees clockwise about `(x, y)`, and `points` are relative to `(x, y)`.
      # `gid` keeps its flip bits and loses only bit 29, as `Tiled.gid` says.
      # Converting any of it is the transform's job, so that the parse can be
      # checked against Tiled's own reference.
      #
      # `shape` is `:rectangle`, `:ellipse`, `:capsule`, `:point`, `:polygon`,
      # `:polyline` or `:text`, and `points` is empty unless it is a polygon or
      # polyline. A child element that is no shape rgame knows raises, so a
      # shape Tiled adds later cannot read as a rectangle.
      Object = Data.define(:id, :name, :class_name, :x, :y, :width, :height, :rotation,
                           :gid, :visible, :shape, :points, :properties) do
        # Builds the record from an `<object>` REXML element. `source_path` is
        # the file it came from, which a `file` property resolves against.
        def self.parse(element, source_path: nil)
          read = ->(name) { Attributes.float(element, name, source_path, default: 0.0) }
          shape, points = shape_of(element, source_path)
          new(id: Attributes.integer(element, 'id', source_path),
              name: element.attributes['name'].to_s,
              class_name: (element.attributes['type'] || element.attributes['class']).to_s,
              x: read['x'], y: read['y'], width: read['width'], height: read['height'],
              rotation: read['rotation'],
              gid: Attributes.integer(element, 'gid', source_path)&.then { Tiled.gid(it) },
              visible: element.attributes['visible'] != '0',
              shape: shape, points: points,
              properties: Properties.parse(element.elements['properties'], source_path: source_path))
        end

        # The child element that gives `element` its shape, or `nil` for a
        # rectangle, which has none.
        def self.shape_element(element) = element.elements.find { it.name != 'properties' }

        def self.shape_of(element, source_path)
          child = shape_element(element) or return [:rectangle, [].freeze]
          unless SHAPES.include?(child.name)
            where = source_path ? " in #{source_path}" : ''
            raise FormatError, "object #{element.attributes['id']}#{where} has a <#{child.name}>, " \
                               'which is no shape rgame reads'
          end
          [child.name.to_sym, points(child, source_path)]
        end

        def self.points(child, source_path)
          text = child.attributes['points'] or return [].freeze

          text.split.map do |pair|
            pair.split(',').map { Float(it) }.tap { raise ArgumentError unless it.size == 2 }.freeze
          end.freeze
        rescue ArgumentError
          Attributes.refuse(child, 'points', source_path, 'is not a list of x,y pairs')
        end
        private_class_method :shape_of, :points

        def visible? = visible
      end
    end
  end
end
