# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A place a node comes back to after a fall, once it has touched it.
      #
      #   flag.add_component(BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -16,
      #                                      layer: :checkpoint))
      #   flag.add_component(Checkpoint.new(by: :hero)).on_reached { |other| ... }
      #
      # It takes Collectable's shape: it listens to its own node's collider, and acts
      # on the step a collider on the `by` layer starts overlapping it. It moves the
      # Respawn point of the node that touched it to its own node's world position,
      # then emits `reached`. A touch moves only the toucher's point, so two heroes
      # each come back at the last checkpoint they touched.
      #
      # **A node on `by` with no Respawn raises at the touch.** A layer named here is
      # one whose nodes come back, and a node that would not is a mistake the touch
      # names. A game that ends on a fall decides at the fall instead: it removes the
      # Respawn in Footing's `on_fell`.
      #
      # **It stands on ground.** With a TileWorld on the scene, the attach raises
      # ArgumentError where the node's cell is a gap, as Respawn raises for its point,
      # so a checkpoint placed over a gap fails as the scene loads.
      #
      # It has no _update. A touch is an event, and costs nothing per frame.
      class Checkpoint < Engine::Component
        # The collider that touched it. Emitted once its node's Respawn has the new
        # point.
        signal :reached, :other

        # The layer whose colliders reach it.
        sealed_reader :by

        # `by` is the layer whose colliders reach it; every other layer is ignored.
        def initialize(by:)
          super()
          @rgame_by = by
          @rgame_collider = nil
          @rgame_handle = nil
        end

        # Raises without a Collider on the node, and when the scene's TileWorld has
        # no ground under the node.
        def _attach
          @rgame_collider = require_sibling(Collider)
          refuse_gap
          @rgame_handle = @rgame_collider.on_hit { |other| reach(other) if other.layer == @rgame_by }
        end

        # Ends the connection to the collider, as Collectable does.
        def _detach
          @rgame_collider&.disconnect_hit(@rgame_handle)
          @rgame_collider = nil
          @rgame_handle = nil
        end

        private

        def refuse_gap
          world = node.system(TileWorld)
          x = node.world_x
          y = node.world_y
          return if world.nil? || world.ground_at?(x, y)

          raise ArgumentError, "#{node.class}'s Checkpoint at (#{x}, #{y}) is over a gap, so a node would " \
                               'come back there only to fall again. Stand it on ground.'
        end

        def reach(other)
          respawn = other.node.get_component(Respawn) ||
                    raise("#{other.node.class} on :#{@rgame_by} touched a Checkpoint, and has no Respawn to " \
                          'set. A game that ends on a fall removes the Respawn in Footing#on_fell instead.')
          respawn.set_point(node.world_x, node.world_y)
          reached_signal.emit(other)
        end
      end
    end
  end
end
