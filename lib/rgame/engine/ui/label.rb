# frozen_string_literal: true

require_relative '../paragraph'

module RGame
  module Engine
    module UI
      # A translated text drawn as lines that fit a width, one page at a time.
      #
      #   @intro = UI::Label.new(text: 'intro.story', x: 100, y: 150, width: 440,
      #                          typeface: Util::Typeface.default(24), lines_per_page: 3,
      #                          align: :center)
      #
      #   @intro.page += 1   # stays on the last page
      #   @intro.last_page?  # => true once there
      #
      # It holds an Engine::Paragraph, which breaks the text at the width and
      # groups the lines into pages. So the label follows a variable, a language
      # switch and a new width with no call of its own, and an unchanged draw
      # allocates nothing.
      #
      # It draws the lines of the current page from its top-left corner, one
      # `typeface.height` apart, with `font: typeface`. The width it breaks at is
      # the width it aligns against, and the face it measures with is the face
      # it draws with.
      #
      # A label reads no input. Its owner decides which page shows and when to
      # turn it.
      class Label < Node2D
        COLOR = TextButton::LABEL_COLOR

        ALIGNS = %i[left center right].freeze

        attr_reader :typeface, :align, :color

        # `text:` is a translation key, as a String or Symbol, or an
        # Engine::Text. `width:` must be positive. `align:` is `:left`,
        # `:center` or `:right`, and places each line against the width.
        # Without `lines_per_page:` the whole text is one page.
        def initialize(text:, width:, typeface: Util::Typeface.default, lines_per_page: nil,
                       align: :left, color: COLOR, **)
          unless ALIGNS.include?(align)
            raise ArgumentError, "align: must be one of #{ALIGNS.inspect}, not #{align.inspect}"
          end

          @paragraph = Paragraph.new(text, width: width, typeface: typeface, lines_per_page: lines_per_page)
          super(width: width, **)
          @typeface = typeface
          @align = align
          @color = Util::Color.coerce(color)
          @page = 0
        end

        # Gives the text its variables, as Engine::Text#with does, and returns
        # the label.
        def with(...)
          @paragraph.with(...)
          self
        end

        # Changes the width the text breaks at and aligns against. The next
        # draw breaks it again. A width of zero or less raises ArgumentError.
        def width=(width)
          @paragraph.width = width
          super
        end

        # The page drawn, counted from 0. It reads as the last page when a
        # language switch has left fewer pages than the one set.
        def page = @page.clamp(0, page_count - 1)

        # Sets the page drawn, clamped to the pages there are, so `page += 1`
        # on the last page stays there.
        def page=(index)
          @page = index.clamp(0, page_count - 1)
        end

        # How many pages the text fills: at least 1.
        def page_count = @paragraph.page_count

        def last_page? = page == page_count - 1

        def on_draw(renderer, _view)
          lines = @paragraph.page(@page)
          index = 0
          while index < lines.size
            line = lines[index]
            renderer.text(line, line_x(line), index * @typeface.height, font: @typeface, color: @color)
            index += 1
          end
        end

        private

        def line_x(line)
          case @align
          when :left then 0
          when :center then (width - @typeface.text_width(line)) / 2
          else width - @typeface.text_width(line)
          end
        end
      end
    end
  end
end
