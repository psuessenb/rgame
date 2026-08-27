# frozen_string_literal: true

RSpec.describe RGame::Util::Color do
  describe 'construction' do
    it 'takes r, g, b with alpha defaulting to opaque' do
      c = described_class.new(255, 128, 0)

      expect([c.r, c.g, c.b, c.a]).to eq([255, 128, 0, 255])
    end

    it 'takes an explicit alpha' do
      expect(described_class.new(1, 2, 3, 4).a).to eq(4)
    end

    it 'accepts .rgba as the named alias' do
      expect(described_class.rgba(1, 2, 3, 4)).to eq(described_class.new(1, 2, 3, 4))
    end

    it 'round-trips through the packed 0xRRGGBBAA form' do
      c = described_class.new(0xAA, 0xBB, 0xCC, 0xDD)

      expect(c.packed).to eq(0xAABBCCDD)
      expect(described_class.from_packed(0xAABBCCDD)).to eq(c)
    end

    it 'rejects an out-of-range component rather than clamping it' do
      # The C layer clamps because it must be total; Ruby raises, because a
      # caller passing 300 has a bug and silently dimming it hides that.
      expect { described_class.new(300, 0, 0) }.to raise_error(ArgumentError, /0\.\.255/)
      expect { described_class.new(0, -1, 0) }.to raise_error(ArgumentError, /0\.\.255/)
      expect { described_class.new(0, 0, 0, 256) }.to raise_error(ArgumentError, /alpha/)
    end

    it 'rejects a packed value wider than 32 bits' do
      expect { described_class.from_packed(0x1_0000_0000) }.to raise_error(ArgumentError)
    end
  end

  describe 'the named colours' do
    it 'are what they say' do
      expect(described_class::WHITE.packed).to eq(0xFFFFFFFF)
      expect(described_class::BLACK.packed).to eq(0x000000FF)
      expect(described_class::TRANSPARENT.a).to be_zero
    end

    it 'names the primaries and secondaries' do
      expect(described_class::RED.packed).to eq(0xFF0000FF)
      expect(described_class::GREEN.packed).to eq(0x00FF00FF)
      expect(described_class::BLUE.packed).to eq(0x0000FFFF)
      expect(described_class::YELLOW.packed).to eq(0xFFFF00FF)
      expect(described_class::CYAN.packed).to eq(0x00FFFFFF)
      expect(described_class::MAGENTA.packed).to eq(0xFF00FFFF)
    end

    it 'names the mixed colours and the greys' do
      expect(described_class::ORANGE.packed).to eq(0xFFA500FF)
      expect(described_class::PURPLE.packed).to eq(0x800080FF)
      expect(described_class::BROWN.packed).to eq(0x8B4513FF)
      expect(described_class::PINK.packed).to eq(0xFFC0CBFF)
      expect(described_class::GRAY.packed).to eq(0x808080FF)
      expect(described_class::LIGHT_GRAY.packed).to eq(0xC0C0C0FF)
      expect(described_class::DARK_GRAY.packed).to eq(0x404040FF)
    end

    it 'are opaque and frozen, so one can be shared as a default tint' do
      # The Ruby-defined half of the palette goes through the same C
      # constructor as WHITE, so this checks the reopened class did not
      # introduce a second, laxer way to build a Color.
      palette = %i[RED GREEN BLUE YELLOW CYAN MAGENTA ORANGE PURPLE BROWN PINK
                   GRAY LIGHT_GRAY DARK_GRAY].map { |name| described_class.const_get(name) }

      expect(palette).to all(be_frozen)
      expect(palette.map(&:a)).to all(eq(255))
    end
  end

  describe 'value semantics' do
    it 'compares equal when the components match' do
      # rubocop:disable RSpec/IdenticalEqualityAssertion -- these are two
      # distinct objects that happen to hold the same value, which is precisely
      # what a value-equality test has to compare. The cop cannot see that.
      expect(described_class.new(1, 2, 3, 4)).to eq(described_class.new(1, 2, 3, 4))
      # rubocop:enable RSpec/IdenticalEqualityAssertion
      expect(described_class.new(1, 2, 3, 4)).not_to eq(described_class.new(1, 2, 3, 5))
    end

    it 'is not equal to a non-colour' do
      # A Color is not its own packed integer, and not a string that names it.
      expect(described_class.new(1, 2, 3)).not_to eq(0x010203FF)
      expect(described_class.new(1, 2, 3)).not_to eq('red')
    end

    it 'works as a Hash key, which a colour cache depends on' do
      cache = { described_class.new(1, 2, 3) => :hit }

      expect(cache[described_class.new(1, 2, 3)]).to eq(:hit)
    end

    it 'is frozen, so a shared colour cannot be tinted out from under anyone' do
      expect(described_class.new(1, 2, 3)).to be_frozen
      expect(described_class::WHITE).to be_frozen
    end

    it 'inspects readably' do
      expect(described_class.new(1, 2, 3, 4).inspect).to eq('#<RGame::Util::Color r=1 g=2 b=3 a=4>')
    end
  end

  describe '.coerce' do
    # Every draw call accepts a colour in any of these forms, so the conversion
    # lives in one place rather than in each primitive.
    it 'treats nil as white, which is what an untinted draw has always meant' do
      expect(described_class.coerce(nil)).to eq(described_class::WHITE)
    end

    it 'accepts a three-element array as opaque' do
      expect(described_class.coerce([10, 20, 30])).to eq(described_class.new(10, 20, 30, 255))
    end

    it 'accepts a four-element array' do
      expect(described_class.coerce([10, 20, 30, 40])).to eq(described_class.new(10, 20, 30, 40))
    end

    it 'passes a Color straight through, without allocating another' do
      c = described_class.new(1, 2, 3)

      expect(described_class.coerce(c)).to be(c)
    end

    it 'rejects an array of the wrong length' do
      expect { described_class.coerce([1, 2]) }.to raise_error(ArgumentError, /r, g, b/)
      expect { described_class.coerce([1, 2, 3, 4, 5]) }.to raise_error(ArgumentError)
    end

    it 'rejects something that is not a colour at all' do
      expect { described_class.coerce('red') }.to raise_error(TypeError)
    end
  end
end
