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
    # reaches `context`, `facts` and `visits` from one argument. One written as a
    # Symbol is sent to the context, and the machine checks at construction that
    # the context answers every one, so a misspelt predicate fails when the
    # machine is built rather than when a player reaches that branch.
    #
    # `to_h` is where the machine has got to, as `Util::SaveFile#write` takes it,
    # and `from:` puts a new machine back there:
    #
    #   save.write(hammer: quest.to_h)
    #   quest = Engine::StateMachine.new(HAMMER, context: hero, from: save.read[:hammer])
    #
    # A game's quests normally take a `name:` instead, and `Components::Facts`
    # saves and restores every named machine with its flags.
    class StateMachine
      extend Signal::DSL

      signal :changed, :from, :to, :transition

      NOTHING = [].freeze
      private_constant :NOTHING

      attr_reader :graph, :context, :facts, :state, :name

      # Enters the graph's start state, counts it visited once and runs its
      # `enter:` effect. `context` is the game's object conditions ask; `facts`
      # the shared store they read.
      #
      # With `from:`, a Hash `to_h` returned, the machine resumes there instead,
      # running no effect. State names may be Strings, as JSON returns them, and
      # a nil state resumes the machine ended. `from: nil` starts fresh.
      #
      # With `name:`, a Symbol, the machine registers with `facts`, which then
      # saves and restores it. It resumes from the entry the facts hold for that
      # name, or starts fresh with none, so `name:` takes the place of `from:`.
      #
      # A second machine under the same name takes over from the first, where
      # the first had got to, and the first raises if it is moved again. So a
      # scene built twice is fine, and two machines both driving one quest are
      # caught.
      #
      # Raises `ArgumentError` for a saved state the graph lacks, and for
      # `name:` without `facts:` or with `from:`. Raises `NoMethodError` listing
      # every Symbol in the graph the context does not answer.
      def initialize(graph, context: nil, facts: nil, from: nil, name: nil)
        @graph = graph
        @context = context
        @facts = facts
        @name = name
        @busy = false
        @retired = false
        check_name(from)
        check_symbols
        if name
          facts.register(self) { begin_at(it) }
        else
          begin_at(from)
        end
      end

      # The frozen Array of transitions out of the current state; an empty one
      # once the machine has ended. Allocates nothing.
      def transitions = @state.nil? ? NOTHING : @graph.transitions(@state)

      # Whether `transition`'s conditions hold now: `if:` must, and `unless:`
      # must not. Runs them on every call. Raises `ArgumentError` for a
      # transition not listed for the current state.
      def available?(transition)
        check_listed(transition)
        holds?(transition) || false
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

      # Where the machine has got to: the state, nil once ended, and the visits.
      def to_h = { state: @state, visits: @visits.dup }

      # The state and visits a saved Hash names, checked against the graph; the
      # start state visited once for nil. `Facts#restore` checks every machine
      # with this before it changes any.
      #
      # @api private
      def parse_saved(saved)
        check_idle
        return [@graph.start, { @graph.start => 1 }] if saved.nil?
        raise ArgumentError, "a saved machine is a Hash, got #{saved.class}" unless saved.is_a?(Hash)

        state = saved.fetch(:state) { raise ArgumentError, "a saved machine has no :state, got #{saved.inspect}" }
        unless state.nil? || @graph.state?(state.to_sym)
          raise ArgumentError, "a saved machine names #{state.inspect}, which is no state"
        end

        [state&.to_sym, saved.fetch(:visits, {}).to_h { |name, count| [name.to_sym, Integer(count)] }]
      end

      # Puts the machine where `parse_saved` said, running no effect and
      # telling no one.
      #
      # @api private
      def place(parsed)
        @state, @visits = parsed
        self
      end

      # The transitions available now, for `Engine::Exploration`.
      #
      # @api private
      def moves = transitions.select { holds?(it) }

      # Takes a move `moves` listed, for `Engine::Exploration`.
      #
      # @api private
      def make(move) = take(move)

      # A move as a path shows it: the state it leaves, and its event.
      #
      # @api private
      def explain(move) = "#{move.from}: #{move.event || (move.to ? "go to #{move.to}" : 'go, ending')}"

      # Enters the start state again after the machine ended, keeping every
      # visit: counts it, runs its `enter:`, and emits nothing. A `Dialogue`
      # resumed from an ended conversation starts over this way.
      #
      # @api private
      def restart
        check_idle
        raise "the machine #{@name.inspect} restarts only once it has ended" unless ended?

        guarded { arrive(@graph.start) }
        self
      end

      # Raises `NoMethodError` naming every Symbol in `symbols` that `context`
      # does not answer, as a machine does at construction.
      #
      # @api private
      def self.check_answers(context, symbols)
        missing = symbols.reject { context&.respond_to?(it) }
        return if missing.empty?

        who = context.nil? ? 'a machine with no context' : context.class
        raise NoMethodError.new("#{who} does not answer #{missing.map(&:inspect).join(', ')}", missing.first)
      end

      # Marks the machine as replaced by a newer one under its name, so moving
      # it raises.
      #
      # @api private
      def retire
        @retired = true
        self
      end

      private

      def move(transition)
        run(transition.effect)
        from = @state
        transition.to ? arrive(transition.to) : @state = nil
        changed_signal.emit(from:, to: @state, transition:)
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

      def ask(condition) = condition.is_a?(Symbol) ? @context.public_send(condition) : condition.call(self)

      def run(effect)
        ask(effect) unless effect.nil?
      end

      def begin_at(saved)
        if saved
          place(parse_saved(saved))
        else
          @visits = {}
          guarded { arrive(@graph.start) }
        end
      end

      def check_name(from)
        return if @name.nil?
        raise TypeError, "a machine's name is a Symbol, got #{@name.inspect} (#{@name.class})" unless @name in Symbol
        raise ArgumentError, "the machine #{@name.inspect} registers with its facts, so it needs facts:" unless @facts
        return unless from

        raise ArgumentError, "the machine #{@name.inspect} resumes from its facts, so it takes no from:"
      end

      def check_symbols = self.class.check_answers(@context, @graph.each_symbol)

      def guarded
        @busy = true
        yield
      ensure
        @busy = false
      end

      def check_idle
        raise "the machine #{@name.inspect} was replaced by a newer one under the same name; move that one" if @retired
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
