# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What its node stands on, and the fall when that is nothing. It watches the
      # centre of the node's BoxCollider box against the floor its scene's TileWorld
      # describes (TileWorld#floor_at?), and drops the node into a gap it walked into.
      #
      #   hero.add_component(FeetCollider.new(width: 12, height: 6))
      #   hero.add_component(Hop.new(peak: 18, duration: 0.5))
      #   hero.add_component(Footing.new(coyote: 0.1))
      #
      # **A node in the air never falls.** A node with a Hop that is `airborne?` crosses
      # a gap, and one that lands on a gap falls on the tick it lands. That is all a
      # jump over a chasm needs: Hop knows nothing of gaps, and this reads only whether
      # the node is in the air.
      #
      # **Coyote time.** A node that walks off the floor falls once it has been off it
      # for more than `coyote` seconds, so a hop pressed just after the edge still counts.
      # #coyote_left says how much is left, for a game that shows it.
      #
      # **The fall stops the node and shrinks it into the gap** over `fall` seconds,
      # through Node2D#scale, toward the node's origin, where it stands. A node with a
      # Respawn then comes back on its respawn point, controllable at once; any other
      # node is freed.
      # `on_fell` fires as the fall starts, which is where a game takes a life.
      #
      # The fall runs from an Engine::Fall this keeps for its life, lent to the node's
      # parent for each fall: a suspended node stops its own components, this one
      # included. So a fall pauses with the world around it, and a node taken out of the
      # tree mid-fall, through a door or freed, stops falling at once, unscaled and
      # resumed.
      #
      # **It rides the platform under it.** Where the centre of the box stands on a
      # Components::Platform over a gap, in the air or not, the node boards it, and the
      # platform carries it by every step it takes: through the node's Mover, so its own
      # `blocked_by:` still stops it, or straight onto the node when it has none. The node
      # leaves as the centre leaves the platform, as it falls, and as it leaves the tree.
      #
      # It finds the node's Hop and Mover on its first update rather than at attach, so
      # either added after it, from an `_enter_tree`, still counts.
      class Footing < Engine::Component
        # Fired once as the node starts to fall, before it shrinks.
        signal :fell

        # How far over `coyote` the time off the floor must run before the node falls,
        # in seconds. Six ticks of 1/60 add up to 0.09999999999999999, and at another
        # step the sum lands just over the whole instead, so a comparison with no slack
        # would change the rule by a tick with the step size.
        SLACK = 1e-9

        sealed_reader :coyote

        # Seconds the fall takes, from the drop to the respawn.
        sealed_reader :fall

        # The Components::Platform the node rides, or nil.
        sealed_reader :platform

        # `coyote` and `fall` are in seconds. `coyote: 0` drops the node on the first
        # tick off the floor, and `fall` must be positive.
        def initialize(coyote: 0.1, fall: 0.4)
          super()
          self.coyote = coyote
          unless fall.is_a?(Numeric) && fall.positive?
            raise ArgumentError, "fall must be a positive number of seconds, not #{fall.inspect}"
          end

          @rgame_fall = fall
          @rgame_fall_node = Engine::Fall.new(self)
          @rgame_left = @rgame_coyote
          @rgame_airborne = false
          @rgame_falling = false
          @rgame_hop = nil
          @rgame_mover = nil
          @rgame_siblings_known = false
          @rgame_platform = nil
        end

        # Seconds the node may stand off the floor after walking off it, and still hop.
        # Refuses a negative number.
        def coyote=(seconds)
          unless seconds.is_a?(Numeric) && seconds >= 0
            raise ArgumentError, "coyote must be a number of seconds, 0 or more, not #{seconds.inspect}"
          end

          @rgame_coyote = seconds
        end

        # Raises when the node has no BoxCollider, or the scene no TileWorld.
        def _attach
          @rgame_collider = require_sibling(BoxCollider)
          @rgame_world = node.system(TileWorld) ||
                         raise("#{self.class} reads the floor from the scene's TileWorld, and the scene has none. " \
                               'Mount one.')
          @rgame_siblings_known = false
          @rgame_left = @rgame_coyote
          @rgame_airborne = false
        end

        # Leaves its platform, and ends a fall under way, so a node taken out of the tree
        # mid-fall leaves it unscaled and resumed.
        def _detach
          board(nil)
          @rgame_fall_node.stop if @rgame_falling
        end

        # Whether the centre of the node's box is on the floor.
        def standing? = @rgame_world.floor_at?(@rgame_collider.cx, @rgame_collider.cy)

        # Seconds of coyote time left: `coyote` while standing, counting down off the
        # floor, 0 in the air and while falling.
        def coyote_left
          return 0.0 if @rgame_falling || @rgame_airborne

          @rgame_left.clamp(0.0, @rgame_coyote)
        end

        def falling? = @rgame_falling

        # hot-path
        def _update(dt)
          find_siblings unless @rgame_siblings_known
          x = @rgame_collider.cx
          y = @rgame_collider.cy
          platform = @rgame_world.platform_under(x, y)
          board(platform)
          landed = @rgame_airborne
          @rgame_airborne = @rgame_hop ? @rgame_hop.airborne? : false
          return if @rgame_airborne

          if platform || @rgame_world.floor_at?(x, y)
            @rgame_left = @rgame_coyote
          elsif landed
            drop
          else
            @rgame_left -= dt
            drop if @rgame_left < -SLACK
          end
        end

        # The Fall calls it once the node is back on its feet, or out of the tree.
        #
        # @api private
        def fall_ended
          @rgame_falling = false
          @rgame_left = @rgame_coyote
          @rgame_airborne = false
        end

        # Moves the node by what its platform moved: through its Mover when it has one,
        # directly when it has not.
        #
        # @api private
        def ride(dx, dy)
          if @rgame_mover
            @rgame_mover.ride(dx, dy)
          else
            node.world_x += dx
            node.world_y += dy
          end
        end

        # How far the corner of the box that leads along (dx, dy) lies along it, which is
        # the order a platform carries its riders in.
        #
        # @api private
        def lead(dx, dy)
          x = dx.positive? ? @rgame_collider.aabb_x + @rgame_collider.aabb_w : @rgame_collider.aabb_x
          y = dy.positive? ? @rgame_collider.aabb_y + @rgame_collider.aabb_h : @rgame_collider.aabb_y
          (x * dx) + (y * dy)
        end

        # Its platform let it go, as the platform left the tree.
        #
        # @api private
        def ride_ended
          @rgame_platform = nil
        end

        private

        def find_siblings
          @rgame_siblings_known = true
          @rgame_hop = node.get_component(Hop)
          @rgame_mover = node.get_component(Mover)
        end

        def board(platform)
          return if platform.equal?(@rgame_platform)

          @rgame_platform&.leave(self)
          @rgame_platform = platform
          platform&.board(self)
        end

        def drop
          board(nil)
          @rgame_falling = true
          fell_signal.emit
          @rgame_fall_node.start(node)
        end
      end
    end
  end
end
