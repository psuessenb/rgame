# frozen_string_literal: true

module RGame
  module Engine
    # Polls one player's device through an InputMap and produces their Actions
    # snapshot.
    #
    #   mapper = ActionMapper.new(input_map, device: Controls.gamepad(0))
    #   actions = mapper.poll(input)
    #
    # **One of these per player.** The device is what makes that work: every
    # query carries it, so two mappers over the same map read two different
    # controllers, and each keeps its own previous-frame state so their edge
    # queries are independent.
    #
    # Pure logic. The backend is duck-typed and the whole interface is
    # `down?(physical_id, device:)` and `axis(axis_id, device:)` — a spec passes
    # a fake and a game passes RGame::Core::Input.
    class ActionMapper
      # A resting analog stick genuinely reports small non-zero values, so
      # something has to ignore them. Here rather than in the game, because it
      # is a property of the device, and here rather than in Core, because how
      # much to ignore is a judgement rather than a fact about the hardware.
      DEAD_ZONE = 0.15

      attr_reader :map, :actions
      attr_accessor :device, :dead_zone

      def initialize(map, device: RGame::Util::Controls::KEYBOARD, dead_zone: DEAD_ZONE)
        @map = map
        @device = device
        @dead_zone = dead_zone

        # One reusable snapshot: there is exactly one input state per tick per
        # player, so these are mutated in place each poll instead of allocated.
        # Seeded from the map's action list, so the hashes are warm before the
        # first poll and steady-state polling allocates nothing at all.
        @held = {}
        @prev_held = {}
        @axes = {}
        map.bindings.each_key do |name|
          @held[name] = false
          @prev_held[name] = false
          @axes[name] = 0.0
        end
        @actions = Actions.new(held: @held, axes: @axes, prev_held: @prev_held)
      end

      def poll(backend)
        # Snapshot this frame's held state as "previous" before recomputing it
        # (in-place copy: no allocation, the keys already exist).
        @held.each { |name, down| @prev_held[name] = down }

        return rest if @device.nil?

        @map.bindings.each do |name, binding|
          @held[name] = any_down?(backend, binding.buttons) if binding.buttons
          @axes[name] = axis_value(backend, binding) if binding.positive || binding.stick
        end

        @actions
      end

      private

      # A player with no device — an empty seat waiting for a controller — reads
      # as nothing held and every axis centred. Returning the snapshot rather
      # than refusing to poll is what lets a game show "press a button to join"
      # with no special case, and it releases anything that was held when the
      # controller was unplugged mid-press.
      def rest
        @held.each_key { |name| @held[name] = false }
        @axes.each_key { |name| @axes[name] = 0.0 }
        @actions
      end

      # hot-path
      def any_down?(backend, ids)
        ids.any? { |id| backend.down?(id, device: @device) }
      end

      # A digital axis and an analog one can both be bound to the same action —
      # arrows *and* the left stick — so the larger deflection wins. That needs
      # no per-device branching: a keyboard reads 0.0 for every axis and a stick
      # reads 0.0 for every key, so whichever device the player is on, the other
      # source contributes nothing.
      # hot-path
      def axis_value(backend, binding)
        digital = digital_axis(backend, binding)
        return digital unless binding.stick

        analog = dead_zoned(backend.axis(binding.stick, device: @device))
        digital.abs >= analog.abs ? digital : analog
      end

      # hot-path
      def digital_axis(backend, binding)
        return 0.0 unless binding.positive

        (backend.down?(binding.positive, device: @device) ? 1.0 : 0.0) -
          (backend.down?(binding.negative, device: @device) ? 1.0 : 0.0)
      end

      # Rescaled rather than merely cut off, so the value ramps from zero as the
      # stick leaves the dead zone. Cutting off alone makes it jump to the dead
      # zone's width the moment it starts reading, which is a visible twitch.
      # hot-path
      def dead_zoned(value)
        magnitude = value.abs
        return 0.0 if magnitude <= @dead_zone

        scaled = (magnitude - @dead_zone) / (1.0 - @dead_zone)
        value.negative? ? -scaled : scaled
      end
    end
  end
end
