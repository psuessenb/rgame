# frozen_string_literal: true

require 'rgame/core_ext'

module RGame
  module Core
    # A picture on the GPU, and the sprites cut out of it.
    #
    #   img = RGame::Core::Image.new(app, 'hero.png')
    #   img.width                       # => 64
    #   frame = img.subimage(0, 0, 16, 16)
    #   walk  = RGame::Core::Image.load_tiles(app, 'hero.png', 16, 16)
    #
    # Everything below the constructor is a *view*: `subimage`, `tile` and
    # `load_tiles` share the one texture the file was decoded into, so slicing a
    # sheet into a hundred frames costs a hundred small objects and no extra
    # video memory. The texture is released when the last view of it is
    # collected, in whatever order that happens.
    #
    # Images are always sampled nearest-neighbour: this engine draws pixel art,
    # and there is no setting to blur it.
    #
    # The class itself is defined in C (ext/rgame_core/ruby/image_ext.c); what is
    # added here is the sheet-slicing convenience, which is a loop and belongs
    # in Ruby.
    class Image
      # Every whole `tile_width` x `tile_height` tile of an image file, in
      # reading order: left to right, then top to bottom. A partial tile along
      # the right or bottom edge is padding and is skipped.
      #
      # The file is decoded and uploaded exactly once however many tiles come
      # out of it — the returned images are views of that single texture.
      def self.load_tiles(app, path, tile_width, tile_height)
        new(app, path).tiles(tile_width, tile_height)
      end

      # This image sliced into whole tiles, as an Array. `load_tiles` is the
      # same thing starting from a path.
      def tiles(tile_width, tile_height)
        Array.new(tile_count(tile_width, tile_height)) do |index|
          tile(tile_width, tile_height, index)
        end
      end

      # Yields each tile in turn, without building the Array.
      def each_tile(tile_width, tile_height)
        return enum_for(:each_tile, tile_width, tile_height) unless block_given?

        tile_count(tile_width, tile_height).times do |index|
          yield tile(tile_width, tile_height, index)
        end
      end
    end
  end
end
