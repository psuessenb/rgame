# frozen_string_literal: true

module Engine
  # Polls an InputBackend through a binding map and produces an Actions snapshot.
  # The map is `{ action_name => { axis: %i[neg pos] } | { button: %i[ids] } }`;
  # physical ids are decoupled from Gosu constants (the backend resolves them), so
  # remapping is just swapping this data.
  # Pure logic: the backend is duck-typed (`down?(physical_id)`), so tests pass a
  # fake and real code passes the Gosu-backed one.
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
      # Mutated in place each poll (no per-frame allocation), shared into the snapshot.
      @pointer = { x: 0.0, y: 0.0 }
      @actions = Actions.new(held: @held, axes: @axes, prev_held: @prev_held, pointer: @pointer)
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

      @pointer[:x] = backend.pointer_x
      @pointer[:y] = backend.pointer_y

      @actions
    end
  end
end
