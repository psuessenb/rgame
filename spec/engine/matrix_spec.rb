# frozen_string_literal: true

RSpec.describe Engine::Matrix do
  subject(:matrix) { described_class.new(4, 3) }

  it 'exposes its dimensions' do
    expect(matrix.width).to eq(4)
    expect(matrix.height).to eq(3)
  end

  describe '#[]' do
    it 'starts with nil values' do
      expect(matrix[0, 0]).to be_nil
    end

    it 'sets and reads a value at a specific position' do
      matrix[1, 1] = 4
      expect(matrix[1, 1]).to eq(4)
    end

    it 'addresses cells independently across the flat backing' do
      matrix[0, 0] = :a
      matrix[3, 2] = :b # last cell
      expect([matrix[0, 0], matrix[3, 2], matrix[1, 0]]).to eq([:a, :b, nil])
    end
  end

  it 'fills with an initial value' do
    filled = described_class.new(2, 2, initial: 0)
    expect([filled[0, 0], filled[1, 1]]).to eq([0, 0])
  end
end
