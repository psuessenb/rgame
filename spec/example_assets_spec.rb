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

  # A PNG opens with an 8-byte signature and then the IHDR chunk, whose first
  # two fields are width and height as big-endian uint32 at offsets 16 and 20.
  # Reading them here rather than loading the image keeps this suite headless —
  # RGame::Core::Image would pull in SDL and is an undefined constant in this
  # process by design.
  def png_size(path)
    File.binread(path, 24).unpack('@16 N2')
  end
end
