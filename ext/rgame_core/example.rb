# frozen_string_literal: true

# Manual/visual smoke test for the core extension (layer 3 — the real
# SDL/GL path). Build it first, then run this from the project root:
#
#   make ext-core
#   ruby ext/rgame_core/example.rb
#
# It opens a window that shows the engine's clear color. Close the window or
# press Escape to quit; the fps reading prints on the way out. This is the
# Ruby-side mirror of src/main.c.
#
# The load path points at lib/, not at this directory: `make ext-core`
# copies the built core_ext.so to lib/rgame/, so this runs against exactly
# the layout a user of the library would see.

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'rgame/core'

app = RGame::Core::App.new(800, 600, 'rgame via Ruby')

frames = 0

app.run(
  ->(dt) {}, # update: fixed-timestep tick (no state yet)
  -> { frames += 1 } # draw: one frame (no primitives yet)
)

puts "drew #{frames} frames, last fps: #{app.fps.round(1)}"
