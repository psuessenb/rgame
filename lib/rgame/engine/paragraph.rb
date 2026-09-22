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
    # With `lines_per_page:` it also groups the lines into pages, for a dialogue
    # box that shows a few lines at a time:
    #
    #   @speech = Engine::Paragraph.new('npc.story', width: 520, lines_per_page: 3)
    #   @speech.page_count   # => 2
    #   @speech.page(0)      # => the first three lines
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

      # How many lines a page holds, or nil when the whole text is one page.
      attr_reader :lines_per_page

      # `text` is a translation key, as a String or Symbol, or an `Engine::Text`.
      # Any other object raises `TypeError`, so player-visible prose cannot
      # arrive as a String that no translation reaches.
      #
      # `lines_per_page:` below 1 raises `ArgumentError`.
      def initialize(text, width:, typeface: Util::Typeface.default, lines_per_page: nil)
        @text = text_for(text)
        @typeface = typeface
        @lines_per_page = check_lines_per_page(lines_per_page)
        self.width = width
      end

      # Changes the text: a translation key or an `Engine::Text`, as `new`
      # takes, with the same `TypeError` for anything else. The next read
      # breaks it again.
      def text=(text)
        @text = text_for(text)
        @source = nil
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

      # How many pages the lines fill: 1 for an empty text, and 1 without
      # `lines_per_page:`.
      def page_count
        lines
        @pages.size
      end

      # The lines of page `index`, counted from 0, as a frozen Array. An index
      # past either end answers the nearest page, because a language switch can
      # shorten a paragraph while a game shows its last page.
      def page(index)
        lines
        @pages[index.clamp(0, @pages.size - 1)]
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
        @pages = paginate(@lines)
        @source = source
        @broken_at = @width
        @lines
      end

      def paginate(lines)
        return [lines].freeze unless @lines_per_page && lines.size > @lines_per_page

        lines.each_slice(@lines_per_page).map(&:freeze).freeze
      end

      def check_lines_per_page(count)
        return nil if count.nil?
        raise TypeError, "lines_per_page must be an Integer, got #{count.inspect}" unless count.is_a?(Integer)
        raise ArgumentError, "a page needs at least 1 line, got #{count}" if count < 1

        count
      end
    end
  end
end
