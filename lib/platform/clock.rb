# frozen_string_literal: true

module Platform
  # Wraps Gosu's wall-clock. The ONLY place the engine reads real time; game
  # logic receives fixed steps and never sees this.
  class Clock
    def initialize
      @last = Gosu.milliseconds
    end

    # Seconds elapsed since the previous call.
    def delta
      now = Gosu.milliseconds
      dt = (now - @last) / 1000.0
      @last = now
      dt
    end
  end
end
