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
      # Cell (col, row) → one integer key. The offset keeps negative cells (objects
      # off-screen / mid-wrap) non-negative; the stride keeps pairs unique. Both are
      # sized to keep every packed key inside a tagged Fixnum, so keying allocates
      # nothing on the query path (CLAUDE.md: never allocate on the per-frame path).
      #
      # The ceiling that sizes them is Windows, not Linux/macOS: CRuby's immediate
      # Fixnum range comes from a C `long`, which is 64 bits on LP64 (Linux, macOS)
      # but stays 32 bits on Windows' LLP64 even in a 64-bit process — so a value
      # comfortably inside Fixnum range on Linux (this packing used to run up to
      # ~2**42) silently becomes a heap-allocated Bignum on Windows instead, one
      # allocation per cell per query. OFFSET/STRIDE here keep the largest possible
      # packed key (both coordinates at the far corner) under 2**28 — well inside
      # Windows' ~2**30 Fixnum ceiling — while still allowing cell coordinates out
      # to +/-8192, i.e. a world some sixteen million pixels wide at this file's own
      # cell_size: 64 example. A game whose world exceeds that wraps into a
      # neighbouring cell's key instead of raising; see #each_cell below.
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

      # The one place the packing above is spelled out — see OFFSET/STRIDE for what
      # keeps the result a Fixnum on every platform.
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

      # The cell holding the far edge of a region starting in cell `first`.
      #
      # A region spans [start, edge), so one ending exactly on a cell boundary stops at
      # the cell before it — a box filling one cell is bucketed into that cell and no
      # other. This mirrors CollisionBox.overlap?, and the two have to agree: bucketing
      # that reached one cell further would report neighbours as candidates (harmless
      # but wasteful), and one that reached less far would miss a real contact.
      #
      # The floor is for a zero-size region, which the occupancy queries use to name a
      # single cell: [x, x) ends where it starts, and would otherwise span nothing.
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
