# frozen_string_literal: true

# Components::Timer#update ticks every frame for every spawner/tower that owns one, so it
# must not allocate. The emit path runs only every ~Nth frame, so warm up past one fire.
RSpec.describe Engine::Components::Timer do
  it 'ticks (and emits) without allocating per frame' do
    node = Engine::Node2D.new
    timer = node.add_component(described_class.new(0.8))
    timer.on_timeout { nil } # a real, allocation-free listener
    dt = 1.0 / 60.0
    expect { timer.update(dt) }.to allocate_nothing.after_warmup(120)
  end

  # A one-shot's steady state is the inert post-fire phase (a projectile's despawn timer
  # spends most of its life already fired); the early-out must not allocate either.
  it 'does not allocate while inert after a one-shot has fired' do
    node = Engine::Node2D.new
    timer = node.add_component(described_class.new(0.8, repeating: false))
    timer.on_timeout { nil }
    timer.update(1.0) # fire once, then it stays inert
    dt = 1.0 / 60.0
    expect { timer.update(dt) }.to allocate_nothing
  end
end
