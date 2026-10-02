# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Picks a node for the owning node to aim at. Each update it asks the scene's
      # CollisionWorld for a collider around its node's world origin, and #target is that
      # collider's node, or nil. The owner reads it to act: Targeting only selects, and
      # never moves or shoots.
      #
      #   turret.add_component(Targeting.new(range: 120, having: Hostile))
      #
      # **It picks by a component on the target, never by its layer.** A layer says what
      # a node collides as, and a node has one. What the owner may do to it is a component,
      # and a node can hold many. `having` matches by `is_a?`, as `get_component` does, so
      # a module such as Collider matches every node holding one. A turret that aims at
      # some nodes and not others gives them a component of the game's own, even an empty
      # one. It never picks its own node.
      #
      # The CollisionWorld is the broadphase every collider registers with, so targeting
      # keeps no candidate list of its own.
      #
      # Policies say how to choose among the candidates in range:
      #   - :nearest, the closest candidate, and the default.
      #   - :facing, the closest candidate in front of the node, by the node's Facing. A
      #     candidate behind or to the side is never the target, however near it is, so
      #     the target is nil when nothing in range is in front. Attach raises for a node
      #     with no Facing.
      # More policies, such as furthest along a path, arrive with the state they need.
      class Targeting < Engine::Component
        POLICIES = %i[nearest facing].freeze

        # `having` is the component class, or module, a target's node must hold. Raises
        # ArgumentError for an unknown policy, and for a `having` that is not a Module.
        def initialize(range:, having:, policy: :nearest)
          super()
          raise ArgumentError, "unknown targeting policy #{policy.inspect}" unless POLICIES.include?(policy)
          unless having.is_a?(Module)
            raise ArgumentError, "having is the component class a target holds, not #{having.inspect}"
          end

          @rgame_range = range
          @rgame_policy = policy
          @rgame_having = having
          @rgame_target = nil
        end

        # The chosen node, or nil when nothing is in range. Refreshed every update.
        sealed_reader :target

        # Pull the broadphase once it's reachable (scene scope, resolved up the tree), and,
        # under `:facing`, the node's Facing.
        def _attach
          @rgame_world = node.system(CollisionWorld)
          @rgame_facing = (require_sibling(Facing) if @rgame_policy == :facing)
        end

        def _update(_dt)
          collider = pick
          @rgame_target = collider&.node
        end

        private

        def pick
          @rgame_world.nearest(node.world_x, node.world_y, @rgame_range,
                               having: @rgame_having, except: node, in_front_of: @rgame_facing)
        end
      end
    end
  end
end
