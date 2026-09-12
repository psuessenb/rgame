# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What every component that moves its node has in common: a step computed some way
      # of its own, landing either straight on the node or against whatever may stop it.
      # CharacterBody, Velocity and PathFollow are the three, and they are three classes
      # because walking an intent, integrating a velocity and following a path are three
      # different jobs. What they share is what happens *after* a step is computed, and
      # that is this class.
      #
      # A mover fills in one private hook, `take_step(dt)`, and calls `apply_move(dx, dy)`
      # from it. `update` is not for overriding: it opens the step, calls the hook and
      # reports what stopped being in the way, so no mover can forget either edge.
      #
      # **Why a base class, and not a sibling component or a Node2D method.** A separate
      # `Blocking` component that movers write through was tried, and it is order-dependent:
      # closing the step has to happen after the mover's step, and a sibling can only do
      # that from its own `update`, which runs wherever it sits in the component list — two
      # add orders fired on_unblocked on two different ticks. A `Node2D#move_by` owning
      # `blocked_by` is order-free, but puts collision into the base of every node, HUDs and
      # menus included. A base class is order-free and touches only what moves.
      #
      # ## What stops a step is declared, not subclassed
      #
      # `blocked_by:` lists what a step may not pass through, and the default is nothing:
      # the mover writes the node's position directly and needs no collider and no system
      # on the scene. That free step is not quite free: `update` → `take_step` →
      # `apply_move` is one dispatch more than a component writing `node.x` itself, which
      # measured about 12% on a bare Velocity step (tens of nanoseconds). Inlining the free
      # write into each subclass wins it back, at the cost of every mover copying
      # `apply_move`'s free branch and reading this class's ivars — not taken.
      #
      #   Velocity.new(vx: 120)                                    # flies wherever it points
      #   Velocity.new(vx: 120, blocked_by: [:wall])                # stops flush against a :wall collider
      #   CharacterBody.new(speed: 80, blocked_by: [:tiles])        # slides along the map's solid tiles
      #   CharacterBody.new(speed: 80, blocked_by: %i[tiles npc])   # ...and does not walk through NPCs
      #   CharacterBody.new(speed: 80, blocked_by: %i[npc bounds])  # ...and cannot leave the world
      #
      # Two names are reserved: **`:tiles`** is the scene's TileWorld, and **`:bounds`** is the
      # edge of the region the scene's WorldBounds describes. **Every other name is a collider
      # layer**, resolved against the scene's CollisionWorld: a mover declaring `:npc` is
      # stopped by any BoxCollider whose `layer` is `:npc`, flush against its edge, exactly the
      # way a solid tile stops it. A layer that is empty, or whose colliders all leave, is not
      # an error — the declaration says what *may* stop this mover, not what does.
      #
      # `:bounds` is declared rather than automatic, and a mover that does not declare it
      # leaves the world. Stopping at the edge is one of three responses to it, beside
      # ScreenWrap and DespawnOffscreen, and a node may carry only one — declaring `:bounds`
      # beside either raises at attach (WorldBounds.one_response!).
      #
      # Blocking is box-versus-box: a CircleCollider on a declared layer reports its contacts
      # as usual and stops nothing, and a mover that declares anything needs a BoxCollider of
      # its own.
      #
      # The two are not alternatives. `blocked_by` and `on_hit` answer different questions —
      # what may I pass through, and what am I touching — and a flush-blocked pair does not
      # overlap, so a mover that must both stop and react needs both.
      #
      # A declaration this scene cannot honour raises at on_attach rather than quietly
      # falling back to free movement — a mover passing through walls looks like a collision
      # bug, and the cause would be a scene three files away that never mounted the system.
      #
      # ## A blocked step slides
      #
      # Where a step lands is decided by Engine::CollisionSystem, which resolves X and then Y,
      # so a diagonal push into a wall keeps the component that is still free. That is the
      # right feel for a character and the wrong one for a bullet — and a bullet does not
      # need a different resolver for it, it needs to react: `on_blocked` fires on the step
      # it hits, and a bullet that queue-frees itself there is gone before it slides anywhere.
      # One that bounces reads which axis was stopped and turns that half of its velocity:
      #
      #   velocity = Velocity.new(vx: 120, vy: 80, blocked_by: %i[wall bounds])
      #   velocity.on_blocked do |_by, axis|
      #     velocity.vx = -velocity.vx unless axis == :y
      #     velocity.vy = -velocity.vy unless axis == :x
      #   end
      #
      # ## The shape has one owner, and it is not this
      #
      # A blocked step is resolved against the node's **collider** box, read from the
      # sibling BoxCollider (FeetCollider is the one a walking character wants). The box is
      # therefore given once, to the component that *is* a shape, and the same rectangle both
      # stops the step and reports contacts — there is nothing to hand from one component to
      # the other and nothing to keep in sync.
      class Mover < Engine::Component
        # The two edges of being stopped: on_blocked on the step this mover starts being
        # stopped by something, on_unblocked on the step it stops. Each fires once per
        # blocker, so a handler may spend a life or play a sound — the spiky ball that
        # both stops the player and hurts them is the two signals plus an on_hit.
        #
        # The listener gets whatever stopped the step and reads its #layer and #node, so
        # one handler covers every kind: a collider answers its own layer and its owning
        # node, the map's solid tiles answer :tiles and nil (Engine::TileBlockers::TILES),
        # and the world's edge answers :bounds and nil.
        #
        # on_blocked also says which axis of the step it stopped — :x, :y, or :both when one
        # blocker stopped the two at once — which is what a bounce branches on. A listener
        # that names only the blocker, `{ |by| ... }`, never sees it: a block drops the
        # arguments it does not name.
        #
        # on_unblocked has no axis, because what ends is a blocker stopping this mover, not
        # an axis. A blocker that stopped x on one step and y on the next was in the way the
        # whole time, and ends once.
        signal :on_blocked, Engine::Signal.define(:by, :axis)
        signal :on_unblocked, Engine::Signal.define(:by)

        # The two blocker names that are not collider layers: the scene's solid tiles, and
        # the edge of the world.
        TILES  = :tiles
        BOUNDS = :bounds
        RESERVED = [TILES, BOUNDS].freeze

        def initialize(blocked_by: [])
          super()
          # Array() so a single blocker reads as `blocked_by: :tiles` too. Built once at
          # construction; nothing on a frame looks at this list.
          @blocked_by = Array(blocked_by)
          @collider = nil
          @collision = nil
          @last_move_blocked = false
          # What stopped this mover, this step and last — the same two-array swap that turns
          # a per-step overlap into on_hit / on_separated, pointed at blockers instead.
          @stopped_by = Engine::ContactSet.new
        end

        # Resolve each declared blocker and build the resolver that runs them, once the node
        # is in the tree and both the scene's systems and this node's other components are
        # reachable.
        #
        # **The resolver is the mover's own**, rather than something borrowed off the scene.
        # It has to be: a source over other colliders holds this mover's collider and this
        # mover's layer list, so two movers declaring different `blocked_by` cannot share
        # one — and a scene may mount a CollisionWorld with no TileWorld at all, so there is
        # not always a scene-level resolver to borrow in the first place. What is shared is
        # what can be: the TileWorld's own source is borrowed, not rebuilt.
        #
        # Nothing here runs on a frame. The list is built once, and a step only walks it.
        #
        # A subclass that needs its own attach work calls `super` first — PathFollow does,
        # to place its node before walking.
        def on_attach
          # A pooled mover coming back from the dead would otherwise still be holding
          # whatever stopped it when it was freed, and would report one spurious
          # on_unblocked on its first step — the rule CollisionWorld#register follows for
          # contacts, for the same reason.
          @stopped_by.reset
          return if @blocked_by.empty?

          WorldBounds.one_response!(node) if blocked_by?(BOUNDS)

          # Every blocker resolves the same rectangle, so the collider is required whatever
          # was declared — and required before the systems, because a missing shape is the
          # likelier mistake of the two.
          @collider = require_sibling(BoxCollider)
          @collision = Engine::CollisionSystem.new(blockers: resolve_blockers)
        end

        # Take this step, then report what stopped being in the way.
        #
        # **The set advances once per update, not once per apply_move**, and that is what
        # makes standing still an unblocking: a mover that stops pushing into something
        # records nothing this step, so what it was pressing against ends and on_unblocked
        # fires. It also keeps the bookkeeping where a subclass cannot lose it — a mover
        # that resolves a step in several moves, or overrides apply_move, still opens the
        # step once and still reports its edges.
        def update(dt)
          return take_step(dt) unless @collision

          @stopped_by.begin_frame
          take_step(dt)
          @stopped_by.each_ended { on_unblocked_signal.emit(it) }
        end

        # Whether `name` is one of the things this mover declared it may be stopped by.
        def blocked_by?(name) = @blocked_by.include?(name)

        # Where a step lands. Public, and kept separate from `take_step`, so a mover that
        # resolves a step some other way — a platformer's CharacterBody, with gravity and a
        # jump — inherits everything around it rather than restating it.
        #
        # The branch is on what was declared rather than on a subclass: an unblocked mover
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
          # update: a mover that resolves a step in several moves records what stopped each
          # of them, and one that does not move at all records nothing.
          blocked_x = @collision.blocked_x
          blocked_y = @collision.blocked_y
          @last_move_blocked = !(blocked_x.nil? && blocked_y.nil?)
          if blocked_x.equal?(blocked_y)
            record_blocker(blocked_x, :both)
          else
            record_blocker(blocked_x, :x)
            record_blocker(blocked_y, :y)
          end
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
        # BoxCollider#aabb_x reports `node.world_x + box.offset_x`. A mover under an offset
        # ancestor that reported its local position would resolve against a map shifted by
        # the ancestor, and would be compared against other colliders in a different frame
        # entirely.
        #
        # Writing goes back through Node2D#world_x= / #world_y=, which turn the resolved world
        # position into the local one the node actually lives in.
        #
        # A mover under a rotated ancestor is still outside what an axis-aligned box supports
        # (docs/api/components.md: a thing that spins wants a circle) — the position it lands
        # at is exact, but the box it was resolved with does not turn with the frame.
        def collision_box = @collider.box
        def x = node.world_x
        def y = node.world_y

        def x=(value)
          node.world_x = value
        end

        def y=(value)
          node.world_y = value
        end

        private

        # The blank hook: compute this step and hand it to apply_move. Empty here, so a
        # Mover on its own is a node that stands still.
        def take_step(_dt) = nil

        # Whether anything was declared — for a subclass whose free path is not a delta,
        # the way PathFollow places its node absolutely when nothing can stop it.
        def blocking? = !@collision.nil?

        # Whether either axis of the most recent apply_move was stopped short.
        def last_move_blocked? = @last_move_blocked

        # Record what stopped one axis, and fire the starting edge for a blocker that was
        # not already stopping this mover. `started?` is asked before the add and reads only
        # last step's list, exactly as CollisionWorld does with a contact, so the guard
        # gives the same answer either side of it.
        #
        # A step stopped on both axes by the *same* blocker arrives here once, as :both.
        # Only the map does that: CollisionSystem snaps x flush before it resolves y, so a
        # single collider no longer overlaps on the far axis, while every solid tile reports
        # the one Engine::TileBlockers::TILES — so a diagonal push into an inside corner of
        # wall tiles is stopped on both axes by one blocker.
        #
        # The `touching?` check is for a mover that resolves a step in several moves: what
        # stopped the first of them is not reported again by the second.
        def record_blocker(by, axis)
          return if by.nil? || @stopped_by.touching?(by)

          started = @stopped_by.started?(by)
          @stopped_by.add(by)
          on_blocked_signal.emit(by:, axis:) if started
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
                  raise("#{mover_name} is blocked_by :tiles, and the scene has no TileWorld " \
                        'system to resolve a step against. Mount one, or drop blocked_by for ' \
                        'a mover with nothing to collide with.')
          world.blockers
        end

        def bounds_blockers
          bounds = node.system(WorldBounds) ||
                   raise("#{mover_name} is blocked_by :bounds, and the scene has no world " \
                         'bounds to stop at. Mount a World (or a TileWorld, which is one), or ' \
                         'drop :bounds for a mover that may leave the world.')
          Engine::BoundsBlockers.new(bounds: bounds)
        end

        def actor_blockers(layers)
          world = node.system(CollisionWorld) ||
                  raise("#{mover_name} is blocked_by #{layers.map(&:inspect).join(', ')}, which " \
                        'names collider layers, and the scene has no CollisionWorld system to ' \
                        'find them in. Mount one, or drop those names for a mover that only ' \
                        'the map stops.')
          Engine::ActorBlockers.new(world: world, owner: @collider, layers: layers)
        end

        # The class's own short name, so the message names the component the game wrote. An
        # anonymous subclass has no name, and says what it is instead.
        def mover_name = self.class.name&.split('::')&.last || self.class.inspect
      end
    end
  end
end
