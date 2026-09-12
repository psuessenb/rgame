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
      #   CharacterBody.new(speed: 80)                             # walks wherever the intent points
      #   CharacterBody.new(speed: 80, blocked_by: [:tiles])        # slides along the map's solid tiles
      #   CharacterBody.new(speed: 80, blocked_by: %i[tiles npc])   # ...and does not walk through NPCs
      #   CharacterBody.new(speed: 80, blocked_by: %i[npc bounds])  # ...and cannot leave the world
      #
      # Two names are reserved: **`:tiles`** is the scene's TileWorld, and **`:bounds`** is the
      # edge of the region the scene's WorldBounds describes. **Every other name is a collider
      # layer**, resolved against the scene's CollisionWorld: a body declaring `:npc` is stopped
      # by any BoxCollider whose `layer` is `:npc`, flush against its edge, exactly the way a
      # solid tile stops it. A layer that is empty, or whose colliders all leave, is not an
      # error — the declaration says what *may* stop this body, not what does.
      #
      # `:bounds` is declared rather than automatic, and a body that does not declare it walks
      # out of the world. That is the point: a game whose entities wrap or despawn at the edge
      # reads the same bounds through ScreenWrap and DespawnOffscreen, which act on the node
      # rather than on its box, and a clamp nobody asked for made those two misfire. See
      # Engine::BoundsBlockers.
      #
      # Blocking is box-versus-box: a CircleCollider on a declared layer reports its contacts
      # as usual and stops nothing.
      #
      # The two are not alternatives. `blocked_by` and `on_hit` answer different questions —
      # what may I walk through, and what am I touching — and a flush-blocked pair does not
      # overlap, so a body that must both stop and react needs both.
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
        # The two edges of being stopped: on_blocked on the step this body starts being
        # stopped by something, on_unblocked on the step it stops. Each fires once per
        # blocker, so a handler may spend a life or play a sound — the spiky ball that
        # both stops the player and hurts them is the two signals plus an on_hit.
        #
        # The listener gets whatever stopped the step and reads its #layer and #node, so
        # one handler covers every kind: a collider answers its own layer and its owning
        # node, the map's solid tiles answer :tiles and nil (Engine::TileBlockers::TILES),
        # and the world's edge answers :bounds and nil.
        signal :on_blocked, Engine::Signal.define(:by)
        signal :on_unblocked, Engine::Signal.define(:by)

        # The two blocker names that are not collider layers: the scene's solid tiles, and
        # the edge of the world.
        TILES  = :tiles
        BOUNDS = :bounds
        RESERVED = [TILES, BOUNDS].freeze

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
          @collision = nil
          # What stopped this body, this step and last — the same two-array swap that turns
          # a per-step overlap into on_hit / on_separated, pointed at blockers instead.
          @stopped_by = Engine::ContactSet.new
        end

        # Resolve each declared blocker and build the resolver that runs them, once the node
        # is in the tree and both the scene's systems and this node's other components are
        # reachable.
        #
        # **The resolver is the body's own**, rather than something borrowed off the scene.
        # It has to be: a source over other actors holds this body's collider and this
        # body's layer list, so two bodies declaring different `blocked_by` cannot share
        # one — and four scenes in this repository mount a CollisionWorld with no TileWorld
        # at all, so there is no scene-level resolver to borrow in the first place. What is
        # shared is what can be: the TileWorld's own source is borrowed, not rebuilt.
        #
        # Nothing here runs on a frame. The list is built once, and a step only walks it.
        def on_attach
          # A pooled body coming back from the dead would otherwise still be holding
          # whatever stopped it when it was freed, and would report one spurious
          # on_unblocked on its first step — the rule CollisionWorld#register follows for
          # contacts, for the same reason.
          @stopped_by.reset
          return if @blocked_by.empty?

          # Every blocker resolves the same rectangle, so the collider is required whatever
          # was declared — and required before the systems, because a missing shape is the
          # likelier mistake of the two.
          @collider = require_sibling(BoxCollider)
          @collision = Engine::CollisionSystem.new(blockers: resolve_blockers)
        end

        # Set this step's movement intent; each axis is in -1..1.
        def set_intent(intent_x, intent_y)
          @move_x = intent_x
          @move_y = intent_y
        end

        # Take this step, then report what stopped being in the way.
        #
        # **The set advances once per update, not once per apply_move**, and that is what
        # makes standing still an unblocking: a body that stops pushing into something
        # records nothing this step, so what it was pressing against ends and on_unblocked
        # fires. It also keeps the bookkeeping where a subclass cannot lose it — a body
        # that overrides apply_move to resolve a step some other way still opens the step
        # and still reports its edges.
        def update(dt)
          return take_step(dt) unless @collision

          @stopped_by.begin_frame
          take_step(dt)
          @stopped_by.each_ended { on_unblocked_signal.emit(it) }
        end

        # Where a step lands. Kept separate from `update` so a body that resolves a step
        # some other way — a platformer's, with gravity and a jump — inherits the intent,
        # the speed and the "don't bother when standing still" check rather than restating
        # them.
        #
        # The branch is on what was declared rather than on a subclass: an unblocked body
        # writes straight to the node, and a blocked one hands *itself* to its resolver as
        # the actor being moved (see the adapter below).
        def apply_move(dx, dy)
          unless @collision
            node.x += dx
            node.y += dy
            return
          end

          @collision.move(self, dx, dy)
          # Read straight after the move that set them, rather than once at the end of the
          # update: a body that resolves a step in several moves records what stopped each
          # of them, and one that does not move at all records nothing.
          record_blocker(@collision.blocked_x)
          record_blocker(@collision.blocked_y)
        end

        # The actor adapter CollisionSystem#move drives: it reads x/y/collision_box, works
        # out where the step lands, and writes the resolved position back. The box is the
        # sibling collider's — the node's one shape, so retuning `collider.box` retunes
        # what a step collides with.
        #
        # ## The adapter is in world space
        #
        # x and y are the node's **world** position, because that is the space everything
        # else about collision is already in: the tile grid is a world-coordinate grid, and
        # BoxCollider#aabb_x reports `node.world_x + box.offset_x`. A body under an offset
        # ancestor that reported its local position would resolve against a map shifted by
        # the ancestor, and would be compared against other colliders in a different frame
        # entirely.
        #
        # Writing goes back through the node's *local* position as a translation — move the
        # node by however far the resolved position is from where it is now — because the
        # node lives in its parent's frame and only the parent knows how to get there.
        #
        # **The limit, deliberately not a raise:** that translation is exact for an
        # unrotated ancestor chain and approximate under a rotated one, since a world-space
        # delta is applied to local axes the rotation has turned. An actor under a rotated
        # ancestor is already outside what an axis-aligned box supports (docs/api/components.md:
        # a thing that spins wants a circle). A guard would only catch an ancestor that was
        # rotated at attach and miss one that starts rotating later, which is worse than a
        # sentence that is always true.
        def collision_box = @collider.box
        def x = node.world_x
        def y = node.world_y

        def x=(value)
          node.x += value - node.world_x
        end

        def y=(value)
          node.y += value - node.world_y
        end

        private

        def take_step(dt)
          return if @move_x.zero? && @move_y.zero?

          apply_move(@move_x * @speed * dt, @move_y * @speed * dt)
        end

        # Record what stopped one axis, and fire the starting edge for a blocker that was
        # not already stopping this body. `started?` is asked before the add and reads only
        # last step's list, exactly as CollisionWorld does with a contact, so the guard
        # gives the same answer either side of it.
        #
        # The `touching?` check is what makes a step stopped on both axes by the *same*
        # blocker — a box walking diagonally into one wide collider — fire once.
        def record_blocker(by)
          return if by.nil? || @stopped_by.touching?(by)

          started = @stopped_by.started?(by)
          @stopped_by.add(by)
          on_blocked_signal.emit(by) if started
        end

        # One source per *kind* of blocker rather than per declared name: every collider
        # layer named goes into a single ActorBlockers, since one broadphase query answers
        # for all of them at once.
        def resolve_blockers
          sources = []
          sources << tile_blockers if @blocked_by.include?(TILES)
          sources << bounds_blockers if @blocked_by.include?(BOUNDS)
          layers = @blocked_by.reject { RESERVED.include?(it) }
          sources << actor_blockers(layers) unless layers.empty?
          sources
        end

        def tile_blockers
          world = node.system(TileWorld) ||
                  raise('CharacterBody is blocked_by :tiles, and the scene has no TileWorld ' \
                        'system to resolve a step against. Mount one, or drop blocked_by for ' \
                        'an actor with nothing to collide with.')
          world.blockers
        end

        def bounds_blockers
          bounds = node.system(WorldBounds) ||
                   raise('CharacterBody is blocked_by :bounds, and the scene has no world ' \
                         'bounds to stop at. Mount a World (or a TileWorld, which is one), or ' \
                         'drop :bounds for an actor that may leave the world.')
          Engine::BoundsBlockers.new(bounds: bounds)
        end

        def actor_blockers(layers)
          world = node.system(CollisionWorld) ||
                  raise("CharacterBody is blocked_by #{layers.map(&:inspect).join(', ')}, which " \
                        'names collider layers, and the scene has no CollisionWorld system to ' \
                        'find them in. Mount one, or drop those names for an actor that only ' \
                        'the map stops.')
          Engine::ActorBlockers.new(world: world, owner: @collider, layers: layers)
        end
      end
    end
  end
end
