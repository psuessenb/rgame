# frozen_string_literal: true

RSpec.describe RGame::Util::Z do
  describe 'bands' do
    it 'lists them back to front' do
      expect(described_class::BANDS).to eq(%i[world hud overlay debug])
    end

    it 'defaults to the world one, so a game that names none is in it' do
      expect(described_class::DEFAULT).to eq(:world)
    end

    it 'recognises each of them' do
      expect(described_class::BANDS).to all(satisfy { |band| described_class.band?(band) })
    end

    it 'does not recognise anything else' do
      expect(described_class.band?(:hood)).to be(false)
    end

    it 'names the alternatives when a band is not one' do
      # Raised where a band is *set*, so a typo surfaces at assignment with the
      # list in hand rather than as a KeyError from inside a draw.
      expect { described_class.band!(:hood) }
        .to raise_error(ArgumentError, /unknown z band :hood; expected one of/)
    end
  end

  describe '.base' do
    it 'starts the world band at the middle of its first slot' do
      expect(described_class.base(:world, 0)).to eq(described_class::HALF)
    end

    it 'steps by one slot per index' do
      expect(described_class.base(:world, 1) - described_class.base(:world, 0))
        .to eq(described_class::SLOT)
    end

    it 'leaves a gap between slots that no offset can cross' do
      # The guarantee the whole design rests on: the top of one node's room is
      # below the bottom of the next node's.
      first = described_class.base(:world, 0) + described_class::Z_MAX
      second = described_class.base(:world, 1) + described_class::Z_MIN

      expect(first).to be < second
    end

    it 'puts every slot of a band above every slot of the one before it' do
      last_world = described_class.base(:world, described_class::SLOTS_PER_BAND - 1)

      expect(described_class.base(:hud, 0)).to be > last_world + described_class::Z_MAX
    end

    it 'stays exactly representable as a double' do
      # The draw queue sorts on a double. Two slots that rounded together would
      # show up as two sprites swapping places between frames — very hard to
      # see as a precision problem.
      highest = described_class.base(:debug, described_class::SLOTS_PER_BAND - 1)

      expect(highest).to be < 2**53
      expect(highest.to_f.to_i).to eq(highest)
    end

    it 'refuses a slot past the end of a band' do
      expect { described_class.base(:world, described_class::SLOTS_PER_BAND) }
        .to raise_error(RangeError, /is full/)
    end
  end

  describe '.offset' do
    it 'accepts a z inside one slot' do
      expect(described_class.offset(50)).to eq(50)
      expect(described_class.offset(described_class::Z_MIN)).to eq(described_class::Z_MIN)
      expect(described_class.offset(described_class::Z_MAX)).to eq(described_class::Z_MAX)
    end

    it 'refuses a stale global z' do
      # The bands used to be Integers a caller passed. Every one of those
      # spellings has to raise rather than sort somewhere surprising.
      expect { described_class.offset(100_000) }
        .to raise_error(ArgumentError, /outside a node's slot/)
    end

    it 'refuses one below the slot too' do
      expect { described_class.offset(-1000) }.to raise_error(ArgumentError)
    end

    it 'refuses a z that is not a number' do
      expect { described_class.offset(nil) }.to raise_error(TypeError)
    end
  end
end
