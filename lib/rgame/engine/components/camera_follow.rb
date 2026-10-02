# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Points a camera at the node it is attached to.
      #
      #   player_node.add_component(CameraFollow.new(camera: players.primary.camera))
      #
      # ## Ownership and behaviour are different questions
      #
      # The camera cannot be *owned* by a node in the world — with several
      # viewers there are several cameras, and a world that holds one has to know
      # how many times it is being drawn. But deciding *where a camera points* is
      # exactly a per-node concern, so it belongs here: the player owns the
      # camera, and a component in the world moves it.
      #
      # That also makes "player two's camera follows player two" nothing more
      # than attaching this to their node with their camera.
      #
      # `offset_x` / `offset_y` shift the point being centred on, for a node
      # whose origin is not what should be in the middle of the screen — a
      # bottom-anchored sprite usually wants its feet, not its head.
      #
      # ## The camera reads the node, so no sibling's order shows
      #
      # This hands the camera the node rather than a position, through
      # Camera#follow. The camera reads where the node is as the frame is drawn,
      # after every update, so it centres on where the node is now in either
      # add order. A position copied in `_update` was read before or after the
      # node's mover stepped, and the node sat a step off centre when this came
      # first.
      #
      # It points the camera as the node enters the tree, so the first frame
      # already shows the node. It points it again each tick the node updates,
      # so a scene uncovered by a pop takes back a camera the scene above it
      # held. As the node leaves the tree, the camera stays where the node was,
      # unless something else has pointed it since.
      class CameraFollow < Engine::Component
        def initialize(camera:, offset_x: 0.0, offset_y: 0.0)
          super()
          @rgame_camera = camera
          @rgame_offset_x = offset_x
          @rgame_offset_y = offset_y
        end

        def _attach = point_camera
        def _update(_dt) = point_camera
        def _detach = @rgame_camera.unfollow(node)

        private

        def point_camera
          @rgame_camera.follow(node, offset_x: @rgame_offset_x, offset_y: @rgame_offset_y)
        end
      end
    end
  end
end
