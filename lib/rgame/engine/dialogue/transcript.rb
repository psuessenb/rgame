# frozen_string_literal: true

module RGame
  module Engine
    class Dialogue
      # What one conversation said, in order: each line shown and each response
      # picked. A `Dialogue` records into its own, and hands it over frozen
      # through `on_ended`.
      #
      #   talk.on_ended do |transcript|
      #     transcript.each { |entry| log << (entry.response ? entry.text : entry.speaker_name) }
      #   end
      #
      # The engine keeps a transcript for one conversation and saves nothing.
      # The game decides what to do with it: show it, or drop it.
      #
      # A line with variables keeps the values it was shown with, so a later
      # visit to the same beat with other values leaves the earlier entry as it
      # was.
      class Transcript
        include Enumerable

        # One line shown or one response picked. For a line, `speaker` and
        # `speaker_name` name who said it, `text` is the line and `vars` the
        # values it was shown with, or nil for a line without variables. For a
        # response, `text` is its label, `response` the transition picked, and
        # `beat` the beat it was picked at; `speaker`, `speaker_name` and `vars`
        # are nil.
        Entry = Data.define(:beat, :speaker, :speaker_name, :text, :vars, :response)

        # The script whose conversation this records.
        attr_reader :script

        # An empty transcript of a conversation running `script`.
        def initialize(script)
          @script = script
          @entries = []
        end

        # Yields each entry in the order it was recorded. Without a block, an
        # Enumerator.
        def each(&)
          return @entries.each unless block_given?

          @entries.each(&)
          self
        end

        def size = @entries.size
        def [](index) = @entries[index]
        def empty? = @entries.empty?
        def last = @entries.last

        # Freezes the transcript and its entries' list, so nothing records into
        # it any more.
        def freeze
          @entries.freeze
          super
        end

        # A copy that records on from here; never frozen.
        def initialize_copy(source)
          super
          @entries = source.entries_list.dup
        end

        # Records the line of `beat`, whose data is `data`, shown with `vars`.
        #
        # @api private
        def record_line(beat, data, vars)
          text = data.line
          if vars
            text = text.clone
            text.with(**vars)
            vars = vars.dup.freeze unless vars.frozen?
          end
          @entries << Entry.new(beat:, speaker: data.speaker, speaker_name: data.speaker_name, text:, vars:,
                                response: nil)
        end

        # Records `response`, picked at `beat`.
        #
        # @api private
        def record_response(beat, response)
          @entries << Entry.new(beat:, speaker: nil, speaker_name: nil, text: response.data.label, vars: nil,
                                response:)
        end

        # Whether the last entry is the line of `beat`.
        #
        # @api private
        def ends_with_line?(beat) = !last.nil? && last.response.nil? && last.beat == beat

        protected

        def entries_list = @entries
      end
    end
  end
end
