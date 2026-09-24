# frozen_string_literal: true

RSpec.describe RGame::Util::Blend do
  describe '.index' do
    it 'answers each mode by its position, which is the number the C takes' do
      expect(described_class::MODES.map { described_class.index(it) }).to eq([0, 1])
    end

    it 'refuses a mode it does not know, listing the ones it does' do
      expect { described_class.index(:screen) }
        .to raise_error(ArgumentError, 'unknown blend mode :screen; expected one of [:alpha, :add]')
    end
  end

  describe '.opacity' do
    it 'returns an opacity from 0 to 1 as it was given, whatever kind of number' do
      [0, 1, 0.25, Rational(1, 3)].each { expect(described_class.opacity(it)).to equal(it) }
    end

    it 'refuses a number outside 0 to 1, and NaN' do
      [-0.01, 1.01, Float::INFINITY, Float::NAN].each do |value|
        expect { described_class.opacity(value) }.to raise_error(ArgumentError, /outside 0\.\.1/)
      end
    end

    it 'refuses what is not a number, as the renderer\'s C would' do
      expect { described_class.opacity('0.5') }
        .to raise_error(TypeError, 'no implicit conversion of String into Float')
    end

    it 'allocates nothing for an opacity it accepts' do
      expect { described_class.opacity(0.5) }.to allocate_nothing
    end
  end
end
