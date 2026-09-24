# frozen_string_literal: true

module RGame
  module Util
    # How a drawing combines with what is already on screen: the blend modes a
    # renderer knows, and the opacity it fades by.
    #
    #   RGame::Util::Blend::MODES          # => [:alpha, :add]
    #   RGame::Util::Blend.mode?(:add)     # => true
    #   RGame::Util::Blend.opacity(0.4)    # => 0.4
    #
    # `:alpha` draws over what is behind at the source's alpha, as every draw
    # does outside `blended`. `:add` adds to it, so light drawn on light gets
    # brighter. A mode's position in `MODES` is the number the renderer's C
    # takes for it.
    #
    # It lives in `Util` for the reason `Z` does. The renderer turns a mode into
    # GL state, the recording fake a spec draws with must refuse what the
    # renderer refuses, and a node checks its opacity when it is set. All three
    # name `Blend`, and none of them may name another's layer. So a bad mode or
    # opacity raises the same error wherever it is given.
    module Blend
      MODES = %i[alpha add].freeze

      INDICES = MODES.each_with_index.to_h.freeze

      def self.mode?(mode) = INDICES.key?(mode)

      # Raises unless `mode` names one, with the list in the message.
      #
      # @api private
      def self.mode!(mode)
        return mode if mode?(mode)

        raise ArgumentError, "unknown blend mode #{mode.inspect}; expected one of #{MODES.inspect}"
      end

      # The number the renderer's C takes for `mode`, and where a bad mode is
      # caught.
      #
      # @api private
      # hot-path
      def self.index(mode)
        INDICES[mode] || mode!(mode)
      end

      # Checks an opacity and returns it: a number from 0, which hides what it
      # fades, to 1, which changes nothing. Anything else raises, NaN included,
      # where the C below would clamp it and hide the mistake.
      # hot-path
      def self.opacity(value)
        raise TypeError, "no implicit conversion of #{value.class} into Float" unless value.is_a?(Numeric)
        # rubocop:disable Style/ComparableBetween -- between? raises its own
        # ArgumentError on NaN, where a comparison answers false
        return value if value >= 0 && value <= 1
        # rubocop:enable Style/ComparableBetween

        raise ArgumentError, "opacity #{value} is outside 0..1"
      end
    end
  end
end
