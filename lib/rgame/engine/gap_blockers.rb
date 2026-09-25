# frozen_string_literal: true

module RGame
  module Engine
    # The edge of the floor as a blocker source: a step may not take the centre of a
    # mover's box off the floor that Components::TileWorld#floor_at? describes. A mover
    # declaring `blocked_by: [:gaps]` gets the one its TileWorld hands out.
    #
    # It answers the blocker-source question Engine::CollisionSystem asks of every source
    # it holds; see that class's header for the protocol. Beside a TileBlockers the system
    # takes whichever landing is nearer, so a mover stops at a wall or at a gap, whichever
    # it meets first.
    #
    # **The centre decides, not the box.** A walker whose box overlaps a gap still stands
    # on the floor while its centre does, which is what lets it stand at the very edge, and
    # it is the same point Components::Footing will watch to decide it falls. A box that
    # could not overlap a gap cell at all would also stop a walker on a platform, which
    # stands inside gap cells.
    #
    # **A step that starts off the floor is free**, so a node that lands in a gap is never
    # held there by its own blocker.
    #
    # It holds no per-step state, so every mover on the map shares one.
    class GapBlockers
      # What a GapBlockers reports as having stopped a step, as TileBlockers reports
      # TILES: one object for the life of the process, answering `layer` with `:gaps` and
      # `node` with nil.
      class Gaps
        def layer = :gaps
        def node = nil
      end

      GAPS = Gaps.new.freeze

      # `world` is the Components::TileWorld whose floor this stops a step at.
      def initialize(world:)
        @world = world
      end

      # Move an AABB (top-left x, y; size w, h) by dx, stopping its centre short of a gap.
      #
      # hot-path
      def resolve_x(x, y, w, h, dx) = x + @world.floor_reach_x(x + (w / 2.0), y + (h / 2.0), dx)

      # hot-path
      def resolve_y(x, y, w, h, dy) = y + @world.floor_reach_y(x + (w / 2.0), y + (h / 2.0), dy)

      # The floor's edge is the same for everybody, so this is a constant rather than a
      # record of the last step. See GAPS.
      def blocker = GAPS

      # A gap does not move, so there is nothing to re-index.
      def moved(_actor, _from_x, _from_y, _w, _h) = nil
    end
  end
end
