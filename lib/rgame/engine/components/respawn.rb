# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Where a node comes back after a fall, and the flash that shows it has.
      #
      #   hero.add_component(Footing.new(coyote: 0.1))
      #   hero.add_component(Respawn.new(flash: 1.0))
      #
      # A Footing whose node has one calls #respawn at the end of a fall, rather than
      # freeing the node. The node stands on its point at once, and its controls work
      # from that tick: the flash only shows where it came back, blinking `opacity`
      # until `flash` seconds have passed. A camera following the node cuts there.
      #
      # **The point is where the node first stood**: the first attach records its world
      # position. Later attaches, such as a door moving the node to another room, keep
      # it. #set_point moves it, which is what a checkpoint calls.
      #
      # #respawn works without a fall too, for a game whose hero can come back from
      # something that is not one.
      class Respawn < Engine::Component
        # Fired once the node stands on its respawn point, as the flash starts.
        signal :respawned

        # Seconds one blink shows the node, and seconds it hides it.
        BLINK = 0.1

        # Seconds of slack in counting blinks, as Footing::SLACK: six ticks of 1/60
        # add up to just under 0.1, and would otherwise make the first blink a tick
        # longer than the rest.
        SLACK = 1e-9

        # The respawn point, in world pixels, nil until the node first attaches.
        attr_reader :point_x, :point_y

        # Seconds the flash lasts.
        attr_reader :flash

        # `flash` is in seconds. 0 flashes nothing.
        def initialize(flash: 1.0)
          super()
          unless flash.is_a?(Numeric) && flash >= 0
            raise ArgumentError, "flash must be a number of seconds, 0 or more, not #{flash.inspect}"
          end

          @flash = flash
          @point_x = nil
          @point_y = nil
          @flashing = false
          @elapsed = 0.0
          @found = 1
        end

        # The first attach records where the node stands as its point.
        def _attach
          return if @point_x

          @point_x = node.world_x
          @point_y = node.world_y
        end

        # A new respawn point, in world pixels. Returns self.
        def set_point(x, y)
          @point_x = x
          @point_y = y
          self
        end

        # Places the node on its point and starts the flash. A flash already under way
        # starts again, and still gives back the opacity it found first.
        def respawn
          node.world_x = @point_x
          node.world_y = @point_y
          @found = node.opacity unless @flashing
          @elapsed = 0.0
          @flashing = @flash.positive?
          respawned_signal.emit
        end

        def flashing? = @flashing

        # Blinks `opacity`, shown first, until `flash` has passed, then gives back the
        # opacity it found.
        #
        # hot-path
        def _update(dt)
          return unless @flashing

          @elapsed += dt
          return stop_flash if @elapsed + SLACK >= @flash

          node.opacity = ((@elapsed + SLACK) / BLINK).floor.even? ? @found : 0
        end

        # Stops a flash and gives the opacity back.
        def _detach
          stop_flash if @flashing
        end

        private

        def stop_flash
          @flashing = false
          node.opacity = @found
        end
      end
    end
  end
end
