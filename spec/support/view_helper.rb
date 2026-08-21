# frozen_string_literal: true

# A viewport to draw into, for specs.
#
# `draw(renderer, view)` hands every node the region it is being drawn into, so
# a spec that draws needs one. Most do not care what is in it — they are
# asserting what reached the renderer — so this builds a plain full-screen view
# with no camera, which is what a screen-space band gets.
#
# Pass a camera when the spec is about a world view: that is what makes
# `view.offset_x` and `view.visible?` mean something.
module ViewHelper
  def screen_view(width: 640, height: 480, x: 0, y: 0, camera: nil, player: nil)
    RGame::Engine::View.new(x: x, y: y, width: width, height: height,
                            camera: camera, player: player)
  end
end

RSpec.configure { |config| config.include ViewHelper }
