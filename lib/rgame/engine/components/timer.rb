# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # A node-driven interval timer: it rides the node's update tick — so nothing can
      # forget to advance it — and emits `on_elapsed` each time a whole interval elapses.
      # It wraps the pure Engine::Timer, reusing its carry-forward `consume` (the remainder
      # rolls over, so the cadence doesn't drift); this only adds the per-frame drive and
      # the signal.
      #
      #   timer = node.add_component(Engine::Components::Timer.new(0.8), as: :spawn)
      #   timer.on_elapsed { spawn_enemy }
      #
      # For something that happens once — a lifetime, a delay, a fade — use
      # Components::Tween, which emits `on_finished` once and says how far along it is.
      #
      # The countdown restarts in `_attach`, so a pooled node reacquired and re-added
      # starts fresh rather than inheriting the previous life's elapsed time.
      #
      # When a node needs more than one (a spawn cadence and a wave cadence), give them
      # distinct `as:` names — a node holds one component per slot.
      class Timer < Engine::Component
        signal :elapsed

        def initialize(interval)
          super()
          @rgame_timer = Engine::Timer.new(interval)
        end

        def interval = @rgame_timer.interval

        def interval=(seconds)
          @rgame_timer.interval = seconds
        end

        # Start the countdown fresh whenever the node (re-)enters the tree, so a pooled node
        # never inherits a previous life's accumulated time.
        def _attach = reset

        # Advance one step and fire on_elapsed once per whole interval that elapsed — so a
        # single long step still emits the right number of times (catch-up, not drift).
        def _update(dt)
          @rgame_timer.update(dt)
          while @rgame_timer.ready?
            @rgame_timer.consume
            elapsed_signal.emit
          end
        end

        # Back to a fresh timer: drop accumulated time (e.g. after retuning the interval,
        # or when a pooled node is reused). Returns self.
        def reset
          @rgame_timer.reset
          self
        end
      end
    end
  end
end
