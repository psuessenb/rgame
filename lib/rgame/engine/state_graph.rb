# frozen_string_literal: true

module RGame
  module Engine
    # A recipe for a state machine: named states, and the transitions out of each.
    # A `StateMachine` runs one; many machines can run the same graph.
    #
    #   HAMMER = Engine::StateGraph.build(start: :not_started) do
    #     state :not_started do
    #       on :accepted, to: :searching
    #     end
    #     state :searching do
    #       on :hammer_found, to: :found
    #     end
    #     state :found do
    #       on :returned, to: :done, then: :pay_reward
    #     end
    #     state :done
    #   end
    #
    # `on` declares a transition fired by an event, `go` one taken by picking it.
    # A transition with no `to:` ends the machine. `if:` and `unless:` are
    # conditions, `then:` an effect of taking the transition, and a state's
    # `enter:` an effect of arriving. Each is a block called with the machine, or
    # a Symbol the machine sends to its context. `data:` is carried through
    # untouched, for a layer above to keep its own words on a state or a
    # transition.
    #
    # `build` checks the graph and freezes it, so a mistake raises where the graph
    # is written, not when a player first reaches the broken branch.
    class StateGraph
      # One transition, frozen. `event` is nil for a transition taken by picking
      # it, and `to` is nil for one that ends the machine. The builder's `if:`,
      # `unless:` and `then:` land in `requires`, `forbids` and `effect`, because
      # Ruby keywords make poor reader names.
      Transition = Data.define(:from, :event, :to, :requires, :forbids, :effect, :data)

      # One state, frozen: the effect run on arriving, the data a layer above
      # attached, and the frozen Array of transitions out.
      State = Data.define(:name, :enter, :data, :transitions)

      # Builds a graph from the block, which runs against a `Builder`. Returns it
      # frozen. Raises `ArgumentError` for a `to:` naming no state, a start that
      # is not a state, a state declared twice, a transition outside a `state`
      # block, or a condition or effect that is neither callable nor a Symbol.
      def self.build(start:, &)
        builder = Builder.new
        builder.instance_exec(&) if block_given?
        new(start, builder.states)
      end

      private_class_method :new

      attr_reader :start

      def initialize(start, states)
        @start = start
        @states = states.freeze
        check_targets
        raise ArgumentError, "the start #{start.inspect} is not a state" unless state?(start)

        @symbols = collect_symbols
        freeze
      end

      def state?(name) = @states.key?(name)

      # The `State` called `name`. Raises `ArgumentError` for a name the graph lacks.
      def state(name)
        @states.fetch(name) { raise ArgumentError, "no state #{name.inspect}" }
      end

      # The frozen Array of transitions out of `name`, in the order they were
      # declared. Reading it allocates nothing.
      def transitions(name) = state(name).transitions

      # Yields every Symbol given as a condition or an effect, once each. A
      # machine checks them against its context. Without a block, an Enumerator.
      def each_symbol(&)
        return @symbols.each unless block_given?

        @symbols.each(&)
        self
      end

      private

      def check_targets
        @states.each_value do |state|
          state.transitions.each do |transition|
            next if transition.to.nil? || state?(transition.to)

            raise ArgumentError, "#{state.name.inspect} has a transition to #{transition.to.inspect}, which is no state"
          end
        end
      end

      def collect_symbols
        symbols = []
        @states.each_value do |state|
          symbols << state.enter
          state.transitions.each { symbols.push(it.requires, it.forbids, it.effect) }
        end
        symbols.grep(Symbol).uniq.freeze
      end

      # What `StateGraph.build`'s block runs against. `state` declares a state;
      # inside its block, `on` and `go` declare the transitions out of it.
      class Builder
        # @api private
        attr_reader :states

        def initialize
          @states = {}
          @current = nil
        end

        # Declares a state. `enter:` is an effect run on arriving; `data:` is
        # kept on the `State` untouched. The block declares its transitions.
        def state(name, enter: nil, data: nil, &)
          raise ArgumentError, "state #{name.inspect} declared inside #{@current.inspect}" if @current

          check_name(name, 'a state')
          raise ArgumentError, "state #{name.inspect} declared twice" if @states.key?(name)

          check_callable(enter, "#{name.inspect}'s enter:")
          @current = name
          @transitions = []
          instance_exec(&) if block_given?
          @states[name] = State.new(name:, enter:, data:, transitions: @transitions.freeze)
        ensure
          @current = nil
        end

        # A transition taken when the machine fires `event`.
        def on(event, to: nil, if: nil, unless: nil, then: nil, data: nil)
          check_name(event, 'an event')
          add(event, to, binding.local_variable_get(:if), binding.local_variable_get(:unless),
              binding.local_variable_get(:then), data)
        end

        # A transition with no event, taken by picking it from the machine's list.
        def go(to: nil, if: nil, unless: nil, then: nil, data: nil)
          add(nil, to, binding.local_variable_get(:if), binding.local_variable_get(:unless),
              binding.local_variable_get(:then), data)
        end

        private

        def add(event, to, requires, forbids, effect, data)
          raise ArgumentError, 'a transition must be declared inside a state block' unless @current

          check_name(to, 'to:') unless to.nil?
          check_callable(requires, 'if:')
          check_callable(forbids, 'unless:')
          check_callable(effect, 'then:')
          @transitions << Transition.new(from: @current, event:, to:, requires:, forbids:, effect:, data:)
        end

        def check_name(name, what)
          return if name.is_a?(Symbol)

          raise ArgumentError, "#{what} must be a Symbol, got #{name.inspect}"
        end

        def check_callable(value, what)
          return if value.nil? || value.is_a?(Symbol) || value.respond_to?(:call)

          raise ArgumentError, "#{what} must be callable or a Symbol, got #{value.inspect}"
        end
      end
    end
  end
end
