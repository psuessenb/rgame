# frozen_string_literal: true

require_relative '../util'
require_relative 'properties'
require_relative 'map_object'

module RGame
  module Engine
    # A map made in Tiled, as a game reads it: a grid of tiles per layer, what
    # each tile is, and the map's objects. Pure data, with no image and no file.
    #
    #   map = RGame::Engine::TileMap.from_tiled(parsed)
    #   map.tile(0, 12, 7)     # => the tile in layer 0 at column 12, row 7
    #   map.solid_tile?(12, 7) # => whether any layer blocks that cell
    #   map.cell_x(12)         # => 192, the column's left edge in pixels
    #
    # **A cell holds a tile id.** Ids are dense and start at 1, across every
    # tileset the map uses, so every fact about a tile is one Array read; 0 is
    # the empty cell. `tile_table` says which tileset and which tile in it an
    # id came from, which is what the glue slices the images against.
    #
    # **Layers are flat.** Tiled's groups contribute no index of their own:
    # their layers follow one another depth first, in Tiled's order, with the
    # groups' opacity and visibility folded in. `layer_index` finds a layer by
    # its name or its `'Group/layer'` path, which survive a group added above.
    #
    # **Everything here is in the game's terms.** Cell `(0, 0)` is the map's
    # top-left, an animation frame lasts seconds, and an object's `(x, y)` is
    # its top-left corner. `from_tiled`, the only thing that builds one, does
    # every conversion from the file's terms, so no caller does.
    #
    # **Cells and pixels convert here.** `cell_x`, `cell_y`, `col_at` and
    # `row_at` are the only arithmetic on the tile size. The renderer and
    # `Components::TileWorld` call them, so a grid that stops being uniform
    # changes in one class.
    #
    # `initialize` takes plain Arrays and builds the grids itself, so a built
    # map holds nothing but Ruby values and the `Util::Tensor`s made from
    # them.
    class TileMap
      # How a tile in a cell is turned: `quarter_turns` clockwise, 0 to 3, and
      # then, if `mirrored?`, flipped across its vertical axis. The eight values
      # are `ALL`, and every unturned cell answers `IDENTITY`.
      Orientation = Data.define(:quarter_turns, :mirrored) do
        def mirrored? = mirrored

        # True for a tile drawn as its sheet shows it.
        def identity? = quarter_turns.zero? && !mirrored
      end

      class Orientation
        ALL = Array.new(8) { new(quarter_turns: it % 4, mirrored: it >= 4) }.freeze
        IDENTITY = ALL.first
      end

      NO_OFFSET = [0, 0].freeze
      private_constant :NO_OFFSET

      # Where a tile id came from: the index of its tileset, in the order the
      # map lists them by first gid, and the tile's index in that tileset.
      TileSource = Data.define(:tileset, :local_id)

      # What a map was built from: the file it was read from, or `nil`, and
      # the version of the parse that read it.
      Source = Data.define(:path, :parser_version)

      # One layer of the flat list. `path` is the names of the groups around
      # it and its own, outermost first. `kind` is `:tile`, `:image` or
      # `:object`. `visible?` and `opacity` already include every group around
      # the layer.
      class Layer
        attr_reader :index, :name, :path, :kind, :class_name, :opacity, :properties

        def initialize(index:, path:, kind:, class_name:, visible:, opacity:, above:, properties:)
          @index = index
          @path = path.dup.freeze
          @name = @path.last
          @kind = kind
          @class_name = class_name
          @visible = visible
          @opacity = opacity
          @above = above
          @properties = properties
          freeze
        end

        def visible? = @visible

        # Whether the layer covers the actors: a canopy or a roof. Set in Tiled
        # with a bool property named `above`.
        def above? = @above
      end

      # A layer that shows one image, placed at `(offset_x, offset_y)` in the
      # map's pixels and repeated along each axis the designer asked. `image`
      # is the image's path, or `nil` for a layer that names none.
      class ImageLayer < Layer
        attr_reader :image, :offset_x, :offset_y

        def initialize(image:, offset_x:, offset_y:, repeat_x:, repeat_y:, **)
          @image = image
          @offset_x = offset_x
          @offset_y = offset_y
          @repeat_x = repeat_x
          @repeat_y = repeat_y
          super(kind: :image, **)
        end

        def repeat_x? = @repeat_x

        def repeat_y? = @repeat_y
      end

      attr_reader :width, :height, :tile_width, :tile_height,
                  :pixel_width, :pixel_height, :tile_table,
                  :image_layers, :objects, :properties, :source

      # A map from already-built data. `layers` is the flat list of `Layer`s.
      # `cells` has one entry per layer: a flat Array of `width * height` tile
      # ids in reading order, or `nil` for a layer that is not a tile layer.
      # `orientations` is `nil` for a map with no turned tile, or the same
      # shape as `cells` holding indexes into `Orientation::ALL`.
      #
      # `tile_table` starts with `nil` for id 0. `solid`, `tile_classes`,
      # `tile_properties` and `frames` are indexed by tile id alike, and so is
      # `tile_offsets`, which may be `nil` for a map drawn at no offset. A
      # tile's `frames` are `[[tile, until], ...]`, or `nil` when it does not
      # animate: each frame shows until `until` seconds into the loop, so the
      # last frame's `until` is the loop's length.
      def initialize(width:, height:, tile_width:, tile_height:, layers:, cells:, tile_table:,
                     solid:, tile_classes:, tile_properties:, frames:, tile_offsets: nil, orientations: nil,
                     objects: [], properties: Properties::EMPTY, source: Source.new(path: nil, parser_version: 0))
        @width = width
        @height = height
        @tile_width = tile_width
        @tile_height = tile_height
        @pixel_width = width * tile_width
        @pixel_height = height * tile_height
        @layers = layers.dup.freeze
        @image_layers = @layers.grep(ImageLayer).freeze
        @tile_table = tile_table.dup.freeze
        @solid = solid.dup.freeze
        @tile_classes = tile_classes.dup.freeze
        @tile_properties = tile_properties.dup.freeze
        @tile_offsets = (tile_offsets || Array.new(@tile_table.size, NO_OFFSET)).map(&:freeze).freeze
        @frames = frames.map { it&.map { |pair| pair.dup.freeze }&.freeze }.freeze
        @animated_tiles = @frames.each_index.select { @frames[it] }.freeze
        @objects = objects.dup.freeze
        @properties = properties
        @source = source
        @plane_of = plane_indexes(cells)
        @tiles = grid(cells)
        @orientations = orientations && grid(orientations)
      end

      # How many layers the flat list holds, of every kind.
      def layer_count = @layers.size

      # The `Layer` at `index`. Raises `IndexError` for one the map lacks.
      def layer(index) = @layers.fetch(index)

      # The index of the layer named `name_or_path`: a layer's name, or the
      # names of the groups around it and its own joined with `/`. Raises
      # `KeyError` naming the map's layers when none matches, and when a bare
      # name matches layers in two groups.
      def layer_index(name_or_path)
        found = @layers.select { it.path.join('/') == name_or_path }
        found = @layers.select { it.name == name_or_path } if found.empty?
        return found.first.index if found.size == 1

        paths = (found.empty? ? @layers : found).map { it.path.join('/') }.join(', ')
        problem = found.empty? ? "no layer '#{name_or_path}'" : "'#{name_or_path}' names #{found.size} layers"
        raise KeyError.new("#{problem} in this map (#{found.empty? ? 'has' : 'give the path'}: #{paths})",
                           receiver: self, key: name_or_path)
      end

      def in_bounds?(col, row)
        col >= 0 && row >= 0 && col < @width && row < @height
      end

      # The tile id at `(col, row)` of `layer`, or 0 when the cell is empty,
      # outside the map, or in a layer that holds no tiles.
      def tile(layer, col, row)
        plane = @plane_of.fetch(layer)
        return 0 unless plane && in_bounds?(col, row)

        @tiles[col, row, plane]
      end

      # How the tile at `(col, row)` of `layer` is turned. `IDENTITY` for every
      # cell of a map with no turned tile, and for a cell with no tile.
      def orientation(layer, col, row)
        plane = @plane_of.fetch(layer)
        return Orientation::IDENTITY unless @orientations && plane && in_bounds?(col, row)

        Orientation::ALL[@orientations[col, row, plane]]
      end

      # How many tiles the map's tilesets hold together; ids run 1 to this.
      def tile_count = @tile_table.size - 1

      # Whether `tile` blocks movement: it has a collision shape in Tiled.
      # Tile 0, the empty cell, never does.
      def solid?(tile) = @solid.fetch(tile)

      # The class the designer gave `tile` in Tiled, or `nil`.
      def tile_class(tile) = @tile_classes.fetch(tile)

      # The custom properties of `tile`, `Properties::EMPTY` when it has none.
      def tile_properties(tile) = @tile_properties.fetch(tile)

      # How far `tile` draws from its cell, as a frozen `[x, y]` in pixels with
      # `y` down: the drawing offset the designer gave its tileset in Tiled.
      # Every tile of a tileset with none answers the same `[0, 0]`.
      def tile_offset(tile) = @tile_offsets.fetch(tile)

      # The tiles that animate.
      attr_reader :animated_tiles

      # The tile showing for `tile` after `elapsed` seconds of its animation,
      # which loops. A tile that does not animate answers itself.
      def frame_tile(tile, elapsed)
        frames = @frames[tile] or return tile

        into = elapsed % frames.last.last
        frames.each { |shown, ends| return shown if into < ends }
        frames.last.first
      end

      # Solid if any layer has a solid tile at (col, row). Out of bounds is not
      # solid — the camera/bounds clamp keeps the player inside the map.
      # Hidden layers count: `visible` is how a layer draws, not whether it
      # blocks.
      def solid_tile?(col, row)
        return false unless in_bounds?(col, row)

        @tiles.depth.times { |plane| return true if @solid[@tiles[col, row, plane]] }
        false
      end

      def solid_at?(world_x, world_y) = solid_tile?(col_at(world_x), row_at(world_y))

      # The left edge of column `col`, in world pixels. Any column, inside the
      # map or not: `cell_x(width)` is the map's right edge.
      def cell_x(col) = col * @tile_width

      # The top edge of row `row`, in world pixels.
      def cell_y(row) = row * @tile_height

      # The column holding `world_x`, floored, so a point left of the map is in
      # a negative column rather than column 0. A point on a cell's left edge is
      # in that cell.
      def col_at(world_x) = (world_x / @tile_width).floor

      # The row holding `world_y`, floored like `col_at`.
      def row_at(world_y) = (world_y / @tile_height).floor

      private

      def plane_indexes(cells)
        planes = 0
        cells.map { it && (planes += 1) - 1 }.freeze
      end

      def grid(planes)
        present = planes.compact
        grid = Util::Tensor.new(@width, @height, present.size, initial: 0)
        present.each_with_index do |values, plane|
          @height.times do |row|
            base = row * @width
            @width.times { |col| grid[col, row, plane] = values[base + col] }
          end
        end
        grid
      end
    end
  end
end

require_relative 'tile_map/from_tiled'
