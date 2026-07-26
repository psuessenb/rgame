# frozen_string_literal: true

# RGame::Core::App is implemented in C — see ext/rgame_core/. It wraps the
# engine's public API (ext/rgame_core/include/rgame/core.h): an SDL window plus
# OpenGL context, and a fixed-timestep main loop that drives callbacks.
#
# App is meant to be subclassed. The engine calls back into methods on the
# object itself, so a game overrides the hooks it needs and inherits no-ops for
# the rest:
#
#   class MyGame < RGame::Core::App
#     def initialize = super(width: 800, height: 600, caption: 'my game')
#
#     def frame_begin; end     # once per frame, before that frame's ticks
#     def update(dt); end      # one fixed simulation tick; dt is always the
#                              # fixed step, never wall-clock frame time
#     def needs_redraw?; end   # false skips the draw (simulation still runs)
#     def draw; end            # render one frame
#     def button_down(id); end # discrete key press (no repeats)
#     def button_up(id); end
#     def resize(w, h); end
#   end
#
#   MyGame.new.run
#
# Also inherited: #close (stops the loop; safe from inside a callback), #width,
# #height, #caption, #caption=, #ticks_ms (monotonic ms since startup) and #fps.
#
# The loop owns the fixed-timestep accumulator, so #update is called once per
# whole tick and may run zero or several times per rendered frame. #frame_begin
# is the place to sample input once and reuse it across every tick of that
# frame.
#
# If a callback raises, the exception is carried out of #run with its original
# class, message and backtrace, and the loop shuts down cleanly first. A
# non-local exit (throw/break/return) out of a callback cannot be carried
# across the C loop and is reported as a RuntimeError instead — use #close to
# stop the loop.
#
# Loading this .so pulls SDL2 and OpenGL into the process — see
# lib/rgame/core.rb for why that's kept off the default `require "rgame"`.
# It loads from lib/rgame/core_ext.so, which the build (`make ext-core`)
# copies out of ext/rgame_core/.
require 'rgame/core_ext'
