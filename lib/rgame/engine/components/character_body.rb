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

        def collision_box
          @collision_box ||= Engine::CollisionBox.bottom_anchored(
            sprite_width: node.width, sprite_height: node.height,
            width: @feet_width, height: @feet_height
          )
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
      end
    end
  end
end
