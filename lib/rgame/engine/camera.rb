# frozen_string_literal: true

module RGame
  module Engine
    # A 2D camera: a point in the world to look at, plus the world bounds it may
    # not show past. Pure; the offset it produces is applied as a draw-time
    # transform, never baked into a node.
    #
    #   camera = Camera.new(world_width: map.pixel_width, world_height: map.pixel_height)
    #   camera.center_on(player.abs_x, player.abs_y)   # in update, every tick
    #   camera.resolve(view_width, view_height)        # at draw, for one viewport
    #   camera.x, camera.y                             # the offset to translate by
    #
    # ## Why the viewport size is an argument and not state
    #
    # A camera used to be built with its viewport size and clamp against it in
    # `center_on`. That cannot survive split-screen: the same world is drawn
    # through several viewports whose rects come from the layout and change when
    # a player joins or the window resizes. Clamping has to happen against the
    # rect actually being drawn into, and the difference is visible rather than
    # theoretical — near a world edge, the same target sits at a different place
    # on screen in a half-width viewport than in a full-width one.
    #
    # So `center_on` records *intent* and `resolve` computes the offset. Nothing
    # calls `resolve` by hand: the platform resolves each camera against the
    # viewport it is about to draw, which is what keeps the two from drifting.
    #
    # ## The camera belongs to a player, not to a scene
    #
    # A scene may have any number of viewers, so it cannot own "the" camera.
    # RGame::Engine::Player owns one; a scene sets its world bounds when it
    # loads a map, and a CameraFollow component in the world points it.
    class Camera
      attr_reader :x, :y, :target_x, :target_y
      attr_accessor :world_width, :world_height

      # `world_width` / `world_height` bound what the camera may show. Left nil
      # the camera is unbounded and follows its target exactly — which is the
      # right default: a game that has not declared its world yet gets a camera
      # that visibly works, rather than one silently pinned to the origin.
      def initialize(world_width: nil, world_height: nil)
        @world_width = world_width
        @world_height = world_height
        @target_x = 0.0
        @target_y = 0.0
        @x = 0.0
        @y = 0.0
      end

      # Look at this world point. Records the target; the offset is worked out
      # by #resolve, which is the only place that knows how big the view is.
      def center_on(world_x, world_y)
        @target_x = world_x
        @target_y = world_y
      end

      # Work out the draw offset for a viewport of this size, clamped so the
      # view never shows past the world's edges.
      def resolve(view_width, view_height)
        @x = clamp(@target_x - (view_width / 2.0), @world_width, view_width)
        @y = clamp(@target_y - (view_height / 2.0), @world_height, view_height)
        self
      end

      private

      def clamp(value, world_size, view_size)
        return value.to_f if world_size.nil? # unbounded: follow exactly

        max = world_size - view_size
        return 0.0 if max <= 0 # world smaller than the view -> pin to origin

        value.clamp(0.0, max.to_f)
      end
    end
  end
end
