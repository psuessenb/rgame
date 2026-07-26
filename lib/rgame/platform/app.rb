# frozen_string_literal: true

# RGame::Platform::App is implemented in C — see ext/rgame_platform/. It wraps
# the engine's public API (ext/rgame_platform/include/rgame/core.h): an SDL
# window plus OpenGL context, and a fixed-timestep main loop that drives
# caller-supplied update/draw callbacks.
#
#   app = RGame::Platform::App.new(width, height, title)
#   app.run(update_proc, draw_proc, needs_redraw_proc = nil)
#   app.ticks_ms  # => Integer, monotonic ms since startup
#   app.fps       # => Float, most recent FPS reading
#
# Loading this .so pulls SDL2 and OpenGL into the process — see
# lib/rgame/platform.rb for why that's kept off the default `require "rgame"`.
# It loads from lib/rgame/platform_ext.so, which the build (`make ext-platform`)
# copies out of ext/rgame_platform/.
require 'rgame/platform_ext'
