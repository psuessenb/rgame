# frozen_string_literal: true

module RGame
  module Engine
    # Polls an InputBackend through a binding map and produces an Actions snapshot.
    # The map is `{ action_name => { axis: %i[neg pos] } | { button: %i[ids] } }`;
    # physical ids are decoupled from any backend's constants (the backend resolves
    # them), so remapping is just swapping this data.
    #
    # Pure logic: the backend is duck-typed — the whole interface is
    # `down?(physical_id)` — so a test passes a fake and a game passes
    # `RGame::Core::Input`.
    class ActionMapper
      attr_accessor :map

      def initialize(map)
        @map = map
        # One reusable snapshot: there's exactly one input state per tick, so we
        # mutate these in place each poll instead of allocating (after the first
        # poll warms the hash keys, steady-state polling allocates nothing).
        # `@prev_held` carries last frame's button state so Actions can answer edge
        # queries (pressed?/released?).
        @held = {}
        @prev_held = {}
        @axes = {}
        @actions = Actions.new(held: @held, axes: @axes, prev_held: @prev_held)
      end

      def poll(backend)
        # Snapshot this frame's held state as "previous" before recomputing it
        # (in-place copy: no allocation once the keys exist).
        @held.each { |name, down| @prev_held[name] = down }

        @map.each do |name, binding|
          if (axis = binding[:axis])
            neg, pos = axis
            @axes[name] = (backend.down?(pos) ? 1.0 : 0.0) - (backend.down?(neg) ? 1.0 : 0.0)
          end
          @held[name] = binding[:button].any? { |b| backend.down?(b) } if binding[:button]
        end

        @actions
      end
    end
  end
end
