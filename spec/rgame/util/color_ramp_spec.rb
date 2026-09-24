# frozen_string_literal: true

RSpec.describe RGame::Util::ColorRamp do
  let(:color) { RGame::Util::Color }
  let(:from) { color.new(255, 240, 160) }
  let(:to) { color.new(255, 120, 0, 0) }
  let(:ramp) { described_class.new(from, to, steps: 5) }

  it 'answers the objects it was given at 0 and at 1' do
    expect(ramp.at(0)).to be(from)
    expect(ramp.at(1)).to be(to)
  end

  it 'moves every channel in a straight line, alpha included' do
    expect(ramp.at(0.5)).to eq(color.new(255, 180, 80, 128))
  end

  it 'answers the nearest step between two' do
    expect(ramp.at(0.3)).to eq(ramp.at(0.25))
  end

  it 'holds a number outside 0 to 1 at the nearer end, and NaN at the start' do
    expect(ramp.at(-0.5)).to be(from)
    expect(ramp.at(7)).to be(to)
    expect(ramp.at(Float::NAN)).to be(from)
  end

  it 'answers the same object for the same step, so reading builds nothing' do
    expect(ramp.at(0.5)).to equal(ramp.at(0.5))
  end

  it 'allocates nothing to read' do
    expect { ramp.at(0.37) }.to allocate_nothing
  end

  it 'refuses fewer than two steps' do
    [1, 0, 2.5, nil].each do |steps|
      expect { described_class.new(from, to, steps:) }.to raise_error(ArgumentError, /steps: must be/)
    end
  end

  it 'refuses anything but two colours' do
    expect { described_class.new(from, 0xFFFFFFFF) }.to raise_error(TypeError, /between two/)
    expect { described_class.new(nil, to) }.to raise_error(TypeError, /between two/)
  end

  it 'keeps what it was built with' do
    expect([ramp.from, ramp.to, ramp.steps]).to eq([from, to, 5])
  end
end
