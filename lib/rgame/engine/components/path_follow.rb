# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Walks the owning node along an Engine::Path at a constant speed, segment by
      # segment, and emits `on_finished` once it reaches the final waypoint — the seam for
      # whatever should happen when a walker arrives.
      #
      # The walk is allocation-free: it tracks the current segment and the distance into
      # it, advancing through as many segments as one step crosses (so a fast mover over
      # short segments still lands correctly), then interpolates the node's position from
      # the segment endpoints. Movement is driven purely by `speed * dt`; this is not a
      # Velocity integrator and ignores the node's angle.
      #
      # ## Blocked, the walk waits
      #
      # A Mover, so `blocked_by:` stops it the way it stops a CharacterBody — see Mover's
      # header. Declaring nothing keeps the walk exactly as described above: the node is
      # *placed* on the path each step.
      #
      # Declaring something turns the placement into a move: the walk still works out
      # where the node should be, and then gets there through `apply_move`. **A step that
      # is stopped short does not advance the walk** — progress goes back to where the
      # step began. The obvious alternative, letting progress run on and the node catch up,
      # is wrong twice over: a follower held behind something for a second would race
      # ahead to where it "should" be once let go, and `on_finished` could fire for a
      # walker still standing in front of the obstacle.
      #
      # One consequence is easy to miss: **a held follower does not slide along what stopped
      # it** the way a Velocity does. A step's free axis still moves, but the rewind aims the
      # next step at the same point on the path, from a little closer, so a follower pressed
      # diagonally against a wall creeps to rest instead of sliding to the corner. A walker
      # meant to get round something replans its path rather than relying on the slide.
      #
      # `_attach` still places the node on the first waypoint absolutely, blocked or
      # not: where a walker starts is a placement, not a step.
      #
      # ## A new route, and none
      #
      # `path: nil` builds an idle follower, which moves nothing and never finishes, and
      # `follow(path)` hands any follower a route to walk from its start — the same restart
      # entering the tree gives, so a walker that finished one route walks the next and
      # finishes again, and one still walking drops its old route at once. `finish` puts
      # the walker at the end of its route at once, as skipping a cutscene does.
      #
      # Its heading is the unit direction of the segment it is on, worked out when the walk
      # crosses into a segment rather than on every read.
      class PathFollow < Mover
        signal :finished

        sealed_accessor :speed
        sealed_reader :path, :heading_x, :heading_y

        def initialize(speed:, path: nil, blocked_by: [], pushes: [])
          super(blocked_by:, pushes:)
          @rgame_path = path
          @rgame_speed = speed
          restart
        end

        def finished? = @rgame_finished

        # Restart the walk as the node enters the tree — back to the first waypoint, with
        # progress cleared — so a pooled follower reacquired and re-added begins a fresh walk
        # rather than resuming (or staying finished) where its previous life ended.
        def _attach
          super
          restart
        end

        # Walk `path` from its first waypoint, where the node is placed, whatever this
        # follower was doing — idle, finished, or halfway along another route. `nil` stops
        # it where it stands.
        def follow(path)
          @rgame_path = path
          restart
        end

        # Places the node on the last waypoint and emits `on_finished`, as
        # reaching it does, whatever stands in the way. Does nothing when the
        # walk has finished or there is no route. Returns self.
        def finish
          return self if @rgame_finished || @rgame_path.nil?

          place_at(@rgame_path.count - 1) if node
          arrive
          self
        end

        private

        def take_step(dt)
          return if @rgame_finished || @rgame_path.nil?

          from_segment = @rgame_segment
          from_distance = @rgame_distance

          if advance_to_end?(@rgame_speed * dt)
            last = @rgame_path.count - 1
            return arrive if moved_to?(@rgame_path.x_at(last), @rgame_path.y_at(last))

            rewind(from_segment, from_distance)
          else
            seg_len = @rgame_path.segment_length(@rgame_segment)
            t = seg_len.zero? ? 0.0 : @rgame_distance / seg_len
            sx = @rgame_path.x_at(@rgame_segment)
            sy = @rgame_path.y_at(@rgame_segment)
            reached = moved_to?(sx + ((@rgame_path.x_at(@rgame_segment + 1) - sx) * t),
                                sy + ((@rgame_path.y_at(@rgame_segment + 1) - sy) * t))
            rewind(from_segment, from_distance) unless reached
          end
          aim
        end

        def advance_to_end?(remaining)
          while remaining.positive?
            left = @rgame_path.segment_length(@rgame_segment) - @rgame_distance
            if remaining < left
              @rgame_distance += remaining
              return false
            end
            remaining -= left
            @rgame_segment += 1
            @rgame_distance = 0.0
            return true if @rgame_segment >= @rgame_path.count - 1
          end
          false
        end

        def moved_to?(x, y)
          unless blocking?
            node.x = x
            node.y = y
            return true
          end

          apply_move(x - node.x, y - node.y)
          !last_move_blocked?
        end

        def rewind(segment, distance)
          @rgame_segment = segment
          @rgame_distance = distance
        end

        def arrive
          @rgame_finished = true
          head_nowhere
          finished_signal.emit
        end

        def restart
          @rgame_segment = 0
          @rgame_distance = 0.0
          @rgame_finished = false
          head_nowhere
          return unless @rgame_path

          aim
          place_at(0) if node
        end

        def aim
          return if @rgame_segment == @rgame_aimed_segment

          @rgame_aimed_segment = @rgame_segment
          length = @rgame_path.segment_length(@rgame_segment)
          return head_nowhere if length.zero?

          @rgame_heading_x = (@rgame_path.x_at(@rgame_segment + 1) - @rgame_path.x_at(@rgame_segment)) / length
          @rgame_heading_y = (@rgame_path.y_at(@rgame_segment + 1) - @rgame_path.y_at(@rgame_segment)) / length
        end

        def head_nowhere
          @rgame_aimed_segment = nil
          @rgame_heading_x = 0.0
          @rgame_heading_y = 0.0
        end

        def place_at(waypoint)
          node.x = @rgame_path.x_at(waypoint)
          node.y = @rgame_path.y_at(waypoint)
        end
      end
    end
  end
end
