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
