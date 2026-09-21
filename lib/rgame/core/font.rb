# frozen_string_literal: true

require 'rgame/core_ext'
require_relative '../util/typeface'

module RGame
  module Core
    # A typeface at one pixel size, with a glyph atlas behind it.
    #
    #   font = RGame::Core::Font.new(app, 18)
    #   font.height                    # => 18
    #   font.text_width('Score: 1200') # => 78.4
    #
    #   renderer.text('Score: 1200', 10, 10, font: font)
    #
    # A font is always built from a `RGame::Util::Typeface`, and `typeface`
    # answers it. The size forms build one first:
    #
    #   RGame::Core::Font.new(app, typeface)                  # draws what `typeface` measures
    #   RGame::Core::Font.new(app, 18)                        # Typeface.default(18)
    #   RGame::Core::Font.new(app, 18, path: 'assets/x.ttf')  # Typeface.new('assets/x.ttf', 18)
    #
    # So a width a game measured with the typeface, in `update` or in a headless
    # spec, is the width this font draws.
    #
    # Two sizes are two fonts. Glyphs are rasterised the first time they are
    # drawn and kept afterwards, so what a font costs is bounded by the
    # characters a game actually uses — a score that changes every frame is free
    # after the first ten digits.
    #
    # Measuring works anywhere; drawing, like everything else, only inside
    # `draw`. That split is deliberate: laying out a menu happens while
    # updating.
    #
    # ## The default font
    #
    # Passing no path uses the one the engine ships — Liberation Sans, which
    # covers Western European languages including `ß`, `ẞ`, accents, `«»` and
    # `€`. There is no font-*name* lookup and no system font database: a font is
    # a file. That is what makes text render identically on every machine, which
    # a system lookup cannot promise.
    #
    # Scripts outside the shipped font's coverage — CJK, Arabic, Hebrew — need
    # their own file. No font of this size covers them.
    class Font
      DEFAULT_PATH = RGame::Util::Typeface::DEFAULT_PATH

      # `face` is a `RGame::Util::Typeface`, or a pixel size. A size opens the
      # file at `path:`, or the shipped font without one. A file that cannot be
      # read or is not a font raises `LoadError` naming the path, and so does a
      # size below 1. `path:` beside a typeface raises `ArgumentError`, because
      # the typeface already names its file.
      def self.new(app, face, path: nil)
        return super(app, typeface_for(face, path)) unless face.is_a?(RGame::Util::Typeface)
        raise ArgumentError, 'a typeface already names its file, so path: goes to Typeface.new' if path

        super(app, face)
      end

      def self.typeface_for(pixel_height, path)
        if pixel_height.is_a?(Numeric) && !pixel_height.positive?
          raise LoadError, "a font size must be positive, got #{pixel_height}"
        end

        path ? RGame::Util::Typeface.new(path, pixel_height) : RGame::Util::Typeface.default(pixel_height)
      rescue RGame::Util::Typeface::LoadError => e
        raise LoadError, e.message
      end
      private_class_method :typeface_for
    end
  end
end
