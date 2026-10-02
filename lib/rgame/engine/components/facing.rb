# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Says which way its node faces. A game turns it with #face, and a node with a Mover
      # also turns as it moves. While the mover heads somewhere, the facing is that heading.
      # Once the mover stops, the facing stays on the last heading. So a character that
      # walked up to a sign and stopped still faces the sign. A guard with no mover faces
      # wherever the game last turned it.
      #
      #   hero.add_component(CharacterBody.new(speed: 80))
      #   hero.add_component(Facing.new(y: 1)) # starts facing down
      #   hero.add_component(Interactor.new(range: 48, policy: :facing))
      #
      # #in_front? asks whether a point lies within 45° either side of the facing. Targeting's
      # `:facing` policy picks through it, and so do Interactor's and Grab's. Behind and to
      # the side are not in front. A node facing 0, 0, the default, faces nowhere, and
      # nothing is in front of it.
      #
      # **Why a component, and not a method of Mover.** Remembering reads the mover's heading
      # on every update, and Velocity works its heading out on each read. Measured without
      # YJIT, that added about 60 ns to a standing CharacterBody's update and about 230 ns to
      # a bare Velocity's. On Mover, every bullet would pay for a facing it never uses.
      #
      # It finds the node's Mover on first use after each attach, so the two may be added in
      # either order. A Mover added after that first use goes unseen until the node enters
      # the tree again. Two Movers raise, since there would be no telling which way the node
      # faces.
      #
      # Every answer takes the mover's heading as it is asked, not only what the last update
      # kept. A heading set this tick therefore counts at once, and a sibling sees the same
      # facing whichever of the two updates first.
      class Facing < Engine::Component
        # `x` and `y` are the facing it starts with, as #face takes them.
        def initialize(x: 0.0, y: 0.0)
          super()
          @rgame_mover = nil
          @rgame_mover_known = false
          face(x, y)
        end

        def _attach = @rgame_mover_known = false

        # hot-path
        def _update(_dt) = follow_mover

        # The facing, each axis in -1..1.
        # hot-path
        def x
          follow_mover
          @rgame_x
        end

        # hot-path
        def y
          follow_mover
          @rgame_y
        end

        # Turns the node to face the direction (x, y), scaled so its larger axis is ±1. So
        # a game may pass the offset to whatever the node should face. (0, 0) faces nowhere.
        #
        # While the node's mover heads somewhere, its heading wins, and the next update or
        # answer takes the facing back. Allocates nothing.
        # hot-path
        def face(x, y)
          larger = [x.abs, y.abs].max
          if larger.zero?
            @rgame_x = 0.0
            @rgame_y = 0.0
          else
            @rgame_x = x / larger.to_f
            @rgame_y = y / larger.to_f
          end
        end

        # Whether the world point (point_x, point_y) lies in front of the node: within 45°
        # either side of the facing, measured from the node's world origin, the 45° itself
        # included. A point behind or to the side is not in front. Nor is the origin itself,
        # nor any point while the node faces nowhere.
        #
        # It allocates nothing. A product with a zero factor counts as 0, because Ruby cannot
        # keep -0.0 inline and would allocate it.
        # hot-path
        def in_front?(point_x, point_y)
          follow_mover
          dx = point_x - node.world_x
          dy = point_y - node.world_y
          ahead = product(@rgame_x, dx) + product(@rgame_y, dy)
          across = product(@rgame_x, dy) - product(@rgame_y, dx)
          ahead.positive? && across.abs <= ahead
        end

        private

        def follow_mover
          find_mover unless @rgame_mover_known
          return unless @rgame_mover

          along_x = @rgame_mover.heading_x
          along_y = @rgame_mover.heading_y
          return if along_x.zero? && along_y.zero?

          @rgame_x = along_x
          @rgame_y = along_y
        end

        def find_mover
          @rgame_mover_known = true
          movers = node.components.grep(Mover)
          if movers.length > 1
            raise ArgumentError, "Facing turns with one #{Mover} on the same node, and this node has " \
                                 "#{movers.length}: #{movers.map(&:class).join(', ')}. Keep one of them."
          end

          @rgame_mover = movers.first
        end

        def product(factor, other) = factor.zero? || other.zero? ? 0 : factor * other
      end
    end
  end
end
