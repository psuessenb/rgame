# frozen_string_literal: true

module RGame
  module Engine
    # Every path a `Dialogue` or a `StateMachine` can take, walked in a spec,
    # and where one gets stuck. A conversation that strands a player raises
    # while they play; this finds it first.
    #
    #   report = Engine::Exploration.run do
    #     Engine::Dialogue.new(SMITH, context: Hero.new, facts: Engine::Components::FactsDatabase.new)
    #   end
    #   expect(report.problems).to eq([])
    #
    # The block builds a fresh world and returns the dialogue or machine in it.
    # The walk replays each path in a world of its own, so effects and facts
    # behave as in play, and a condition sees only what the block set up and
    # what the walk's own moves changed. A move is any available transition: a
    # response or a continue for a dialogue, any transition, fired or picked,
    # for a machine.
    #
    # A position is stuck when a move raises, or when a machine has transitions
    # and none is available. A machine's state with no transitions is an end,
    # as a finished quest's is, and so is an ended machine or conversation.
    #
    # Positions count as the same when the state, the states ever entered, the
    # facts and the `key:` block's answer all match. Visits count as entered or
    # not, so a question a player may ask again and again does not multiply
    # positions. A condition that counts visits past one is explored as if it
    # did not; a condition on the context that the facts do not show needs
    # `key:`, returning what it reads.
    class Exploration
      # A position with no way on: the moves that reached it, the state it is
      # at, and the error a move raised, or nil when none was available.
      Stuck = Data.define(:path, :state, :error)

      # Walks every path from the world the block builds, breadth first, and
      # returns the report. Stops at a path of `max_moves` moves, or after
      # `max_positions` positions, and says so in `truncated?`. Raises
      # `ArgumentError` when the block builds a different world on a replay.
      def self.run(max_moves: 100, max_positions: 10_000, key: nil, &build)
        raise ArgumentError, 'Exploration.run needs a block that builds the world' unless build

        new(build, key, max_moves, max_positions)
      end

      Entry = Data.define(:indices, :path, :position)
      private_constant :Entry

      private_class_method :new

      # Each position with no way on, a frozen Array of `Stuck`, shortest
      # path first.
      attr_reader :stuck

      # The moves of the shortest path to an end, or nil when none reaches one.
      attr_reader :ending

      # The states no path entered, in the order the graph declares them.
      # Not a problem by itself: the world a spec builds may shut a branch on
      # purpose, and a spec that expects every state reached asserts this is
      # empty.
      attr_reader :unreached

      # How many distinct positions the walk saw.
      attr_reader :positions

      def initialize(build, key, max_moves, max_positions)
        @build = build
        @key = key
        @max_moves = max_moves
        @max_positions = max_positions
        @stuck = []
        @ending = nil
        @reached = {}
        @seen = {}
        @truncated = false
        walk
        finish
      end

      # Whether some path ends.
      def ends? = !@ending.nil?

      # Whether the walk stopped at a limit with positions still unexplored.
      def truncated? = @truncated

      # One String per problem: each stuck position with its path, no end
      # reached, and a walk cut short. An empty Array means every path the
      # world allows has a way on and some path ends.
      def problems
        list = @stuck.map { describe(it) }
        list << 'no path reaches an end' unless ends?
        list << "stopped with positions unexplored, at #{@max_moves} moves or #{@max_positions} positions" if truncated?
        list.freeze
      end

      private

      def walk
        root = start or return
        queue = [enqueue(root, [], [])]
        until queue.empty?
          entry = queue.shift
          visit(replay(entry), entry, queue)
        end
      end

      def start
        world = @build.call
        @graph = world.graph
        note(world)
        world
      rescue StandardError => e
        @stuck << Stuck.new(path: [].freeze, state: nil, error: e)
        nil
      end

      def visit(world, entry, queue)
        return @ending ||= entry.path if end?(world)

        count = count_moves(world, entry.path) or return

        count.times do |index|
          world ||= replay(entry)
          step(world, index, entry, queue)
          world = nil
        end
      end

      def count_moves(world, path)
        count = world.moves.size
        return count if count.positive?

        stuck_at(path, world, nil)
        nil
      rescue StandardError => e
        stuck_at(path, world, e)
        nil
      end

      def step(world, index, entry, queue)
        move = world.moves[index]
        path = [*entry.path, world.explain(move)].freeze
        begin
          world.make(move)
        rescue StandardError => e
          return stuck_at(path, world, e)
        end
        note(world)
        entry = enqueue(world, [*entry.indices, index], path)
        queue << entry if entry
      end

      def enqueue(world, indices, path)
        position = position_of(world)
        return if @seen.key?(position)

        if indices.size > @max_moves || @seen.size >= @max_positions
          @truncated = true
          return
        end

        @seen[position] = true
        Entry.new(indices:, path:, position:)
      end

      def replay(entry)
        world = @build.call
        entry.indices.each { world.make(world.moves[it] || different_world!) }
        position_of(world) == entry.position ? world : different_world!
      end

      def different_world!
        raise ArgumentError, 'the block built a different world on a replay; it must build the same one every time'
      end

      def end?(world) = world.ended? || world.graph.transitions(world.to_h[:state]).empty?

      def stuck_at(path, world, error)
        @stuck << Stuck.new(path:, state: world.to_h[:state], error:)
      end

      def note(world)
        world.to_h[:visits].each { |name, count| @reached[name] = true if count.positive? }
      end

      def position_of(world)
        saved = world.to_h
        [saved[:state], visited(saved[:visits]), facts_of(world.facts), @key&.call(world)]
      end

      def facts_of(facts)
        return unless facts.is_a?(Components::FactsDatabase)

        saved = facts.to_h
        [saved[:values], saved[:machines].transform_values { [it[:state], visited(it[:visits] || {})] }]
      end

      def visited(visits) = visits.filter_map { |name, count| name.to_sym if count.positive? }.sort

      def finish
        @stuck.freeze
        @positions = @seen.size
        @unreached = (@graph ? @graph.state_names.reject { @reached.key?(it) } : []).freeze
        freeze
      end

      def describe(stuck)
        return "the block raised building the world: #{reason(stuck)}" if stuck.state.nil? && stuck.path.empty?

        path = stuck.path.empty? ? 'the start' : stuck.path.join(', ')
        "stuck at #{stuck.state.inspect} after #{path}: #{reason(stuck)}"
      end

      def reason(stuck)
        return 'no transition is available' unless stuck.error

        "#{stuck.error.class}: #{stuck.error.message}"
      end
    end
  end
end
