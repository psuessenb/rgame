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
      #     def _arrive(node, entrance)
      #       node.x, node.y = ENTRANCES.fetch(entrance)
      #       @actors.add_node(node)
      #     end
      #   end
      #
      # **`_arrive` places each node a move brings.** Rooms calls it as the move
      # lands, after the room entered the tree, with the node and the entrance
      # the move named. The node is in no room when it comes from another one,
      # and the hook adds it to a node in this room. It is still here when the
      # move was a warp inside this room, and adding it to its own parent again
      # changes nothing. A node `_arrive` leaves outside the room raises.
      #
      # A room is its own `scene`, so its systems are found first by the nodes
      # in it. A system it lacks is looked for on the world scene that holds the
      # rooms, and then on the root.
      class Room < Engine::Node2D
        hook :_arrive

        # The Symbol the room was defined under. Rooms sets it as it builds the
        # room.
        attr_accessor :name

        # The players who stand in this room. Rooms keeps the list: read it,
        # and leave it alone.
        attr_reader :players

        def initialize(**)
          super
          @name = nil
          @players = []
        end

        # Places `node`, which a move brought to this room at `entrance`.
        # Empty here, so a room that does not place what arrives raises.
        def _arrive(node, entrance); end
      end
    end
  end
end
