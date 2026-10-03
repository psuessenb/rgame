# frozen_string_literal: true

module RGame
  module Engine
    module Scene
      # One room of a world: a scene that Scene::Rooms builds, runs beside the
      # other rooms players stand in, and frees once nobody is in it.
      #
      #   class Garden < RGame::Engine::Scene::Room
      #     def _enter_tree
      #       @actors = add_node(RGame::Engine::WorldView.new)
      #     end
      #
      #     def _arrive(node, location)
      #       node.x, node.y = LOCATIONS.fetch(location)
      #       @actors.add_node(node)
      #     end
      #   end
      #
      # **`_arrive` places each node a move brings.** Rooms calls it as the move
      # lands, after the room entered the tree, with the node and the location
      # the move named, such as an entrance. The node is in no room when it
      # comes from another one, and the hook adds it to a node in this room. It
      # is still here when the move was a warp inside this room, and adding it
      # to its own parent again changes nothing. A node `_arrive` leaves outside
      # the room raises. A Components::Respawn::RoomPoint calls it too, to bring
      # back a node that fell in this room. The node is still here then, as for a
      # warp.
      #
      # **Place the node before adding it.** The add attaches the node's
      # components. A Components::Respawn bringing the node back from another
      # room fires `on_respawned` as it attaches, and a listener would otherwise
      # find the node where it stood in the room it fell in.
      #
      # A room is its own `scene`, so its systems are found first by the nodes
      # in it. A system it lacks is looked for on the world scene that holds the
      # rooms, and then on the root.
      class Room < Engine::Node2D
        hook :_arrive

        # The Symbol the room was defined under. Rooms sets it as it builds the
        # room.
        sealed_accessor :name

        # The players who stand in this room. Rooms keeps the list: read it,
        # and leave it alone.
        sealed_reader :players

        def initialize(**)
          super
          @rgame_name = nil
          @rgame_players = []
        end

        # The room `node` stands in: the nearest enclosing scene that is a Room,
        # the node itself if it is one, or nil outside every room.
        def self.of(node)
          around = node.scene
          around = around.parent&.scene until around.nil? || around.is_a?(Room)
          around
        end

        # Places `node`, which a move brought to this room at `location`.
        # Empty here, so a room that does not place what arrives raises.
        def _arrive(node, location); end
      end
    end
  end
end
