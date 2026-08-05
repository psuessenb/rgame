# frozen_string_literal: true

module Engine
  # An immutable per-frame snapshot of abstract action state. Game logic reads
  # this, never physical keys. Built by ActionMapper (or constructed directly in
  # tests with a fake).
  #
  # Edge queries (`pressed?`/`released?`) compare against the previous frame's held
  # state, so a one-shot action (menu confirm, jump) fires exactly once per press
  # rather than every frame it's held.
  class Actions
    # `pointer` is a mutable `{ x:, y: }` hash the mapper updates in place each poll
    # (like `held`/`axes`), so the snapshot stays a single reused, allocation-free object.
    # The pointer *button* (click) rides the normal button path: bind a `:pointer` physical
    # id and query it through held?/pressed?/released? like any other action.
    def initialize(held: {}, axes: {}, prev_held: {}, pointer: { x: 0.0, y: 0.0 })
      @held = held
      @axes = axes
      @prev_held = prev_held
      @pointer = pointer
    end

    def held?(name)
      @held.fetch(name, false)
    end

    # True only on the frame the action transitions up→down.
    def pressed?(name)
      @held.fetch(name, false) && !@prev_held.fetch(name, false)
    end

    # True only on the frame the action transitions down→up.
    def released?(name)
      !@held.fetch(name, false) && @prev_held.fetch(name, false)
    end

    # Analog value in [-1.0, 1.0]; 0.0 if unbound/neutral.
    def axis(name)
      @axes.fetch(name, 0.0)
    end

    # Cursor position in screen pixels (the same space widgets lay out in).
    def pointer_x = @pointer[:x]
    def pointer_y = @pointer[:y]
  end
end
