# frozen_string_literal: true

# A drifting, spinning rock with four size tiers. Pool-built blank (the factory
# captures the world size for ScreenWrap); #reset retunes it to a tier each spawn —
# velocity, collider radius and sprite scale all come from the per-tier tables.
# A bullet hit asks the scene to score + split it (the scene owns the pool); split
# acquires two rocks one tier smaller, except at the smallest tier. The on_hit
# listener is wired once at construction (not per-spawn), so reuse never stacks
# listeners.
class Rock < Engine::Node2D
  MAX_TIER = 3
  RADII    = [40, 26, 17, 11].freeze
  SPEEDS   = [40.0, 60.0, 85.0, 115.0].freeze
  POINTS   = [20, 50, 100, 200].freeze
  SCALES   = [1.0, 0.65, 0.42, 0.28].freeze
  SPLIT_SPREAD = 0.5
  SPLIT_JITTER = 0.2
  SPLIT_SIGNS  = [-1, 1].freeze # the two diverging directions; frozen so split allocates none
  ENTITY_Z = 10

  attr_reader :tier, :points

  def initialize(world_width:, world_height:)
    super()
    @velocity = add_component(Engine::Components::Velocity.new)
    @sprite   = add_component(Engine::Components::Sprite.new(id: :rock, z: ENTITY_Z))
    add_component(Engine::Components::ScreenWrap.new(width: world_width, height: world_height, margin: RADII.first))
    @collider = add_component(Engine::Components::CircleCollider.new(radius: RADII.first, layer: :rock))
    @collider.on_hit { |other| scene.destroy_rock(self) if other.layer == :bullet }
  end

  def reset(x:, y:, tier:, travel_angle:, spin:)
    @tier = tier
    @points = POINTS[tier]
    self.x = x
    self.y = y
    self.angle = 0.0
    @velocity.vx = Math.cos(travel_angle) * SPEEDS[tier]
    @velocity.vy = Math.sin(travel_angle) * SPEEDS[tier]
    @velocity.spin = spin
    @collider.radius = RADII[tier]
    @sprite.scale = SCALES[tier]
    self
  end

  # Spawn two rocks one tier smaller, diverging from this rock's heading. The
  # smallest tier just vanishes (no children).
  def split(pool, rng)
    return if @tier >= MAX_TIER

    heading = Math.atan2(@velocity.vy, @velocity.vx)
    SPLIT_SIGNS.each do |sign|
      angle = heading + (sign * SPLIT_SPREAD) + ((rng.rand - 0.5) * 2 * SPLIT_JITTER)
      child = pool.acquire
      child.reset(x: x, y: y, tier: @tier + 1, travel_angle: angle, spin: (rng.rand - 0.5) * 3.0)
      scene.add_node(child)
    end
  end
end
