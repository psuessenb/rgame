# frozen_string_literal: true

module Engine
  module Components
    # Wraps an Engine::Pool of nodes and folds the tree bookkeeping into the frame tick:
    # `spawn` takes a node from the pool (recycled or freshly built) and adds it as a
    # child of the owner, and `update` returns freed nodes to the pool — so a game only
    # ever writes `pool.spawn` and the ordinary `node.queue_free`, never a hand-written
    # acquire/add/reclaim bridge. Pooled nodes are normal children, so the scene's usual
    # traversal updates and draws them; this component only manages their pool membership.
    #
    #   pool = add_component(Engine::Components::Pool.new { Enemy.new(path: @path) })
    #   pool.spawn                       # acquire + add as a child
    #   pool.spawn { |b| b.reset(x, y) } # reset before it enters the tree (projectiles)
    #   enemy.queue_free                 # → reclaimed back to the pool automatically
    #
    # Add it named (`as:`) like any component when a node needs more than one pool.
    class Pool < Engine::Component
      def initialize(&)
        super()
        @pool = Engine::Pool.new(&)
      end

      # Take a node from the pool, let the caller re-initialise it before it goes live
      # (optional block — runs before on_attach), and add it as a child of the owner.
      def spawn
        child = @pool.acquire
        yield child if block_given?
        node.add_node(child)
        child
      end

      # Ride the tick: return every freed pooled node to the free list, detaching any that
      # are still in the tree — so a queue_free elsewhere recycles with no game-side wiring.
      def update(_dt)
        @pool.reclaim_if do |child|
          next false unless child.freed?

          node.remove_node(child) # idempotent if the deferred-free sweep already detached it
          true
        end
      end

      def size = @pool.size

      # True when no spawned node is currently live (all reclaimed) — a scene reads this to
      # tell when a wave/round has been fully cleared.
      def empty? = @pool.empty?
    end
  end
end
