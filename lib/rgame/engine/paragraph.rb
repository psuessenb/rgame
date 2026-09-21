# frozen_string_literal: true

require_relative '../util/typeface'
require_relative 'text'

module RGame
  module Engine
    # A translated text broken into lines that fit a width.
    #
    #   @speech = Engine::Paragraph.new(Engine::Text.new('npc.greeting', :name), width: 520)
    #   @notice = Engine::Paragraph.new('gate.notice', width: 300)   # a key, no variables
    #
    #   @speech.with(name: @hero_name).lines   # => a frozen Array of frozen Strings
    #
    # It breaks the text with `Util::Typeface#text_lines`, at spaces and at
    # newlines, and keeps the result. A read breaks again only when the String its
    # `Text` returns is a different object, or when the width changed. A `Text`
    # returns the identical String until a variable or the language changes, so
    # a paragraph follows both without a check of its own. An unchanged read
    # allocates nothing, and `lines` is safe to call in `draw`.
    #
    # A paragraph holds a typeface, never a renderer, so it lays text out in
    # `update` or in a headless spec. `Util::Typeface.default` is the typeface
    # unless `typeface:` names another.
    class Paragraph
      # The width the lines fit, in pixels.
      attr_reader :width

      attr_reader :typeface

      # `text` is a translation key, as a String or Symbol, or an `Engine::Text`.
      # Any other object raises `TypeError`, so player-visible prose cannot
      # arrive as a String that no translation reaches.
      def initialize(text, width:, typeface: Util::Typeface.default)
        @text = text_for(text)
        @typeface = typeface
        self.width = width
      end

      # Gives the text its variables, as `Text#with` does, and returns the
      # paragraph: `@speech.with(name: @hero_name).lines`.
      def with(...)
        @text.with(...)
        self
      end

      # Changes the width. The next read breaks the text again, unless the width
      # is the one it already had. A width of zero or less raises `ArgumentError`.
      def width=(width)
        raise TypeError, "a paragraph's width must be a number, got #{width.inspect}" unless width.is_a?(Numeric)
        raise ArgumentError, "a paragraph needs a positive width, got #{width}" unless width.positive?

        @width = width
      end

      # The lines, as a frozen Array of frozen Strings. The same Array comes back
      # until the text or the width changes.
      def lines
        source = @text.to_s
        return @lines if source.equal?(@source) && @width == @broken_at

        break_lines(source)
      end

      private

      def text_for(text)
        case text
        when Text then text
        when String, Symbol then Text.new(text)
        else raise TypeError, "a paragraph takes a translation key or an Engine::Text, got #{text.inspect}"
        end
      end

      def break_lines(source)
        @lines = @typeface.text_lines(source, @width).each(&:freeze).freeze
        @source = source
        @broken_at = @width
        @lines
      end
    end
  end
end
