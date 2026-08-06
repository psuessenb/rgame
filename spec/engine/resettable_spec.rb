# frozen_string_literal: true

RSpec.describe Engine::Resettable do
  let(:point) { described_class.define(:x, :y) }

  it 'exposes read-only accessors for its fields' do
    p = point.new(3, 4)
    expect([p.x, p.y]).to eq([3, 4])
  end

  it 'has no per-field setters (only a bulk reset)' do
    p = point.new(1, 2)
    expect(p).not_to respond_to(:x=)
    expect(p).not_to respond_to(:y=)
  end

  it 'reset overwrites every field and returns the same object' do
    p = point.new(1, 2)
    result = p.reset(9, 8)
    expect(result).to equal(p) # recycled in place
    expect([p.x, p.y]).to eq([9, 8])
  end

  it 'reset allocates nothing in steady state' do
    p = point.new(0, 0)
    p.reset(1, 1) # warm up
    before = GC.stat(:total_allocated_objects)
    1000.times { p.reset(2, 3) }
    after = GC.stat(:total_allocated_objects)
    expect(after - before).to be < 100
  end

  it 'rejects field names that are not plain identifiers' do
    expect { described_class.define(:'a-b') }.to raise_error(ArgumentError)
  end

  context 'with keyword_init: true' do
    let(:point) { described_class.define(:x, :y, keyword_init: true) }

    it 'constructs and resets via keyword fields' do
      p = point.new(x: 1, y: 2)
      expect([p.x, p.y]).to eq([1, 2])
      p.reset(x: 9, y: 8)
      expect([p.x, p.y]).to eq([9, 8])
    end

    it 'still exposes no setters' do
      expect(point.new(x: 1, y: 2)).not_to respond_to(:x=)
    end

    it 'reset allocates nothing in steady state (named keywords, not **splat)' do
      p = point.new(x: 0, y: 0)
      p.reset(x: 1, y: 1) # warm up
      before = GC.stat(:total_allocated_objects)
      1000.times { p.reset(x: 2, y: 3) }
      after = GC.stat(:total_allocated_objects)
      expect(after - before).to be < 100
    end
  end
end
