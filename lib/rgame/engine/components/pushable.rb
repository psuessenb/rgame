# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A mover with no step of its own: it moves only when something pushes it.
      #
      #   crate.add_component(BoxCollider.new(width: 16, height: 16, layer: :crate))
      #   crate.add_component(Pushable.new(blocked_by: %i[tiles wall crate hero]))
      #
      #   hero.add_component(CharacterBody.new(speed: 80, blocked_by: %i[tiles crate],
      #                                        pushes: [:crate]))
      #
      # A mover declaring the crate's layer in `pushes:` calls #push with what is left of
      # a step the crate stopped. The crate resolves that push against its own
      # `blocked_by:`, as any mover resolves a step, so it stops against a wall, a solid
      # tile or another crate. How far it went is how far the pusher follows. Mover's
      # header has the rest of the rule.
      #
      # **Put the pushers' layer in `blocked_by:`.** Two heroes pushing one crate from
      # opposite sides then hold it still. A crate that is not stopped by heroes is pushed
      # into the one on the far side, and an overlap that already exists stops nobody.
      #
      # `pushes:` makes this crate push the crates behind it, up to Mover::PUSH_DEPTH in a
      # row. Its `on_blocked` and `on_unblocked` fire as any mover's do, and Mover#stopped?
      # says whether the last #push was cut short.
      #
      # It needs a BoxCollider, because that is what a pusher runs into, and the scene's
      # CollisionWorld, because that is where a pusher finds it. Both raise at attach when
      # missing.
      class Pushable < Mover
        def initialize(blocked_by:, pushes: [])
          super
          @rgame_pushed_x = 0.0
          @rgame_pushed_y = 0.0
        end

        # How far the last #push moved the node, on each axis, in world pixels.
        sealed_reader :pushed_x, :pushed_y

        # The BoxCollider a pusher runs into.
        sealed_reader :collider

        def _attach
          super
          @rgame_collider ||= require_sibling(BoxCollider)
          @rgame_world = node.system(CollisionWorld) ||
                         raise('Pushable is found by the movers that push it through the scene\'s ' \
                               'CollisionWorld, and the scene has none. Mount one.')
        end

        # A pushed crate has no step of its own. Its pushes arrive during other movers'
        # updates, before or after this one, so the step it reports blockers over runs from
        # one of its updates to the next. Each pusher updates once in that span, whatever
        # the order, so a crate held against a wall is blocked once rather than every tick.
        def _update(_dt)
          return unless blocking?

          close_step
          open_step
        end

        # Move by (dx, dy), as far as `blocked_by:` allows, and record how far that was in
        # #pushed_x and #pushed_y. `by` is the node pushing or pulling, which this neither
        # pushes back nor is stopped by, and `depth` is how many crates stand between it and
        # the first pusher.
        #
        # Movers call this through `pushes:`; a game may call it too, for a crate a spell
        # shoves. It re-indexes the collider in the CollisionWorld straight away, so a mover
        # resolving later in the same step meets the crate where it now is.
        def push(dx, dy, by: nil, depth: 1)
          from_x = x
          from_y = y
          box_x = @rgame_collider.aabb_x
          box_y = @rgame_collider.aabb_y
          @rgame_pushed_by = by
          @rgame_push_depth = depth
          @rgame_actor_source&.passing = by
          apply_move(dx, dy)
          @rgame_world.reindex(@rgame_collider, box_x, box_y, @rgame_collider.aabb_w, @rgame_collider.aabb_h)
          @rgame_pushed_x = x - from_x
          @rgame_pushed_y = y - from_y
        ensure
          @rgame_actor_source&.passing = nil
          @rgame_pushed_by = nil
          @rgame_push_depth = 0
        end
      end
    end
  end
end
