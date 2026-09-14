# frozen_string_literal: true

module RGame
  module Engine
    # The tile grid as a blocker source: axis-separated AABB-vs-tile collision
    # resolution over a Util::SolidGrid, at a tile size. Assumes per-step movement smaller
    # than a tile (no tunneling), which holds for our speeds.
    #
    # It answers the blocker-source question — "where does this box land moving dx" —
    # which CollisionSystem asks of every source it holds; see its header for the
    # protocol. Resolving X then Y (with the X result) is what gives wall-sliding, and
    # that ordering lives in the system rather than here, so every source shares it.
    #
    # It also answers the protocol's optional fourth question, #travel? — whether a box can
    # move along a segment without any resolve falling short — which is how a route is
    # checked against the resolver that will stop the walker on it. It is the only source
    # that answers it today.
    #
    # The arithmetic for both is Util::TileSweep's, in C: this class is its blocker-source
    # face, adding what the protocol asks beyond the numbers. The grid is read, never copied,
    # so a cell changed with SolidGrid#set_solid stops the next step.
    class TileBlockers
      # What a TileBlockers reports as having stopped a step. One object for the life of
      # the process, answering the same two questions a collider does — so a handler reads
      # `by.layer` whatever stopped it and never branches on what kind of thing it was. A
      # tile has no node, so `node` is nil.
      #
      # It holds no state at all, which is what makes one TileBlockers safe to share
      # between every body on the map: there is nothing here for two of them to race over.
      class Tiles
        def layer = :tiles
        def node = nil
      end

      TILES = Tiles.new.freeze

      def initialize(grid:, tile_width:, tile_height:)
        @sweep = Util::TileSweep.new(grid, tile_width, tile_height)
      end

      def grid = @sweep.grid

      # Move an AABB (top-left x, y; size w, h) by dx, snapping flush against solids. A Float.
      def resolve_x(x, y, w, h, dx) = @sweep.resolve_x(x, y, w, h, dx)

      def resolve_y(x, y, w, h, dy) = @sweep.resolve_y(x, y, w, h, dy)

      # Whether the box travels (dx, dy) without any resolve along the way falling short of
      # where it was heading — so a walker resolving its own steps against this source, each
      # under a quarter tile, is never stopped on that segment. A landing *past* the intended
      # one does not count as stopped, which is how CollisionSystem reads every source.
      def travel?(x, y, w, h, dx, dy) = @sweep.travel?(x, y, w, h, dx, dy)

      # The grid stopped it, and the grid is the same for everybody — so this is a
      # constant rather than a record of the last step. See TILES.
      def blocker = TILES

      # A grid does not move, so there is nothing to re-index. Part of the blocker-source
      # protocol Engine::CollisionSystem calls after every step; see its header.
      def moved(_actor, _from_x, _from_y, _w, _h) = nil
    end
  end
end
