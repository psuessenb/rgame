# frozen_string_literal: true

# The shipped example assets, checked against what the engine actually asks of
# them.
#
# These files are data, so nothing type-checks them and nothing fails to compile
# when one drifts. A misspelt animation key in hero.json is a `KeyError` out of
# AnimationSet on the first frame the hero faces that way — at runtime, in a
# window, in whichever example happens to walk left first. A re-exported PNG one
# row short is a frame sliced out of empty space, which draws nothing and raises
# nothing at all.
#
# Both are cheap to catch here: the descriptor is JSON, AnimationSet is pure
# Engine, and a PNG's dimensions are in the first 24 bytes. No window, no Core.

require 'json'

RSpec.describe 'examples/assets' do # rubocop:disable RSpec/DescribeClass -- the subject is shipped data, not a class
  let(:assets) { File.expand_path('../examples/assets', __dir__) }

  describe 'hero.json' do
    subject(:animations) { RGame::Engine::AnimationSet.new(descriptor[:animations]) }

    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'hero.json')), symbolize_names: true) }

    # The names are not ours to choose: Components::AnimatedSprite picks one of
    # these five from the body's movement intent and looks it up by name, and
    # AnimationSet#row uses `fetch`. A sheet missing one is a crash the moment a
    # player walks that way.
    %i[stand walk_up walk_down walk_left walk_right].each do |name|
      it "declares #{name}, which AnimatedSprite resolves by name" do
        expect { animations.row(name) }.not_to raise_error
      end
    end

    it 'mirrors walk_left off the walk_right row rather than repeating the art' do
      # Every left frame in the source was a pixel-exact mirror of its right
      # counterpart, so the sheet ships three rows and flips one. If a future
      # sheet draws left properly, this example is the thing to delete — but it
      # should be deleted deliberately, not silently stop being true.
      expect(animations.row(:walk_left)).to eq(animations.row(:walk_right))
      expect(animations.flip_x(:walk_left)).to be(true)
      expect(animations.flip_x(:walk_right)).to be(false)
    end

    it 'cycles every walk through all six frames' do
      %i[walk_up walk_down walk_left walk_right].each do |name|
        columns = (0...6).map { |i| animations.col(name, i * 0.125) }

        expect(columns).to eq([0, 1, 2, 3, 4, 5])
      end
    end

    it 'holds stand on one frame' do
      expect((0..5).map { |i| animations.col(:stand, i * 0.5) }.uniq).to eq([0])
    end

    it 'fits every frame inside hero.png' do
      # The guard against a re-export at a different size. Frames are sliced by
      # arithmetic, so a row past the bottom edge is not an error anywhere — it
      # is a sprite that draws nothing.
      width, height = png_size(File.join(assets, descriptor[:image]))
      rows = descriptor[:animations].values.map { |a| a[:row] }.max + 1
      columns = descriptor[:animations].values.map { |a| (a[:col] || 0) + a[:frames] }.max

      expect(columns * descriptor[:frame_width]).to be <= width
      expect(rows * descriptor[:frame_height]).to be <= height
    end
  end

  describe 'ui.json' do
    subject(:elements) { descriptor[:nine_slices] }

    let(:descriptor) { JSON.parse(File.read(File.join(assets, 'ui.json')), symbolize_names: true) }

    # UI::MenuItem draws one of these four by state, and a nine-slice id is
    # resolved by *registration* only — it is an element name, never a file — so
    # a missing one is a KeyError out of the renderer the first time an item
    # reaches that state. The disabled and pressed ones are the nasty pair: a
    # menu can run for a long time before either is drawn.
    it 'declares every element UI::MenuItem draws, plus the panel' do
      required = RGame::Engine::UI::MenuItem::STYLE.values.map(&:to_sym) + [:panel]

      expect(elements.keys).to include(*required)
    end

    it 'keeps every element inside ui.png' do
      width, height = png_size(File.join(assets, descriptor[:image]))

      elements.each_value do |e|
        expect(e[:x] + e[:w]).to be <= width
        expect(e[:y] + e[:h]).to be <= height
      end
    end

    it 'leaves a middle for every element to stretch' do
      # A nine-slice cuts `border` off each side; borders meeting in the middle
      # leave nothing to tile and the widget draws as corners alone.
      elements.each_value do |e|
        expect(e[:border] * 2).to be < e[:w]
        expect(e[:border] * 2).to be < e[:h]
      end
    end
  end

  describe 'town.tmx' do
    subject(:map) { RGame::Engine::TileMap.load(File.join(assets, 'town.tmx')).first }

    let(:fence_row) { 20 }
    let(:gap) { 12..14 }
    let(:north) { [45, 8] }
    let(:south) { [45, 30] }

    it 'is larger than the window on both axes, so there is something to scroll' do
      # A map that fits on screen makes examples/scroll_map a still image:
      # Camera#resolve pins a camera to the origin when the world is smaller
      # than the view, so the failure is a scrolling example that does not.
      # 640x480 is the window every example opens. Written out rather than read
      # off RGame::Game, which lives behind rgame/core and is an undefined
      # constant in this suite by design.
      expect(map.pixel_width).to be > 640
      expect(map.pixel_height).to be > 480
    end

    it 'has exactly one gap in the fence, where the map says it is' do
      # The mistake this catches was made once already: a fence stopping a tile
      # short of the border leaves a second gap nobody planned, and the route
      # quietly uses that one instead of the intended one.
      open_tiles = (0...map.width).reject { |col| map.solid_tile?(col, fence_row) }

      expect(open_tiles).to eq(gap.to_a)
    end

    it 'starts and ends the route on walkable tiles' do
      expect(map.solid_tile?(*north)).to be(false)
      expect(map.solid_tile?(*south)).to be(false)
    end

    it 'forces a route far longer than the straight line between the clearings' do
      # The other mistake made once: with the gap sitting between start and
      # goal, the shortest route cost exactly the straight-line distance and a
      # pathfinder had nothing to show. This is what examples/pathfinding needs
      # from the map, so it is asserted rather than admired.
      steps = shortest_route(map, north, south)
      straight = (south[0] - north[0]).abs + (south[1] - north[1]).abs

      expect(steps).not_to be_nil, 'the two clearings are not connected at all'
      expect(steps).to be > straight * 2
    end
  end

  # Breadth-first over the walkable tiles: how many steps the shortest route
  # takes, or nil if there is none. Deliberately not A* — this states what the
  # map guarantees without depending on the algorithm the example under test
  # will use to find it.
  def shortest_route(map, from, to)
    # Bound once rather than written inside the loop, which would rebuild it per
    # tile visited.
    neighbours = [[1, 0], [-1, 0], [0, 1], [0, -1]].freeze
    distance = { from => 0 }
    queue = [from]
    until queue.empty?
      col, row = queue.shift
      return distance[[col, row]] if [col, row] == to

      neighbours.each do |d_col, d_row|
        step = [col + d_col, row + d_row]
        next if distance.key?(step)
        next unless step[0].between?(0, map.width - 1) && step[1].between?(0, map.height - 1)
        next if map.solid_tile?(*step)

        distance[step] = distance[[col, row]] + 1
        queue << step
      end
    end
    nil
  end

  # A PNG opens with an 8-byte signature and then the IHDR chunk, whose first
  # two fields are width and height as big-endian uint32 at offsets 16 and 20.
  # Reading them here rather than loading the image keeps this suite headless —
  # RGame::Core::Image would pull in SDL and is an undefined constant in this
  # process by design.
  def png_size(path)
    File.binread(path, 24).unpack('@16 N2')
  end
end
