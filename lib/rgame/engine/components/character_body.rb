# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Direct, per-step movement for a walking actor (player or NPC). A controller writes a
      # movement intent — each axis in -1..1 — and this component turns it into a real move
      # each update, at a fixed speed and with no inertia (unlike Velocity, which integrates
      # a velocity the controller sets, and ThrustController, which accelerates one).
      #
      # The intent doubles as the facing for AnimatedSprite (move_x / move_y readers), so
      # a character is just CharacterBody + a controller + AnimatedSprite.
      #
      # ## What stops a step is declared, not subclassed
      #
      # `blocked_by:` lists what a step may not pass through, and the default is nothing:
      # the body moves the node freely and needs no sprite, no dimensions, no collider and
      # no system on the scene — an actor in a world with nothing to bump into.
      #
      #   CharacterBody.new(speed: 80)                       # walks wherever the intent points
      #   CharacterBody.new(speed: 80, blocked_by: [:tiles])  # slides along the map's solid tiles
      #
      # `:tiles` is the scene's TileWorld, and it is the only blocker there is today. Actors
      # that must notice each other carry a collider each and read its on_hit; that reports a
      # contact without stopping anyone.
      #
      # A declaration this scene cannot honour raises at on_attach rather than quietly
      # falling back to free movement — an actor walking through walls looks like a
      # collision bug, and the cause would be a scene three files away that never mounted
      # the system.
      #
      # ## The shape has one owner, and it is not this
      #
      # A blocked step is resolved against the node's **collider** box, read from the
      # sibling BoxCollider (FeetCollider is the one a walking character wants). The feet
      # box is therefore given once, to the component that *is* a shape, and the same
      # rectangle both stops the step and reports contacts — there is nothing to hand from
      # one component to the other and nothing to keep in sync.
      class CharacterBody < Engine::Component
        # The one blocker name that is not a collider layer: the scene's solid tiles.
        TILES = :tiles

        attr_reader :move_x, :move_y

        def initialize(speed:, blocked_by: [])
          super()
          @speed = speed
          # Array() so a single blocker reads as `blocked_by: :tiles` too. Built once at
          # construction; nothing on a frame looks at this list.
          @blocked_by = Array(blocked_by)
          @move_x = 0.0
          @move_y = 0.0
          @collider = nil
          @tile_world = nil
        end

        # Resolve each declared blocker, once the node is in the tree and both the scene's
        # systems and this node's other components are reachable.
        def on_attach
          return if @blocked_by.empty?

          # Every blocker resolves the same rectangle, so the collider is required whatever
          # was declared — and required before the systems, because a missing shape is the
          # likelier mistake of the two.
          @collider = require_sibling(BoxCollider)
          @blocked_by.each { |blocker| resolve_blocker(blocker) }
        end

        # Set this step's movement intent; each axis is in -1..1.
        def set_intent(intent_x, intent_y)
          @move_x = intent_x
          @move_y = intent_y
        end

        def update(dt)
          return if @move_x.zero? && @move_y.zero?

          apply_move(@move_x * @speed * dt, @move_y * @speed * dt)
        end

        # Where a step lands. Kept separate from `update` so a body that resolves a step
        # some other way — a platformer's, with gravity and a jump — inherits the intent,
        # the speed and the "don't bother when standing still" check rather than restating
        # them.
        #
        # The branch is on what was declared rather than on a subclass: an unblocked body
        # writes straight to the node, and a blocked one hands *itself* to the tile world
        # as the actor the resolver drives (see the adapter below).
        def apply_move(dx, dy)
          return @tile_world.move(self, dx, dy) if @tile_world

          node.x += dx
          node.y += dy
        end

        # The actor adapter CollisionSystem#move drives: it reads x/y/collision_box, works
        # out where the step lands, and writes the resolved position back. x and y are the
        # owning node's, and the box is the sibling collider's — the node's one shape, so
        # retuning `collider.box` retunes what a step collides with.
        def collision_box = @collider.box
        def x = node.x
        def y = node.y

        def x=(value)
          node.x = value
        end

        def y=(value)
          node.y = value
        end

        private

        def resolve_blocker(blocker)
          unless blocker == TILES
            raise "CharacterBody is blocked_by #{blocker.inspect}, and :tiles is the only " \
                  'blocker there is. Two actors that must notice each other carry a collider ' \
                  'each and read its on_hit, which reports the contact without stopping ' \
                  'either of them.'
          end

          @tile_world = node.system(TileWorld) ||
                        raise('CharacterBody is blocked_by :tiles, and the scene has no ' \
                              'TileWorld system to resolve a step against. Mount one, or drop ' \
                              'blocked_by for an actor with nothing to collide with.')
        end
      end
    end
  end
end
