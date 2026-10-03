# frozen_string_literal: true

module RGame
  module Engine
    # One object from a map's object layers, in the game's coordinates: pixels,
    # with the map's top-left corner at `(0, 0)`.
    #
    # `(x, y)` is the object's top-left corner for every shape, a tile object
    # included, and `rotation` turns the object clockwise, in degrees, about
    # that corner. `points` are the corners of a polygon or polyline in the
    # same coordinates, before `rotation`, and empty for any other shape.
    # `origin_x` and `origin_y` say where a node built from the object stands.
    #
    # `tile` is the map's own id for a tile object, or `nil` for a shape, and
    # `orientation` says how that tile is turned. A tile object with no class of
    # its own has its tile's, and its `properties` hold its tile's under its
    # own, which win.
    #
    # `shape` is `:rectangle`, `:ellipse`, `:capsule`, `:point`, `:polygon`,
    # `:polyline` or `:text`. `layer` is the index of the layer the object sits
    # in, as `TileMap#layer` counts them.
    MapObject = Data.define(:id, :name, :class_name, :layer, :x, :y, :width, :height, :rotation,
                            :tile, :orientation, :visible, :shape, :points, :properties) do
      # False when the designer hid the object in Tiled.
      def visible? = visible
    end

    class MapObject
      UNBOXED = %i[point polygon polyline].freeze
      private_constant :UNBOXED

      # Where a node built from this object stands, in pixels: the object's own
      # `(x, y)` for a point, a polygon or a polyline, and the bottom centre of
      # its box, turned by `rotation`, for any other shape.
      def origin_x
        return x if UNBOXED.include?(shape)

        x + (width / 2.0 * Math.cos(radians)) - (height * Math.sin(radians))
      end

      def origin_y
        return y if UNBOXED.include?(shape)

        y + (width / 2.0 * Math.sin(radians)) + (height * Math.cos(radians))
      end

      private

      def radians = rotation * Math::PI / 180.0
    end
  end
end
