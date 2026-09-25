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
      # it. #set_point moves it, which is what a Checkpoint calls.
      #
      # **The point stands on ground.** With a TileWorld on the scene, each attach and
      # each #set_point on an attached Respawn raises ArgumentError for a point whose
      # cell is a gap, a gap under a platform included. A node brought back there
      # would fall again as soon as it stood, every time, and the raise names the
      # point as the scene loads instead. A node that starts on a platform takes a
      # point on ground from #set_point before it is added.
      #
      # A game decides at each fall whether the node comes back: the fall looks the
      # Respawn up as it ends, so one removed in Footing's `on_fell` frees the node.
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
        sealed_reader :point_x, :point_y

        # Seconds the flash lasts.
        sealed_reader :flash

        # `flash` is in seconds. 0 flashes nothing.
        def initialize(flash: 1.0)
          super()
          unless flash.is_a?(Numeric) && flash >= 0
            raise ArgumentError, "flash must be a number of seconds, 0 or more, not #{flash.inspect}"
          end

          @rgame_flash = flash
          @rgame_point_x = nil
          @rgame_point_y = nil
          @rgame_flashing = false
          @rgame_elapsed = 0.0
          @rgame_found = 1
          @rgame_world = nil
        end

        # The first attach records where the node stands as its point. Raises
        # ArgumentError when the scene's TileWorld has no ground under the point.
        def _attach
          @rgame_world = node.system(TileWorld)
          unless @rgame_point_x
            @rgame_point_x = node.world_x
            @rgame_point_y = node.world_y
          end
          refuse_gap(@rgame_point_x, @rgame_point_y)
        end

        # A new respawn point, in world pixels. Returns self. Once attached, raises
        # ArgumentError for a point with no ground under it, and keeps the point it
        # had. A point set before the first attach is checked by that attach.
        def set_point(x, y)
          refuse_gap(x, y)
          @rgame_point_x = x
          @rgame_point_y = y
          self
        end

        # Places the node on its point and starts the flash. A flash already under way
        # starts again, and still gives back the opacity it found first.
        def respawn
          node.world_x = @rgame_point_x
          node.world_y = @rgame_point_y
          @rgame_found = node.opacity unless @rgame_flashing
          @rgame_elapsed = 0.0
          @rgame_flashing = @rgame_flash.positive?
          respawned_signal.emit
        end

        def flashing? = @rgame_flashing

        # Blinks `opacity`, shown first, until `flash` has passed, then gives back the
        # opacity it found.
        #
        # hot-path
        def _update(dt)
          return unless @rgame_flashing

          @rgame_elapsed += dt
          return stop_flash if @rgame_elapsed + SLACK >= @rgame_flash

          node.opacity = ((@rgame_elapsed + SLACK) / BLINK).floor.even? ? @rgame_found : 0
        end

        # Stops a flash and gives the opacity back.
        def _detach
          stop_flash if @rgame_flashing
          @rgame_world = nil
        end

        private

        def refuse_gap(x, y)
          return if @rgame_world.nil? || @rgame_world.ground_at?(x, y)

          raise ArgumentError, "#{node.class}'s respawn point (#{x}, #{y}) is over a gap, so it would fall " \
                               'again as it came back. Stand it on ground, or call set_point before adding it.'
        end

        def stop_flash
          @rgame_flashing = false
          node.opacity = @rgame_found
        end
      end
    end
  end
end
