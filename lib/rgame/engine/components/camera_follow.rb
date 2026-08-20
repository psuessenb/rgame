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
      class CameraFollow < Engine::Component
        def initialize(camera:, offset_x: 0.0, offset_y: 0.0)
          super()
          @camera = camera
          @offset_x = offset_x
          @offset_y = offset_y
        end

        # Reads the absolute origin resolved at the top of this node's update,
        # so the camera trails the node's own movement by one step (a couple of
        # pixels at walking speed). That is deliberate and uniform: everything
        # drawn through this camera trails equally, so nothing drifts apart on
        # screen, and the alternative — re-resolving here — would put this
        # component's ordering among its siblings on show.
        def update(_dt)
          @camera.center_on(node.abs_x + @offset_x, node.abs_y + @offset_y)
        end
      end
    end
  end
end
