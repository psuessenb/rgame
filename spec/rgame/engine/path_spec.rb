# frozen_string_literal: true

RSpec.describe RGame::Engine::Path do
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

  it 'is open unless told otherwise' do
    expect(path).not_to be_closed
  end

  describe 'closed: true' do
    subject(:loop) { described_class.new([[0.0, 0.0], [100.0, 0.0], [100.0, 100.0]], closed: true) }

    it 'walks back to the first waypoint from the last' do
      expect([loop.count, loop.x_at(3), loop.y_at(3), loop.segment_length(2)])
        .to eq([4, 0.0, 0.0, Math.hypot(100.0, 100.0)])
    end

    it 'counts the closing segment in its length' do
      expect(loop.length).to eq(200.0 + Math.hypot(100.0, 100.0))
    end

    it 'measures the distance to the closing segment too' do
      expect(loop.distance_to(40.0, 60.0)).to be_within(1e-9).of(Math.hypot(10.0, 10.0))
    end

    it 'says it is closed' do
      expect(loop).to be_closed
    end
  end

  # From a parsed map, so the route is checked against the objects it will meet.
  describe '.from_object' do
    def object(shape_xml, rotation: 0)
      tmx = <<~TMX
        <map orientation="orthogonal" width="10" height="10" tilewidth="16" tileheight="16">
          <objectgroup name="routes">
            <object id="1" class="route" x="32" y="16" rotation="#{rotation}">#{shape_xml}</object>
          </objectgroup>
        </map>
      TMX
      RGame::Engine::TileMap.from_tiled(RGame::Engine::Tiled::Map.parse(tmx)).objects.first
    end

    def corners(route) = Array.new(route.count) { [route.x_at(it), route.y_at(it)] }

    it 'walks a polyline open, in the map’s pixels' do
      route = described_class.from_object(object('<polyline points="0,0 64,0 64,32"/>'))
      expect([corners(route), route.closed?]).to eq([[[32.0, 16.0], [96.0, 16.0], [96.0, 48.0]], false])
    end

    it 'walks a polygon closed' do
      route = described_class.from_object(object('<polygon points="0,0 64,0 64,32"/>'))
      expect([route.count, route.closed?]).to eq([4, true])
    end

    it 'turns the route clockwise about the object’s corner by its rotation' do
      route = described_class.from_object(object('<polyline points="0,0 64,0"/>', rotation: 90))
      expect([route.x_at(1), route.y_at(1)]).to match([be_within(1e-9).of(32.0), be_within(1e-9).of(80.0)])
    end

    it 'refuses a rectangle, which has no route' do
      expect { described_class.from_object(object('')) }.to raise_error(ArgumentError, /rectangle.*polyline/)
    end
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

    it 'measures the same from Integer waypoints and an Integer point' do
      integer_path = described_class.new([[0, 0], [100, 0], [100, 100]])

      expect(integer_path.distance_to(50, 10)).to eq(10.0)
    end

    it 'takes the minimum across all segments' do
      # Near the shared corner (100, 0): closest point is the corner itself.
      expect(path.distance_to(110.0, -10.0)).to be_within(1e-9).of(Math.hypot(10.0, 10.0))
    end
  end
end
