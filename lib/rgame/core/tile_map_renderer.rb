# frozen_string_literal: true

module RGame
  module Core
    # Draws a tile map: the static layers baked once, the animated tiles drawn
    # per frame and culled to the viewport.
    #
    #   tiles = RGame::Core::TileMapRenderer.new(map, tileset_images)
    #
    #   tiles.draw(renderer, camera_x, camera_y, view_w, view_h, elapsed: seconds)
    #   tiles.draw_overlay(renderer, camera_x, camera_y, view_w, view_h, z: 20,
    #                      elapsed: seconds)
    #
    # ## Two bands, with the actors between them
    #
    # Layers split by the map's own `above_layer?` flag. The **below** band —
    # ground, and detail on the actors' level — is drawn under them by `#draw`;
    # the **above** band — tree canopies, roofs — over them by `#draw_overlay`,
    # at a `z` the scene picks. Two calls rather than one because the scene
    # draws its actors in between, and collapsing them would put every canopy
    # behind every character.
    #
    # ## What is baked and what is not
    #
    # Within each band, every tile that is *not* animated is baked into one
    # recording, the first time that band is drawn. Scrolling a baked layer is
    # then one call per texture however many thousand tiles went into it. The
    # handful that *are* animated are drawn individually each frame, culled to
    # the viewport — a map far larger than the screen costs only what is on it.
    #
    # ## It loads nothing and holds no clock
    #
    # The tiles arrive already sliced, so two maps sharing a tileset share one
    # GPU upload — which is only true if something above pulled the image
    # through the asset manager, and is why this class does not load its own.
    #
    # And `elapsed` is an argument rather than a clock read, so animation is
    # something the caller advances. Pausing is "stop accumulating"; a spec
    # picks the frame it wants. See CLAUDE.md, "`draw` renders state; time
    # enters through `update`".
    #
    # ## What it needs of a map
    #
    # It never names the map's class — the tile map lives a layer *above* this
    # one and Core may not reach up (CLAUDE.md, "The rule points both ways").
    # What it calls is the 'a tile map' contract in
    # `spec/support/shared_examples/`: `layer_count`, `above_layer?`, `width`,
    # `height`, `tile_width`, `tile_height`, `gid`, and a `tileset` answering
    # `local_id`, `animations` and `frame_local_id`.
    class TileMapRenderer
      # The map this was built from. A scene reads it for collision and world
      # bounds, which are its business rather than this class's.
      attr_reader :map

      # `tiles` is the tileset image sliced into an Array indexed by local tile
      # id — what `Image#tiles` returns.
      def initialize(map, tiles)
        @map = map
        @tileset = map.tileset
        @tiles = tiles
        @animated_below, @animated_above = collect_animated_tiles
        # Baked on first draw, not here: recording needs a live frame, and there
        # is no renderer at construction.
        @static_below = nil
        @static_above = nil
      end

      def draw(renderer, camera_x, camera_y, viewport_width, viewport_height, elapsed: 0.0)
        @static_below ||= bake(renderer) { |layer| !@map.above_layer?(layer) }
        @static_below.draw(-camera_x, -camera_y, z: BELOW_Z)
        draw_animated(renderer, @animated_below, camera_x, camera_y,
                      viewport_width, viewport_height, BELOW_Z, elapsed)
      end

      def draw_overlay(renderer, camera_x, camera_y, viewport_width, viewport_height,
                       z:, elapsed: 0.0)
        @static_above ||= bake(renderer) { |layer| @map.above_layer?(layer) }
        @static_above.draw(-camera_x, -camera_y, z: z)
        draw_animated(renderer, @animated_above, camera_x, camera_y,
                      viewport_width, viewport_height, z, elapsed)
      end

      # The ground band sits at the bottom; the scene chooses where the overlay
      # goes, because only it knows what its actors are drawn at.
      BELOW_Z = 0

      private

      # [col, row, local_id] for every animated tile, split into the two bands.
      # Walked once at construction: a map is thousands of tiles and a handful
      # of animated ones, and finding them again each frame would be the whole
      # cost this class exists to avoid.
      def collect_animated_tiles
        below = []
        above = []
        each_tile do |layer, col, row, local|
          next unless @tileset.animations.key?(local)

          (@map.above_layer?(layer) ? above : below) << [col, row, local]
        end
        [below, above]
      end

      # Every non-empty tile of every layer, as [layer, col, row, local_id].
      def each_tile
        @map.layer_count.times do |layer|
          @map.height.times do |row|
            @map.width.times do |col|
              gid = @map.gid(layer, col, row)
              next if gid.zero?

              yield(layer, col, row, @tileset.local_id(gid))
            end
          end
        end
      end

      # Bakes the static tiles of the layers the block accepts into one
      # recording, in layer order so a later layer covers an earlier one.
      def bake(renderer)
        renderer.record do
          each_tile do |layer, col, row, local|
            next unless yield(layer)
            next if @tileset.animations.key?(local)

            renderer.image_at(@tiles[local], col * @map.tile_width, row * @map.tile_height,
                              z: BELOW_Z)
          end
        end
      end

      def draw_animated(renderer, tiles, camera_x, camera_y, viewport_width, viewport_height,
                        z, elapsed)
        tile_width = @map.tile_width
        tile_height = @map.tile_height

        # Tiled writes frame durations in milliseconds; everything here counts
        # in seconds. Converted once per draw rather than once per tile.
        ms = (elapsed * 1000.0).to_i

        # fdiv, not `/`. With two Integers — an integer camera position, which
        # is entirely ordinary — `/` floors first and the `.ceil` below becomes
        # a no-op, leaving the last column of tiles undrawn: a one-tile strip of
        # nothing along the right and bottom edges of the screen, and only when
        # the camera happens to be on a whole pixel.
        col_start = camera_x.fdiv(tile_width).floor
        row_start = camera_y.fdiv(tile_height).floor
        col_end = (camera_x + viewport_width).fdiv(tile_width).ceil
        row_end = (camera_y + viewport_height).fdiv(tile_height).ceil

        tiles.each do |col, row, local|
          next if col < col_start || col >= col_end || row < row_start || row >= row_end

          renderer.image_at(@tiles[@tileset.frame_local_id(local, ms)],
                            (col * tile_width) - camera_x, (row * tile_height) - camera_y, z: z)
        end
      end
    end
  end
end
