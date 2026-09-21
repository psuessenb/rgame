# frozen_string_literal: true

module RGame
  module Engine
    # Where one run of a `StateGraph` has got to: the current state, and how
    # often each state was entered. A quest is one; a dialogue holds one.
    #
    #   quest = Engine::StateMachine.new(HAMMER, context: hero, facts: facts)
    #   quest.fire(:accepted)       # takes the first available transition for the event
    #   quest.state                 # => :searching
    #   quest.visits(:searching)    # => 1
    #
    # `transitions` lists every transition out of the current state, and
    # `available?` answers whether one's conditions hold now. The machine decides
    # what may be taken; what a game shows of the rest is the game's business.
    #
    # Taking a transition runs, in order: its `then:` effect, the state change,
    # the visit count, the new state's `enter:` effect, then `on_changed`. So an
    # effect reads where the machine was, and `enter:` and the listeners read
    # where it is. Taking or firing from inside one of this machine's own effects
    # or listeners raises; driving a second machine from there is how one moves
    # another on.
    #
    # A condition or effect written as a block is called with the machine, which
    # reaches `context`, `facts` and `visits` from one argument.
    class StateMachine
      extend Signal::DSL

      signal :on_changed, Signal.define(:from, :to, :transition)

      NOTHING = [].freeze
      private_constant :NOTHING

      attr_reader :graph, :context, :facts, :state

      # Enters the graph's start state, counts it visited once and runs its
      # `enter:` effect. `context` is the game's object conditions ask; `facts`
      # the shared store they read.
      def initialize(graph, context: nil, facts: nil)
        @graph = graph
        @context = context
        @facts = facts
        @busy = false
        @visits = {}
        @state = nil
        guarded { arrive(graph.start) }
      end

      # The frozen Array of transitions out of the current state; an empty one
      # once the machine has ended. Allocates nothing.
      def transitions = @state.nil? ? NOTHING : @graph.transitions(@state)

      # Whether `transition`'s conditions hold now: `if:` must, and `unless:`
      # must not. Runs them on every call. Raises `ArgumentError` for a
      # transition not listed for the current state.
      def available?(transition)
        check_listed(transition)
        holds?(transition)
      end

      # Takes `transition`, and returns it. Raises `ArgumentError` for one not
      # listed for the current state or not available.
      def take(transition)
        check_idle
        check_listed(transition)
        raise ArgumentError, "#{describe(transition)} is not available" unless holds?(transition)

        guarded { move(transition) }
        transition
      end

      # Takes the first available transition for `event`, and returns it. With
      # none, returns nil and changes nothing, so a machine in the wrong state
      # ignores an event meant for another.
      def fire(event)
        check_idle
        transition = transitions.find { it.event == event && holds?(it) }
        take(transition) if transition
      end

      # How often the machine has entered `name`; 0 for a state never entered.
      def visits(name) = @visits.fetch(name, 0)

      # Whether a transition with no `to:` was taken. An ended machine lists no
      # transitions and fires nothing.
      def ended? = @state.nil?

      private

      def move(transition)
        run(transition.effect)
        from = @state
        transition.to ? arrive(transition.to) : @state = nil
        on_changed_signal.emit(from:, to: @state, transition:)
      end

      def arrive(name)
        @state = name
        @visits[name] = visits(name) + 1
        run(@graph.state(name).enter)
      end

      def holds?(transition)
        (transition.requires.nil? || ask(transition.requires)) &&
          (transition.forbids.nil? || !ask(transition.forbids))
      end

      def ask(condition) = condition.call(self)

      def run(effect)
        ask(effect) unless effect.nil?
      end

      def guarded
        @busy = true
        yield
      ensure
        @busy = false
      end

      def check_idle
        return unless @busy

        raise 'a machine cannot take a transition from inside its own effect or listener'
      end

      def check_listed(transition)
        return if transitions.include?(transition)

        raise ArgumentError, "#{describe(transition)} is not listed for #{@state.inspect}"
      end

      def describe(transition)
        "the transition #{transition.from.inspect} -> #{transition.to.inspect}"
      end
    end
  end
end
