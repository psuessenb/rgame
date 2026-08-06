# frozen_string_literal: true

# Timer.update ticks every frame for every spawner/tower that owns one, so it must not
# allocate. Guards that with the allocate_nothing matcher.
RSpec.describe Engine::Timer do
  it 'ticks without allocating per frame' do
    timer = described_class.new(0.8)
    dt = 1.0 / 60.0
    # The full read cadence a spawner runs each frame: tick, check, and (when it fires)
    # consume. The interval fires only every ~48 frames, so warm up well past one fire —
    # otherwise the consume branch's one-time setup lands in the measured window.
    expect do
      timer.update(dt)
      timer.consume if timer.ready?
    end.to allocate_nothing.after_warmup(120)
  end
end
