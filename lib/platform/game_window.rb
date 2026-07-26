# frozen_string_literal: true

module Platform
  # The Gosu shell: owns the fixed-timestep loop and drives the SceneManager.
  # Game logic lives in scenes/entities; this class only translates Gosu's
  # variable frame timing into deterministic fixed steps.
  class GameWindow < Gosu::Window
    STEP      = 1.0 / 60.0   # seconds of simulation per step
    MAX_STEPS = 5            # catch-up cap (spiral-of-death defense)

    attr_accessor :root

    def initialize(width:, height:, caption:, root:, renderer:, mapper:)
      super(width, height)
      self.caption = caption

      @root        = root
      @renderer    = renderer
      @mapper      = mapper
      @backend     = GosuInput.new(self)
      @clock       = Clock.new
      @accumulator = 0.0
      @dirty       = true # draw the first frame
      @overlay     = Engine::DebugOverlay.new # always wired up; F1 reveals it
    end

    def update
      @accumulator += @clock.delta

      # Input is constant within a tick: poll once and reuse across catch-up steps.
      actions = @mapper.poll(@backend)

      steps = 0
      while @accumulator >= STEP && steps < MAX_STEPS
        @root.control(actions)
        @root.update(STEP)
        @root.sweep_freed # flush queue_free'd nodes outside the update traversal
        @accumulator -= STEP
        steps += 1
      end

      # Couldn't keep up: drop the backlog and run slow-mo rather than spiral.
      @accumulator = 0.0 if steps == MAX_STEPS

      # Only the simulation advancing makes the frame stale; if no step ran this
      # tick (rendering faster than the sim), there's nothing new to show.
      @dirty = true if steps.positive?
    end

    # Regime 1 (see docs §4): when draw is the bottleneck, Gosu keeps calling
    # update at cadence and skips draw, so the sim stays real-time. The OS may
    # still force a redraw, which is fine — draw always renders valid state.
    def needs_redraw?
      # While the overlay is up, redraw every tick so its FPS/Δ-per-frame stay live even
      # when the simulation is idle (which would otherwise skip the frame).
      @dirty || @overlay.visible?
    end

    def draw
      @root.draw(@renderer)
      @overlay.draw(@renderer, width, height, Gosu.fps) # last, so it layers on top
      @dirty = false
    end

    def button_down(id)
      close if id == Gosu::KB_ESCAPE
      @overlay.toggle if id == Gosu::KB_F1
    end
  end
end
