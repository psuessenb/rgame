# frozen_string_literal: true

require 'rgame/core_ext'

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
    #   RGame::Core::Font.new(app, 18, path: 'assets/pixel.ttf')
    #
    # Scripts outside the shipped font's coverage — CJK, Arabic, Hebrew — need
    # their own file. No font of this size covers them.
    class Font
      # Shipped with the gem, alongside its SIL OFL 1.1 licence. Resolved from
      # this file's location so it works the same from a checkout and from an
      # installed gem.
      DEFAULT_PATH = File.expand_path('../fonts/LiberationSans-Regular.ttf', __dir__)

      # `path:` is a keyword for callers but positional for the C initialize,
      # which has no business knowing where a gem installs its data.
      def self.new(app, pixel_height, path: DEFAULT_PATH)
        super(app, pixel_height, path)
      end
    end
  end
end
