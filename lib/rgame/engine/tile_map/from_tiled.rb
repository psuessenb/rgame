# frozen_string_literal: true

require_relative '../tiled/map'

module RGame
  module Engine
    # The transform from the parse to the runtime view, and the one file
    # outside `lib/rgame/engine/tiled/` that names `Tiled::`. Everything the
    # file format says in its own terms is turned into the game's here, once:
    #
    # - a gid, counted across tilesets from each one's `firstgid`, becomes a
    #   dense tile id, and a gid no tileset covers raises;
    # - Tiled's three flip bits become an `Orientation`;
    # - the group tree becomes the flat layer list;
    # - frame durations in milliseconds become the second each frame ends at,
    #   summed in whole milliseconds so that no rounding moves a boundary;
    # - a tile object's bottom-left corner becomes its top-left, and every
    #   position moves by the infinite-map origin so that cell `(0, 0)` is the
    #   map's top-left;
    # - a tileset's drawing offset becomes each of its tiles' `tile_offset`.
    class TileMap
      # Builds a map from a `Tiled::Map`. The only way one is built.
      def self.from_tiled(tiled_map) = FromTiled.new(tiled_map).map

      # One run of the transform over one parsed map.
      class FromTiled
        FLIPS = [0, 4, 6, 2, 5, 1, 3, 7].freeze

        def initialize(tiled)
          @tiled = tiled
          @shift_x = tiled.origin_col * tiled.tile_width
          @shift_y = tiled.origin_row * tiled.tile_height
          @gids = []
          @layers = []
          @cells = []
          @orientations = []
          @objects = []
        end

        def map
          table = tile_table
          flatten(@tiled.layers, [])
          TileMap.new(width: @tiled.width, height: @tiled.height,
                      tile_width: @tiled.tile_width, tile_height: @tiled.tile_height,
                      layers: @layers, cells: @cells,
                      orientations: (@orientations if @orientations.any? { it&.any?(&:nonzero?) }),
                      objects: @objects, properties: @tiled.properties,
                      source: Source.new(path: @tiled.source_path, parser_version: Tiled::PARSER_VERSION),
                      **table)
        end

        private

        def tile_table
          table = { tile_table: [nil], solid: [false], tile_classes: [nil],
                    tile_properties: [Properties::EMPTY], frames: [nil], tile_offsets: [NO_OFFSET] }
          @tiled.tilesets.each_with_index do |ref, index|
            offset = offset_of(ref.tileset)
            local_ids(ref.tileset).each { add_tile(table, ref, index, it, offset) }
          end
          @tiled.tilesets.each { |ref| animate(table[:frames], ref) }
          table
        end

        def local_ids(tileset) = tileset.collection? ? tileset.tiles.keys.sort : (0...tileset.tile_count)

        def offset_of(tileset)
          return NO_OFFSET if tileset.offset_x.zero? && tileset.offset_y.zero?

          [tileset.offset_x, tileset.offset_y].freeze
        end

        def add_tile(table, ref, index, local_id, offset)
          tile = ref.tileset.tile(local_id)
          @gids[ref.firstgid + local_id] = table[:tile_table].size
          table[:tile_table] << TileSource.new(tileset: index, local_id: local_id)
          table[:solid] << (tile ? !tile.collision_shapes.empty? : false)
          table[:tile_classes] << (tile.class_name unless tile.nil? || tile.class_name.empty?)
          table[:tile_properties] << (tile ? tile.properties : Properties::EMPTY)
          table[:frames] << nil
          table[:tile_offsets] << offset
        end

        def animate(frames, ref)
          ref.tileset.tiles.each_value do |tile|
            next unless tile.animated? && tile.frames.sum(&:duration_ms).positive?

            where = "tileset '#{ref.tileset.name}', tile #{tile.id}"
            elapsed_ms = 0
            frames[tile_of(ref.firstgid + tile.id) { where }] = tile.frames.map do |frame|
              elapsed_ms += frame.duration_ms
              [tile_of(ref.firstgid + frame.tile_id) { "the animation of #{where}" }, elapsed_ms / 1000.0]
            end
          end
        end

        def tile_of(raw_gid)
          gid = raw_gid & Tiled::GID_MASK
          return 0 if gid.zero?

          @gids[gid] or raise Tiled::FormatError,
                              "#{yield} names gid #{gid}, which no tileset in #{@tiled.source_path || 'the map'} covers"
        end

        def orientation_of(raw_gid)
          FLIPS[((raw_gid >> 31) & 1) | (((raw_gid >> 30) & 1) << 1) | (((raw_gid >> 29) & 1) << 2)]
        end

        def flatten(layers, groups)
          layers.each do |layer|
            next flatten(layer.layers, groups + [layer.name]) if layer.is_a?(Tiled::GroupLayer)

            common = { index: @layers.size, path: groups + [layer.name], class_name: layer.class_name,
                       visible: layer.effective_visible?, opacity: layer.effective_opacity,
                       above: above?(layer), properties: layer.properties }
            @layers << runtime_layer(layer, common)
            tiles = layer.is_a?(Tiled::TileLayer)
            @cells << (layer.gids.each_with_index.map { |raw, cell| tile_of(raw) { cell_name(layer, cell) } } if tiles)
            @orientations << (layer.gids.map { orientation_of(it) } if tiles)
            layer.objects.each { @objects << object(it, common[:index]) } if layer.is_a?(Tiled::ObjectLayer)
          end
        end

        def runtime_layer(layer, common)
          case layer
          when Tiled::TileLayer then Layer.new(kind: :tile, **common)
          when Tiled::ObjectLayer then Layer.new(kind: :object, **common)
          when Tiled::ImageLayer
            ImageLayer.new(image: layer.image&.source,
                           offset_x: layer.offset_x - @shift_x, offset_y: layer.offset_y - @shift_y,
                           repeat_x: layer.repeat_x?, repeat_y: layer.repeat_y?, **common)
          end
        end

        def above?(layer)
          above = layer.properties.fetch('above', false)
          return above if [true, false].include?(above)

          raise Tiled::FormatError, "layer '#{layer.name}' in #{@tiled.source_path || 'the map'} has an " \
                                    "'above' property of #{above.inspect}; make it a bool property in Tiled"
        end

        def cell_name(layer, cell)
          row, col = cell.divmod(layer.width)
          "layer '#{layer.name}' at column #{col}, row #{row}"
        end

        def object(object, layer)
          tile = object.gid && tile_of(object.gid) { "object #{object.id}" }
          x = object.x - @shift_x
          y = object.y - @shift_y
          points = object.points.map { |px, py| [x + px, y + py].freeze }.freeze
          x, y = top_left(x, y, object) if tile&.nonzero?
          MapObject.new(id: object.id, name: object.name, class_name: object.class_name, layer: layer,
                        x: x, y: y, width: object.width, height: object.height, rotation: object.rotation,
                        tile: tile&.nonzero?, orientation: Orientation::ALL[orientation_of(object.gid || 0)],
                        visible: object.visible?, shape: object.shape, points: points,
                        properties: object.properties)
        end

        def top_left(x, y, object)
          radians = object.rotation * Math::PI / 180.0
          [x + (object.height * Math.sin(radians)), y - (object.height * Math.cos(radians))]
        end
      end
      private_constant :FromTiled
    end
  end
end
