# frozen_string_literal: true

module RGame
  module Core
    # Draws a tile map: the static layers baked once, the animated tiles drawn
    # per frame, both culled to a rectangle of the world.
    #
    #   tiles = RGame::Core::TileMapRenderer.new(map, tile_images, layer_images: images)
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
    # It is also why nothing here asks a layer whether it is `above?`: which
    # layers cover the actors is a question about where the actors are in the
    # scene, and Tiled already answers "in what order do the layers go" by
    # listing them. `RGame::Engine::TileMapLayer` mounts one node per
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
    # ## Image layers are drawn every frame
    #
    # An image layer draws its one image at its offset, and again every image's
    # width or height along each axis it repeats on, as far as the cull rect
    # reaches in both directions. Only the copies that meet the cull rect are
    # drawn, and nothing is baked: a repeated layer has no edge to bake up to.
    #
    # ## What Tiled shows
    #
    # A hidden layer draws nothing and is never baked. A translucent one
    # replays tinted by its opacity, and its animated tiles draw with the same
    # tint. A turned tile is baked inside a rotation about its own centre,
    # mirrored within its rectangle first when it is flipped. Every tile stands
    # on its cell's bottom-left corner, as Tiled draws one taller than the grid,
    # moved by its tileset's drawing offset, which does not turn with it.
    #
    # ## It loads nothing and holds no clock
    #
    # The tiles arrive already sliced, so two maps sharing a tileset share one
    # GPU upload — which is only true if something above pulled the image
    # through the asset manager, and is why this class does not load its own.
    #
    # And `elapsed` is an argument rather than a clock read, so animation is
    # something the caller advances. Pausing is "stop accumulating"; a spec
    # picks the frame it wants.
    # See "`draw` renders state; time enters through `update`".
    #
    # ## What it needs of a map
    #
    # It never names the map's class — the tile map lives a layer *above* this
    # one and Core may not reach up (see "The rule points both ways").
    # What it calls is the 'a tile map' contract in
    # `spec/support/shared_examples/`: `layer_count`, `layer(i).visible?`,
    # `opacity` and `kind`, an image layer's `offset_x`, `offset_y`, `repeat_x?`
    # and `repeat_y?`, `width`, `height`, `tile_width`, `tile_height`, `tile`,
    # `orientation`, `tile_offset`, `animated_tiles` and `frame_tile`.
    class TileMapRenderer
      # The map this was built from. A scene reads it for collision and world
      # bounds, which are its business rather than this class's.
      attr_reader :map

      # `tiles` is an Array of tile images indexed by the map's tile ids, with
      # nothing at 0, the empty cell. `layer_images` is indexed by layer: the
      # image of each image layer, and `nil` for every other layer and for an
      # image layer that shows none.
      def initialize(map, tiles, layer_images: [])
        @map = map
        @image_layers = Array.new(map.layer_count) do |index|
          layer = map.layer(index)
          layer if layer.kind == :image
        end
        @layer_images = layer_images
        @animates = map.animated_tiles.to_set
        @tiles = tiles
        @animated = collect_animated_tiles
        @static = Array.new(map.layer_count)
        @shown = Array.new(map.layer_count) { map.layer(it).visible? }
        @tints = Array.new(map.layer_count) { tint(map.layer(it).opacity) }
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
      #
      # @api private
      def draw_layer(renderer, index, cull_x, cull_y, cull_width, cull_height, elapsed: 0.0)
        unless index.is_a?(Integer) && index >= 0 && index < @static.size
          raise ArgumentError, "no layer #{index.inspect} in this map (it has #{@static.size})"
        end

        return unless @shown[index]

        image_layer = @image_layers[index]
        return draw_image_layer(renderer, image_layer, index, cull_x, cull_y, cull_width, cull_height) if image_layer

        @static[index] ||= bake(renderer, index)
        @static[index].draw(color: @tints[index])
        draw_animated(renderer, @animated[index], @tints[index], cull_x, cull_y,
                      cull_width, cull_height, elapsed)
      end

      private

      def draw_image_layer(renderer, layer, index, cull_x, cull_y, cull_width, cull_height)
        image = @layer_images[index] or return

        tint = @tints[index]
        x = first_copy(layer.offset_x, image.width, layer.repeat_x?, cull_x)
        while x < cull_x + cull_width
          y = first_copy(layer.offset_y, image.height, layer.repeat_y?, cull_y)
          while y < cull_y + cull_height
            renderer.image_at(image, x, y, color: tint) if x + image.width > cull_x && y + image.height > cull_y
            break unless layer.repeat_y?

            y += image.height
          end
          break unless layer.repeat_x?

          x += image.width
        end
      end

      def first_copy(offset, size, repeats, cull)
        return offset unless repeats

        offset + ((cull - offset).fdiv(size).floor * size)
      end

      def collect_animated_tiles
        found = Array.new(@map.layer_count) { [] }
        each_tile do |layer, col, row, tile|
          next unless @animates.include?(tile)

          found[layer] << [col, row, tile, @map.orientation(layer, col, row)]
        end
        found
      end

      def each_tile
        @map.layer_count.times do |layer|
          @map.height.times do |row|
            @map.width.times do |col|
              tile = @map.tile(layer, col, row)
              next if tile.zero?

              yield(layer, col, row, tile)
            end
          end
        end
      end

      def bake(renderer, index)
        renderer.record do
          each_tile do |layer, col, row, tile|
            next unless layer == index
            next if @animates.include?(tile)

            draw_tile(renderer, tile, col, row, @map.orientation(layer, col, row), nil)
          end
        end
      end

      def draw_animated(renderer, tiles, tint, cull_x, cull_y, cull_width, cull_height, elapsed)
        tile_width = @map.tile_width
        tile_height = @map.tile_height

        col_start = cull_x.fdiv(tile_width).floor
        row_start = cull_y.fdiv(tile_height).floor
        col_end = (cull_x + cull_width).fdiv(tile_width).ceil
        row_end = (cull_y + cull_height).fdiv(tile_height).ceil

        tiles.each do |col, row, tile, orientation|
          next if col < col_start || col >= col_end || row < row_start || row >= row_end

          draw_tile(renderer, @map.frame_tile(tile, elapsed), col, row, orientation, tint)
        end
      end

      def draw_tile(renderer, tile, col, row, orientation, tint)
        image = @tiles[tile]
        offset_x, offset_y = @map.tile_offset(tile)
        x = (col * @map.tile_width) + offset_x
        y = ((row + 1) * @map.tile_height) - image.height + offset_y
        return renderer.image_at(image, x, y, color: tint) if orientation.identity?

        turns = orientation.quarter_turns
        shift = turns.odd? ? (image.height - image.width) / 2.0 : 0
        angle = orientation.mirrored? ? -90 * turns : 90 * turns
        renderer.rotated(angle, x + shift + (image.width / 2.0), y + shift + (image.height / 2.0)) do
          renderer.image_at(image, x + shift, y + shift, scale_x: orientation.mirrored? ? -1 : 1, color: tint)
        end
      end

      def tint(opacity) = (RGame::Util::Color.new(255, 255, 255, (opacity * 255).round) if opacity < 1)
    end
  end
end
