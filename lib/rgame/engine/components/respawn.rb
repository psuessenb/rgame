# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Where a node comes back after a fall.
      #
      #   hero.add_component(Footing.new(coyote: 0.1))
      #   hero.add_component(Fall.new)
      #   hero.add_component(Shrink.new)
      #   blink = hero.add_component(Blink.new)
      #   hero.add_component(Respawn.new).on_respawned { blink.start(1.0) }
      #
      # A Fall whose node has one calls #respawn at the end of the fall, rather than
      # freeing the node. In the node's own room, the node stands on its point at
      # once, and its controls work from that tick. A camera following the node
      # cuts there. A game shows where it came back from `on_respawned`, with a
      # Blink as above.
      #
      # **The point is an object that places the node.** It answers `room`,
      # `place(node)` and `check_ground(world)`. The engine offers two:
      #
      # - A Point, at world coordinates. The first attach with no point takes
      #   one where the node stands.
      # - A RoomPoint, at a location a room of the scene's Scene::Rooms names.
      #   A move hands one to a Respawn with no point, at the room and the
      #   location it lands the node at, before the room's `_arrive`.
      #
      # Later attaches and later moves keep the point, so a door leaves it where
      # it was set. #set_point moves it, which is what a Checkpoint calls.
      #
      # **A point belongs to a room.** A RoomPoint's room is its own. A point
      # whose `room` is nil, a Point among them, belongs to the Scene::Room the
      # node stood in as the point was set, or to no room outside rooms. A point
      # set while the node is out of the tree belongs to the room of its next
      # attach. #respawn raises for such a point while the node stands in another
      # room, where the same coordinates are another place, and names both rooms.
      #
      # **A respawn into another room is a move.** A RoomPoint asks the rooms to
      # move the node to its room, under the rooms' transition, as a door does.
      # Its `place` answers false, and the respawn waits. The node's next attach
      # in the point's room ends the wait and fires `on_respawned`, once the
      # room's `_arrive` has placed it. A move that lands the node in another
      # room first ends the wait with no signal. In the node's own room, a
      # RoomPoint calls the room's `_arrive` at once: a warp, without the cover.
      #
      # **The point stands on ground.** With a TileWorld on the scene, each attach
      # and each #set_point on an attached Respawn raises ArgumentError for a point
      # whose cell is a gap, a gap under a platform included. A node brought back
      # there would fall again as soon as it stood, every time, and the raise names
      # the point as the scene loads instead. Only a point in the room the node
      # stands in is checked, since only that room's TileWorld knows its ground. A
      # RoomPoint in another room is checked as the node attaches there. A node
      # that starts on a platform takes a point on ground from #set_point before
      # it is added.
      #
      # A game decides at each fall whether the node comes back: the Fall looks the
      # Respawn up as it ends, so one removed in its `on_fell` frees the node.
      #
      # #respawn works without a fall too, for a game whose hero can come back from
      # something that is not one.
      class Respawn < Engine::Component
        # A respawn point at world coordinates, in the room the node stood in as
        # the point was set.
        Point = Data.define(:x, :y) do
          # None: Respawn keeps the room the node stood in as it set the point.
          def room = nil

          # Places `node` on the point. Returns true: the node stands there now.
          # rubocop:disable Naming/PredicateMethod -- a command that reports whether the node landed, as every point's does
          def place(node)
            node.world_x = x
            node.world_y = y
            true
          end
          # rubocop:enable Naming/PredicateMethod

          # Raises ArgumentError when `world`, a TileWorld, has no ground under
          # the point.
          def check_ground(world)
            return if world.ground_at?(x, y)

            raise ArgumentError, "respawn point (#{x}, #{y}) is over a gap, so it would fall again as it came " \
                                 'back. Stand it on ground, or call set_point before adding the node.'
          end
        end

        # A respawn point at a location a room names, in a room of the scene's
        # Scene::Rooms. `room` is the Symbol the room was defined under, and
        # `location` reaches the room's `_arrive` as a move's does. Raises
        # TypeError for a room that is not a Symbol.
        RoomPoint = Data.define(:room, :location) do
          def initialize(room:, location:)
            unless room.is_a?(Symbol)
              raise TypeError, "a RoomPoint's room is the Symbol it was defined under, not #{room.inspect}"
            end

            super
          end

          # Places `node` at the location. In the room the node stands in, the
          # room's `_arrive` places it at once, and this returns true. Raises
          # when `_arrive` leaves the node outside the room, as a move does.
          # From another room, the rooms move the node there, and this returns
          # false.
          def place(node)
            here = Scene::Room.of(node)
            unless here&.name == room
              node.system!(Scene::Rooms).move(node, to: room, location:)
              return false
            end

            here._arrive(node, location)
            return true if Scene::Room.of(node).equal?(here)

            raise "#{here.class}#_arrive left #{node.class} outside the room. Add it to a node in the room"
          end

          # Raises ArgumentError when `world`, the TileWorld of the point's
          # room, has no ground under the location, and KeyError when it names
          # no such location.
          def check_ground(world)
            at = world.location(location)
            return if world.ground_at?(at.x, at.y)

            raise ArgumentError, "respawn point #{location.inspect} in room #{room.inspect} is over a gap, so it " \
                                 'would fall again as it came back. Stand the location on ground.'
          end
        end

        ANSWERS = %i[room place check_ground].freeze
        private_constant :ANSWERS

        # Fired once the node stands on its respawn point.
        signal :respawned

        # The point, nil until the first attach or the first #set_point.
        sealed_reader :point

        def initialize
          super
          @rgame_point = nil
          @rgame_set_in = nil
          @rgame_room_due = true
          @rgame_world = nil
          @rgame_waiting = false
        end

        # The first attach with no point takes a Point where the node stands. A
        # point set while the node was out of the tree belongs to the room of
        # this attach. Raises ArgumentError when the node stands in its point's
        # room and the scene's TileWorld has no ground under the point. An
        # attach there ends a respawn that waits, and fires `on_respawned`.
        def _attach
          @rgame_world = node.system(TileWorld)
          @rgame_point ||= Point.new(x: node.world_x, y: node.world_y)
          if @rgame_room_due
            @rgame_set_in = room_name
            @rgame_room_due = false
          end
          return unless point_room == room_name

          check_ground(@rgame_point)
          return unless @rgame_waiting

          @rgame_waiting = false
          respawned_signal.emit
        end

        # A new point, answering `room`, `place` and `check_ground`. Returns self.
        # Raises TypeError for an object that does not answer all three. Once
        # attached, raises ArgumentError for a point over a gap in the room the
        # node stands in, and keeps the point it had.
        def set_point(point) # rubocop:disable Naming/AccessorMethodName -- returns self, so Respawn.new.set_point(...) goes straight into add_component
          refuse_unknown(point)
          if node&.in_tree?
            here = room_name
            check_ground(point) if point.room.nil? || point.room == here
            @rgame_set_in = here
            @rgame_room_due = false
          else
            @rgame_room_due = true
          end
          @rgame_point = point
          self
        end

        # Places the node on its point, and emits `on_respawned` once it stands
        # there: at once when the point's `place` answers true, and otherwise as
        # the node attaches in the point's room. Raises for a point with no room
        # while the node stands in another room than the one it stood in as the
        # point was set.
        def respawn
          here = room_name
          if @rgame_point.room.nil? && @rgame_set_in != here
            raise "#{node.class}'s respawn point #{@rgame_point.inspect} was set in #{room_label(@rgame_set_in)}, " \
                  "and the node fell in #{room_label(here)}, where those coordinates are another place. Set a " \
                  'Respawn::RoomPoint, which the rooms bring the node back to, or set a point in ' \
                  "#{room_label(here)} as the node arrives there."
          end

          @rgame_waiting = !@rgame_point.place(node)
          respawned_signal.emit unless @rgame_waiting
        end

        # Scene::Rooms calls it as a move lands the node, before the room's
        # `_arrive`, with the room's name and the move's location. A Respawn
        # with no point takes a RoomPoint there. A landing in another room than
        # the point's ends a respawn that waits, with no `on_respawned`.
        #
        # @api private
        def take_landing(room, location)
          @rgame_point ||= RoomPoint.new(room:, location:)
          @rgame_waiting = false unless point_room == room
        end

        def _detach
          @rgame_world = nil
        end

        private

        def room_name = Scene::Room.of(node)&.name

        def point_room = @rgame_point.room || @rgame_set_in

        def room_label(name) = name ? "room #{name.inspect}" : 'no room'

        def check_ground(point)
          point.check_ground(@rgame_world) if @rgame_world
        rescue ArgumentError => e
          raise ArgumentError, "#{node.class}'s #{e.message}"
        end

        def refuse_unknown(point)
          missing = ANSWERS.reject { point.respond_to?(it) }
          return if missing.empty?

          raise TypeError, "a respawn point answers room, place and check_ground, and #{point.inspect} does not " \
                           "answer #{missing.join(', ')}. Pass a Respawn::Point, a Respawn::RoomPoint, or an object " \
                           "of the game's own"
        end
      end
    end
  end
end
