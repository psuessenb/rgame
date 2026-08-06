# frozen_string_literal: true

module RGame
  module Engine
    # Owns animation playback state for one actor: the AnimationSet plus the current
    # animation name and elapsed time. Pure logic — the renderer asks it for the
    # current [row, col, flip_x] cell. This is what makes an actor own its own
    # animations instead of the scene passing an AnimationSet in every frame.
    class Animator
      def initialize(animation_set, initial: :stand)
        @animation_set = animation_set
        @current = initial
        @elapsed = 0.0
      end

      attr_reader :current, :elapsed

      # Switch to `name`; restarts elapsed time on an actual change (a no-op if the
      # animation is already playing, so a continuing walk keeps cycling).
      def play(name)
        return if name == @current

        @current = name
        @elapsed = 0.0
      end

      def update(dt)
        @elapsed += dt
      end

      # Current animation's row/col/flip_x, resolved without allocating — the per-frame
      # draw path reads these directly.
      def row = @animation_set.row(@current)
      def col = @animation_set.col(@current, @elapsed)
      def flip_x = @animation_set.flip_x(@current)

      # [row, col, flip_x] for the current animation at the current elapsed time. A
      # convenience for tests/inspection; it allocates, so draw uses the accessors above.
      def frame
        @animation_set.frame(@current, @elapsed)
      end
    end
  end
end
