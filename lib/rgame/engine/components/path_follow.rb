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
      # finishes again, and one still walking drops its old route at once.
      #
      # Its heading is the unit direction of the segment it is on, worked out when the walk
      # crosses into a segment rather than on every read.
      class PathFollow < Mover
        signal :finished

        attr_accessor :speed
        attr_reader :path, :heading_x, :heading_y

        def initialize(speed:, path: nil, blocked_by: [], pushes: [])
          super(blocked_by:, pushes:)
          @path = path
          @speed = speed
          restart
        end

        def finished? = @finished

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
          @path = path
          restart
        end

        private

        def take_step(dt)
          return if @finished || @path.nil?

          from_segment = @segment
          from_distance = @distance

          if advance_to_end?(@speed * dt)
            last = @path.count - 1
            return finish if moved_to?(@path.x_at(last), @path.y_at(last))

            rewind(from_segment, from_distance)
          else
            seg_len = @path.segment_length(@segment)
            t = seg_len.zero? ? 0.0 : @distance / seg_len
            sx = @path.x_at(@segment)
            sy = @path.y_at(@segment)
            reached = moved_to?(sx + ((@path.x_at(@segment + 1) - sx) * t),
                                sy + ((@path.y_at(@segment + 1) - sy) * t))
            rewind(from_segment, from_distance) unless reached
          end
          aim
        end

        def advance_to_end?(remaining)
          while remaining.positive?
            left = @path.segment_length(@segment) - @distance
            if remaining < left
              @distance += remaining
              return false
            end
            remaining -= left
            @segment += 1
            @distance = 0.0
            return true if @segment >= @path.count - 1
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
          @segment = segment
          @distance = distance
        end

        def finish
          @finished = true
          head_nowhere
          finished_signal.emit
        end

        def restart
          @segment = 0
          @distance = 0.0
          @finished = false
          head_nowhere
          return unless @path

          aim
          place_at(0) if node
        end

        def aim
          return if @segment == @aimed_segment

          @aimed_segment = @segment
          length = @path.segment_length(@segment)
          return head_nowhere if length.zero?

          @heading_x = (@path.x_at(@segment + 1) - @path.x_at(@segment)) / length
          @heading_y = (@path.y_at(@segment + 1) - @path.y_at(@segment)) / length
        end

        def head_nowhere
          @aimed_segment = nil
          @heading_x = 0.0
          @heading_y = 0.0
        end

        def place_at(waypoint)
          node.x = @path.x_at(waypoint)
          node.y = @path.y_at(waypoint)
        end
      end
    end
  end
end
