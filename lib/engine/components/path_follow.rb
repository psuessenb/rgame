# frozen_string_literal: true

module Engine
  module Components
    # Walks the owning node along an Engine::Path at a constant speed, segment by
    # segment, and emits `on_finished` once it reaches the final waypoint — the seam a
    # tower defense game uses to leak a life when an enemy reaches the base.
    #
    # The walk is allocation-free: it tracks the current segment and the distance into
    # it, advancing through as many segments as one step crosses (so a fast mover over
    # short segments still lands correctly), then interpolates the node's position from
    # the segment endpoints. Movement is driven purely by `speed * dt`; this is not a
    # Velocity integrator and ignores the node's angle.
    class PathFollow < Engine::Component
      signal :on_finished # emits no payload; the owning node identifies which follower finished

      attr_accessor :speed

      def initialize(path:, speed:)
        super()
        @path = path
        @speed = speed
        @segment = 0       # walking from waypoint @segment to @segment + 1
        @distance = 0.0    # distance travelled into the current segment
        @finished = false
      end

      def finished? = @finished

      # Restart the walk as the node enters the tree — back to the first waypoint, with
      # progress cleared — so a pooled follower reacquired and re-added begins a fresh walk
      # rather than resuming (or staying finished) where its previous life ended.
      def on_attach
        @segment = 0
        @distance = 0.0
        @finished = false
        place_at(0)
      end

      def update(dt)
        return if @finished

        remaining = @speed * dt
        while remaining.positive?
          left = @path.segment_length(@segment) - @distance
          if remaining < left
            @distance += remaining
            break
          end
          # Consume the rest of this segment and step onto the next waypoint.
          remaining -= left
          @segment += 1
          @distance = 0.0
          return finish if @segment >= @path.count - 1
        end
        place_along_segment
      end

      private

      def finish
        place_at(@path.count - 1)
        @finished = true
        on_finished_signal.emit
      end

      def place_at(waypoint)
        node.x = @path.x_at(waypoint)
        node.y = @path.y_at(waypoint)
      end

      def place_along_segment
        seg_len = @path.segment_length(@segment)
        t = seg_len.zero? ? 0.0 : @distance / seg_len
        sx = @path.x_at(@segment)
        sy = @path.y_at(@segment)
        node.x = sx + ((@path.x_at(@segment + 1) - sx) * t)
        node.y = sy + ((@path.y_at(@segment + 1) - sy) * t)
      end
    end
  end
end
