# frozen_string_literal: true

RSpec.describe Engine::Camera do
  subject(:camera) do
    described_class.new(viewport_width: 100, viewport_height: 100,
                        world_width: 500, world_height: 500)
  end

  it 'centres on the target away from edges' do
    camera.center_on(250, 250)
    expect(camera.x).to eq(200.0) # 250 - 100/2
    expect(camera.y).to eq(200.0)
  end

  it 'clamps to the top-left edge' do
    camera.center_on(10, 10)
    expect(camera.x).to eq(0.0)
    expect(camera.y).to eq(0.0)
  end

  it 'clamps to the bottom-right edge' do
    camera.center_on(490, 490)
    expect(camera.x).to eq(400.0) # world 500 - viewport 100
    expect(camera.y).to eq(400.0)
  end

  it 'pins to origin when the world is smaller than the viewport' do
    small = described_class.new(viewport_width: 100, viewport_height: 100,
                                world_width: 60, world_height: 60)
    small.center_on(30, 30)
    expect(small.x).to eq(0.0)
    expect(small.y).to eq(0.0)
  end
end
