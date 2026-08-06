# frozen_string_literal: true

RSpec.describe Engine::AnimationSet do
  subject(:set) do
    described_class.new(
      stand: { row: 0, frames: 6, fps: 6 },
      walk_left: { row: 1, frames: 6, fps: 8, flip_x: true }
    )
  end

  it 'starts on column 0' do
    expect(set.frame(:stand, 0.0)).to eq([0, 0, false])
  end

  it 'advances one column per frame interval (1/fps seconds)' do
    expect(set.frame(:stand, 1.0 / 6)).to eq([0, 1, false])
    expect(set.frame(:stand, 2.0 / 6)).to eq([0, 2, false])
  end

  it 'wraps back to column 0 after the last frame' do
    expect(set.frame(:stand, 6 * (1.0 / 6))).to eq([0, 0, false])
  end

  it 'carries the row and flip flag for the animation' do
    expect(set.frame(:walk_left, 0.0)).to eq([1, 0, true])
  end

  it 'raises for an unknown animation' do
    expect { set.frame(:fly, 0.0) }.to raise_error(KeyError)
  end

  it 'starts at the given column offset and advances from there' do
    offset = described_class.new(
      idle: { row: 0, col: 1, frames: 1, fps: 1 },
      run: { row: 2, col: 3, frames: 2, fps: 4 }
    )
    expect(offset.frame(:idle, 0.0)).to eq([0, 1, false])     # 1-frame anim pinned at col 1
    expect(offset.frame(:idle, 99.0)).to eq([0, 1, false])
    expect(offset.frame(:run, 0.0)).to eq([2, 3, false])      # begins at col 3
    expect(offset.frame(:run, 1.0 / 4)).to eq([2, 4, false])  # advances to col 4
    expect(offset.frame(:run, 2.0 / 4)).to eq([2, 3, false])  # wraps back to col 3
  end
end
