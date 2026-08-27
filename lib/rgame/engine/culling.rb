# frozen_string_literal: true

module RGame
  module Engine
    # Skipping a drawable that the viewport cannot show.
    #
    # Mixed into the components that draw a node's own footprint, which are the
    # ones that know both where they put it and how big it is.
    #
    # ## Why it is worth doing at all
    #
    # It was not, while the world was drawn once: a handful of skipped draws
    # against a frame's worth of work. Split-screen changes the arithmetic —
    # the world is walked once per viewport, and an actor at one player's end of
    # the map is off the *other* player's view every frame. What used to be a
    # small saving becomes a saving multiplied by the number of people playing.
    #
    # ## Conservative on purpose
    #
    # Culling one frame too eagerly is a sprite popping in at the edge of the
    # screen, which is worse than the draw it saved. So two rules:
    #
    # - **No size means no culling.** `node.width`/`height` are what a drawable's
    #   footprint is measured from, and a node that never set them (nothing
    #   requires it — `examples/14_asteroids` does not) reads as 0×0, which would
    #   otherwise cull everything instantly. Unknown means draw.
    # - **A rotated node is measured generously.** `Node2D#draw` rotates about the
    #   node's own origin, so a rotated footprint can reach further than its
    #   box in any direction. The margin is `width + height`, which is always at
    #   least the diagonal `hypot(width, height)` and costs no square root on a
    #   path that runs once per drawable per viewport.
    module Culling
      private

      # Can this box be skipped for `view`? Coordinates are **world** ones, which
      # is the one thing on the draw path still stated that way: the view is a
      # camera rectangle in the world, so a node's local box says nothing about
      # whether it is on screen. Callers draw at their own origin and cull at
      # `node.world_x`/`world_y`.
      # hot-path
      def culled?(view, x, y, width, height)
        return false if width.zero? || height.zero?
        return !view.visible?(x, y, width, height) if node.world_angle.zero?

        margin = width + height
        !view.visible?(x - margin, y - margin, width + (margin * 2), height + (margin * 2))
      end
    end
  end
end
