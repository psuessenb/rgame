# frozen_string_literal: true

RSpec.describe RGame::Engine::Components::RandomSource do
  let(:source) { described_class.new(seed: 42) }

  describe '#rand' do
    it 'gives the sequence a Random with the same seed gives' do
      random = Random.new(42)

      expect(Array.new(3) { source.rand }).to eq(Array.new(3) { random.rand })
    end

    it 'gives two sources with one seed one sequence' do
      other = described_class.new(seed: 42)

      expect(Array.new(5) { source.rand(100) }).to eq(Array.new(5) { other.rand(100) })
    end

    it 'takes an Integer, a Float range and an Integer range, as Random#rand does' do
      random = Random.new(42)
      drawn = [source.rand(6), source.rand(1.0..2.0), source.rand(3..9)]

      expect(drawn).to eq([random.rand(6), random.rand(1.0..2.0), random.rand(3..9)])
    end

    it 'answers what Array#sample needs from a random:' do
      expect(%i[a b c d].sample(random: source)).to eq(%i[a b c d].sample(random: Random.new(42)))
    end

    it 'allocates nothing, with no argument, an Integer or a Range' do
      range = 1.0..2.0

      expect do
        source.rand
        source.rand(6)
        source.rand(range)
      end.to allocate_nothing
    end
  end

  describe '#seed' do
    it 'reads back the seed it was built with' do
      expect(source.seed).to eq(42)
    end
  end
end
