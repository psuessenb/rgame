# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A place a node comes back to after a fall, once it has touched it.
      #
      #   flag.add_component(BoxCollider.new(width: 16, height: 16, offset_x: -8, offset_y: -16,
      #                                      layer: :checkpoint))
      #   flag.add_component(Checkpoint.new(by: :hero, location: 'bridge')).on_reached { |other| ... }
      #
      # It takes Collectable's shape: it listens to its own node's collider, and acts
      # on the step a collider on the `by` layer starts overlapping it. It moves the
      # Respawn point of the node that touched it to itself, then emits `reached`. A
      # touch moves only the toucher's point, so two heroes each come back at the
      # last checkpoint they touched.
      #
      # **Its location names the place it stands.** That is its map object's name,
      # for a checkpoint the map builds, or a name of its own. With a TileWorld on
      # the scene, it adds that name as a location while attached, so
      # TileWorld#location finds it either way. A name the map or another node
      # already gives raises at the attach.
      #
      # **In a Scene::Room, a touch hands a Respawn::RoomPoint** at that room and
      # the location, so a node that falls in another room comes back here. A
      # checkpoint in a room with no location raises at the attach. Outside rooms,
      # a touch hands a Respawn::Point at its node's world position.
      #
      # **A node on `by` with no Respawn raises at the touch.** A layer named here is
      # one whose nodes come back, and a node that would not is a mistake the touch
      # names. A game that ends on a fall decides at the fall instead: it removes the
      # Respawn in Fall's `on_fell`.
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

        # The name of the place it stands, or nil.
        sealed_reader :location

        # `by` is the layer whose colliders reach it; every other layer is ignored.
        # `location` names the place it stands, and a checkpoint in a room needs
        # one. Raises TypeError for a location that is not a String, and
        # ArgumentError for an empty one, the name a map gives an unnamed object.
        def initialize(by:, location: nil)
          super()
          @rgame_by = by
          @rgame_location = checked(location)
          @rgame_room = nil
          @rgame_world = nil
          @rgame_named_in = nil
          @rgame_collider = nil
          @rgame_handle = nil
        end

        # Raises without a Collider on the node, when the scene's TileWorld has no
        # ground under the node, in a room with no location, and for a location
        # the TileWorld already knows from another object or node.
        def _attach
          @rgame_collider = require_sibling(Collider)
          @rgame_world = node.system(TileWorld)
          refuse_gap
          @rgame_room = Scene::Room.of(node)&.name
          refuse_unnamed
          name_place
          @rgame_handle = @rgame_collider.on_hit { |other| reach(other) if other.layer == @rgame_by }
        end

        # Ends the connection to the collider, as Collectable does, and removes the
        # location it added.
        def _detach
          @rgame_collider&.disconnect_hit(@rgame_handle)
          @rgame_named_in&.remove_location(@rgame_location)
          @rgame_named_in = nil
          @rgame_world = nil
          @rgame_collider = nil
          @rgame_handle = nil
        end

        private

        def checked(location)
          return location if location.nil?
          unless location.is_a?(String)
            raise TypeError, "a Checkpoint's location is a String, as a map's names are, not #{location.inspect}"
          end

          if location.empty?
            raise ArgumentError, "a Checkpoint's location names its place, and '' is the name a map gives every " \
                                 'object it leaves unnamed. Name the object, or pass a name of its own'
          end

          location
        end

        def refuse_gap
          world = @rgame_world
          x = node.world_x
          y = node.world_y
          return if world.nil? || world.ground_at?(x, y)

          raise ArgumentError, "#{node.class}'s Checkpoint at (#{x}, #{y}) is over a gap, so a node would " \
                               'come back there only to fall again. Stand it on ground.'
        end

        def refuse_unnamed
          return unless @rgame_room && @rgame_location.nil?

          raise ArgumentError, "#{node.class}'s Checkpoint stands in room #{@rgame_room.inspect} and has no " \
                               'location, so a node that falls in another room has no place to come back to. ' \
                               'Pass location:, such as the name of its map object'
        end

        def name_place
          return unless @rgame_world && @rgame_location

          @rgame_world.add_location(@rgame_location, node)
          @rgame_named_in = @rgame_world
        end

        def reach(other)
          respawn = other.node.get_component(Respawn) ||
                    raise("#{other.node.class} on :#{@rgame_by} touched a Checkpoint, and has no Respawn to " \
                          'set. A game that ends on a fall removes the Respawn in Fall#on_fell instead.')
          respawn.set_point(point)
          reached_signal.emit(other)
        end

        def point
          return Respawn::RoomPoint.new(room: @rgame_room, location: @rgame_location) if @rgame_room

          Respawn::Point.new(x: node.world_x, y: node.world_y)
        end
      end
    end
  end
end
