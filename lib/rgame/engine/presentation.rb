# frozen_string_literal: true

module RGame
  module Engine
    # How a game's own resolution is presented on a window that may be a
    # different size. Pure arithmetic: a size, a mode, and the scale and offset
    # they imply. No renderer, no window, nothing to draw with.
    #
    #   presentation = Presentation.new(width: 640, height: 480, mode: :integer)
    #   presentation.fit(1920, 1080)
    #   presentation.scale_x   # => 2.0
    #   presentation.offset_x  # => 320   (1920 - 640*2, halved)
    #
    # ## The problem it exists for
    #
    # A game laid out against fixed numbers — a 500x500 board centred by writing
    # `x: 150` in a 800x600 window — keeps those numbers when the window grows.
    # It does not re-centre; it sits in the top-left corner with the new space
    # piled up to its right. Fullscreen makes that happen to every game that has
    # not thought about it, because fullscreen is the screen's resolution and
    # never the one the game asked for.
    #
    # There are two honest answers, and this is the second one:
    #
    # - **Re-layout.** Read the size you are drawing into and place things
    #   relative to its edges. Right for a HUD or a menu, where extra space is
    #   extra room. `examples/fullscreen` does this.
    # - **Scale.** Keep the design size, and map it onto whatever the window is.
    #   Right for a play area, where extra space should mean a bigger picture of
    #   the same thing rather than more world. This class.
    #
    # A game usually wants both at once, which works: the scale applies to
    # everything, and nodes still read their view's size — that size is just the
    # *logical* one now, so it stops changing.
    #
    # ## The modes
    #
    # | | |
    # |---|---|
    # | `:disabled` | No scaling. The logical size *is* the window size, so it changes as the window does. |
    # | `:stretch` | Fill the window exactly, distorting if the aspect ratios differ. |
    # | `:letterbox` | Largest scale that fits, equal on both axes, centred. Bars on two sides. |
    # | `:integer` | The same, rounded down to a whole number. |
    #
    # `:integer` is the one pixel art wants. A sprite drawn at 1.875x with nearest
    # filtering has some source pixels covering two screen pixels and some
    # covering one, and the unevenness crawls as anything moves. A whole-number
    # factor makes every source pixel exactly the same square, which is what
    # "pixel perfect" means.
    #
    # **It costs screen, sometimes a lot of it.** The factor is bounded by the
    # tighter axis, and rounding that down can throw away most of a window. A
    # 640x480 design measured against real screens:
    #
    # | window | `:integer` | `:letterbox` |
    # |---|---|---|
    # | 1920x1080 | 2x, 320px border | 2.25x |
    # | 2560x1440 | 3x, 320px border | 3x |
    # | 1600x900 | **1x**, 480px border | 1.875x |
    # | 1280x720 | **1x**, 320px border | 1.5x |
    #
    # The 16:9 rows are the ones to look at before choosing this mode: 900 and
    # 720 pixels of height are both short of the 960 that 2x needs, so the whole
    # window drops to 1x and the game sits in a small island. A design height
    # that divides common screen heights — 360 rather than 480 — is what avoids
    # that, and it is a decision about the game's art, not about this class.
    #
    # ## What `:integer` does when the window is too small
    #
    # It scales by 1 and lets the content overrun, rather than dropping below a
    # whole number. So the design size is a **minimum**: shrink the window under
    # it and you see part of the game rather than all of it, smaller.
    #
    # That is the same choice SDL makes, and the alternative is worse for the
    # case the mode exists for — falling back to a fractional scale would
    # reintroduce exactly the uneven pixels the game asked to avoid, at the
    # moment nobody is looking. Nothing here enforces a minimum window size;
    # that would need SDL, and this class is pure.
    class Presentation
      MODES = %i[disabled stretch letterbox integer].freeze

      # The logical size a game draws in. Under `:disabled` these follow the
      # window; under every other mode they are fixed and the window does not
      # matter to anything above this class.
      attr_reader :width, :height

      attr_reader :mode, :scale_x, :scale_y, :offset_x, :offset_y

      def initialize(width:, height:, mode: :disabled)
        raise ArgumentError, "unknown scale mode #{mode.inspect} — one of #{MODES.inspect}" \
          unless MODES.include?(mode)
        raise ArgumentError, 'a logical size needs a positive width and height' \
          unless width.positive? && height.positive?

        @logical_width = width
        @logical_height = height
        @mode = mode
        fit(width, height)
      end

      # Switches mode and refits against the window it last saw, so a settings
      # screen can change this while the game runs.
      #
      # The window size is remembered for exactly this: a caller changing the
      # mode knows which mode it wants and has no reason to also know how big
      # the window currently is, and asking it to pass one would be asking it to
      # keep a copy of something this object already has.
      def mode=(mode)
        raise ArgumentError, "unknown scale mode #{mode.inspect} — one of #{MODES.inspect}" \
          unless MODES.include?(mode)

        @mode = mode
        fit(@window_width, @window_height)
      end

      # Whether anything is being scaled. `:disabled` means the caller can skip
      # pushing a transform at all rather than pushing an identity one.
      def scaled? = @mode != :disabled

      # Recomputes for a window of this size. Mutates rather than returning a
      # new object: it is read every frame and recomputed only on a resize, so
      # there is no reason to allocate.
      def fit(window_width, window_height)
        @window_width = window_width
        @window_height = window_height
        case @mode
        when :disabled then fit_disabled(window_width, window_height)
        when :stretch then fit_stretch(window_width, window_height)
        else fit_uniform(window_width, window_height)
        end
        self
      end

      private

      def fit_disabled(window_width, window_height)
        @width = window_width
        @height = window_height
        @scale_x = @scale_y = 1.0
        @offset_x = @offset_y = 0.0
      end

      def fit_stretch(window_width, window_height)
        @width = @logical_width
        @height = @logical_height
        @scale_x = window_width.to_f / @logical_width
        @scale_y = window_height.to_f / @logical_height
        @offset_x = @offset_y = 0.0
      end

      def fit_uniform(window_width, window_height)
        @width = @logical_width
        @height = @logical_height

        fitting = [window_width.to_f / @logical_width, window_height.to_f / @logical_height].min
        scale = @mode == :integer ? integer_scale(fitting) : fitting

        @scale_x = @scale_y = scale
        @offset_x = ((window_width - (@logical_width * scale)) / 2.0).floor
        @offset_y = ((window_height - (@logical_height * scale)) / 2.0).floor
      end

      def integer_scale(fitting)
        floored = fitting.floor
        floored < 1 ? 1.0 : floored.to_f
      end
    end
  end
end
