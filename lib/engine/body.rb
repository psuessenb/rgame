# frozen_string_literal: true

module Engine
  # Reusable kinematics for free-moving, rotating entities (ship, rocks, bullets):
  # position, linear velocity, facing angle and angular velocity. `integrate`
  # advances them by a fixed dt; `wrap!` implements toroidal screen-wrap and
  # `offscreen?` the despawn test. Pure logic; no Gosu.
  #
  # Angle is in radians, 0 = pointing right (+x), increasing clockwise on screen
  # (since y grows downward). A heading's unit vector is therefore (cos, sin).
  class Body
    attr_accessor :x, :y, :vx, :vy, :angle, :spin

    def initialize(x: 0.0, y: 0.0, vx: 0.0, vy: 0.0, angle: 0.0, spin: 0.0)
      @x = x
      @y = y
      @vx = vx
      @vy = vy
      @angle = angle
      @spin = spin
    end

    def integrate(dt)
      @x += @vx * dt
      @y += @vy * dt
      @angle += @spin * dt
    end

    # Toroidal wrap: once the centre passes `margin` beyond an edge it reappears on
    # the opposite side. Using margin = the entity's radius means an object spawned
    # flush against an edge (centre at -radius) is exactly *at* the threshold, not
    # past it, so it never wraps on the frame it spawns.
    def wrap!(width, height, margin)
      span_x = width + (2 * margin)
      span_y = height + (2 * margin)
      @x += span_x while @x < -margin
      @x -= span_x while @x > width + margin
      @y += span_y while @y < -margin
      @y -= span_y while @y > height + margin
    end

    # Fully past an edge by `margin` (e.g. a bullet that left the screen).
    def offscreen?(width, height, margin)
      @x < -margin || @x > width + margin || @y < -margin || @y > height + margin
    end
  end
end
