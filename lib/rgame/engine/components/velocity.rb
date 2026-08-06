# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Integrates linear and angular velocity into the node's transform each step.
      # Free-moving entities (rocks, bullets) use it alone; a controller component
      # (or the node's own control hook) writes vx/vy/spin as intent. From Body#integrate.
      class Velocity < Engine::Component
        attr_accessor :vx, :vy, :spin

        def initialize(vx: 0.0, vy: 0.0, spin: 0.0)
          super()
          @vx = vx
          @vy = vy
          @spin = spin
        end

        def update(dt)
          node.x += @vx * dt
          node.y += @vy * dt
          node.angle += @spin * dt
        end
      end
    end
  end
end
