# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # What its node stands on: the ground, a Components::Platform it rides, or a
      # gap. It watches the centre of the node's BoxCollider box against the floor
      # its scene's TileWorld describes (TileWorld#floor_at?). A node that stands over
      # a gap loses its footing, and its Components::Fall starts, if it has one.
      #
      #   hero.add_component(FeetCollider.new(width: 12, height: 6))
      #   hero.add_component(Hop.new(peak: 18, duration: 0.5))
      #   hero.add_component(Footing.new(coyote: 0.1))
      #   hero.add_component(Fall.new)
      #   hero.add_component(Shrink.new)
      #
      # **A node in the air never falls.** A node with a Hop that is `airborne?` crosses
      # a gap, and one that lands on a gap loses its footing on the tick it lands. That
      # is all a jump over a chasm needs: Hop knows nothing of gaps, and this reads only
      # whether the node is in the air.
      #
      # **Coyote time.** A node that walks off the floor loses its footing once it has
      # been off it for more than `coyote` seconds, so a hop pressed just after the edge
      # still counts. #coyote_left says how much is left, for a game that shows it.
      #
      # **The fall is the node's Fall.** This looks it up each time the node loses its
      # footing, so it may be added in any order, or later. A node with none stands over
      # the gap, riding what it rode, and its Fall starts on the next update after one
      # arrives. So a node that only rides, such as a walker kept on a ring by
      # `blocked_by: :gaps`, holds a Footing and nothing else.
      #
      # **It rides the platform under it.** Where the centre of the box stands on a
      # Components::Platform over a gap, in the air or not, the node boards it, and the
      # platform carries it by every step it takes: through the node's Mover, so its own
      # `blocked_by:` still stops it, or straight onto the node when it has none. The node
      # leaves as the centre leaves the platform, as its Fall starts, and as it leaves the
      # tree.
      #
      # It looks the Mover up at each carry, so one added or removed while the node rides
      # counts from the platform's next step. A node whose Mover is gone has nothing left
      # to stop it, so the platform moves it straight. It finds the Hop, which it reads
      # every tick, on its first update rather than at attach. So a Hop added after it,
      # from an `_enter_tree`, still counts.
      class Footing < Engine::Component
        # How far over `coyote` the time off the floor must run before the node loses
        # its footing, in seconds. Six ticks of 1/60 add up to 0.09999999999999999, and
        # at another step the sum lands just over the whole instead, so a comparison with
        # no slack would change the rule by a tick with the step size.
        SLACK = 1e-9

        sealed_reader :coyote

        # The Components::Platform the node rides, or nil.
        sealed_reader :platform

        # `coyote` is in seconds, 0 or more, or it raises ArgumentError. `coyote: 0`
        # drops the node on the first tick off the floor.
        def initialize(coyote: 0.1)
          super()
          self.coyote = coyote
          @rgame_left = @rgame_coyote
          @rgame_airborne = false
          @rgame_lost = false
          @rgame_hop = nil
          @rgame_hop_known = false
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
          @rgame_hop_known = false
          @rgame_left = @rgame_coyote
          @rgame_airborne = false
          @rgame_lost = false
        end

        def _detach = board(nil)

        # Whether the centre of the node's box is on the floor.
        def standing? = @rgame_world.floor_at?(@rgame_collider.cx, @rgame_collider.cy)

        # Seconds of coyote time left: `coyote` while standing, counting down off the
        # floor, and 0 in the air and once the node has lost its footing.
        def coyote_left
          return 0.0 if @rgame_airborne
          return @rgame_coyote if standing?
          return 0.0 if @rgame_lost

          @rgame_left.clamp(0.0, @rgame_coyote)
        end

        # hot-path
        def _update(dt)
          find_hop unless @rgame_hop_known
          x = @rgame_collider.cx
          y = @rgame_collider.cy
          platform = @rgame_world.platform_under(x, y)
          board(platform)
          landed = @rgame_airborne
          @rgame_airborne = @rgame_hop ? @rgame_hop.airborne? : false
          return if @rgame_airborne

          if platform || @rgame_world.floor_at?(x, y)
            @rgame_left = @rgame_coyote
            @rgame_lost = false
          elsif landed || @rgame_lost
            lose_footing
          else
            @rgame_left -= dt
            lose_footing if @rgame_left < -SLACK
          end
        end

        # Moves the node by what its platform moved: through its Mover when it has one,
        # directly when it has not.
        #
        # @api private
        def ride(dx, dy)
          mover = node.get_component(Mover)
          if mover
            mover.ride(dx, dy)
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

        # Leaves the platform the node rides, as its Fall starts.
        #
        # @api private
        def leave_platform = board(nil)

        private

        def find_hop
          @rgame_hop_known = true
          @rgame_hop = node.get_component(Hop)
        end

        def board(platform)
          return if platform.equal?(@rgame_platform)

          @rgame_platform&.leave(self)
          @rgame_platform = platform
          platform&.board(self)
        end

        def lose_footing
          @rgame_lost = true
          node.get_component(Fall)&.start
        end
      end
    end
  end
end
