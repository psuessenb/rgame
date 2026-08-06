# frozen_string_literal: true

RSpec.describe RGame::Engine::Tensor do
  subject(:matrix) { described_class.new(4, 3, 2) }

  it 'exposes its dimensions' do
    expect(matrix.width).to eq(4)
    expect(matrix.height).to eq(3)
    expect(matrix.depth).to eq(2)
  end

  describe '#[]' do
    it 'starts with nil values' do
      expect(matrix[0, 0, 0]).to be_nil
    end

    it 'sets and reads a value at a specific position' do
      matrix[1, 2, 1] = 7
      expect(matrix[1, 2, 1]).to eq(7)
    end

    it 'keeps z-slices independent' do
      matrix[1, 1, 0] = :ground
      matrix[1, 1, 1] = :over
      expect([matrix[1, 1, 0], matrix[1, 1, 1]]).to eq(%i[ground over])
    end

    it 'addresses the first and last cell independently' do
      matrix[0, 0, 0] = :a
      matrix[3, 2, 1] = :b # last cell
      expect([matrix[0, 0, 0], matrix[3, 2, 1]]).to eq(%i[a b])
    end
  end

  it 'fills with an initial value' do
    filled = described_class.new(2, 2, 2, initial: 0)
    expect([filled[0, 0, 0], filled[1, 1, 1]]).to eq([0, 0])
  end
end
