# frozen_string_literal: true

module RGame
  module Core
    # Draws a tile map: the static layers baked once, the animated tiles drawn
    # per frame, both culled to a rectangle of the world.
    #
    #   tiles = RGame::Core::TileMapRenderer.new(map, tileset_images)
    #
    #   map.layer_count.times do |layer|
    #     tiles.draw_layer(renderer, layer, cull_x, cull_y, cull_w, cull_h,
    #                      elapsed: seconds)
    #   end
    #
    # ## It draws in world coordinates
    #
    # A tile at column 3 is drawn at `3 * tile_width`, and getting it onto the
    # screen is the caller's transform — the same deal every other drawable
    # gets. The rectangle passed in is therefore a **cull rect** and nothing
    # else: which part of the world is worth drawing.
    #
    # It used to be both, offsetting the output by `-camera` as well as culling
    # to it, which worked exactly as long as there was one camera. Under
    # split-screen the same map is drawn through several, so a call that bakes
    # placement into its output can only be right for one of them. Culling is
    # genuinely per-camera; placement is the transform stack's job.
    #
    # ## One call per layer, because the actors go between them
    #
    # A layer is drawn on its own, and the order they are drawn in is the
    # caller's. That is what lets a scene put its actors between two of them —
    # tree trunks below, canopies above — which is the whole reason this does
    # not simply draw the map in one go.
    #
    # It is also why nothing here consults the map's `above_layer?` flag any
    # more: which layers cover the actors is a question about where the actors
    # are in the scene, and Tiled already answers "in what order do the layers
    # go" by listing them. `RGame::Engine::TileMapLayer` mounts one node per
    # layer and the tree does the rest.
    #
    # ## What is baked and what is not
    #
    # Within each layer, every tile that is *not* animated is baked into one
    # recording, the first time that layer is drawn. Scrolling a baked layer is
    # then one call per texture however many thousand tiles went into it. The
    # handful that *are* animated are drawn individually each frame, culled to
    # the viewport — a map far larger than the screen costs only what is on it.
    #
    # Splitting per layer rather than into two bands bakes the same tiles into
    # more recordings, not more vertices: the partition changed, the contents
    # did not.
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
    # `spec/support/shared_examples/`: `layer_count`, `width`, `height`,
    # `tile_width`, `tile_height`, `gid`, and a `tileset` answering `local_id`,
    # `animations` and `frame_local_id`.
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
        @animated = collect_animated_tiles
        # Baked on first draw, not here: recording needs a live frame, and there
        # is no renderer at construction.
        @static = Array.new(map.layer_count)
      end

      def layer_count = @map.layer_count

      # One layer, culled to `(cull_x, cull_y, cull_width, cull_height)` in world
      # coordinates and drawn in them.
      #
      # The recording is replayed at its own origin, so it lands wherever the
      # caller's transform puts it. That also makes it **view-independent**: one
      # bake serves every viewport, which is what keeps split-screen affordable
      # and is why the bake is not keyed on a camera. Baking happens on the
      # first draw, and it is safe to do that inside a transform or a clip —
      # recording runs on its own canvas, begun at identity, and captures
      # neither.
      #
      # No `z:`. A layer is drawn by a node of its own, so where it sits is the
      # scene tree's answer; everything this issues belongs to that one node and
      # goes in its slot.
      def draw_layer(renderer, index, cull_x, cull_y, cull_width, cull_height, elapsed: 0.0)
        unless index.is_a?(Integer) && index >= 0 && index < @static.size
          raise ArgumentError, "no layer #{index.inspect} in this map (it has #{@static.size})"
        end

        @static[index] ||= bake(renderer, index)
        @static[index].draw
        draw_animated(renderer, @animated[index], cull_x, cull_y,
                      cull_width, cull_height, elapsed)
      end

      private

      # [col, row, local_id] for every animated tile, per layer. Walked once at
      # construction: a map is thousands of tiles and a handful of animated
      # ones, and finding them again each frame would be the whole cost this
      # class exists to avoid.
      def collect_animated_tiles
        found = Array.new(@map.layer_count) { [] }
        each_tile do |layer, col, row, local|
          next unless @tileset.animations.key?(local)

          found[layer] << [col, row, local]
        end
        found
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

      # Bakes one layer's static tiles into a recording. An empty layer bakes an
      # empty recording, which replays as nothing — so a map with a spacer layer
      # in it needs no special case here or at the call site.
      def bake(renderer, index)
        renderer.record do
          each_tile do |layer, col, row, local|
            next unless layer == index
            next if @tileset.animations.key?(local)

            renderer.image_at(@tiles[local], col * @map.tile_width, row * @map.tile_height)
          end
        end
      end

      def draw_animated(renderer, tiles, cull_x, cull_y, cull_width, cull_height, elapsed)
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
        col_start = cull_x.fdiv(tile_width).floor
        row_start = cull_y.fdiv(tile_height).floor
        col_end = (cull_x + cull_width).fdiv(tile_width).ceil
        row_end = (cull_y + cull_height).fdiv(tile_height).ceil

        tiles.each do |col, row, local|
          next if col < col_start || col >= col_end || row < row_start || row >= row_end

          # World coordinates, like the baked band above it: the caller's
          # transform is what puts either on screen.
          renderer.image_at(@tiles[@tileset.frame_local_id(local, ms)],
                            col * tile_width, row * tile_height)
        end
      end
    end
  end
end
