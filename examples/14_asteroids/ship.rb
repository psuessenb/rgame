# frozen_string_literal: true

# The player ship — pure composition, almost no hand-written logic. Movement is the
# reusable ThrustController (turn → spin, thrust → forward acceleration); firing is
# the reusable ActionTrigger (held fire + cooldown → on_triggered), which the ship
# turns into its own on_fire signal carrying the muzzle position/heading. The scene
# listens for on_fire (to spawn a pooled bullet) and on_destroyed (to end the game),
# so the ship stays pool-agnostic. Rendered with the :ship texture; Node2D#draw
# orients it by the ship's absolute angle.
class Ship < RGame::Engine::Node2D
  RADIUS        = 16
  TURN_SPEED    = 4.0
  ACCEL         = 260.0
  MAX_SPEED     = 320.0
  DRAG          = 0.4
  FIRE_COOLDOWN = 0.22

  signal :on_fire, RGame::Engine::Signal.define(:x, :y, :angle)
  signal :on_destroyed

  def initialize(world_width:, world_height:)
    super(x: world_width / 2.0, y: world_height / 2.0)
    add_component(RGame::Engine::Components::Velocity.new)
    add_component(RGame::Engine::Components::ThrustController.new(
                    turn_speed: TURN_SPEED, accel: ACCEL, max_speed: MAX_SPEED, drag: DRAG
                  ))
    add_component(RGame::Engine::Components::ScreenWrap.new(width: world_width, height: world_height, margin: RADIUS))
    add_component(RGame::Engine::Components::Sprite.new(id: :ship))
    trigger = add_component(RGame::Engine::Components::ActionTrigger.new(fire: FIRE_COOLDOWN))
    trigger.on_triggered { |action| fire if action == :fire }
    collider = add_component(RGame::Engine::Components::CircleCollider.new(radius: RADIUS, layer: :ship))
    collider.on_hit { |other| on_destroyed_signal.emit if other.layer == :rock }
  end

  private

  # Emit the muzzle position + heading; the scene spawns the actual bullet.
  def fire
    on_fire_signal.emit(
      x: x + (Math.cos(angle) * RADIUS),
      y: y + (Math.sin(angle) * RADIUS),
      angle: angle
    )
  end
end
