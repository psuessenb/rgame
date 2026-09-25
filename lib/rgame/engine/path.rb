# frozen_string_literal: true

module RGame
  module Engine
    # An ordered polyline of waypoints an entity walks along — a road, a patrol
    # route, a track. Pure data: it holds the waypoints and the precomputed per-segment
    # lengths, so a follower walking it at runtime allocates nothing.
    #
    # Waypoints are stored flat (x0, y0, x1, y1, …) in one contiguous array rather than a
    # pair-object per point, and read back through scalar accessors (`x_at`/`y_at`), so
    # neither construction shape nor traversal leaks per-waypoint Arrays onto the hot path.
    # A follower (see Components::PathFollow) reads segments by index and interpolates
    # itself; Path never returns a coordinate pair.
    #
    # **A closed path walks back to its first waypoint from its last**, as a Tiled polygon
    # does. It stores that first waypoint again at the end, so `count` counts it twice and
    # the last segment is the one that closes the loop. A follower walks a closed path
    # exactly as it walks an open one, and arrives where it started.
    #
    #   Path.new([[0, 0], [100, 0], [100, 100]], closed: true)   # count 4, length ~341
    class Path
      attr_reader :length, :count

      # `points` is an Array of [x, y] waypoint pairs in walk order (construction-time, so
      # the pair Arrays are fine here). At least two are required — a path with one point
      # has nowhere to walk.
      def initialize(points, closed: false)
        raise ArgumentError, 'a Path needs at least two waypoints' if points.length < 2

        points += [points.first] if closed
        @closed = closed
        @coords = points.flatten.freeze
        @count = points.length
        @segment_lengths, @length = build_segments
      end

      # The route a polyline or polygon object on a map describes, in the map's pixels: a
      # polyline is an open path, and a polygon a closed one. The object's rotation turns
      # the route about its (x, y), as Tiled draws it. Raises ArgumentError for any other
      # shape, which has no route to walk.
      #
      #   PathFollow.new(speed: 40, path: Path.from_object(object), loop: true)
      def self.from_object(object)
        unless %i[polyline polygon].include?(object.shape)
          raise ArgumentError, "a #{object.shape} object has no route to walk; draw a polyline or a polygon"
        end

        new(rotated(object), closed: object.shape == :polygon)
      end

      def self.rotated(object)
        return object.points if object.rotation.zero?

        radians = object.rotation * Math::PI / 180
        cos = Math.cos(radians)
        sin = Math.sin(radians)
        object.points.map do |px, py|
          dx = px - object.x
          dy = py - object.y
          [object.x + (dx * cos) - (dy * sin), object.y + (dx * sin) + (dy * cos)]
        end
      end
      private_class_method :rotated

      # Whether the path walks back to its first waypoint.
      def closed? = @closed

      # World coordinates of waypoint `i` (0-based), as scalars (no allocation).
      def x_at(index) = @coords[index * 2]
      def y_at(index) = @coords[(index * 2) + 1]

      # Length of the segment from waypoint `i` to waypoint `i + 1`. There are
      # `count - 1` segments, indexed 0..count-2.
      def segment_length(index) = @segment_lengths[index]

      # Shortest distance from the point (x, y) to the polyline — e.g. how far a spot is
      # from the road, so a level can keep things from being placed on or beside it.
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

      def segment_distance(px, py, ax, ay, bx, by)
        abx = bx - ax
        aby = by - ay
        len2 = ((abx * abx) + (aby * aby)).to_f
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
end
