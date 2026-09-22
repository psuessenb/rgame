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
      #
      # With `reveal:`, a number of characters per second, it shows each page a
      # character at a time, counting in `update(dt)`:
      #
      #   @line = UI::Label.new(text: 'smith.greeting', width: 440, lines_per_page: 3, reveal: 40)
      #
      #   @line.revealed?     # => whether the page is fully shown
      #   @line.reveal_all    # shows the rest at once, as confirm does first
      #
      # A character is a grapheme cluster, so a letter built from a base and a
      # combining mark appears whole. The reveal starts again from nothing when
      # the page turns, the text changes, `text=` is called or the width
      # changes. It draws prefixes of each line, built once when the page
      # appears, and places each where the whole line will stand, so a centred
      # line does not move as it grows.
      # A paused label does not reveal, since time reaches it only through
      # `update`.
      class Label < Node2D
        COLOR = TextButton::LABEL_COLOR

        ALIGNS = %i[left center right].freeze

        attr_reader :typeface, :align, :color

        # Characters a second the page is revealed at, or nil for none.
        attr_reader :reveal

        # `text:` is a translation key, as a String or Symbol, or an
        # Engine::Text. `width:` must be positive. `align:` is `:left`,
        # `:center` or `:right`, and places each line against the width.
        # Without `lines_per_page:` the whole text is one page. `reveal:` is a
        # positive number of characters a second, or nil to draw each page
        # whole.
        def initialize(text:, width:, typeface: Util::Typeface.default, lines_per_page: nil,
                       align: :left, color: COLOR, reveal: nil, **)
          unless ALIGNS.include?(align)
            raise ArgumentError, "align: must be one of #{ALIGNS.inspect}, not #{align.inspect}"
          end
          unless reveal.nil? || (reveal.is_a?(Numeric) && reveal.positive?)
            raise ArgumentError, "reveal: must be a positive number of characters a second, not #{reveal.inspect}"
          end

          @paragraph = Paragraph.new(text, width: width, typeface: typeface, lines_per_page: lines_per_page)
          super(width: width, **)
          @typeface = typeface
          @align = align
          @color = Util::Color.coerce(color)
          @page = 0
          @reveal = reveal
          @built = nil
          @shown = 0.0
          @total = 0
        end

        # Changes the text: a translation key or an Engine::Text, as `new`
        # takes. Always starts again, on page 0 with nothing revealed, even for
        # the `Text` it already shows. A label in the tree with a reveal builds
        # the new page at once, as `page=` does.
        def text=(text)
          @paragraph.text = text
          @page = 0
          return unless @built

          @built = nil
          build_page
        end

        # Gives the text its variables, as Engine::Text#with does, and returns
        # the label.
        def with(...)
          @paragraph.with(...)
          follow_page
          self
        end

        # Changes the width the text breaks at and aligns against. The next
        # draw breaks it again. A width of zero or less raises ArgumentError.
        def width=(width)
          @paragraph.width = width
          super
          follow_page
        end

        # The page drawn, counted from 0. It reads as the last page when a
        # language switch has left fewer pages than the one set.
        def page = @page.clamp(0, page_count - 1)

        # Sets the page drawn, clamped to the pages there are, so `page += 1`
        # on the last page stays there.
        def page=(index)
          @page = index.clamp(0, page_count - 1)
          follow_page
        end

        # How many pages the text fills: at least 1.
        def page_count = @paragraph.page_count

        def last_page? = page == page_count - 1

        # How many characters the page drawn holds, counted in grapheme clusters
        # as the reveal counts them: for sizing how long a page stays up. It
        # counts afresh on every call, so it is not for a draw path.
        def page_length = @paragraph.page(@page).sum { it.grapheme_clusters.size }

        # Whether the whole page is shown: always without `reveal:`, and for a
        # page the label has not yet started revealing, which it draws whole.
        def revealed? = !@paragraph.page(@page).equal?(@built) || @shown >= @total

        # Shows the rest of the page at once.
        def reveal_all
          @shown = @total
          self
        end

        def on_add
          build_page if @reveal
        end

        def on_update(dt)
          return unless @reveal

          build_page
          @shown = (@shown + (@reveal * dt)).clamp(0, @total)
        end

        def on_draw(renderer, _view)
          lines = @paragraph.page(@page)
          return draw_revealing(renderer, lines) if lines.equal?(@built)

          index = 0
          while index < lines.size
            line = lines[index]
            renderer.text(line, line_x(line), index * @typeface.height, font: @typeface, color: @color)
            index += 1
          end
        end

        private

        def draw_revealing(renderer, lines)
          left = @shown.floor
          index = 0
          while index < lines.size && left.positive?
            prefixes = @built_prefixes[index]
            shown = left.clamp(0, prefixes.size - 1)
            line = lines[index]
            if shown.positive?
              renderer.text(prefixes[shown], line_x(line), index * @typeface.height, font: @typeface, color: @color)
            end
            left -= shown
            index += 1
          end
        end

        def follow_page
          build_page if @built
        end

        def build_page
          lines = @paragraph.page(@page)
          return if lines.equal?(@built)

          @built_prefixes = lines.map { prefixes_of(it) }.freeze
          @total = @built_prefixes.sum { it.size - 1 }
          @built = lines
          @shown = 0.0
        end

        def prefixes_of(line)
          prefix = +''
          ['', *line.grapheme_clusters.map { (prefix << it).dup.freeze }].freeze
        end

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
