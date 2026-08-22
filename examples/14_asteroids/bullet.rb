# frozen_string_literal: true

# A short-lived projectile. Pool-built blank (the factory captures the world size
# for DespawnOffscreen); #reset places and launches it each spawn. It despawns when
# it leaves the screen and dies on contact with a rock — both via queue_free, which
# the scene reclaims back to the pool. The on_hit listener is wired once.
class Bullet < RGame::Engine::Node2D
  RADIUS = 3

  def initialize(world_width:, world_height:)
    super()
    @velocity = add_component(RGame::Engine::Components::Velocity.new)
    add_component(RGame::Engine::Components::DespawnOffscreen.new(
                    width: world_width, height: world_height, margin: RADIUS * 2
                  ))
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
