# frozen_string_literal: true

# The blocker-source protocol's optional fourth question, stated once so that every source
# answering it is held to the same meaning.
#
#   source.travel?(x, y, w, h, dx, dy)  # -> can this box move (dx, dy) without being stopped?
#
# "Stopped" is read exactly the way Engine::CollisionSystem reads a source: a resolve stops a
# step when it lands *short* of where the step was heading. A landing past the intended one is
# not a stop — CollisionSystem ignores it — so a travel through one is still clear. Reading it
# that way is what lets a system answer travel? as "every source's travel?", with no sweep over
# several sources at once.
#
# ## What the host must provide
#
#   def blocker_source(rows, tile:) = ...
#
# A source over a map drawn as rows of text — '#' solid, anything else open — at `tile` pixels a
# cell, with outside the rows open.
#
# ## How it is checked
#
# Against TravelOracle, below: a walker that moves the box along the segment in steps no longer
# than a given size, resolving each step X then Y through the source's *own* resolve_x and
# resolve_y, the way a mover does. A source's travel? may be conservative — refuse a segment the
# oracle would walk — but must never clear one the oracle is stopped on, at any step under a
# quarter tile. The group also checks it is not trivially conservative.
module TravelOracle
  module_function

  def short?(landed, intended, delta)
    delta.positive? ? landed < intended : delta.negative? && landed > intended
  end

  # Whether a walker stepping at most `step` pixels at a time along (dx, dy) is stopped.
  def stopped_on_the_way?(source, x, y, w, h, dx, dy, step:)
    start_x = x
    start_y = y
    count = [(Math.hypot(dx, dy) / step).ceil, 1].max
    (1..count).any? do |k|
      step_x = start_x + (dx * k / count) - x
      step_y = start_y + (dy * k / count) - y
      landed_x = source.resolve_x(x, y, w, h, step_x)
      next true if short?(landed_x, x + step_x, step_x)

      landed_y = source.resolve_y(landed_x, y, w, h, step_y)
      next true if short?(landed_y, y + step_y, step_y)

      x = landed_x
      y = landed_y
      false
    end
  end
end

RSpec.shared_examples 'a blocker source answering travel?' do
  let(:tile) { 16 }

  it 'travels open ground' do
    source = blocker_source(Array.new(6) { '........' }, tile: tile)
    expect(source.travel?(4, 4, 12, 6, 100, 60)).to be(true)
  end

  it 'does not travel through a solid tile' do
    source = blocker_source(Array.new(6) { '....#...' }, tile: tile)
    expect([source.travel?(4, 20, 12, 6, 100, 0), source.travel?(4, 20, 12, 6, 40, 0)]).to eq([false, true])
  end

  # From the centre of (0, 0) to the centre of (5, 2) the line passes 1.6 px above the tree's
  # top-left corner: a point clears it and a 12x6 feet box does not.
  it 'refuses a box a corner that a point clears' do
    source = blocker_source(['......', '......', '...#..', '......'], tile: tile)
    expect([source.travel?(8, 8, 0, 0, 80, 32), source.travel?(2, 5, 12, 6, 80, 32)]).to eq([true, false])
  end

  describe 'against a walker resolving its own steps' do
    let(:rows) do
      [
        '....#....#......',
        '..#.....#.#.....',
        '.....###.##.....',
        '.....#.#.#.#....',
        '............#...',
        '...........#..#.',
        '.......#........',
        '....#...........',
        '#............###',
        '..........#.....',
        '##........#....#',
        '#..#.....#......'
      ]
    end

    def open_box?(x, y, w, h)
      ((y / tile).floor..((y + h - 1e-9) / tile).floor).all? do |row|
        ((x / tile).floor..((x + w - 1e-9) / tile).floor).all? { |col| rows[row][col] == '.' }
      end
    end

    # Thousands of segments, because the case that needs the most is rare: a walker's step at
    # nearly a quarter tile straddling two of a sweep's windows. Measured with a sweep whose
    # windows did not overlap, it was stopped on about 3 segments in a thousand.
    it 'never clears a segment the walker is stopped on, at any step under a quarter tile' do
      source = blocker_source(rows, tile: tile)
      random = Random.new(11)
      answers = Hash.new(0)
      wrong = []

      3000.times do
        w, h = [[12, 6], [16, 16], [5.5, 3.25]].sample(random: random)
        x = random.rand(0.0..((rows.first.length * tile) - w))
        y = random.rand(0.0..((rows.length * tile) - h))
        next unless open_box?(x, y, w, h)

        dx = random.rand(-64.0..64.0)
        dy = random.rand(-64.0..64.0)
        clear = source.travel?(x, y, w, h, dx, dy)
        answers[clear] += 1
        next unless clear

        [1.0, 2.3, tile * 0.22, (tile / 4.0) - 0.01].each do |step|
          stopped = TravelOracle.stopped_on_the_way?(source, x, y, w, h, dx, dy, step: step)
          wrong << [x, y, w, h, dx, dy, step] if stopped
        end
      end

      expect([wrong, answers[true] > 300, answers[false] > 300]).to eq([[], true, true])
    end
  end

  describe 'the walker it is checked against' do
    # A box starting left of the world, moving right: the world edge lands it on 0.0, past the
    # -8.0 it was heading for. CollisionSystem ignores that, and so does the walker.
    it 'is not stopped by a landing past the one it was heading for' do
      bounds = RGame::Engine::BoundsBlockers.new(bounds: RGame::Engine::Components::World.new(width: 100, height: 100))
      expect([bounds.resolve_x(-10, 10, 4, 4, 2),
              TravelOracle.stopped_on_the_way?(bounds, -10, 10, 4, 4, 2, 0, step: 2.0)]).to eq([0.0, false])
    end

    it 'is stopped by a landing short of it' do
      source = blocker_source(Array.new(2) { '..#.' }, tile: tile)
      expect(TravelOracle.stopped_on_the_way?(source, 4, 4, 8, 8, 40, 0, step: 1.0)).to be(true)
    end
  end
end
