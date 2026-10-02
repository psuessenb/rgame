# frozen_string_literal: true

module RGame
  module Engine
    # A 2D camera: a point in the world to look at, plus the world bounds it may
    # not show past. Pure; the offset it produces is applied as a draw-time
    # transform, never baked into a node.
    #
    #   camera = Camera.new(world_width: map.pixel_width, world_height: map.pixel_height)
    #   camera.follow(player)                          # look wherever the player is
    #   camera.center_on(400, 300)                     # or at a fixed point, which stops following
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
    # So `center_on` and `follow` record *intent* and `resolve` computes the
    # offset. Nothing calls `resolve` by hand: the platform resolves each camera
    # against the viewport it is about to draw, which is what keeps the two from
    # drifting.
    #
    # ## A followed target is read as the frame is drawn
    #
    # `follow` keeps the target itself, and `resolve` reads its position. The
    # platform resolves after the tick's last update, so the frame centres on
    # where the target is now. A camera that copied the position during
    # `update` read it before or after the step that moved the target,
    # depending on which ran first. The target was then drawn a step off centre
    # in one order and on it in the other.
    #
    # ## The camera belongs to a player, not to a scene
    #
    # A scene may have any number of viewers, so it cannot own "the" camera.
    # RGame::Engine::Player owns one; a scene sets its world bounds when it
    # loads a map, and a CameraFollow component in the world points it.
    class Camera
      attr_reader :x, :y
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
        @followed = nil
        @offset_x = 0.0
        @offset_y = 0.0
        @x = 0.0
        @y = 0.0
      end

      # Look at this world point, and stop following. Records the target; the
      # offset is worked out by #resolve, which is the only place that knows
      # how big the view is.
      def center_on(world_x, world_y)
        @followed = nil
        @target_x = world_x
        @target_y = world_y
        self
      end

      # Look at `target` from now on, wherever it moves: anything answering
      # `world_x` and `world_y`, such as a node. The offsets shift the point
      # looked at. The camera reads the target each time it resolves, so it
      # never trails it. Following replaces a `center_on`, and a `center_on`
      # replaces following: the later call wins. A target without both methods
      # raises `TypeError`.
      def follow(target, offset_x: 0.0, offset_y: 0.0)
        unless target.respond_to?(:world_x) && target.respond_to?(:world_y)
          raise TypeError, "a camera follows something with world_x and world_y, not #{target.class}"
        end

        @followed = target
        @offset_x = offset_x
        @offset_y = offset_y
        self
      end

      # Stop following `target`, and keep looking where it is now. Does nothing
      # while the camera follows something else or nothing, so one follower
      # letting go never undoes another's `follow` or a `center_on`.
      def unfollow(target)
        center_on(target_x, target_y) if @followed.equal?(target)
        self
      end

      # The world point the camera looks at: the followed target's position
      # plus the offsets, read now, or the point given to `center_on`.
      # hot-path
      def target_x = @followed ? @followed.world_x + @offset_x : @target_x
      # hot-path
      def target_y = @followed ? @followed.world_y + @offset_y : @target_y

      # Work out the draw offset for a viewport of this size, clamped so the
      # view never shows past the world's edges.
      def resolve(view_width, view_height)
        @x = clamp(target_x - (view_width / 2.0), @world_width, view_width)
        @y = clamp(target_y - (view_height / 2.0), @world_height, view_height)
        self
      end

      private

      def clamp(value, world_size, view_size)
        return value.to_f if world_size.nil?

        max = world_size - view_size
        return 0.0 if max <= 0

        value.clamp(0.0, max.to_f)
      end
    end
  end
end
