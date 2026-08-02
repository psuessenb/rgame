# frozen_string_literal: true

# RGame::Util::Color is implemented in C — see ext/rgame_util/color_ext.c for
# the Ruby binding and ext/rgame_util/color.c for the packing arithmetic.
#
#   Color = RGame::Util::Color
#   Color.new(255, 128, 0)        # r, g, b, a defaults to 255
#   Color.rgba(255, 128, 0, 200)  # the same thing, named
#   Color.from_packed(0xFF8000FF) # 0xRRGGBBAA
#   Color::WHITE                  # also BLACK and TRANSPARENT
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
