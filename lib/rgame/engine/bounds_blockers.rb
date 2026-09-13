# frozen_string_literal: true

module RGame
  module Engine
    # The edges of the world as a blocker source: a box may not leave the region the
    # scene's Components::WorldBounds describes. Pure — it is four numbers and the same
    # snapping arithmetic every other source uses.
    #
    # It answers the blocker-source question Engine::CollisionSystem asks of every source
    # it holds; see that class's header for the protocol.
    #
    # ## Why the world edge is declared rather than automatic
    #
    # Stopping at the edge is one of three responses to it. ScreenWrap and DespawnOffscreen
    # are the other two, and a node may carry only one of them
    # (Components::WorldBounds.one_response!). A clamp applied to every step would be a
    # response nobody chose, contradicting a wrap or a despawn on every node that has one.
    # So a game that wants the world edge to stop an actor says so, and gets an ordinary
    # blocker with a layer like any other.
    class BoundsBlockers
      # What a BoundsBlockers reports as having stopped a step: one object for the life of
      # the process, answering the same two questions a collider does, so a handler reads
      # `by.layer` whatever stopped it. The world's edge has no node.
      class Bounds
        def layer = :bounds
        def node = nil
      end

      BOUNDS = Bounds.new.freeze

      # `bounds` is anything answering world_width / world_height — a Components::World or
      # a Components::TileWorld. The two numbers are read once, here, because WorldBounds
      # is documented immutable: a world that genuinely changes size is a new scene.
      def initialize(bounds:)
        @world_width = bounds.world_width
        @world_height = bounds.world_height
        @blocker = nil
      end

      # The world's edge stopped the last resolve on this axis, or nil when it did not.
      attr_reader :blocker

      # The far axis is nothing to a rectangle: a box leaves the world on one axis
      # independently of where it is on the other, so `_y` and `_h` go unread here and
      # `_x` and `_w` in the mirror. The five arguments are the protocol's, not this
      # source's need.
      def resolve_x(x, _y, w, _h, dx) = resolve(x + dx, w, @world_width, dx)
      def resolve_y(_x, y, _w, h, dy) = resolve(y + dy, h, @world_height, dy)

      # The world does not move, so there is nothing to re-index.
      def moved(_actor, _from_x, _from_y, _w, _h) = nil

      private

      def resolve(landed, span, extent, delta)
        @blocker = nil
        return landed if delta.zero?

        limit = extent - span
        limit = 0.0 if limit.negative?

        if landed.negative?
          @blocker = BOUNDS
          0.0
        elsif landed > limit
          @blocker = BOUNDS
          limit.to_f
        else
          landed
        end
      end
    end
  end
end
