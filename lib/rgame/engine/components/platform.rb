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
      class Platform < Engine::Component
        # The BoxCollider whose box is the floor.
        sealed_reader :collider

        def initialize
          super
          @rgame_collider = nil
          @rgame_world = nil
        end

        # Raises when the node has no BoxCollider, or the scene no TileWorld.
        def _attach
          @rgame_collider = require_sibling(BoxCollider)
          @rgame_world = node.system(TileWorld) ||
                         raise("#{self.class} is floor over the gaps of the scene's TileWorld, and the scene " \
                               'has none. Mount one.')
          @rgame_world.bridge(self)
        end

        # Leaves the TileWorld, so its box is a gap again.
        def _detach
          @rgame_world&.unbridge(self)
          @rgame_world = nil
        end

        # Whether the world point (x, y) lies on the box. A point on its left or top edge
        # does, and one on its right or bottom edge does not, as with a cell.
        #
        # hot-path
        def covers?(x, y)
          left = @rgame_collider.aabb_x
          top = @rgame_collider.aabb_y
          x >= left && x < left + @rgame_collider.aabb_w && y >= top && y < top + @rgame_collider.aabb_h
        end

        # The box's edges, in world pixels.
        def left = @rgame_collider.aabb_x
        def top = @rgame_collider.aabb_y
        def right = @rgame_collider.aabb_x + @rgame_collider.aabb_w
        def bottom = @rgame_collider.aabb_y + @rgame_collider.aabb_h
      end
    end
  end
end
