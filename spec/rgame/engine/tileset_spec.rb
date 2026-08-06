# frozen_string_literal: true

RSpec.describe RGame::Engine::Tileset do
  subject(:tileset) { described_class.parse(tsx, firstgid: 1) }

  let(:tsx) do
    <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <tileset version="1.8" name="t" tilewidth="16" tileheight="16" tilecount="9" columns="3">
       <image source="t.png" width="48" height="48"/>
       <tile id="4">
        <animation>
         <frame tileid="4" duration="100"/>
         <frame tileid="5" duration="100"/>
        </animation>
       </tile>
       <tile id="7">
        <objectgroup draw-order="index">
         <object id="1" x="0" y="0" width="16" height="16"/>
        </objectgroup>
       </tile>
      </tileset>
    XML
  end

  it 'parses geometry, columns and image source' do
    expect(tileset.columns).to eq(3)
    expect(tileset.tile_width).to eq(16)
    expect(tileset.tile_height).to eq(16)
    expect(tileset.image_source).to eq('t.png')
  end

  it 'collects animated tile ids' do
    expect(tileset.animated_ids).to eq([4])
  end

  it 'maps a gid to a local id via firstgid' do
    expect(tileset.local_id(1)).to eq(0)
    expect(tileset.local_id(5)).to eq(4)
  end

  describe 'baked collision' do
    it 'marks tiles carrying a collision objectgroup as solid' do
      expect(tileset.solid_ids).to contain_exactly(7)
    end

    it 'reports those tiles solid by gid' do
      expect(tileset.solid?(8)).to be(true) # local 7
    end

    it 'does not mark a merely-animated tile solid' do
      expect(tileset.solid?(5)).to be(false) # local 4, animated but no collision shape
    end
  end

  describe '#solid?' do
    before { tileset.solid_ids = Set.new([4]) } # override the baked set

    it 'is false for gid 0 (empty)' do
      expect(tileset.solid?(0)).to be(false)
    end

    it 'is true when the local id is in solid_ids' do
      expect(tileset.solid?(5)).to be(true) # local 4
    end

    it 'is false when the local id is not solid' do
      expect(tileset.solid?(2)).to be(false) # local 1
    end
  end

  describe '#frame_local_id' do
    it 'returns the id unchanged for a non-animated tile' do
      expect(tileset.frame_local_id(0, 12_345)).to eq(0)
    end

    it 'resolves the animation frame from elapsed ms' do
      expect(tileset.frame_local_id(4, 0)).to eq(4)    # first frame
      expect(tileset.frame_local_id(4, 100)).to eq(5)  # second frame
      expect(tileset.frame_local_id(4, 200)).to eq(4)  # wraps (period 200)
    end
  end
end
