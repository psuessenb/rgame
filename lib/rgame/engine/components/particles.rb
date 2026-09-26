# frozen_string_literal: true

module RGame
  module Engine
    module Components
      # Sparks, embers and dust: small squares that fly out from a point, fall,
      # change colour as they age, and vanish.
      #
      #   EMBER = Util::ColorRamp.new(Util::Color.new(255, 240, 160), Util::Color.new(255, 120, 0, 0))
      #
      #   sparkles = actors.add_node(Engine::Node2D.new)
      #   particles = sparkles.add_component(Engine::Components::Particles.new(
      #     limit: 48, lifetime: 0.4..0.7, speed: 30.0..80.0, spread: Math::PI,
      #     gravity: 90.0, size: 3, ramp: EMBER, blend: :add
      #   ))
      #   particles.burst(16, x, y)   # 16 at once
      #   particles.rate = 40         # a stream from the node's origin, per second
      #
      # **A particle is a plain object in a Pool, not a node.** The pool builds
      # `limit` of them when the component is made, so bursting, streaming,
      # stepping and drawing allocate nothing after that. A burst past the limit
      # places what fits and drops the rest.
      #
      # Each particle takes a lifetime and a speed from its ranges, and a
      # heading up to `spread` radians either side of `direction`. Each update
      # adds `gravity` to its downward speed, moves it, and frees it once its
      # age reaches its lifetime. It draws as a square of `size` centred on
      # where it is, in `ramp.at(age / lifetime)`, inside the renderer's
      # `blended(blend)`.
      #
      # Particles live in the node's local space, so they move with the node.
      # An emitter that must outlive what it sparkles for, as a coin that frees
      # itself when taken, goes on a node of its own, and the coin is handed it.
      #
      # They draw from the root's RandomSource, found when the component
      # attaches, so a seeded game places every particle the same each run. An
      # `rng:` passed in wins; it is anything answering `rand` as `Random#rand`
      # does. Time reaches particles only through `update`, so a paused node's
      # particles hold still. A node that leaves the tree takes
      # its particles with it.
      class Particles < Engine::Component
        # One particle's state, rewritten each time the pool hands it out.
        class Particle
          attr_accessor :x, :y, :vx, :vy, :age, :lifetime

          def place(x, y, vx, vy, lifetime)
            @x = x
            @y = y
            @vx = vx
            @vy = vy
            @age = 0.0
            @lifetime = lifetime
            self
          end
        end
        private_constant :Particle

        CARRY_SLACK = 1e-9
        private_constant :CARRY_SLACK

        sealed_reader :limit, :blend

        # Particles a second, streamed from the node's origin. 0, the default,
        # streams none.
        sealed_reader :rate

        # `limit` is how many can be alive at once. `lifetime` in seconds and
        # `speed` in pixels a second are each a number or a Range to draw one
        # from. `direction` and `spread` are radians: 0 is right and
        # -Math::PI / 2 up, and a spread of Math::PI is every way. `gravity` is
        # pixels a second added to the downward speed each second. `ramp` is a
        # Util::ColorRamp, and `blend` a mode `renderer.blended` takes.
        def initialize(limit:, lifetime:, speed:, ramp:, direction: -Math::PI / 2, spread: Math::PI,
                       gravity: 0.0, size: 2, blend: :alpha, rng: nil)
          super()
          @rgame_limit = positive(limit, 'limit', integer: true)
          @rgame_lifetime = float_range(lifetime, 'lifetime', above_zero: true)
          @rgame_speed = float_range(speed, 'speed')
          @rgame_ramp = ramp!(ramp)
          @rgame_direction = direction.to_f
          @rgame_spread = spread.to_f
          @rgame_gravity = gravity.to_f
          @rgame_size = positive(size, 'size')
          @rgame_half = @rgame_size / 2.0
          @rgame_blend = Util::Blend.mode!(blend)
          @rgame_given_rng = rng
          @rgame_rate = 0
          @rgame_carry = 0.0
          @rgame_pool = Engine::Pool.new { Particle.new }.reserve(limit)
        end

        # Changes the stream's rate. Must be a number of 0 or more.
        def rate=(per_second)
          unless per_second.is_a?(Numeric) && per_second >= 0
            raise ArgumentError, "rate must be a number of particles a second, 0 or more, not #{per_second.inspect}"
          end

          @rgame_carry = 0.0 if per_second.zero?
          @rgame_rate = per_second
        end

        # How many are alive.
        def live = @rgame_pool.size

        # Places `count` particles at (x, y) in the node's local space, or as
        # many as the limit leaves room for. `count` is an Integer. Returns how
        # many it placed. With no `rng:`, it raises until the node is in the
        # tree, where it finds the RandomSource.
        # hot-path
        def burst(count, x = 0.0, y = 0.0)
          unless @rgame_rng
            raise 'Particles#burst draws from the root\'s RandomSource, found once its node is in the ' \
                  'tree. Burst after the node enters the tree, or pass an rng: to Particles.new.'
          end

          placed = [count, @rgame_limit - @rgame_pool.size].min
          placed = 0 if placed.negative?
          i = 0
          while i < placed
            emit(x, y)
            i += 1
          end
          placed
        end

        def _update(dt)
          @rgame_pool.each { step(it, dt) }
          @rgame_pool.reclaim_if { it.age >= it.lifetime }
          stream(dt) if @rgame_rate.positive?
        end

        def _draw(renderer, _view)
          return if @rgame_pool.empty?

          renderer.blended(@rgame_blend) do
            @rgame_pool.each { draw_particle(renderer, it) }
          end
        end

        def _attach
          @rgame_rng = @rgame_given_rng || node.system!(RandomSource)
        end

        def _detach
          @rgame_pool.reclaim_if { true }
          @rgame_carry = 0.0
        end

        private

        def step(particle, dt)
          particle.vy += @rgame_gravity * dt
          particle.x += particle.vx * dt
          particle.y += particle.vy * dt
          particle.age += dt
        end

        def stream(dt)
          @rgame_carry += @rgame_rate * dt
          whole = (@rgame_carry + CARRY_SLACK).floor
          return if whole.zero?

          @rgame_carry -= whole
          burst(whole)
        end

        def emit(x, y)
          heading = @rgame_direction + (@rgame_spread * ((2.0 * @rgame_rng.rand) - 1.0))
          speed = @rgame_rng.rand(@rgame_speed)
          @rgame_pool.acquire.place(x, y, Math.cos(heading) * speed, Math.sin(heading) * speed,
                                    @rgame_rng.rand(@rgame_lifetime))
        end

        def draw_particle(renderer, particle)
          renderer.rect(particle.x - @rgame_half, particle.y - @rgame_half, @rgame_size, @rgame_size,
                        color: @rgame_ramp.at(particle.age / particle.lifetime))
        end

        def ramp!(ramp)
          return ramp if ramp.is_a?(Util::ColorRamp)

          raise TypeError, "ramp: must be a #{Util::ColorRamp}, not #{ramp.inspect}"
        end

        def positive(value, name, integer: false)
          return value if (integer ? value.is_a?(Integer) : value.is_a?(Numeric)) && value.positive?

          raise ArgumentError, "#{name}: must be a positive #{integer ? 'Integer' : 'number'}, not #{value.inspect}"
        end

        def float_range(value, name, above_zero: false)
          low, high = value.is_a?(Range) ? [value.begin, value.end] : [value, value]
          unless low.is_a?(Numeric) && high.is_a?(Numeric) && low <= high && (above_zero ? low.positive? : low >= 0)
            raise ArgumentError, "#{name}: must be a number or a Range of numbers, " \
                                 "#{above_zero ? 'above' : 'from'} 0, not #{value.inspect}"
          end

          low.to_f..high.to_f
        end
      end
    end
  end
end
