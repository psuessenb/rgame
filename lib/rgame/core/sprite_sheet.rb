# frozen_string_literal: true

require 'json'

require_relative 'image'

module RGame
  module Core
    # A texture atlas — one image plus a JSON descriptor — sliced into frames and
    # drawn one at a time.
    #
    #   sheet = RGame::Core::SpriteSheet.load(app, 'media/hero.json')
    #   sheet.draw(renderer, row, col, x, y, flip_x: facing_left, z: 10)
    #
    # ## The descriptor
    #
    #   {
    #     "image": "hero.png",
    #     "frame_width": 16, "frame_height": 24,
    #     "cell_width": 32, "cell_height": 32,
    #     "origin_x": 8, "origin_y": 4,
    #     "animations": { "walk_left": { "row": 1, "frames": 4, "fps": 8 } }
    #   }
    #
    # `image` is resolved next to the descriptor. The rest describes the grid.
    #
    # **A frame can be smaller than its cell.** Cells are laid out on a fixed
    # `cell_width` x `cell_height` grid, but what is *drawn* is a
    # `frame_width` x `frame_height` rectangle offset by `origin_x`/`origin_y`
    # inside the cell. That is what lets a sheet whose cells are sized for the
    # widest pose — an attack, a swing — still expose a tight, centred box for
    # walking, so a character does not appear to change size between animations.
    # Leave the cell and origin keys out and frame == cell, which is what a
    # simple sheet wants.
    #
    # `animations` is handed back untouched by `#animations`. This class knows
    # nothing about time; the scene layer builds its own animation table from
    # that hash, which is why the raw form is what gets exposed.
    #
    # ## Slicing costs nothing
    #
    # Every frame is cut once, at construction, as a view onto the one upload —
    # so a sheet of two hundred frames is two hundred small objects and a single
    # texture, and `#draw` is an array index plus one call.
    class SpriteSheet
      attr_reader :frame_width, :frame_height, :animations

      # Loads a descriptor and the image beside it.
      #
      # The `AssetManager` does not use this — it calls `.new` with an image it
      # has already cached, so a sheet's PNG is shared with a standalone load of
      # the same file. This is the standalone path, for a game with one sheet
      # and no asset manager.
      def self.load(app, atlas_path)
        atlas = JSON.parse(File.read(atlas_path), symbolize_names: true)
        directory = File.dirname(File.expand_path(atlas_path))
        new(Image.new(app, File.join(directory, atlas[:image])), atlas)
      end

      # `atlas` is the parsed descriptor; `image` an already-loaded sheet image.
      def initialize(image, atlas)
        @frame_width = atlas.fetch(:frame_width) { missing(:frame_width) }
        @frame_height = atlas.fetch(:frame_height) { missing(:frame_height) }
        @animations = atlas[:animations] || {}

        @frames = slice(image, atlas)
      end

      # Draws one frame with its top-left at (x, y).
      #
      # `flip_x` mirrors the frame within that same rectangle, so a character
      # occupies the same pixels whichever way it faces — see
      # RGame::Core::Renderer#image_at.
      def draw(renderer, row, col, x, y, flip_x: false, z: 0)
        renderer.image_at(@frames[row][col], x, y, scale_x: flip_x ? -1 : 1, z: z)
      end

      # How many frames the sheet was cut into, as [rows, columns].
      def grid = [@frames.length, @frames.empty? ? 0 : @frames[0].length]

      private

      def slice(image, atlas)
        cell_width = atlas[:cell_width] || @frame_width
        cell_height = atlas[:cell_height] || @frame_height
        origin_x = atlas[:origin_x] || 0
        origin_y = atlas[:origin_y] || 0

        columns = image.width / cell_width
        rows = image.height / cell_height

        Array.new(rows) do |row|
          Array.new(columns) do |col|
            image.subimage((col * cell_width) + origin_x, (row * cell_height) + origin_y,
                           @frame_width, @frame_height)
          end
        end
      end

      # A typo'd or missing key would otherwise surface as a NoMethodError on nil
      # from inside the slicing arithmetic, which says nothing about the file
      # that is actually wrong.
      def missing(key)
        raise ArgumentError, "sprite sheet descriptor has no #{key}"
      end
    end
  end
end
