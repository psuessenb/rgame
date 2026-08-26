# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A CharacterBody bound to a tile map: every step is resolved against the scene's
      # TileWorld, so the actor slides along walls and stays inside the map instead of
      # walking wherever the intent points.
      #
      # Everything about the intent — writing it, reading it back as the facing, scaling
      # it by the speed — is inherited. All that is added here is where a step lands
      # (`apply_move`), the box it lands with, and the actor adapter the collision system
      # drives. Siblings that pull `node.get_component(CharacterBody)` — PlayerController,
      # WanderController, AnimatedSprite — find one of these just as readily, because
      # Node2D#get_component matches with `is_a?`.
      #
      # The feet box is built from the node's dimensions (which AnimatedSprite sets from the
      # sprite frame), not a passed-in sprite size — `feet_width`/`feet_height` are the box,
      # centred horizontally and anchored to the node's bottom. It's built lazily on first
      # use (the first update, after every on_attach has run), so the order components are
      # added in doesn't matter. A body with no sprite must set the node's width/height.
      class TileCharacterBody < CharacterBody
        def initialize(feet_width:, feet_height:, speed:)
          super(speed: speed)
          @feet_width = feet_width
          @feet_height = feet_height
          @collision_box = nil
        end

        # The feet box, derived from the node's sprite size and memoised.
        #
        # **Only valid once the node is in the tree**, and it says so rather than
        # letting you find out later. The size comes from AnimatedSprite#on_attach,
        # so a read from a constructor sees a 0x0 node and bakes a box anchored to
        # nothing — permanently, because this memoises, and for the collision
        # system too, because it reads the same box. The symptom is an actor that
        # walks through walls it should not, a long way from the call that caused
        # it. Guarding costs one comparison, once.
        def collision_box
          @collision_box ||= build_collision_box
        end

        # The TileWorld is a scene-scoped system, reachable once we're in the tree. Missing
        # it is fatal rather than a silent fall back to free movement: an actor that walks
        # through walls looks like a collision bug, and the cause would be a scene three
        # files away that never mounted the system.
        def on_attach
          @world = node.system(TileWorld)
          return if @world

          raise 'TileCharacterBody needs a TileWorld system on the scene. Mount one, or use ' \
                'CharacterBody for an actor with nothing to collide with.'
        end

        def apply_move(dx, dy) = @world.move(self, dx, dy)

        # CollisionSystem#move drives an "actor" through x/y/collision_box and writes the
        # resolved position back — back those by the owning node's transform.
        def x = node.x
        def y = node.y

        def x=(value)
          node.x = value
        end

        def y=(value)
          node.y = value
        end

        private

        def build_collision_box
          if node.width.zero? || node.height.zero?
            raise "collision_box needs the node's sprite size, but it is " \
                  "#{node.width}x#{node.height}. AnimatedSprite sets that when it attaches, so " \
                  'read this after the node is in the tree, not while building it.'
          end

          Engine::CollisionBox.bottom_anchored(
            sprite_width: node.width, sprite_height: node.height,
            width: @feet_width, height: @feet_height
          )
        end
      end
    end
  end
end
