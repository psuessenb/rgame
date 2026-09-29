# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Hides and shows its node in turn for a while, to mark a moment: coming
      # back from a fall, taking a hit. #start blinks the node's `opacity` for
      # some seconds, shown for `interval` seconds and hidden for as many, then
      # gives back the opacity it found.
      #
      #   blink = hero.add_component(Blink.new)
      #   hero.add_component(Respawn.new).on_respawned { blink.start(1.0) }
      #
      # Only drawing changes. The node updates, collides and answers its
      # controls through a blink, so a game that keeps a blinking hero safe from
      # harm asks #blinking?. A hidden spell hides the node's children too, as
      # Node2D#opacity does.
      #
      # The blink runs from its node's update, so a paused or suspended node's
      # blink waits with it. The node leaving the tree, or the Blink leaving the
      # node, ends a blink and gives the opacity back.
      class Blink < Engine::Component
        # Seconds one blink shows the node, and seconds it hides it.
        INTERVAL = 0.1

        # Seconds of slack in counting blinks, as Footing::SLACK: six ticks of 1/60
        # add up to just under 0.1, and would otherwise make the first blink a tick
        # longer than the rest.
        SLACK = 1e-9
        private_constant :SLACK

        # `interval` must be a positive number of seconds, or it raises
        # ArgumentError.
        def initialize(interval: INTERVAL)
          super()
          @rgame_interval = seconds!(interval, 'interval')
          @rgame_seconds = 0.0
          @rgame_elapsed = 0.0
          @rgame_blinking = false
          @rgame_found = 1
        end

        # Blinks the node's opacity for `seconds`, shown first, then gives back the
        # opacity it found. A blink under way starts again, and still gives back the
        # opacity it found first. `seconds` must be positive, or it raises
        # ArgumentError and a blink under way carries on.
        def start(seconds)
          @rgame_seconds = seconds!(seconds, 'seconds')
          @rgame_found = node.opacity unless @rgame_blinking
          @rgame_elapsed = 0.0
          @rgame_blinking = true
        end

        # Ends a blink under way and gives back the opacity it found. Does nothing
        # when none is under way.
        def stop
          return unless @rgame_blinking

          @rgame_blinking = false
          node.opacity = @rgame_found
        end

        def blinking? = @rgame_blinking

        def _update(dt)
          return unless @rgame_blinking

          @rgame_elapsed += dt
          return stop if @rgame_elapsed + SLACK >= @rgame_seconds

          node.opacity = ((@rgame_elapsed + SLACK) / @rgame_interval).floor.even? ? @rgame_found : 0
        end

        def _detach = stop

        private

        def seconds!(value, name)
          return value if value.is_a?(Numeric) && value.positive?

          raise ArgumentError, "#{name} must be a positive number of seconds, not #{value.inspect}"
        end
      end
    end
  end
end
