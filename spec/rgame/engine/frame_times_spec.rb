# frozen_string_literal: true

RSpec.describe RGame::Engine::FrameTimes do
  # Every tick of ten seconds at 60 a second, added up as a game adds its dt.
  let(:ticks) do
    elapsed = 0.0
    Array.new(600) { elapsed += 1 / 60.0 }
  end

  describe '.even' do
    # AnimationSet#col at 78e99d0, which this replaced.
    def divided(elapsed, count, fps) = (elapsed / (1.0 / fps)).floor % count

    [1, 6, 8].each do |fps|
      it "shows the frame AnimationSet showed, on every tick of ten seconds at #{fps} fps" do
        times = described_class.even(6, 1.0 / fps)

        expect(ticks.reject { times.index_at(it) == divided(it, 6, fps) }).to be_empty
      end
    end

    it "shows the next frame at a frame's exact end, and loops" do
      times = described_class.even(4, 0.25)

      expect([0.0, 0.2, 0.25, 0.5, 0.75, 1.0, 1.3].map { times.index_at(it) }).to eq([0, 0, 1, 2, 3, 0, 1])
    end

    it 'finds every frame of a loop without allocating' do
      times = described_class.even(4, 0.25)

      expect { times.index_at(0.1) + times.index_at(0.3) + times.index_at(0.6) + times.index_at(0.9) }
        .to allocate_nothing
    end
  end

  describe '.new' do
    # tile_map_spec's animated tile, whose frames last 100, 250 and 50 ms.
    let(:ends) { [0.1, 0.35, 0.4] }
    let(:times) { described_class.new(ends) }

    # TileMap#frame_tile at 78e99d0, which this replaced.
    def searched(elapsed)
      into = elapsed % ends.last
      ends.index { into < it } || (ends.size - 1)
    end

    it 'shows the frame TileMap showed, on every tick of ten seconds' do
      expect(ticks.reject { times.index_at(it) == searched(it) }).to be_empty
    end

    it "shows the next frame at a frame's exact end, and loops" do
      expect([0.0, 0.05, 0.1, 0.35, 0.4, 0.55].map { times.index_at(it) }).to eq([0, 0, 1, 2, 0, 1])
    end

    it 'finds every frame of a loop without allocating' do
      expect { times.index_at(0.05) + times.index_at(0.2) + times.index_at(0.38) }.to allocate_nothing
    end
  end
end
