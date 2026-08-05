# frozen_string_literal: true

module Engine
  module Components
    # A node-driven interval timer: it rides the node's update tick — so nothing can
    # forget to advance it — and emits `on_timeout` each time a whole interval elapses.
    # It wraps the pure Engine::Timer, reusing its carry-forward `consume` (the remainder
    # rolls over, so the cadence doesn't drift); this only adds the per-frame drive and
    # the signal.
    #
    #   timer = node.add_component(Engine::Components::Timer.new(0.8), as: :spawn)
    #   timer.on_timeout { spawn_enemy }
    #
    # `repeating: false` makes it a one-shot: it fires `on_timeout` exactly once and then
    # goes inert — the fixed-board despawn case (a projectile that vanishes after N
    # seconds, where DespawnOffscreen doesn't apply):
    #
    #   life = node.add_component(Engine::Components::Timer.new(2.0, repeating: false), as: :despawn)
    #   life.on_timeout { node.queue_free }
    #
    # The countdown restarts in `on_attach`, so a pooled node reacquired and re-added
    # starts fresh — a recycled projectile gets its full interval (and a one-shot can fire
    # again) rather than inheriting the previous life's elapsed time.
    #
    # When a node needs more than one (a spawn cadence and a wave cadence), give them
    # distinct `as:` names — a node holds one component per slot.
    class Timer < Engine::Component
      signal :on_timeout # emits no payload

      def initialize(interval, repeating: true)
        super()
        @timer = Engine::Timer.new(interval)
        @repeating = repeating
        @done = false
      end

      def interval = @timer.interval

      def interval=(seconds)
        @timer.interval = seconds
      end

      # Start the countdown fresh whenever the node (re-)enters the tree, so a pooled node
      # never inherits a previous life's accumulated time or spent one-shot.
      def on_attach = reset

      # Advance one step and fire on_timeout once per whole interval that elapsed — so a
      # single long step still emits the right number of times (catch-up, not drift). A
      # one-shot (`repeating: false`) fires once and then stops accumulating.
      def update(dt)
        return if @done

        @timer.update(dt)
        while @timer.ready?
          @timer.consume
          on_timeout_signal.emit
          unless @repeating
            @done = true
            break
          end
        end
      end

      # Back to a fresh timer: drop accumulated time and re-arm a spent one-shot (e.g.
      # after retuning the interval, or when a pooled node is reused). Returns self.
      def reset
        @timer.reset
        @done = false
        self
      end
    end
  end
end
