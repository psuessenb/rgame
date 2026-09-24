# frozen_string_literal: true

require_relative 'color'

module RGame
  module Util
    # The colours along a straight line from one colour to another, built once
    # and read by how far along they are.
    #
    #   EMBER = RGame::Util::ColorRamp.new(Color.new(255, 240, 160), Color.new(255, 120, 0, 0), steps: 64)
    #   EMBER.at(0.25)   # the colour a quarter of the way along
    #
    # A `Color` is frozen, so a colour that changes every tick would be a new
    # object every tick: 60 a second for one fading spark. A ramp builds its
    # `steps` colours when it is made, and `at` hands back one of them, so
    # reading it allocates nothing. A particle takes its colour from one by its
    # age over its lifetime.
    #
    # Every channel moves in a straight line, alpha included, so a ramp to a
    # colour with alpha 0 fades out as it goes. `at(0)` is `from` and `at(1)` is
    # `to`, the objects given. `at` holds a number below 0 to `from` and one
    # above 1 to `to`, and returns the nearest step for anything between.
    class ColorRamp
      attr_reader :from, :to, :steps

      # `steps` is how many colours to build, `from` and `to` among them: at
      # least 2. Anything but two Colors raises TypeError.
      def initialize(from, to, steps: 64)
        @from = color!(from)
        @to = color!(to)
        unless steps.is_a?(Integer) && steps >= 2
          raise ArgumentError, "steps: must be an Integer of at least 2, not #{steps.inspect}"
        end

        @steps = steps
        @last = steps - 1
        @colors = Array.new(steps) { step(it) }.freeze
      end

      # The colour `t` of the way from `from` to `to`, `t` running from 0 to 1.
      # hot-path
      def at(t)
        return @to if t >= 1
        return @from unless t.positive?

        @colors[(t * @last).round]
      end

      private

      def color!(value)
        return value if value.is_a?(Color)

        raise TypeError, "a ColorRamp runs between two #{Color}s, not #{value.inspect}"
      end

      def step(index)
        return @from if index.zero?
        return @to if index == @last

        fraction = index.fdiv(@last)
        Color.new(channel(@from.r, @to.r, fraction), channel(@from.g, @to.g, fraction),
                  channel(@from.b, @to.b, fraction), channel(@from.a, @to.a, fraction))
      end

      def channel(from, to, fraction) = (from + ((to - from) * fraction)).round
    end
  end
end
