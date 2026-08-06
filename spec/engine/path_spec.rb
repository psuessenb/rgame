# frozen_string_literal: true

RSpec.describe Engine::Path do
  # An L-shaped road: right 100, then down 100. Two segments of length 100, total 200.
  subject(:path) { described_class.new([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]]) }

  it 'exposes its waypoint count' do
    expect(path.count).to eq(3)
  end

  it 'reads back each waypoint as scalar coordinates' do
    expect([path.x_at(0), path.y_at(0)]).to eq([0.0, 0.0])
    expect([path.x_at(1), path.y_at(1)]).to eq([100.0, 0.0])
    expect([path.x_at(2), path.y_at(2)]).to eq([100.0, 100.0])
  end

  it 'precomputes per-segment lengths' do
    expect([path.segment_length(0), path.segment_length(1)]).to eq([100.0, 100.0])
  end

  it 'sums the segment lengths into the total length' do
    expect(path.length).to eq(200.0)
  end

  it 'measures diagonal segments by euclidean distance' do
    diagonal = described_class.new([[0.0, 0.0], [3.0, 4.0]])
    expect(diagonal.length).to eq(5.0)
  end

  it 'rejects a path with fewer than two waypoints' do
    expect { described_class.new([[0.0, 0.0]]) }.to raise_error(ArgumentError)
  end

  describe '#distance_to' do
    it 'is zero for a point on the polyline' do
      expect(path.distance_to(50.0, 0.0)).to eq(0.0)
    end

    it 'is the perpendicular distance to the nearest segment' do
      expect(path.distance_to(50.0, 10.0)).to eq(10.0)  # beside the horizontal segment
      expect(path.distance_to(130.0, 50.0)).to eq(30.0) # beside the vertical segment
    end

    it 'clamps to a segment endpoint when the foot falls past the end' do
      expect(path.distance_to(-30.0, 0.0)).to eq(30.0) # before the start, nearest is (0, 0)
    end

    it 'takes the minimum across all segments' do
      # Near the shared corner (100, 0): closest point is the corner itself.
      expect(path.distance_to(110.0, -10.0)).to be_within(1e-9).of(Math.hypot(10.0, 10.0))
    end
  end
end
