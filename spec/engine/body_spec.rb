# frozen_string_literal: true

RSpec.describe Engine::Body do
  it 'integrates position and angle by velocity over dt' do
    body = described_class.new(x: 0.0, y: 0.0, vx: 10.0, vy: -4.0, angle: 0.0, spin: 2.0)
    body.integrate(0.5)
    expect(body.x).to eq(5.0)
    expect(body.y).to eq(-2.0)
    expect(body.angle).to eq(1.0)
  end

  describe '#wrap!' do
    it 'wraps the centre to the opposite side once it passes the margin' do
      body = described_class.new(x: -11.0, y: 50.0)
      body.wrap!(100, 100, 10) # span = 100 + 2*10 = 120
      expect(body.x).to eq(109.0)
    end

    it 'leaves a body exactly at the margin alone (fresh spawn never wraps)' do
      body = described_class.new(x: -10.0, y: 50.0)
      body.wrap!(100, 100, 10)
      expect(body.x).to eq(-10.0)
    end
  end

  describe '#offscreen?' do
    it 'is true only once fully past an edge by the margin' do
      body = described_class.new(x: -11.0, y: 50.0)
      expect(body.offscreen?(100, 100, 10)).to be(true)
    end

    it 'is false while still within the margin' do
      body = described_class.new(x: -9.0, y: 50.0)
      expect(body.offscreen?(100, 100, 10)).to be(false)
    end
  end
end
