# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # How big the world is — the contract, not an implementation.
      #
      # Two systems answer it: `World` below, which is nothing *but* the answer,
      # and `TileWorld`, which derives it from the map it parsed. A component
      # that needs bounds asks for the contract — `node.system(WorldBounds)` —
      # and gets whichever of the two the scene mounted. That works because
      # Node2D#get_component matches with `is_a?`, which matches an included
      # module as readily as a class.
      #
      # Naming the contract is what keeps the two from drifting: ScreenWrap does
      # not know which kind of world it is wrapping inside, and must not need to.
      #
      # ## The bounds are in world coordinates
      #
      # The world runs from (0, 0) to (world_width, world_height) in **world**
      # space — the space `Node2D#world_x` answers in, and the one the tile grid,
      # the collision world and the camera already use. So everything that
      # compares a node against these bounds compares `world_x`/`world_y`, never
      # the node's local `x`/`y`: an entity grouped under an offset container is
      # still inside the world when it is, whatever its position in the container.
      # spec/support/shared_examples/a_world_edge_response.rb holds every reader to it.
      module WorldBounds
        def world_width = raise(NotImplementedError, "#{self.class} must define #world_width")
        def world_height = raise(NotImplementedError, "#{self.class} must define #world_height")

        # The bounds a component should use: whatever it was handed, falling back
        # to the world system on `node` for either axis left nil. The single place
        # that fallback is written, so the components sharing it cannot drift.
        #
        # Call it from `on_attach`, not `initialize` — a node has no scene to ask
        # until it is in the tree, and a pooled entity is built long before it is.
        def self.resolve(node, width, height)
          return [width, height] if width && height

          bounds = node.system(self)
          if bounds.nil?
            raise 'no world bounds in scope: mount a World (or TileWorld) system on the scene, ' \
                  'or pass explicit width:/height:'
          end

          [width || bounds.world_width, height || bounds.world_height]
        end

        # Refuse a node carrying more than one response to the edge of the world:
        # ScreenWrap, DespawnOffscreen, or a Mover declaring `blocked_by: [:bounds]`.
        #
        # Stopping at the edge, wrapping past it and being freed beyond it are three
        # answers to one question, and no two of them mean anything together. Stop and
        # wrap disagree about where the node ends up; wrap and despawn race on which
        # margin is reached first; and the stop works on the collision box while the
        # other two test the node's origin, so a box with an offset holds the origin
        # just past the edge and the other response fires on a node that was held.
        # Rather than a rule each game has to remember, it raises.
        #
        # Every response calls this from its own on_attach, which is what makes it
        # order-free: a node assembled outside the tree already holds all its
        # components when the first attaches, and on a live node each attaches on
        # arrival, so the second response always finds the first.
        #
        # A pooled node re-attaches on every spawn, so this walks the components
        # without allocating, and builds a message only when it raises.
        def self.one_response!(node)
          first = nil
          node.components.each do |component|
            next unless edge_response?(component)
            next first = component if first.nil?

            raise "#{node.class} has two responses to the edge of the world: " \
                  "#{describe_response(first)} and #{describe_response(component)}. " \
                  'A node can stop at the edge, wrap past it or be freed beyond it, but ' \
                  'only one of those — keep the one this node is for.'
          end
        end

        def self.edge_response?(component)
          component.is_a?(ScreenWrap) || component.is_a?(DespawnOffscreen) ||
            (component.is_a?(Mover) && component.blocked_by?(Mover::BOUNDS))
        end
        private_class_method :edge_response?

        def self.describe_response(component)
          name = component.class.name&.split('::')&.last || component.class.inspect
          component.is_a?(Mover) ? "#{name} (blocked_by :bounds)" : name
        end
        private_class_method :describe_response
      end

      # The scene-scoped world: how big it is, and nothing else yet.
      #
      # A game whose world is a plain rectangle mounts one on its scene, and the
      # components that need bounds — ScreenWrap, DespawnOffscreen — find it
      # rather than having the numbers threaded through every constructor between
      # the scene and the entity. That threading is what this replaces, and it was
      # worse than it looks: a pooled entity is built outside the tree, so its
      # factory had to close over the size, and every scene above the factory had
      # to carry the size in order to build it.
      #
      # It is deliberately **not** the window size. The two coincide in a
      # single-screen game, which is exactly what makes the mistake easy to make
      # and hard to see: bind wrapping to the viewport and the world silently
      # changes shape when the window is resized, or when the screen is split and
      # each half is its own viewport. Ask `Viewports` (or the `View` a draw is
      # handed) how big the *window* is; ask this how big the *world* is.
      #
      # The bounds are immutable, which is what lets the components resolve them
      # once at attach rather than re-reading them every frame. A world that
      # genuinely changes size is a new scene.
      class World < Engine::Component
        include WorldBounds

        attr_reader :world_width, :world_height

        def initialize(width:, height:)
          super()
          @world_width = width
          @world_height = height
        end
      end
    end
  end
end
