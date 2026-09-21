# frozen_string_literal: true

require 'rgame/util_ext'

module RGame
  module Util
    # A typeface at one pixel size: what a string measures, with no window, no GPU and no
    # graphics library in the process. A value with nothing to release, which is why it
    # lives in Util and why the engine layer may hold one.
    #
    #   face = RGame::Util::Typeface.default(18)
    #   face.height                     # => 18
    #   face.text_width('Score: 1200')  # => 86.88...
    #   face.text_lines(paragraph, 180) # => ['The gate is shut for the', 'night, traveller.']
    #
    #   RGame::Util::Typeface.new('assets/pixel.ttf', 16)
    #
    # A width measured here is the width `RGame::Core::Font` draws for the same file and
    # size, to the last fraction of a pixel. Both extensions compile the same C over the
    # same bytes, and a spec compares the two string for string. So layout can happen in
    # `update`, or in a headless spec, and still be what reaches the screen.
    #
    # `text_lines` breaks at spaces only, with the same walk, so every line it
    # returns measures what `text_width` says it does.
    #
    # Kerning is applied, and malformed UTF-8 costs one replacement glyph rather than the
    # rest of the string.
    class Typeface
      DEFAULT_PATH = File.expand_path('../fonts/LiberationSans-Regular.ttf', __dir__)

      DEFAULT_SIZE = 18

      # Opens the TrueType file at `path`. Raises `LoadError`, naming the path, for a file
      # that cannot be read or is not a font, and `ArgumentError` for a size below 1.
      def self.new(path, pixel_height)
        bytes = begin
          File.binread(path)
        rescue SystemCallError => e
          raise self::LoadError, "could not read #{path}: #{e.message}"
        end
        super(bytes, pixel_height, path)
      end

      # The shipped font at `pixel_height`, opened once per size and shared after that.
      def self.default(pixel_height = DEFAULT_SIZE)
        @default ||= {}
        @default[pixel_height] ||= new(DEFAULT_PATH, pixel_height)
      end

      # @api private
      # The font file this typeface was opened from, as a new binary String.
      # `RGame::Core::Font` opens its own face from it, so it draws what this
      # measures.
      def bytes = font_data
    end
  end
end
