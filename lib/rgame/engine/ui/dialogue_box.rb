# frozen_string_literal: true

module RGame
  module Engine
    module UI
      # A box that shows one Engine::Dialogue: the speaker's name, the line
      # typed out a page at a time, and the responses to pick from.
      #
      #   talk = Engine::Dialogue.new(SMITH, context: hero)
      #   talk.on_ended { |transcript| @log.concat(transcript.to_a) }
      #   layer.add_node(UI::DialogueBox.new(dialogue: talk, unavailable: :disable, width: 600, y: 300))
      #
      # It is *a* representation of a conversation. A game that draws its own
      # drives the dialogue itself; nothing in Engine::Dialogue needs this box.
      #
      # ## Confirm does the next thing
      #
      # Confirm shows the rest of a page still typing, else turns the page, else
      # continues on a beat without responses. On a beat that waits, the
      # responses replace the ▼ marker once the last page is fully shown, and
      # confirm then picks the focused one. The marker is a button in the box's
      # UI::Menu, so every confirm the box acts on goes through the menu's
      # press rules: the confirm that opened the conversation, or finished a
      # line, picks nothing. The box reads no confirm of its own, and answers
      # to its `input_owner` as every node does.
      #
      # ## Responses the player cannot pick
      #
      # `unavailable:` is required, because whether a response whose condition
      # fails is shown is the game's decision. `:hide` lists only the available
      # responses; `:disable` lists them all and disables the rest, which focus
      # passes over. The box asks once per beat, when the responses appear.
      #
      # ## Its size
      #
      # The box is `width` wide and as tall as the most responses any beat of
      # the script has, so it never resizes during a conversation. The line
      # breaks at what is left of the width after the padding and
      # `portrait_width`, a column kept free at the left for `_draw_portrait`.
      #
      # ## The log
      #
      # `log:` names an action that opens the log, a paged UI::Label over the
      # dialogue's transcript, in place of the speaker, the line and the
      # responses:
      #
      #   UI::DialogueBox.new(dialogue: talk, unavailable: :hide, width: 600, log: :log)
      #
      # It opens on its last page. `ui_up` and `ui_down` turn the pages, and
      # `log` or `ui_cancel` closes it. While it is open the conversation does
      # not move and the line's reveal holds. It renders its text again only
      # when an entry arrives or the language changes, and only while open.
      #
      # Each line reads "Speaker: line", and each response its label alone.
      # Both are punctuation rather than words; a language that wants another
      # form passes `log_entry:`, a Text whose variables are `:speaker` and
      # `:line`, such as `Engine::Text.new('log.entry', :speaker, :line)`. The
      # log is *a* representation of the transcript; a game with its own reads
      # Engine::Dialogue#transcript.
      #
      # ## When the conversation ends
      #
      # The box frees itself, whether it moved the dialogue to its end or
      # another hand ended it with Engine::Dialogue#finish, as skipping a
      # cutscene does. The game hears the end, and gets the transcript, from
      # Engine::Dialogue#on_ended. The box is the only thing meant to move its
      # dialogue on; it reads the dialogue back after each move it makes.
      class DialogueBox < Node2D
        UNAVAILABLE = %i[hide disable].freeze

        COLOR = TextButton::LABEL_COLOR

        # The ▼ marker: the menu's one button while a line is shown or a beat
        # continues. Drawn only once the page is fully shown.
        class Marker < Button
          def initialize(line, color)
            super(activate_on: :press)
            @line = line
            @color = color
          end

          def _draw(renderer, _view)
            return unless @line.revealed?

            middle = height / 2
            renderer.triangle(width - 20, middle - 5, width - 8, middle - 5, width - 14, middle + 5, color: @color)
          end
        end
        private_constant :Marker

        attr_reader :dialogue, :unavailable

        # `unavailable:` is `:hide` or `:disable`. `lines_per_page:` and
        # `reveal:` are the line's, as UI::Label takes them. `panel:` is drawn
        # behind the whole box and `button_style:` behind each response; either
        # is anything answering `draw(renderer, state, width, height)`, as a
        # button's style does. `log:` is the action that opens the log, or nil
        # for no log, and `log_entry:` formats one of its lines. Raises
        # `ArgumentError` for any other `unavailable:`, for a `log_entry:` whose
        # variables are not `:speaker` and `:line`, and for a dialogue that has
        # ended.
        def initialize(dialogue:, unavailable:, width:, lines_per_page: 3, reveal: 40,
                       typeface: Util::Typeface.default, panel: ShapeStyle::DEFAULT,
                       button_style: ShapeStyle::DEFAULT, padding: 12, portrait_width: 0,
                       log: nil, log_entry: nil, **)
          unless UNAVAILABLE.include?(unavailable)
            raise ArgumentError, "unavailable: must be one of #{UNAVAILABLE.inspect}, not #{unavailable.inspect}"
          end
          raise ArgumentError, 'the dialogue has ended; a box needs one still running' if dialogue.ended?

          check_log_entry(log_entry)

          super(width:, **)
          @dialogue = dialogue
          dialogue.on_ended { queue_free }
          @unavailable = unavailable
          @typeface = typeface
          @panel = panel
          @button_style = button_style
          @padding = padding
          @text_x = padding + portrait_width + (portrait_width.positive? ? padding : 0)
          text_width = width - @text_x - padding
          line_y = padding + typeface.height
          @line = add_node(Label.new(text: dialogue.line, x: @text_x, y: line_y, width: text_width,
                                     typeface:, lines_per_page:, reveal:))
          column = Column.new(item_width: text_width, item_height: typeface.height + padding, spacing: padding / 2)
          menu_y = line_y + (lines_per_page * typeface.height) + padding
          @menu = add_node(Menu.new(layout: column, x: @text_x, y: menu_y))
          @marker = Marker.new(@line, COLOR)
          @marker.on_activated { advance }
          self.height = @menu.y + menu_height(column) + padding
          build_log(log, log_entry, text_width)
          read_back
        end

        # The action that opens the log, or nil.
        attr_reader :log

        def log_open? = @log_open

        hook :_draw_portrait

        # A blank hook: draws the speaker's portrait in the `portrait_width`
        # column the box keeps free at its left, which starts at `(padding,
        # padding)` in the box's own space. `speaker` is the beat's speaker
        # Symbol. Draws nothing unless a subclass does.
        def _draw_portrait(renderer, speaker); end

        # Shows a waiting beat's responses once its line is fully shown, after
        # doing what every node does.
        def update(dt)
          super
          show_responses if !@paused && !@log_open && ready_for_responses?
        end

        # Opens and closes the log, and turns its pages.
        # hot-path
        def _control(actions)
          return if @log.nil?
          return open_log if !@log_open && actions.pressed?(@log)
          return unless @log_open
          return close_log if actions.pressed?(@log) || actions.pressed?(:ui_cancel)

          @log_label.page -= 1 if actions.pressed?(:ui_up)
          @log_label.page += 1 if actions.pressed?(:ui_down)
        end

        def _draw(renderer, _view)
          @panel.draw(renderer, :idle, width, height)
          return if @log_open

          _draw_portrait(renderer, @speaker)
          renderer.text(@speaker_name, @text_x, @padding, font: @typeface, color: COLOR)
        end

        private

        def check_log_entry(log_entry)
          return if log_entry.nil? || (log_entry.is_a?(Text) && log_entry.names == %i[line speaker])

          raise ArgumentError, 'log_entry: must be an Engine::Text with the variables :speaker and :line, ' \
                               "got #{log_entry.inspect}"
        end

        def build_log(log, log_entry, text_width)
          @log = log
          @log_open = false
          return if log.nil?

          @log_entry = log_entry || Text.computed(:speaker, :line) { |speaker:, line:| "#{speaker}: #{line}" }
          text = Text.computed(:count) { |count:| log_text(count) }
          lines = ((height - (2 * @padding)) / @typeface.height).floor.clamp(1, nil)
          @log_label = Label.new(text:, x: @text_x, y: @padding, width: text_width, typeface: @typeface,
                                 lines_per_page: lines)
        end

        def log_text(count)
          @dialogue.transcript.first(count).map { log_line(it) }.join("\n")
        end

        def log_line(entry)
          return entry.text.to_s if entry.response

          @log_entry.with(speaker: entry.speaker_name.to_s, line: entry.text.to_s)
        end

        def open_log
          @log_open = true
          remove_node(@line)
          @menu.close
          @log_label.with(count: @dialogue.transcript.size)
          add_node(@log_label)
          @log_label.page = @log_label.page_count - 1
        end

        def close_log
          @log_open = false
          remove_node(@log_label)
          add_node(@line)
          @menu.open
        end

        def advance
          if !@line.revealed?
            @line.reveal_all
            show_responses if ready_for_responses?
          elsif !@line.last_page?
            @line.page += 1
          elsif @dialogue.waiting_for_response?
            show_responses
          else
            @dialogue.continue
            after_move
          end
        end

        def pick(response)
          @dialogue.respond(response)
          after_move
        end

        def after_move
          return if @dialogue.ended?

          @line.text = @dialogue.line
          read_back
        end

        def read_back
          @speaker = @dialogue.speaker
          @speaker_name = @dialogue.speaker_name
          @responses_shown = false
          @menu.clear.add(@marker)
        end

        def ready_for_responses?
          !@responses_shown && @dialogue.waiting_for_response? && @line.last_page? && @line.revealed?
        end

        def show_responses
          @responses_shown = true
          @menu.clear
          @dialogue.responses.each do |response|
            available = @dialogue.available?(response)
            next unless available || @unavailable == :disable

            button = TextButton.new(label: response.data.label, style: @button_style, enabled: available)
            @menu.add(button).on_activated { pick(response) }
          end
        end

        def menu_height(column)
          most = @dialogue.script.graph.state_names.map { responses_at(it) }.max.clamp(1, nil)
          (most * column.item_height) + ((most - 1) * column.spacing)
        end

        def responses_at(name)
          return 0 unless @dialogue.script.beat?(name)

          @dialogue.script.graph.transitions(name).count { it.event.nil? }
        end
      end
    end
  end
end
