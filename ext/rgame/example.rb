# Manual/visual smoke test for the Ruby extension (layer 3 — the real SDL/GL
# path). Build the extension first, then run this:
#
#   cd ext/rgame && ruby extconf.rb && make
#   ruby example.rb
#
# It opens a window that shows the engine's clear color. Close the window or
# press Escape to quit; the fps reading prints on the way out. This is the
# Ruby-side mirror of src/main.c.

$LOAD_PATH.unshift __dir__
require "rgame"

app = Rgame::App.new(800, 600, "rgame via Ruby")

frames = 0

app.run(
  ->(dt) {},              # update: fixed-timestep tick (no state yet)
  -> { frames += 1 },     # draw: one frame (no primitives yet)
)

puts "drew #{frames} frames, last fps: #{app.fps.round(1)}"
