# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Walking movement for a tile-bound actor (player or NPC). A controller writes a
      # per-step movement intent — each axis in -1..1 — and this component turns it into
      # a real move each update, resolved against the scene's TileWorld so the actor
      # slides along walls and stays inside the map. Distinct from Velocity (which
      # integrates blindly): here every step is collision-checked.
      #
      # The intent doubles as the facing for AnimatedSprite (move_x / move_y readers), so
      # a character is just CharacterBody + a controller + AnimatedSprite.
      #
      # The feet box is built from the node's dimensions (which AnimatedSprite sets from the
      # sprite frame), not a passed-in sprite size — `feet_width`/`feet_height` are the box,
      # centred horizontally and anchored to the node's bottom. It's built lazily on first
      # use (the first update, after every on_attach has run), so the order components are
      # added in doesn't matter. A body with no sprite must set the node's width/height.
      class CharacterBody < Engine::Component
        attr_reader :move_x, :move_y

        def initialize(feet_width:, feet_height:, speed:)
          super()
          @feet_width = feet_width
          @feet_height = feet_height
          @speed = speed
          @move_x = 0.0
          @move_y = 0.0
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

        # The TileWorld is a scene-scoped system, reachable once we're in the tree.
        def on_attach = @world = node.system(TileWorld)

        # Set this step's movement intent; each axis is in -1..1.
        def set_intent(intent_x, intent_y)
          @move_x = intent_x
          @move_y = intent_y
        end

        def update(dt)
          return if @move_x.zero? && @move_y.zero?

          @world.move(self, @move_x * @speed * dt, @move_y * @speed * dt)
        end

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
