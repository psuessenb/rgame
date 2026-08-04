# frozen_string_literal: true

require 'rgame/core_ext'
require_relative '../util/color'

module RGame
  module Core
    # A block of drawing baked once and replayed cheaply.
    #
    #   ground = renderer.record do
    #     tiles.each { |tile| renderer.image(tile.image, tile.x, tile.y) }
    #   end
    #
    #   def draw
    #     ground.draw(-camera.x, -camera.y)
    #   end
    #
    # A screen of tiles is a couple of thousand quads that have not changed
    # since the level loaded. Baking them turns the per-frame cost from "walk
    # every tile and transform four corners" into one call per texture — the
    # work happens at bake time and never again.
    #
    # Recordings come from `Renderer#record`; there is no `new`.
    #
    # ## What is baked in and what is not
    #
    # Positions, texture coordinates and colours are baked, and so are any
    # transforms applied *inside* the block. The transform in effect when the
    # recording is *drawn* is applied on top, which is what lets a baked layer
    # scroll under a camera without being rebuilt.
    #
    # Clipping is not baked — it happens when pixels are rasterised, so a clip
    # rectangle captured in one place would be wrong everywhere else the
    # recording is drawn. Pushing a clip inside a `record` block raises. Clip
    # the replay instead:
    #
    #   renderer.clipped(0, 0, 400, 600) { ground.draw(0, 0) }
    class Recording
      Color = RGame::Util::Color

      # Replays everything that was recorded, with the recording's origin at
      # (x, y).
      #
      # `color` tints what was baked: each recorded colour is multiplied by it,
      # so white (the default) draws the recording unchanged and a colour with
      # alpha fades the whole layer out at once.
      def draw(x = 0, y = 0, z: 0, color: nil)
        draw_at(x, y, z, Color.coerce(color).packed)
      end
    end
  end
end
