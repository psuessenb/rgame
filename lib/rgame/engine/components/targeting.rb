# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Picks a node for the owning node to aim at: each update it queries the scene's
      # CollisionWorld around the node's world origin and exposes the chosen target via
      # #target (the candidate's node, or nil). The owner reads it to act — Targeting only
      # selects, it never moves or shoots.
      #
      # The CollisionWorld it queries is the same broadphase every collider registers with,
      # so targeting needs no candidate list of its own. The `layer` restricts candidates
      # (pass :enemy to pick only colliders on that layer, not allies or projectiles).
      #
      # Policies (how to choose among the candidates in range):
      #   - :nearest — the closest candidate (the default; one broadphase nearest-lookup).
      # More policies (e.g. furthest-along-path) arrive with the state they need.
      class Targeting < Engine::Component
        POLICIES = %i[nearest].freeze

        def initialize(range:, policy: :nearest, layer: nil)
          super()
          raise ArgumentError, "unknown targeting policy #{policy.inspect}" unless POLICIES.include?(policy)

          @range = range
          @policy = policy
          @layer = layer
          @target = nil
        end

        # The chosen node, or nil when nothing is in range. Refreshed every update.
        attr_reader :target

        # Pull the broadphase once it's reachable (scene scope, resolved up the tree).
        def on_attach = @world = node.system(CollisionWorld)

        def update(_dt)
          collider = pick
          @target = collider&.node
        end

        private

        # Allocation-free: a symbol dispatch over a known-small policy set, each delegating
        # to an allocation-free CollisionWorld query.
        def pick
          case @policy
          when :nearest then @world.nearest(node.world_x, node.world_y, @range, layer: @layer)
          end
        end
      end
    end
  end
end
