# frozen_string_literal: true

module Platform
  # Draws an Engine::TileMap with Gosu. Layers split into two bands by the map's
  # `above_layer?` flag: the *below* band (ground + same-level detail) is drawn under
  # the actors via #draw, the *above* band (tree canopies, roofs) over them via
  # #draw_overlay at a caller-chosen z. Within each band, static (non-animated) tiles
  # are baked once into a recorded image for cheap scrolling and animated tiles (water)
  # are drawn per frame, culled to the viewport, on top.
  #
  # Caveat: recorded images draw only in white (no tint) — fine here, we don't tint.
  class TileMapRenderer
    # Load a .tmx plus its referenced .tsx and tileset image into a renderer.
    def self.load(tmx_path)
      tmx_dir = File.dirname(tmx_path)
      map = Engine::TileMap.parse(File.read(tmx_path))

      tsx_path = File.join(tmx_dir, map.tileset_source)
      map.tileset = Engine::Tileset.parse(File.read(tsx_path), firstgid: map.firstgid)

      image_path = File.join(File.dirname(tsx_path), map.tileset.image_source)
      new(map, image_path)
    end

    attr_reader :map

    def initialize(map, image_path)
      @map = map
      @tileset = map.tileset
      @tiles = Gosu::Image.load_tiles(
        image_path, @tileset.tile_width, @tileset.tile_height, retro: true
      )
      @animated_below, @animated_above = collect_animated_tiles
      @static_below = nil # baked lazily on first draw (needs a live GL context)
      @static_above = nil
    end

    # The below-the-actor band (ground + same-level detail), drawn at z 0.
    def draw(camera_x, camera_y, viewport_width, viewport_height)
      @static_below ||= bake_layers { |li| !@map.above_layer?(li) }
      @static_below.draw(-camera_x, -camera_y, 0)
      draw_animated(@animated_below, camera_x, camera_y, viewport_width, viewport_height, 0)
    end

    # The above-the-actor band (canopies, roofs), drawn at `z` (above the actors' z).
    def draw_overlay(camera_x, camera_y, viewport_width, viewport_height, z:)
      @static_above ||= bake_layers { |li| @map.above_layer?(li) }
      @static_above.draw(-camera_x, -camera_y, z)
      draw_animated(@animated_above, camera_x, camera_y, viewport_width, viewport_height, z)
    end

    private

    # [col, row, local_id] of every animated tile, split into below/above bands.
    def collect_animated_tiles
      below = []
      above = []
      @map.layer_count.times do |li|
        bucket = @map.above_layer?(li) ? above : below
        @map.height.times do |row|
          @map.width.times do |col|
            gid = @map.gid(li, col, row)
            next if gid.zero?

            local = @tileset.local_id(gid)
            bucket << [col, row, local] if @tileset.animations.key?(local)
          end
        end
      end
      [below, above]
    end

    # Bake every non-animated tile of the included layers (in order) into one image.
    def bake_layers
      Gosu.record(@map.pixel_width, @map.pixel_height) do
        @map.layer_count.times do |li|
          next unless yield(li)

          @map.height.times do |row|
            @map.width.times do |col|
              gid = @map.gid(li, col, row)
              next if gid.zero?

              local = @tileset.local_id(gid)
              next if @tileset.animations.key?(local)

              @tiles[local].draw(col * @map.tile_width, row * @map.tile_height, 0)
            end
          end
        end
      end
    end

    def draw_animated(tiles, camera_x, camera_y, viewport_width, viewport_height, z)
      tw = @map.tile_width
      th = @map.tile_height
      ms = Gosu.milliseconds
      col_start = (camera_x / tw).floor
      row_start = (camera_y / th).floor
      col_end   = ((camera_x + viewport_width) / tw).ceil
      row_end   = ((camera_y + viewport_height) / th).ceil

      tiles.each do |col, row, local|
        next if col < col_start || col >= col_end || row < row_start || row >= row_end

        frame = @tileset.frame_local_id(local, ms)
        @tiles[frame].draw(col * tw - camera_x, row * th - camera_y, z)
      end
    end
  end
end
