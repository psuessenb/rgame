# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Makes its node's box floor over the map's gaps: a raft, a lift, a moving slab of
      # stone over a chasm.
      #
      #   raft.add_component(BoxCollider.new(width: 32, height: 16, layer: :platform))
      #   raft.add_component(Platform.new)
      #   raft.add_component(PathFollow.new(speed: 40, path: route, loop: true))
      #
      # Wherever the box covers a gap cell, TileWorld#floor_at? answers true, so a node
      # with a Footing stands there rather than falling, and a mover declaring
      # `blocked_by: [:gaps]` walks onto it from the ground and stops at its edge. Ground
      # and platforms make one floor: a walker steps from one onto the other wherever
      # they meet or overlap.
      #
      # It registers with the scene's TileWorld as it attaches, as OccupiesCell does, and
      # leaves as it detaches. The box is read every time it is asked, so a platform that
      # moves takes its floor with it.
      #
      # **It carries whoever stands on it.** Boarding is the rider's question: a Footing
      # asks TileWorld#platform_under every update, and boards the platform under the
      # centre of its box, in the air or not. Carrying is the platform's: the Mover that
      # moves this node hands its step to #carry, and every rider moves by it, through its
      # own Mover's blockers. So a platform carries whatever computed its step, and a rider
      # moves by exactly that step whichever of the two updates first.
      class Platform < Engine::Component
        # The BoxCollider whose box is the floor.
        sealed_reader :collider

        # The Footings standing on it now.
        sealed_reader :riders

        def initialize
          super
          @rgame_collider = nil
          @rgame_world = nil
          @rgame_riders = []
        end

        # Raises when the node has no BoxCollider, or the scene no TileWorld.
        def _attach
          @rgame_collider = require_sibling(BoxCollider)
          @rgame_world = node.system(TileWorld) ||
                         raise("#{self.class} is floor over the gaps of the scene's TileWorld, and the scene " \
                               'has none. Mount one.')
          @rgame_world.bridge(self)
        end

        # Lets every rider go, and leaves the TileWorld, so its box is a gap again.
        def _detach
          @rgame_riders.each(&:ride_ended)
          @rgame_riders.clear
          @rgame_world&.unbridge(self)
          @rgame_world = nil
        end

        # A Footing now standing on it.
        #
        # @api private
        def board(footing)
          @rgame_riders << footing unless @rgame_riders.include?(footing)
        end

        # A Footing that stepped off, fell or left the tree.
        #
        # @api private
        def leave(footing) = @rgame_riders.delete(footing)

        # Carries every rider by (dx, dy), front first along the step, so no rider runs
        # into one the step has not moved yet. Its node's Mover calls it after each step.
        #
        # @api private
        def carry(dx, dy)
          return if (dx.zero? && dy.zero?) || @rgame_riders.empty?

          order_front_first(dx, dy)
          i = 0
          while i < @rgame_riders.size
            @rgame_riders[i].ride(dx, dy)
            i += 1
          end
        end

        # Whether the world point (x, y) lies on the box. A point on its left or top edge
        # does, and one on its right or bottom edge does not, as with a cell.
        #
        # hot-path
        def covers?(x, y)
          left = @rgame_collider.aabb_x
          return false if x < left || x >= left + @rgame_collider.aabb_w

          top = @rgame_collider.aabb_y
          y >= top && y < top + @rgame_collider.aabb_h
        end

        # The box's edges, in world pixels.
        def left = @rgame_collider.aabb_x
        def top = @rgame_collider.aabb_y
        def right = @rgame_collider.aabb_x + @rgame_collider.aabb_w
        def bottom = @rgame_collider.aabb_y + @rgame_collider.aabb_h

        private

        def order_front_first(dx, dy)
          i = 1
          while i < @rgame_riders.size
            rider = @rgame_riders[i]
            lead = rider.lead(dx, dy)
            j = i - 1
            while j >= 0 && @rgame_riders[j].lead(dx, dy) < lead
              @rgame_riders[j + 1] = @rgame_riders[j]
              j -= 1
            end
            @rgame_riders[j + 1] = rider
            i += 1
          end
        end
      end
    end
  end
end
