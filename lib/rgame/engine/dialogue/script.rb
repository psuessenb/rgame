# frozen_string_literal: true

module RGame
  module Engine
    class Dialogue
      # The recipe for a conversation: a `StateGraph` whose states are beats — a
      # speaker saying a line — and whose picked transitions are responses. An
      # `Engine::Dialogue` runs one; many can run the same script.
      #
      #   SMITH = Engine::Dialogue::Script.build(start: :greeting, scope: 'smith') do
      #     beat :greeting, speaker: :smith, line: 'greeting' do
      #       respond 'ask_work', to: :work, once: true
      #       respond 'bribe',    to: :bribed, if: :can_bribe?, then: :pay_bribe
      #       respond 'bye'
      #     end
      #     beat :work, speaker: :smith, line: 'work', to: :greeting
      #     beat :bribed, speaker: :smith, line: 'bribed'
      #   end
      #
      # A line and a response label are translation keys under `scope:`, or an
      # `Engine::Text` used as it is, so no String a translation cannot reach
      # gets in. A speaker is a Symbol the game owns; its name is the key
      # `speakers.<speaker>`, outside the scope, so every script shares it.
      #
      # A beat with responses waits for one. A beat without them continues to
      # its `to:`, or ends the conversation with none. `state`, `on` and `go`
      # still declare a state with no line, which a conversation passes straight
      # through: a branch point that decides by condition alone.
      #
      # `build` checks the script and freezes it, as `StateGraph.build` does.
      class Script
        # What a beat's state carries: the speaker Symbol, the `Text` for the
        # speaker's name, the line's `Text`, and the `vars:` that fill it.
        Beat = Data.define(:speaker, :speaker_name, :line, :vars)

        # What a response's transition carries: the label's `Text`.
        Response = Data.define(:label)

        # Builds a script from the block, which runs against a `Builder`, and
        # returns it frozen. Raises as `StateGraph.build` does, and also for a
        # beat with both responses and a `to:`, `once:` with no `to:`, and a
        # line whose variables and `vars:` do not match. A line or label that is
        # neither a key nor an `Engine::Text` raises `TypeError`.
        def self.build(start:, scope: nil, &)
          builder = Builder.new(scope)
          new(StateGraph.assemble(start, builder, &), scope, builder.vars_symbols)
        end

        private_class_method :new

        attr_reader :graph, :scope

        def initialize(graph, scope, vars_symbols)
          @graph = graph
          @scope = scope&.to_s&.freeze
          @symbols = (graph.each_symbol.to_a | vars_symbols).freeze
          freeze
        end

        # Whether `name` is a beat, rather than a state with no line.
        def beat?(name) = @graph.state(name).data.is_a?(Beat)

        # Yields every Symbol the script sends to its context: the graph's
        # conditions and effects, and every beat's `vars:`. Without a block, an
        # Enumerator.
        def each_symbol(&)
          return @symbols.each unless block_given?

          @symbols.each(&)
          self
        end

        # What `Script.build`'s block runs against: `StateGraph::Builder`'s
        # `state`, `on` and `go`, and `beat` and `respond`.
        class Builder < StateGraph::Builder
          # @api private
          attr_reader :vars_symbols

          def initialize(scope)
            super()
            @scope = scope
            @speakers = {}
            @vars_symbols = []
            @beat = nil
          end

          # Declares a beat: `speaker` says `line`. `vars:`, a block called with
          # the machine or a Symbol sent to the context, returns the line's
          # variables on entering the beat. The block declares its responses;
          # with none, the beat continues to `to:`, or ends the conversation
          # when `to:` is nil. `enter:` is an effect of arriving, as on a state.
          def beat(name, speaker:, line:, vars: nil, to: nil, enter: nil, &block)
            data = Beat.new(speaker: check_speaker(speaker), speaker_name: speaker_name(speaker),
                            line: line_text(name, line, vars), vars:)
            state(name, enter:, data:) do
              @beat = name
              instance_exec(&block) if block
              close_beat(name, to)
            ensure
              @beat = nil
            end
          end

          # Declares a response the player may pick: `label` is its key under
          # the scope, or an `Engine::Text`. `to:` nil ends the conversation.
          # `once: true` makes it unavailable once its target was ever entered,
          # and so needs a `to:`, and cannot be combined with `unless:`.
          def respond(label, to: nil, if: nil, unless: nil, then: nil, once: false)
            raise ArgumentError, "respond #{label.inspect} must be declared inside a beat block" unless @beat

            forbids = binding.local_variable_get(:unless)
            forbids = once_condition(label, to, forbids) if once
            add(nil, to, binding.local_variable_get(:if), forbids, binding.local_variable_get(:then),
                Response.new(label: text(label, 'a response label')))
          end

          # As `StateGraph::Builder#on`; refused inside a beat, whose ways out
          # are its responses and its `to:`.
          def on(event, **)
            refuse_in_beat('on')
            super
          end

          # As `StateGraph::Builder#go`; refused inside a beat, as `on` is.
          def go(**)
            refuse_in_beat('go')
            super
          end

          private

          def close_beat(name, to)
            if @transitions.empty?
              add(:continue, to, nil, nil, nil, nil)
            elsif to
              raise ArgumentError, "beat #{name.inspect} has responses and a to:; a player could not tell a continue " \
                                   'from a choice'
            end
          end

          def once_condition(label, to, forbids)
            raise ArgumentError, "respond #{label.inspect} is once: but has no to: to have visited" if to.nil?
            raise ArgumentError, "respond #{label.inspect} takes once: or unless:, not both" if forbids

            ->(machine) { machine.visits(to).positive? }
          end

          def refuse_in_beat(word)
            return unless @beat

            raise ArgumentError, "#{word} inside beat #{@beat.inspect}: a beat's ways out are respond and to:"
          end

          def check_speaker(speaker)
            return speaker if speaker.is_a?(Symbol)

            raise ArgumentError, "a speaker must be a Symbol, got #{speaker.inspect}"
          end

          def speaker_name(speaker) = @speakers[speaker] ||= Text.new("speakers.#{speaker}")

          def line_text(name, line, vars)
            text = text(line, "beat #{name.inspect}'s line:")
            check_callable(vars, "beat #{name.inspect}'s vars:")
            @vars_symbols << vars if vars.is_a?(Symbol)
            if vars && text.names.empty?
              raise ArgumentError, "beat #{name.inspect} has vars: but its line names no variables; " \
                                   'pass an Engine::Text built with them'
            end
            if !vars && text.names.any?
              raise ArgumentError, "beat #{name.inspect}'s line needs #{text.names.map { "#{it}:" }.join(', ')}; " \
                                   'give it vars:'
            end
            text
          end

          def text(value, what)
            case value
            when Text then value
            when String, Symbol then Text.new(value, scope: @scope)
            else raise TypeError, "#{what} takes a translation key or an Engine::Text, got #{value.inspect}"
            end
          end
        end
      end
    end
  end
end
