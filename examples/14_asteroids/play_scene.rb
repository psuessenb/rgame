# frozen_string_literal: true

require_relative 'ship'
require_relative 'rock'
require_relative 'bullet'

# The play scene and scene boundary: it owns the scene-scoped CollisionWorld system
# (a component on itself) plus the bullet/rock object pools. Entities are pooled
# Node2Ds — spawning is `pool.acquire` → `reset` → `add_node` (enter_tree registers
# the collider); despawning is `queue_free`, and #on_update reclaims freed entities
# back to their pool (detaching them from the tree). The reclaim runs before the
# child traversal, so it never mutates the child list mid-iteration.
class PlayScene < Engine::Node2D
  CELL_SIZE     = 96
  INITIAL_ROCKS = 4
  MAX_ROCKS     = 11
  SPAWN_INTERVAL = 3.0
  BULLET_SPEED   = 520.0
  AIM_JITTER     = 0.5
  SCORE_COLOR    = [220, 225, 235].freeze

  def initialize(width:, height:)
    super()
    @width = width
    @height = height
    @score = 0
    @spawn_timer = SPAWN_INTERVAL
    @rng = Random.new
    @rock_pool   = Engine::Pool.new { Rock.new(world_width: @width, world_height: @height) }
    @bullet_pool = Engine::Pool.new { Bullet.new(world_width: @width, world_height: @height) }
    refresh_score
  end

  def on_add
    add_component(Engine::Components::CollisionWorld.new(cell_size: CELL_SIZE))
    @ship = add_node(Ship.new(world_width: @width, world_height: @height))
    @ship.on_fire { |x, y, angle| fire_bullet(x, y, angle) }
    @ship.on_destroyed { lose }
    INITIAL_ROCKS.times { spawn_rock }
    Engine::AudioBus.play_music(:heartbeat)
  end

  def on_remove = Engine::AudioBus.stop_music

  def on_update(dt)
    @spawn_timer -= dt
    if @spawn_timer <= 0.0
      @spawn_timer = SPAWN_INTERVAL
      spawn_rock if @rock_pool.size < MAX_ROCKS
    end
    reclaim
  end

  def on_draw(renderer)
    renderer.background(:space)
    renderer.text(@score_text, 12, 10, z: 20, color: SCORE_COLOR)
  end

  # Called by a Rock when a bullet hits it: score, split into smaller rocks, despawn.
  def destroy_rock(rock)
    @score += rock.points
    refresh_score
    Engine::AudioBus.play_sound(:boom)
    rock.split(@rock_pool, @rng)
    rock.queue_free
  end

  private

  def fire_bullet(x, y, angle)
    bullet = @bullet_pool.acquire
    bullet.reset(x: x, y: y,
                 vx: Math.cos(angle) * BULLET_SPEED,
                 vy: Math.sin(angle) * BULLET_SPEED)
    add_node(bullet)
    Engine::AudioBus.play_sound(:shoot)
  end

  def spawn_rock
    rock = @rock_pool.acquire
    rock.reset(**edge_spawn)
    add_node(rock)
  end

  # A tier-0 rock just outside a random edge, aimed roughly at the ship.
  def edge_spawn
    margin = Rock::RADII.first
    x, y = case @rng.rand(4)
           when 0 then [-margin, @rng.rand * @height]
           when 1 then [@width + margin, @rng.rand * @height]
           when 2 then [@rng.rand * @width, -margin]
           else [@rng.rand * @width, @height + margin]
           end
    aim = Math.atan2(@ship.y - y, @ship.x - x) + ((@rng.rand - 0.5) * AIM_JITTER)
    { x: x, y: y, tier: 0, travel_angle: aim, spin: (@rng.rand - 0.5) * 2.0 }
  end

  def reclaim
    @rock_pool.reclaim_if { |rock| reclaimed?(rock) }
    @bullet_pool.reclaim_if { |bullet| reclaimed?(bullet) }
  end

  # Detach a freed entity from the tree (so its collider unregisters) and report it
  # for the pool to recycle.
  def reclaimed?(entity)
    return false unless entity.freed?

    remove_node(entity)
    true
  end

  def lose
    Engine::AudioBus.play_sound(:hurt)
    root.go(:game_over, score: @score)
  end

  def refresh_score
    @score_text = "Score: #{@score}"
  end
end
