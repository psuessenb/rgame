# frozen_string_literal: true

module RGame
  module Engine
    # Pure animation math: given an atlas's animation table and an elapsed time,
    # resolve which sprite-sheet cell (row, col) to show. No renderer, no images —
    # fully testable.
    #
    # animations: { name => { row:, col:, frames:, fps:, flip_x: }, ... }
    #   row     – sheet row
    #   col     – starting column (default 0); lets an animation begin mid-row,
    #             e.g. a 1-frame "stand" pointing at the neutral middle pose
    #   frames  – number of frames, advancing across columns from `col`
    #   fps     – frames per second
    #   flip_x  – draw mirrored horizontally
    class AnimationSet
      Anim = Struct.new(:row, :first_col, :frames, :frame_secs, :flip_x)

      def initialize(animations)
        @anims = animations.each_with_object({}) do |(name, a), table|
          table[name.to_sym] = Anim.new(a[:row], a[:col] || 0, a[:frames], 1.0 / a[:fps], a[:flip_x] || false)
        end
      end

      # Sheet row of `name` (fixed per animation).
      def row(name)
        @anims.fetch(name).row
      end

      # Sheet column of `name` at `elapsed` seconds — the only part that animates.
      def col(name, elapsed)
        anim = @anims.fetch(name)
        anim.first_col + ((elapsed / anim.frame_secs).floor % anim.frames)
      end

      # Whether `name` draws mirrored (fixed per animation).
      def flip_x(name)
        @anims.fetch(name).flip_x
      end

      # [row, col, flip_x] for the given animation at `elapsed` seconds. A convenience
      # for tests/inspection — it allocates an Array, so the per-frame draw path reads the
      # row/col/flip_x accessors above directly instead.
      def frame(name, elapsed)
        [row(name), col(name, elapsed), flip_x(name)]
      end
    end
  end
end
