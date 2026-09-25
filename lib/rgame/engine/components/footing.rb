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
      # Respawn then comes back on its respawn point; any other node, a crate, is freed.
      # `on_fell` fires as the fall starts, which is where a game takes a life.
      #
      # The fall runs from an Engine::Fall this keeps for its life, lent to the node's
      # parent for each fall: a suspended node stops its own components, this one
      # included. So a fall pauses with the world around it, and a node taken out of the
      # tree mid-fall, through a door or freed, stops falling at once, unscaled and
      # resumed.
      #
      # It finds the node's Hop on its first update rather than at attach, so a Hop
      # added after it, from an `_enter_tree`, still keeps the node up.
      class Footing < Engine::Component
        # Fired once as the node starts to fall, before it shrinks.
        signal :fell

        # How far over `coyote` the time off the floor must run before the node falls,
        # in seconds. Six ticks of 1/60 add up to 0.09999999999999999, and at another
        # step the sum lands just over the whole instead, so a comparison with no slack
        # would change the rule by a tick with the step size.
        SLACK = 1e-9

        attr_reader :coyote

        # Seconds the fall takes, from the drop to the respawn.
        attr_reader :fall

        # `coyote` and `fall` are in seconds. `coyote: 0` drops the node on the first
        # tick off the floor, and `fall` must be positive.
        def initialize(coyote: 0.1, fall: 0.4)
          super()
          self.coyote = coyote
          unless fall.is_a?(Numeric) && fall.positive?
            raise ArgumentError, "fall must be a positive number of seconds, not #{fall.inspect}"
          end

          @fall = fall
          @fall_node = Engine::Fall.new(self)
          @left = @coyote
          @airborne = false
          @falling = false
          @hop = nil
          @hop_known = false
        end

        # Seconds the node may stand off the floor after walking off it, and still hop.
        # Refuses a negative number.
        def coyote=(seconds)
          unless seconds.is_a?(Numeric) && seconds >= 0
            raise ArgumentError, "coyote must be a number of seconds, 0 or more, not #{seconds.inspect}"
          end

          @coyote = seconds
        end

        # Raises when the node has no BoxCollider, or the scene no TileWorld.
        def _attach
          @collider = require_sibling(BoxCollider)
          @world = node.system(TileWorld) ||
                   raise("#{self.class} reads the floor from the scene's TileWorld, and the scene has none. " \
                         'Mount one.')
          @hop_known = false
          @left = @coyote
          @airborne = false
        end

        # Ends a fall under way, so a node taken out of the tree mid-fall leaves it
        # unscaled and resumed.
        def _detach
          @fall_node.stop if @falling
        end

        # Whether the centre of the node's box is on the floor.
        def standing? = @world.floor_at?(@collider.cx, @collider.cy)

        # Seconds of coyote time left: `coyote` while standing, counting down off the
        # floor, 0 in the air and while falling.
        def coyote_left
          return 0.0 if @falling || @airborne

          @left.clamp(0.0, @coyote)
        end

        def falling? = @falling

        # hot-path
        def _update(dt)
          find_hop unless @hop_known
          landed = @airborne
          @airborne = @hop ? @hop.airborne? : false
          return if @airborne

          if standing?
            @left = @coyote
          elsif landed
            drop
          else
            @left -= dt
            drop if @left < -SLACK
          end
        end

        # The Fall calls it once the node is back on its feet, or out of the tree.
        #
        # @api private
        def fall_ended
          @falling = false
          @left = @coyote
          @airborne = false
        end

        private

        def find_hop
          @hop_known = true
          @hop = node.get_component(Hop)
        end

        def drop
          @falling = true
          fell_signal.emit
          @fall_node.start(node)
        end
      end
    end
  end
end
