# frozen_string_literal: true

# RGame::Util::Color is implemented in C — see ext/rgame_util/color_ext.c for
# the Ruby binding and ext/rgame_util/color.c for the packing arithmetic.
#
#   Color = RGame::Util::Color
#   Color.new(255, 128, 0)        # r, g, b, a defaults to 255
#   Color.rgba(255, 128, 0, 200)  # the same thing, named
#   Color.from_packed(0xFF8000FF) # 0xRRGGBBAA
#   Color::WHITE                  # and the rest of the named palette below
#
#   c.r; c.g; c.b; c.a            # => Integer, 0..255
#   c.packed                      # => Integer, 0xRRGGBBAA
#
# Instances are frozen and compare by value, so a Color works as a Hash key and
# can be shared without anyone tinting it out from under its other holders.
#
# Every draw call accepts a colour as nil (white), [r, g, b], [r, g, b, a] or a
# Color; `Color.coerce` is the single place that conversion happens.
#
# A colour is a *value* — no window, no GPU handle — so it lives in Util rather
# than Core. That is what lets the engine layer hold one as an attribute; see
# CLAUDE.md, "Value objects go in Util; only handle-owners go in Core".
#
# It loads from lib/rgame/util_ext.so, which `make ext-util` copies out of
# ext/rgame_util/.
require 'rgame/util_ext'

module RGame
  module Util
    class Color
      # The named palette.
      #
      # WHITE, BLACK and TRANSPARENT are defined in C instead, next to the
      # RGAME_COLOR_* macros the drawing code uses for the same three values —
      # a colour the C layer names itself must not have a second definition
      # here to drift from. The rest have no C consumer, so they are plain Ruby
      # and cost no rebuild to change.
      #
      # Values follow the CSS/X11 names, so `Color::ORANGE` is the orange
      # somebody who has met a colour picker expects.
      RED = new(255, 0, 0)
      GREEN = new(0, 255, 0)
      BLUE = new(0, 0, 255)
      YELLOW = new(255, 255, 0)
      CYAN = new(0, 255, 255)
      MAGENTA = new(255, 0, 255)
      ORANGE = new(255, 165, 0)
      PURPLE = new(128, 0, 128)
      BROWN = new(139, 69, 19)
      PINK = new(255, 192, 203)
      GRAY = new(128, 128, 128)
      LIGHT_GRAY = new(192, 192, 192)
      DARK_GRAY = new(64, 64, 64)
    end
  end
end
