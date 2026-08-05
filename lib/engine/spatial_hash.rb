# frozen_string_literal: true

module Engine
  # A uniform-grid spatial hash for broadphase collision: bucket colliders into
  # fixed-size cells, then test only candidates that share a cell instead of every
  # pair. Pure logic; no Gosu.
  #
  # Typical per-frame use: `clear`, `insert` every collider of the static set
  # (here: rocks), then `query` around each moving collider (bullets, the ship).
  #
  #   hash.clear
  #   rocks.each { |r| hash.insert(r, *r.aabb) }
  #   hash.query(*bullet.aabb) { |rock| ...narrowphase... }
  class SpatialHash
    # Cell (col, row) → one integer key. The offset keeps negative cells (objects
    # off-screen / mid-wrap) non-negative; the stride keeps pairs unique. Both fit
    # in a tagged Fixnum, so keying allocates nothing.
    OFFSET = 1 << 20
    STRIDE = 1 << 21

    def initialize(cell_size:)
      @cell_size = cell_size
      @buckets = Hash.new { |h, key| h[key] = [] }
    end

    # Reuse the bucket arrays across frames (clear contents, keep capacity).
    def clear
      @buckets.each_value(&:clear)
    end

    def insert(item, x, y, w, h)
      each_cell(x, y, w, h) { |key| @buckets[key] << item }
    end

    # Yield every item whose buckets overlap the region. Dedup contract: an item
    # spanning several cells may be yielded more than once. Narrowphase callers
    # must already guard with `next if a.dead? || b.dead?` to make hits idempotent,
    # so we skip a per-query visited set and stay allocation-free.
    def query(x, y, w, h, &)
      each_cell(x, y, w, h) do |key|
        bucket = @buckets[key]
        bucket.each(&) unless bucket.empty?
      end
    end

    # Broadphase a circle: yield every item bucketed in a cell the circle's bounding
    # box covers — the radial counterpart to #query, for range/nearest lookups. Same
    # dedup contract (an item may be yielded more than once; the narrowphase caller
    # refines by true distance). Allocation-free.
    def query_circle(cx, cy, r, &)
      d = r * 2
      query(cx - r, cy - r, d, d, &)
    end

    private

    def each_cell(x, y, w, h)
      col0 = (x / @cell_size).floor
      row0 = (y / @cell_size).floor
      col1 = ((x + w) / @cell_size).floor
      row1 = ((y + h) / @cell_size).floor
      row0.upto(row1) do |row|
        col0.upto(col1) do |col|
          yield (col + OFFSET) * STRIDE + (row + OFFSET)
        end
      end
    end
  end
end
