# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What every component that moves its node has in common: a step computed some way
      # of its own, landing either straight on the node or against whatever may stop it.
      # CharacterBody, Velocity and PathFollow compute one each, and they are three classes
      # because walking an intent, integrating a velocity and following a path are three
      # different jobs. Pushable is the fourth mover, and computes none: it only moves when
      # pushed. What they share is what happens *after* a step is computed, and
      # that is this class.
      #
      # A mover fills in one private hook, `take_step(dt)`, and calls `apply_move(dx, dy)`
      # from it. `_update` is not for overriding: it opens the step, calls the hook and
      # reports what stopped being in the way, so no mover can forget either edge. Pushable
      # replaces it, because a crate's pushes arrive during other movers' updates.
      #
      # **Why a base class, and not a sibling component or a Node2D method.** A separate
      # `Blocking` component that movers write through was tried, and it is order-dependent:
      # closing the step has to happen after the mover's step, and a sibling can only do
      # that from its own `_update`, which runs wherever it sits in the component list — two
      # add orders fired on_unblocked on two different ticks. A `Node2D#move_by` owning
      # `blocked_by` is order-free, but puts collision into the base of every node, HUDs and
      # menus included. A base class is order-free and touches only what moves.
      #
      # ## What stops a step is declared, not subclassed
      #
      # `blocked_by:` lists what a step may not pass through, and the default is nothing:
      # the mover writes the node's position directly and needs no collider and no system
      # on the scene. That free step is not quite free: `_update` → `take_step` →
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
      # Three names are reserved: **`:tiles`** is the scene's TileWorld, **`:bounds`** is the
      # edge of the region the scene's WorldBounds describes, and **`:gaps`** is the edge of
      # the TileWorld's floor, which keeps the centre of the mover's box off the map's gap
      # tiles (Engine::GapBlockers). **Every other name is a collider layer**, resolved
      # against the scene's CollisionWorld: a mover declaring `:npc` is stopped by any
      # BoxCollider whose `layer` is `:npc`, flush against its edge, exactly the way a solid
      # tile stops it. A layer that is empty, or whose colliders all leave, is not
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
      # A declaration this scene cannot honour raises at _attach rather than quietly
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
      # ## What a step pushes is declared too
      #
      # `pushes:` names the collider layers a step moves rather than stops at. It parallels
      # `blocked_by:`, and every layer it names must be there too: a crate you can push is a
      # crate you cannot walk through, so a layer only in `pushes:` raises.
      #
      #   CharacterBody.new(speed: 80, blocked_by: %i[tiles crate], pushes: [:crate])
      #
      # A blocker on a pushed layer whose node holds a Pushable moves by what is left of the
      # step, on the axis it stopped, as far as its own `blocked_by:` lets it. Then this
      # mover resolves the rest of its step again, so it follows the crate that far. A crate
      # against a wall moves nothing, and the pusher stops flush with `on_blocked` as usual.
      # A crate that went the whole way stopped nothing, and nothing is reported.
      #
      # A mover that pushes resolves its two axes one after the other, rather than in one
      # CollisionSystem#move, so the crate it met on x has moved before y is resolved. A
      # mover declaring no `pushes:` takes exactly the step it always took.
      #
      # A Pushable may declare `pushes:` of its own, which is how a crate pushes a crate. The
      # chain stops at PUSH_DEPTH, and a pushed node never pushes the node that pushed it, so
      # a ring of crates ends rather than recursing.
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
        # the world's edge answers :bounds and nil, and the floor's edge :gaps and nil.
        #
        # on_blocked also says which axis of the step it stopped — :x, :y, or :both when one
        # blocker stopped the two at once — which is what a bounce branches on. A listener
        # that names only the blocker, `{ |by| ... }`, never sees it: a block drops the
        # arguments it does not name.
        #
        # on_unblocked has no axis, because what ends is a blocker stopping this mover, not
        # an axis. A blocker that stopped x on one step and y on the next was in the way the
        # whole time, and ends once.
        signal :blocked, :by, :axis
        signal :unblocked, :by

        TILES  = :tiles
        BOUNDS = :bounds
        GAPS   = :gaps
        RESERVED = [TILES, BOUNDS, GAPS].freeze

        PUSH_DEPTH = 4

        # `pushes:` raises ArgumentError for a layer missing from `blocked_by:`, and for
        # `:tiles`, `:bounds` or `:gaps`, which no step can move.
        def initialize(blocked_by: [], pushes: [])
          super()
          @blocked_by = Array(blocked_by)
          @pushes = Array(pushes)
          check_pushes
          @collider = nil
          @collision = nil
          @last_move_blocked = false
          @stopped_by = Engine::ContactSet.new
          @push_depth = 0
          @pushed_by = nil
          @grabbed = nil
          @actor_source = nil
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
        def _attach
          @stopped_by.reset
          return if @blocked_by.empty?

          WorldBounds.one_response!(node) if blocked_by?(BOUNDS)

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
        def _update(dt)
          return take_step(dt) unless @collision

          open_step
          take_step(dt)
          close_step
        end

        # Which way this mover's step is going, each axis in -1..1, and 0, 0 when it is not
        # trying to move. A facing rather than a velocity: a mover pressed into a wall still
        # heads into it, so an AnimatedSprite keeps walking against the wall rather than
        # standing. Each subclass answers from what its step is computed out of.
        def heading_x = 0.0
        def heading_y = 0.0

        # Whether `name` is one of the things this mover declared it may be stopped by.
        def blocked_by?(name) = @blocked_by.include?(name)

        # Whether a step moves colliders on layer `name` rather than stopping at them.
        def pushes?(name) = @pushes.include?(name)

        # The Pushable this mover drags with every step, or nil. Grab sets it from
        # `_control`, before the step that reads it.
        attr_accessor :grabbed

        # Where a step lands. Public, and kept separate from `take_step`, so a mover that
        # resolves a step some other way — a platformer's CharacterBody, with gravity and a
        # jump — inherits everything around it rather than restating it.
        #
        # The branch is on what was declared rather than on a subclass: an unblocked mover
        # writes straight to the node, and a blocked one hands *itself* to its resolver as
        # the actor being moved (see the adapter below).
        def apply_move(dx, dy)
          return drag(dx, dy) if @grabbed

          unless @collision
            node.x += dx
            node.y += dy
            return
          end

          if @pushes.empty?
            @collision.move(self, dx, dy)
            blocked_x = @collision.blocked_x
            blocked_y = @collision.blocked_y
          else
            blocked_x = push_along_x(dx)
            blocked_y = push_along_y(dy)
          end
          report_blockers(blocked_x, blocked_y)
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

        def take_step(_dt) = nil

        def blocking? = !@collision.nil?

        def last_move_blocked? = @last_move_blocked

        def open_step = @stopped_by.begin_frame

        def report_blockers(blocked_x, blocked_y)
          @last_move_blocked = !(blocked_x.nil? && blocked_y.nil?)
          return unless @collision

          if blocked_x.equal?(blocked_y)
            record_blocker(blocked_x, :both)
          else
            record_blocker(blocked_x, :x)
            record_blocker(blocked_y, :y)
          end
        end

        def drag(dx, dy)
          report_blockers(drag_along_x(dx), drag_along_y(dy))
        end

        def drag_along_x(dx)
          return nil if dx.zero?

          crate = @grabbed
          crate.push(dx, 0.0, by: node)
          went = crate.pushed_x
          cut_short = crate.stopped?
          from = x
          @actor_source&.passing = crate.node
          by = step_x(went)
          @actor_source&.passing = nil
          crate.push(x - from - went, 0.0, by: node) if by
          by || (cut_short ? crate.collider : nil)
        end

        def drag_along_y(dy)
          return nil if dy.zero?

          crate = @grabbed
          crate.push(0.0, dy, by: node)
          went = crate.pushed_y
          cut_short = crate.stopped?
          from = y
          @actor_source&.passing = crate.node
          by = step_y(went)
          @actor_source&.passing = nil
          crate.push(0.0, y - from - went, by: node) if by
          by || (cut_short ? crate.collider : nil)
        end

        def step_x(dx)
          unless @collision
            node.x += dx
            return nil
          end
          return push_along_x(dx) unless @pushes.empty?

          @collision.move(self, dx, 0.0)
          @collision.blocked_x
        end

        def step_y(dy)
          unless @collision
            node.y += dy
            return nil
          end
          return push_along_y(dy) unless @pushes.empty?

          @collision.move(self, 0.0, dy)
          @collision.blocked_y
        end

        def close_step
          @stopped_by.each_ended { unblocked_signal.emit(it) }
        end

        def check_pushes
          if @pushes.intersect?(RESERVED)
            raise ArgumentError, "#{mover_name} pushes #{(@pushes & RESERVED).map(&:inspect).join(', ')}, " \
                                 'and no step can move the map, its gaps or the edge of the world. ' \
                                 '`pushes:` names collider layers.'
          end
          missing = @pushes - @blocked_by
          return if missing.empty?

          raise ArgumentError, "#{mover_name} pushes #{missing.map(&:inspect).join(', ')} and is not " \
                               'blocked_by it. A step passes through a layer it is not blocked by, ' \
                               'so nothing on it would ever be pushed. Add it to blocked_by too.'
        end

        def push_along_x(dx)
          from = x
          @collision.move(self, dx, 0.0)
          by = @collision.blocked_x
          pushed = nil
          tries = 0
          while by && !by.equal?(pushed) && tries < PUSH_DEPTH && (crate = pushable(by))
            left = dx - (x - from)
            break unless dx.positive? ? left.positive? : left.negative?

            crate.push(left, 0.0, by: node, depth: @push_depth + 1)
            @collision.move(self, left, 0.0)
            pushed = by
            by = @collision.blocked_x
            by = nil if by.equal?(pushed) && !crate.stopped?
            tries += 1
          end
          by
        end

        def push_along_y(dy)
          from = y
          @collision.move(self, 0.0, dy)
          by = @collision.blocked_y
          pushed = nil
          tries = 0
          while by && !by.equal?(pushed) && tries < PUSH_DEPTH && (crate = pushable(by))
            left = dy - (y - from)
            break unless dy.positive? ? left.positive? : left.negative?

            crate.push(0.0, left, by: node, depth: @push_depth + 1)
            @collision.move(self, 0.0, left)
            pushed = by
            by = @collision.blocked_y
            by = nil if by.equal?(pushed) && !crate.stopped?
            tries += 1
          end
          by
        end

        def pushable(by)
          return nil if @push_depth >= PUSH_DEPTH || !@pushes.include?(by.layer)

          other = by.node
          return nil if other.nil? || other.equal?(@pushed_by)

          other.get_component(Pushable)
        end

        def record_blocker(by, axis)
          return if by.nil? || @stopped_by.touching?(by)

          started = @stopped_by.started?(by)
          @stopped_by.add(by)
          blocked_signal.emit(by:, axis:) if started
        end

        def resolve_blockers
          sources = []
          sources << tile_blockers if @blocked_by.include?(TILES)
          sources << bounds_blockers if @blocked_by.include?(BOUNDS)
          sources << gap_blockers if @blocked_by.include?(GAPS)
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

        def gap_blockers
          world = node.system(TileWorld) ||
                  raise("#{mover_name} is blocked_by :gaps, and the scene has no TileWorld to " \
                        'read the gaps from. Mount one, or drop :gaps.')
          world.gap_blockers
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
          @actor_source = Engine::ActorBlockers.new(world: world, owner: @collider, layers: layers)
        end

        def mover_name = self.class.name&.split('::')&.last || self.class.inspect
      end
    end
  end
end
