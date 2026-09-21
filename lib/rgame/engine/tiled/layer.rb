# frozen_string_literal: true

require_relative 'object'
require_relative 'tileset'

module RGame
  module Engine
    module Tiled
      # What every kind of layer in a map has, as the file states it.
      #
      # `visible?` and `opacity` are the layer's own. A group passes both down
      # to what it holds, so `effective_visible?` is false when the layer or
      # any group around it is hidden. `effective_opacity` multiplies the
      # layer's opacity by every group's around it.
      class Layer
        attr_reader :id, :name, :class_name, :opacity, :effective_opacity, :properties

        def initialize(id:, name:, class_name:, visible:, opacity:, effective_visible:, effective_opacity:,
                       properties:)
          @id = id
          @name = name
          @class_name = class_name
          @visible = visible
          @opacity = opacity
          @effective_visible = effective_visible
          @effective_opacity = effective_opacity
          @properties = properties
        end

        def visible? = @visible

        def effective_visible? = @effective_visible
      end

      # A `<layer>`: a grid of gids, flat and in reading order, each keeping its
      # flip bits. On an infinite map every tile layer covers the same box, the
      # one around every chunk of every layer, and `Map` records where it
      # starts.
      class TileLayer < Layer
        attr_reader :width, :height, :gids

        def initialize(width:, height:, gids:, **)
          super(**)
          @width = width
          @height = height
          @gids = gids.dup.freeze
          freeze
        end

        # The gid at `(col, row)`, flip bits included.
        def gid(col, row) = @gids[(row * @width) + col]
      end

      # An `<imagelayer>`: one image, placed at the layer's offset in pixels and
      # optionally repeated across the map. `image` is `nil` for a layer that
      # names none.
      class ImageLayer < Layer
        attr_reader :image, :offset_x, :offset_y

        def initialize(image:, offset_x:, offset_y:, repeat_x:, repeat_y:, **)
          super(**)
          @image = image
          @offset_x = offset_x
          @offset_y = offset_y
          @repeat_x = repeat_x
          @repeat_y = repeat_y
          freeze
        end

        def repeat_x? = @repeat_x

        def repeat_y? = @repeat_y
      end

      # A `<group>`: layers nested inside another, in Tiled's order.
      class GroupLayer < Layer
        attr_reader :layers

        def initialize(layers:, **)
          super(**)
          @layers = layers.dup.freeze
          freeze
        end
      end

      # An `<objectgroup>`: `Object`s in the coordinates the file states.
      # `draw_order` is `:topdown` or `:index`, Tiled's two ways of ordering
      # them.
      class ObjectLayer < Layer
        attr_reader :draw_order, :objects

        def initialize(draw_order:, objects:, **)
          super(**)
          @draw_order = draw_order
          @objects = objects.dup.freeze
          freeze
        end
      end
    end
  end
end
