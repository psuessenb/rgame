# frozen_string_literal: true

# Particles run every frame, and a burst is exactly when a game would allocate
# without noticing: the pool is built when the emitter is, so nothing after that
# may build anything.
RSpec.describe RGame::Engine::Components::Particles do
  def color = RGame::Util::Color

  def emitter(**)
    ramp = RGame::Util::ColorRamp.new(color.new(255, 240, 160), color.new(255, 120, 0, 0))
    described_class.new(limit: 48, lifetime: 0.2..0.4, speed: 30.0..80.0, spread: Math::PI,
                        gravity: 90.0, size: 3, ramp:, blend: :add, rng: Random.new(1), **)
  end

  def mount(particles)
    node = RGame::Engine::Node2D.new
    node.add_component(particles)
    node.enter_tree
    node
  end

  # Ruby fills a call site's cache the first time it runs, once per process,
  # so the same calls run first on another emitter. The one measured is fresh.
  it 'allocates nothing to burst and run the burst out, a fresh emitter\'s first burst included' do
    run = lambda do |particles, node|
      particles.burst(16, 4.5, -2.5)
      node.update(0.5)
    end
    warm = emitter
    run.call(warm, mount(warm))
    particles = emitter
    node = mount(particles)

    expect { run.call(particles, node) }.to allocate_nothing.after_warmup(0)
  end

  it 'allocates nothing to stream and step' do
    particles = emitter
    node = mount(particles)
    particles.rate = 40

    expect { node.update(1.0 / 60) }.to allocate_nothing
  end

  it 'allocates nothing to draw' do
    particles = emitter
    node = mount(particles)
    particles.burst(16)
    node.update(0.05)
    renderer = QuietRenderer.new
    view = screen_view

    expect { node.draw(renderer, view) }.to allocate_nothing
  end
end
