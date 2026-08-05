# frozen_string_literal: true

module Engine
  # An ordered polyline of waypoints an entity walks along — the "road" of a tower
  # defense level. Pure data: it holds the waypoints and the precomputed per-segment
  # lengths, so a follower walking it at runtime allocates nothing.
  #
  # Waypoints are stored flat (x0, y0, x1, y1, …) in one contiguous array rather than a
  # pair-object per point, and read back through scalar accessors (`x_at`/`y_at`), so
  # neither construction shape nor traversal leaks per-waypoint Arrays onto the hot path.
  # A follower (see Components::PathFollow) reads segments by index and interpolates
  # itself; Path never returns a coordinate pair.
  class Path
    attr_reader :length, :count

    # `points` is an Array of [x, y] waypoint pairs in walk order (construction-time, so
    # the pair Arrays are fine here). At least two are required — a path with one point
    # has nowhere to walk.
    def initialize(points)
      raise ArgumentError, 'a Path needs at least two waypoints' if points.length < 2

      @coords = points.flatten.freeze
      @count = points.length
      @segment_lengths, @length = build_segments
    end

    # World coordinates of waypoint `i` (0-based), as scalars (no allocation).
    def x_at(index) = @coords[index * 2]
    def y_at(index) = @coords[(index * 2) + 1]

    # Length of the segment from waypoint `i` to waypoint `i + 1`. There are
    # `count - 1` segments, indexed 0..count-2.
    def segment_length(index) = @segment_lengths[index]

    # Shortest distance from the point (x, y) to the polyline — e.g. how far a spot is
    # from the road, so a tower-defense level can mask placement cells that sit on it.
    # Pure scalar maths, allocation-free.
    def distance_to(x, y)
      min = Float::INFINITY
      (@count - 1).times do |i|
        d = segment_distance(x, y, x_at(i), y_at(i), x_at(i + 1), y_at(i + 1))
        min = d if d < min
      end
      min
    end

    private

    # Distance from (px, py) to the segment (ax, ay)-(bx, by): project the point onto the
    # segment, clamp the projection to the segment's ends, and measure to that foot.
    def segment_distance(px, py, ax, ay, bx, by)
      abx = bx - ax
      aby = by - ay
      len2 = (abx * abx) + (aby * aby)
      t = len2.zero? ? 0.0 : (((px - ax) * abx) + ((py - ay) * aby)) / len2
      t = 0.0 if t < 0.0
      t = 1.0 if t > 1.0
      dx = px - (ax + (t * abx))
      dy = py - (ay + (t * aby))
      Math.sqrt((dx * dx) + (dy * dy))
    end

    def build_segments
      lengths = []
      total = 0.0
      (@count - 1).times do |i|
        dx = x_at(i + 1) - x_at(i)
        dy = y_at(i + 1) - y_at(i)
        len = Math.sqrt((dx * dx) + (dy * dy))
        lengths << len
        total += len
      end
      [lengths.freeze, total]
    end
  end
end
