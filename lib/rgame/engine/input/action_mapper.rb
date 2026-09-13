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
      DEAD_ZONE = 0.15

      attr_reader :map, :actions
      attr_accessor :device, :dead_zone

      def initialize(map, device: RGame::Util::Controls::KEYBOARD, dead_zone: DEAD_ZONE)
        @map = map
        @device = device
        @dead_zone = dead_zone

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
        @held.each { |name, down| @prev_held[name] = down }

        return rest if @device.nil?

        @map.bindings.each do |name, binding|
          @held[name] = any_down?(backend, binding.buttons) if binding.buttons
          @axes[name] = axis_value(backend, binding) if binding.pairs || binding.stick
        end

        @actions
      end

      private

      def rest
        @held.each_key { |name| @held[name] = false }
        @axes.each_key { |name| @axes[name] = 0.0 }
        @actions
      end

      # hot-path
      def any_down?(backend, ids)
        ids.any? { |id| backend.down?(id, device: @device) }
      end

      # hot-path
      def axis_value(backend, binding)
        digital = digital_axis(backend, binding)
        return digital unless binding.stick

        analog = dead_zoned(backend.axis(binding.stick, device: @device))
        digital.abs >= analog.abs ? digital : analog
      end

      # hot-path
      def digital_axis(backend, binding)
        pairs = binding.pairs
        return 0.0 if pairs.nil?

        best = 0.0
        pairs.each do |pair|
          value = (backend.down?(pair[1], device: @device) ? 1.0 : 0.0) -
                  (backend.down?(pair[0], device: @device) ? 1.0 : 0.0)
          best = value if value.abs > best.abs
        end
        best
      end

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
