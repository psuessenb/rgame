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
      # The game decides what to do with it: show it, save it, or drop it.
      # `to_h` and `Transcript.from` are there for a game that saves one.
      #
      # A line with variables keeps the values it was shown with, so a later
      # visit to the same beat with other values leaves the earlier entry as it
      # was.
      class Transcript
        include Collection.of(:@entries)

        # One line shown or one response picked. For a line, `speaker` and
        # `speaker_name` name who said it, `text` is the line and `vars` the
        # values it was shown with, or nil for a line without variables. For a
        # response, `text` is its label, `response` the transition picked, and
        # `beat` the beat it was picked at; `speaker`, `speaker_name` and `vars`
        # are nil.
        Entry = Data.define(:beat, :speaker, :speaker_name, :text, :vars, :response)

        # Rebuilds a transcript `to_h` saved, for `script`, in the shape
        # `Dialogue.new(transcript:)` takes. Accepts what `SaveFile#read`
        # returns, beat names as Strings included. The words come from the
        # script, so a transcript restored after a language switch reads in the
        # new language. Raises `ArgumentError` for a beat the script lacks, a
        # response the beat does not list, and variables that do not match the
        # line's names.
        def self.from(saved, script)
          raise TypeError, "a transcript restores from a Hash, got #{saved.class}" unless saved.is_a?(Hash)

          transcript = new(script)
          saved.fetch(:entries).each_with_index { |entry, index| transcript.restore_entry(entry, index) }
          transcript
        end

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

        # The transcript as a frozen Hash for a save:
        # `{ entries: [{ beat:, vars: }, { beat:, response: }] }`. A line
        # without variables saves only its beat, and a response the index it
        # has among its beat's responses. Raises `TypeError`, naming the entry
        # and the variable, for a value a save would not bring back as it was,
        # by the rule `Components::Facts` holds its values to.
        def to_h
          entries = @entries.each_with_index.map { |entry, index| save_entry(entry, index) }
          { entries: entries.freeze }.freeze
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

        # Adds one saved entry, checking it against the script.
        #
        # @api private
        def restore_entry(saved, index)
          beat = saved_beat(saved, index)
          if saved.key?(:response)
            record_response(beat, saved_response(saved[:response], beat, index))
          else
            data = @script.graph.state(beat).data
            record_line(beat, data, saved_vars(saved[:vars], data, beat, index))
          end
        end

        protected

        def entries_list = @entries

        private

        def save_entry(entry, index)
          if entry.response
            { beat: entry.beat, response: @script.graph.transitions(entry.beat).index(entry.response) }.freeze
          elsif entry.vars
            entry.vars.each do |key, value|
              Components::Facts.check_value(value) do
                "the variable #{key.inspect} of transcript entry #{index} (#{entry.beat.inspect})"
              end
            end
            { beat: entry.beat, vars: entry.vars }.freeze
          else
            { beat: entry.beat }.freeze
          end
        end

        def saved_beat(saved, index)
          raise ArgumentError, "transcript entry #{index} is not a Hash: #{saved.inspect}" unless saved.is_a?(Hash)

          beat = saved[:beat].to_s.to_sym
          return beat if @script.graph.state?(beat) && @script.beat?(beat)

          raise ArgumentError,
                "transcript entry #{index} names #{saved[:beat].inspect}, which is not a beat of the script"
        end

        def saved_response(index_in_beat, beat, index)
          responses = @script.graph.transitions(beat)
          response = responses[index_in_beat] if index_in_beat.is_a?(Integer) && index_in_beat >= 0
          return response if response && response.event.nil?

          raise ArgumentError, "transcript entry #{index} picks response #{index_in_beat.inspect} at " \
                               "#{beat.inspect}, which lists #{responses.count { it.event.nil? }}"
        end

        def saved_vars(vars, data, beat, index)
          names = data.line.names
          given = vars.is_a?(Hash) ? vars.keys.map(&:to_sym).sort : []
          unless given == names && (vars.nil? == names.empty?)
            raise ArgumentError, "transcript entry #{index} gives #{beat.inspect}'s line #{vars.inspect}; " \
                                 "it needs #{names.empty? ? 'no variables' : names.map { "#{it}:" }.join(', ')}"
          end

          vars&.transform_keys(&:to_sym)
        end
      end
    end
  end
end
