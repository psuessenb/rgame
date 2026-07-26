# frozen_string_literal: true

# RGame::Core::App is implemented in C — see ext/rgame_core/. It wraps the
# engine's public API (ext/rgame_core/include/rgame/core.h): an SDL window plus
# OpenGL context, and a fixed-timestep main loop that drives caller-supplied
# update/draw callbacks.
#
#   app = RGame::Core::App.new(width, height, title)
#   app.run(update_proc, draw_proc, needs_redraw_proc = nil)
#   app.ticks_ms  # => Integer, monotonic ms since startup
#   app.fps       # => Float, most recent FPS reading
#
# Loading this .so pulls SDL2 and OpenGL into the process — see
# lib/rgame/core.rb for why that's kept off the default `require "rgame"`.
# It loads from lib/rgame/core_ext.so, which the build (`make ext-core`)
# copies out of ext/rgame_core/.
require 'rgame/core_ext'
