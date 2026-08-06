# frozen_string_literal: true

module RGame
  module Engine
    # A repeating interval timer for periodic events that aren't driven by input — a
    # spawner emitting an enemy every N seconds, a tower's fire rate, a wave clock.
    #
    # It only accumulates time; the owner decides what each elapsed interval means. That
    # split lets one primitive serve both styles: "act automatically" (consume every ready
    # interval) and "stay loaded until conditions allow" (check `ready?`, but `consume`
    # only when actually acting — so a tower with no target keeps its shot ready instead of
    # wasting it). Pure and allocation-free, so it ticks on the per-frame path.
    #
    #   timer = Engine::Timer.new(0.8)
    #   timer.update(dt)
    #   if timer.ready?       # at least one whole interval has passed
    #     timer.consume       # deduct it (remainder carries forward, so timing won't drift)
    #     spawn_enemy
    #   end
    class Timer
      attr_accessor :interval

      def initialize(interval)
        @interval = interval
        @elapsed = 0.0
      end

      # Advance by one timestep. Returns self so callers can chain.
      def update(dt)
        @elapsed += dt
        self
      end

      # Has at least one whole interval accumulated since the last consume?
      def ready? = @elapsed >= @interval

      # Deduct one interval after acting on a ready timer. Carries the remainder forward
      # (rather than zeroing) so a long-running cadence doesn't drift. Returns self.
      def consume
        @elapsed -= @interval
        self
      end

      # Drop any accumulated time — e.g. after retuning the interval. Returns self.
      def reset
        @elapsed = 0.0
        self
      end
    end
  end
end
