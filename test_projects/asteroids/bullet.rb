# frozen_string_literal: true

# A short-lived projectile. Pool-built blank — DespawnOffscreen finds the world bounds
# itself, so the factory closes over nothing; #reset places and launches it each spawn.
# It despawns when it leaves the world and dies on contact with a rock — both via
# queue_free, which the scene reclaims back to the pool. The on_hit listener is wired
# once.
class Bullet < RGame::Engine::Node2D
  RADIUS = 3

  def initialize
    super
    @velocity = add_component(RGame::Engine::Components::Velocity.new)
    add_component(RGame::Engine::Components::DespawnOffscreen.new(margin: RADIUS * 2))
    add_component(RGame::Engine::Components::Sprite.new(id: :bullet))
    collider = add_component(RGame::Engine::Components::CircleCollider.new(radius: RADIUS, layer: :bullet))
    collider.on_hit { |other| queue_free if other.layer == :rock }
  end

  def reset(x:, y:, vx:, vy:)
    self.x = x
    self.y = y
    @velocity.vx = vx
    @velocity.vy = vy
    self
  end
end
