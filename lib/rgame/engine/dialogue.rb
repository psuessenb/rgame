# frozen_string_literal: true

require_relative 'dialogue/script'

module RGame
  module Engine
    # One conversation running a `Dialogue::Script`: which beat it is at, who
    # speaks, the line, and the responses the player may pick.
    #
    #   talk = Engine::Dialogue.new(SMITH, context: hero, facts: facts)
    #   talk.speaker_name        # => the Text for speakers.smith
    #   talk.line                # => the Text for smith.greeting
    #   talk.responses           # => the greeting's responses, a frozen Array
    #   talk.available?(talk.responses.first)
    #   talk.respond(talk.responses.first)
    #   talk.continue            # on a beat without responses
    #
    # A beat either waits for a response or continues, never both, and each
    # method refuses the other kind of beat. So whatever drives the dialogue
    # never has to guess what confirm means.
    #
    # It holds a `StateMachine` and forwards to it, adding the words and
    # nothing that decides where the conversation goes. A condition, an effect
    # or a `vars:` block is called with that machine, so it reads `context`,
    # `facts` and `visits` exactly as a quest's does.
    #
    # The conversation never rests on a state with no line: it passes through
    # to the next beat within the same move. A state that offers no way on,
    # and a beat that waits with no response available, raise, naming the
    # state, because the player would be stuck. `Engine::Exploration` finds
    # both in a spec before a player does.
    #
    # `name:` saves the conversation in its facts, as a machine's does. One
    # saved after it ended starts again at its first beat and keeps its
    # visits, so a `once:` response stays hidden in every later conversation.
    # An unnamed dialogue starts with no visits, so `once:` lasts one
    # conversation.
    class Dialogue
      extend Signal::DSL

      signal :on_beat, Signal.define(:beat)
      signal :on_ended

      NOTHING = [].freeze
      private_constant :NOTHING

      attr_reader :script

      # Starts the conversation at the script's first beat, or resumes it from
      # `from:` or, with `name:`, from its facts, by `StateMachine.new`'s rules.
      # A save of a conversation that had ended starts it again, keeping its
      # visits. Raises `NoMethodError` listing every Symbol in the script, its
      # `vars:` included, that the context does not answer.
      def initialize(script, context: nil, facts: nil, from: nil, name: nil)
        @script = script
        @lines = {}
        @shown = nil
        StateMachine.check_answers(context, script.each_symbol)
        @machine = StateMachine.new(script.graph, context:, facts:, from:, name:)
        @machine.restart if @machine.ended?
        settle
      end

      # The beat the conversation is at, nil once it has ended.
      def beat = @machine.state

      # The speaker Symbol of this beat, nil once ended.
      def speaker = current&.speaker

      # The `Text` for the speaker's name, the key `speakers.<speaker>`; nil
      # once ended.
      def speaker_name = current&.speaker_name

      # The `Text` for this beat's line, holding the variables its `vars:` gave
      # on entering the beat; nil once ended. The same object every time the
      # beat is the same, so whatever holds it needs no rebuild.
      def line
        data = current
        return unless data

        show(data) unless @shown == beat
        line_for(data)
      end

      # This beat's responses in the order they were declared, a frozen Array;
      # an empty one on a beat that continues, and once ended. Allocates
      # nothing. Each is a `StateGraph::Transition` whose `data.label` is the
      # `Text` to show.
      def responses = waiting_for_response? ? @machine.transitions : NOTHING

      def waiting_for_response? = !ended? && @machine.transitions.first.event.nil?

      # Whether `response`'s conditions hold now. Runs them on every call.
      # Raises `ArgumentError` for a response not listed for this beat.
      def available?(response)
        check_listed(response)
        @machine.available?(response)
      end

      # Picks `response`, moves to the next beat, and returns the response.
      # Raises `RuntimeError` on a beat that does not wait for one and once
      # ended, and `ArgumentError` for a response not listed or not available.
      def respond(response)
        check_open
        raise "#{describe} continues rather than waiting for a response; call continue" unless waiting_for_response?

        check_listed(response)
        @machine.take(response)
        settle
        response
      end

      # Moves on from a beat without responses. Raises `RuntimeError` on a beat
      # that waits for one, and once ended.
      def continue
        check_open
        raise "#{describe} waits for a response; call respond" if waiting_for_response?

        @machine.take(@machine.transitions.first)
        settle
        self
      end

      def ended? = @machine.ended?

      # How often the conversation entered `beat`; 0 for one never entered.
      def visits(beat) = @machine.visits(beat)

      def context = @machine.context
      def facts = @machine.facts

      # The name the conversation is saved under in its facts, or nil.
      def name = @machine.name

      # Where the conversation has got to, in the shape `from:` takes.
      def to_h = @machine.to_h

      private

      def current
        return if ended?

        data = @script.graph.state(beat).data
        data if data.is_a?(Script::Beat)
      end

      def settle
        passed = nil
        passed = pass(passed) until ended? || current
        ended? ? on_ended_signal.emit : arrive
      end

      def pass(passed)
        state = beat
        raise "the conversation reached #{state.inspect} twice without a line between" if passed&.include?(state)

        transition = @machine.transitions.find { @machine.available?(it) }
        unless transition
          raise "#{state.inspect} has no line and no available transition, so the conversation would hang"
        end

        @machine.take(transition)
        (passed || []) << state
      end

      def arrive
        if waiting_for_response? && @machine.transitions.none? { @machine.available?(it) }
          raise "#{describe} waits for a response and none is available, so the player has no way out"
        end

        show(current)
        on_beat_signal.emit(beat)
      end

      def show(data)
        @shown = beat
        return unless data.vars

        vars = data.vars.is_a?(Symbol) ? context.public_send(data.vars) : data.vars.call(@machine)
        line_for(data).with(**vars)
      end

      def line_for(data) = data.vars ? (@lines[beat] ||= data.line.clone) : data.line

      def check_open
        raise 'the conversation has ended' if ended?
      end

      def check_listed(response)
        return if responses.include?(response)

        raise ArgumentError,
              "the response #{response.from.inspect} -> #{response.to.inspect} is not listed for #{describe}"
      end

      def describe = ended? ? 'the ended conversation' : "the beat #{beat.inspect}"
    end
  end
end
