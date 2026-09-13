# frozen_string_literal: true

module RGame
  module Engine
    # A uniform-grid spatial hash for broadphase collision: bucket colliders into
    # fixed-size cells, then test only candidates that share a cell instead of every
    # pair. Pure logic; no graphics.
    #
    # Typical per-frame use: `clear`, `insert` every collider of the static set
    # (here: rocks), then `query` around each moving collider (bullets, the ship).
    #
    #   hash.clear
    #   rocks.each { |r| hash.insert(r, *r.aabb) }
    #   hash.query(*bullet.aabb) { |rock| ...narrowphase... }
    class SpatialHash
      OFFSET = 1 << 13
      STRIDE = 1 << 14

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

      # Un-bucket an item from the cells the given box covers — the exact inverse of
      # #insert, so the caller passes the box the item was **inserted at**, not where it
      # is now. That is what keeps this stateless: nothing here remembers where anything
      # was bucketed, and a mover that knows where it started can undo its own insert.
      #
      # An item that was never inserted (or a box that covers none of its cells) is a
      # no-op rather than an error — removing something twice, or removing something that
      # left the tree between two steps, is ordinary rather than a mistake.
      #
      # Allocation-free: `fetch` sidesteps the bucket Hash's default block, which would
      # *create* an empty bucket for every cell walked.
      def remove(item, x, y, w, h)
        each_cell(x, y, w, h) do |key|
          bucket = @buckets.fetch(key, nil)
          bucket&.delete(item)
        end
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

      # Is the one cell containing the point (x, y) holding nothing? A point, not a
      # region: pass any coordinate inside the cell you mean.
      #
      # An item is bucketed by its *bounding box*, and the cell walk is half-open on the
      # far edge (see #last_cell), so "bucketed here" means "overlaps this cell's area"
      # exactly: a box filling one cell fills that cell's bucket and no other, and one
      # covering four cells fills four. So this answers occupancy, not just candidacy —
      # it is true when nothing overlaps the cell at all. What it cannot know is whether
      # an occupant still counts; `CollisionWorld#cell_empty?` adds that, skipping
      # colliders whose node is queued for removal.
      #
      # Reads whatever the most recent inserts left behind: after `clear` every cell is
      # empty until something is inserted again. Allocation-free — `fetch` deliberately
      # sidesteps the bucket Hash's default block, which would *create* the bucket.
      def cell_empty?(x, y)
        bucket = @buckets.fetch(cell_key((x / @cell_size).floor, (y / @cell_size).floor), nil)
        bucket.nil? || bucket.empty?
      end

      private

      def cell_key(col, row) = (col + OFFSET) * STRIDE + (row + OFFSET)

      def each_cell(x, y, w, h)
        col0 = (x / @cell_size).floor
        row0 = (y / @cell_size).floor
        col1 = last_cell(x + w, col0)
        row1 = last_cell(y + h, row0)
        row0.upto(row1) do |row|
          col0.upto(col1) do |col|
            yield cell_key(col, row)
          end
        end
      end

      def last_cell(edge, first)
        cell = (edge / @cell_size).floor
        cell -= 1 if (edge % @cell_size).zero?
        # rubocop:disable Style/MinMaxComparison -- the [cell, first].max it asks for is
        # what the project's own Game/NoNeedlessAllocation rejects on a per-frame path.
        cell < first ? first : cell
        # rubocop:enable Style/MinMaxComparison
      end
    end
  end
end
