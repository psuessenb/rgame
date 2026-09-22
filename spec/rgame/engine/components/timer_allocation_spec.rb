# frozen_string_literal: true

# Components::Timer#update ticks every frame for every spawner/turret that owns one, so it
# must not allocate. The emit path runs only every ~Nth frame, so warm up past one fire.
RSpec.describe RGame::Engine::Components::Timer do
  it 'ticks (and emits) without allocating per frame' do
    node = RGame::Engine::Node2D.new
    timer = node.add_component(described_class.new(0.8))
    timer.on_elapsed { nil } # a real, allocation-free listener
    dt = 1.0 / 60.0
    expect { timer._update(dt) }.to allocate_nothing.after_warmup(120)
  end
end
