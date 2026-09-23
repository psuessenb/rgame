# frozen_string_literal: true

module RGame
  module Engine
    # Polls one player's device through an InputMap and produces their Actions
    # snapshot.
    #
    #   mapper = ActionMapper.new(input_map, device: Controls.gamepad(0))
    #   actions = mapper.poll(input, dt)
    #
    # **One of these per player.** The device is what makes that work: every
    # query carries it, so two mappers over the same map read two different
    # controllers, and each keeps its own previous-frame state so their edge
    # queries are independent.
    #
    # **`poll` takes the timestep**, because an action can be declared as a hold
    # or a tap and those are answers about time. Nothing else in the engine could
    # supply it: the mapper is the one place that sees every action once a tick,
    # and a caller counting its own seconds is the per-caller timer this exists
    # to remove.
    #
    # ## What the buttons say, and what the action says
    #
    # For a plain action those are the same thing, and for a hold or a tap they
    # are not — so the mapper keeps both. One hash holds the raw button state per
    # action, another the level a game reads:
    #
    # | Declared | `held?` |
    # |---|---|
    # | `buttons:` alone | its buttons are down |
    # | `all:` | every id of one of its chords is down |
    # | `hold: 0.6` | they have been down 0.6 s, until they come up |
    # | `tap: 0.3` | one tick, on a release that came inside 0.3 s |
    #
    # `pressed?` and `released?` are the edges of that level and need no case of
    # their own: a hold presses once, late, and a tap is a one-tick pulse whose
    # up edge follows on the next tick.
    #
    # A held chord then switches off the plain actions on its buttons, over a
    # list the map worked out at construction — so the pass costs one walk of the
    # chords a game declared, and nothing at all for the map of a game that
    # declared none. `held_for` keeps counting through it, because it answers for
    # the buttons rather than for the level.
    #
    # ## When a press began
    #
    # Each poll moves the snapshot's `poll_count` on by one, and `down_since`
    # records the count on which an action's buttons went down. A node compares
    # the two to tell a press it saw start from one begun before it was last
    # controlled; see Node2D#control.
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
        @hold_times = {}
        @down = {}
        @since = {}
        map.bindings.each_key do |name|
          @held[name] = false
          @prev_held[name] = false
          @axes[name] = 0.0
          @hold_times[name] = 0.0
          @down[name] = false
          @since[name] = nil
        end
        @chords = map.bindings.filter_map { |name, binding| [name, binding.silences] if binding.all }.freeze
        @actions = Actions.new(held: @held, axes: @axes, prev_held: @prev_held, hold_times: @hold_times,
                               down_since: @since, poll_count: 0)
      end

      # One tick's input, as the Actions snapshot this mapper reuses. `dt` is the
      # timestep, in seconds, and is what every duration here is counted from.
      def poll(backend, dt)
        @actions.count_poll
        @held.each { |name, down| @prev_held[name] = down }

        return rest if @device.nil?

        @map.bindings.each do |name, binding|
          poll_buttons(name, binding, backend, dt) if binding.buttons || binding.all
          @axes[name] = axis_value(backend, binding) if binding.pairs || binding.stick
        end
        silence_chorded

        @actions
      end

      private

      def rest
        @held.each_key { |name| @held[name] = false }
        @axes.each_key { |name| @axes[name] = 0.0 }
        @hold_times.each_key { |name| @hold_times[name] = 0.0 }
        @down.each_key { |name| @down[name] = false }
        @since.each_key { |name| @since[name] = nil }
        @actions
      end

      # hot-path
      def silence_chorded
        @chords.each do |name, silences|
          next unless @held[name]

          silences.each { |other| @held[other] = false }
        end
      end

      # hot-path
      def poll_buttons(name, binding, backend, dt)
        was_down = @down[name]
        now_down = down?(backend, binding)
        count_hold(name, was_down, now_down, dt)
        @held[name] = level(name, binding, was_down, now_down)
        @down[name] = now_down
        note_start(name, was_down, now_down)
      end

      # hot-path
      def note_start(name, was_down, now_down)
        if now_down
          @since[name] = @actions.poll_count unless was_down
        elsif !@held[name] && !@prev_held[name]
          @since[name] = nil
        end
      end

      # hot-path
      def count_hold(name, was_down, now_down, dt)
        if now_down
          @hold_times[name] += dt
        elsif !was_down
          @hold_times[name] = 0.0
        end
      end

      # hot-path
      def level(name, binding, was_down, now_down)
        return now_down && @hold_times[name] >= binding.hold if binding.hold
        return was_down && !now_down && @hold_times[name] <= binding.tap if binding.tap

        now_down
      end

      # hot-path
      def down?(backend, binding)
        return all_down?(backend, binding.all) if binding.buttons.nil?
        return any_down?(backend, binding.buttons) if binding.all.nil?

        any_down?(backend, binding.buttons) || all_down?(backend, binding.all)
      end

      # hot-path
      def any_down?(backend, ids)
        ids.any? { |id| backend.down?(id, device: @device) }
      end

      # hot-path
      def all_down?(backend, chords)
        chords.any? { |ids| ids.all? { |id| backend.down?(id, device: @device) } }
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
