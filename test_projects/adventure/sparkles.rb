# frozen_string_literal: true

module Adventure
  # Where a coin was taken: a burst of sparkles that runs its life out after the
  # coin is gone.
  #
  # The emitter is a node of its own in the actors slot, not a component on each
  # coin. A coin frees itself as it is taken, and its sparkles would go with it.
  # So the town builds one of these and hands it to every coin. It sits above the
  # heroes in the slot, because the sparkles are light, and it draws under the
  # canopy with everything else there.
  class Sparkles < Engine::Node2D
    COUNT = 12
    RAMP = Util::ColorRamp.new(Util::Color.new(255, 250, 200), Util::Color.new(255, 190, 60, 0))

    def initialize(**)
      super(z: 1, **)
      @particles = add_component(Engine::Components::Particles.new(
                                   limit: 48, lifetime: 0.3..0.6, speed: 20.0..60.0, spread: Math::PI,
                                   gravity: 60.0, size: 2, ramp: RAMP, blend: :add
                                 ))
    end

    # A burst at (x, y), in the actors slot's space.
    def burst(x, y) = @particles.burst(COUNT, x, y)
  end
end
