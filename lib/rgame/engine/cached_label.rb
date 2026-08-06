# frozen_string_literal: true

module RGame
  module Engine
    # Holds a display string and rebuilds it only when its source value changes, so a
    # per-frame draw can show the cached copy without interpolating (allocating) a String
    # every frame. The format block runs only on an actual change.
    #
    #   @score_label = Engine::CachedLabel.new { |score| "Score: #{score}" } # build the block once
    #   renderer.text(@score_label[@score], 12, 10)                          # in on_draw: cached, no alloc
    #
    # `@score_label[value]` returns the cached string when `value` is unchanged, and
    # otherwise rebuilds it through the block. Construct it (and its block) outside the
    # per-frame path — e.g. in `on_add` — so the interpolation isn't itself a per-frame cost.
    class CachedLabel
      def initialize(&format)
        raise ArgumentError, 'CachedLabel needs a format block' unless format

        @format = format
        @value = nil
        @text = nil
      end

      # The cached string for `value`, rebuilt only when `value` differs from last time.
      def [](value)
        return @text if !@text.nil? && value == @value

        @value = value
        @text = @format.call(value)
      end
    end
  end
end
