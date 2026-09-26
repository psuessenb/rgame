# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # The game's one seeded source of random numbers, a system on the root as
      # `FactsDatabase` is. Every node finds it without being handed it:
      #
      #   random = node.system!(Engine::Components::RandomSource)
      #   random.rand(3)          # => 0, 1 or 2
      #   random.rand(1.0..2.0)
      #
      # `RGame::Game` mounts one seeded from `RGAME_SEED`, so a driven run with
      # `--seed N` repeats itself. `WanderController` and `Particles` draw from
      # it unless they are handed an `rng:`.
      #
      # It is not called `Random`: inside `Components`, that name would shadow
      # Ruby's `Random` for every component that writes `Random.new`.
      class RandomSource < Engine::Component
        # The seed it was built with, so a run can be repeated.
        sealed_reader :seed

        def initialize(seed:)
          super()
          @rgame_seed = seed
          @rgame_random = Random.new(seed)
        end

        # As `Random#rand`: a Float in [0, 1) with no argument, an Integer below
        # an Integer, or a number in a Range.
        # hot-path
        def rand(...) = @rgame_random.rand(...)
      end
    end
  end
end
