# frozen_string_literal: true

RSpec.describe RGame::Util::Typeface do
  # The shipped font, measured for real. The advances, kerning and UTF-8 walk
  # underneath are pinned glyph by glyph in test/test_typeface.c; this is what
  # the Ruby binding hands back from them.
  subject(:face) { described_class.default(18) }

  describe '.new' do
    it 'opens a font from a path, at the size asked for' do
      expect(described_class.new(described_class::DEFAULT_PATH, 12).height).to eq(12)
    end

    it 'raises LoadError naming a file that is not a font' do
      expect { described_class.new('README.md', 18) }
        .to raise_error(described_class::LoadError, /not read README\.md as a TrueType font/)
    end

    it 'raises LoadError naming a file it cannot read' do
      expect { described_class.new('/no/such/font.ttf', 18) }
        .to raise_error(described_class::LoadError, %r{/no/such/font\.ttf})
    end

    it 'refuses a size below 1' do
      expect { described_class.new(described_class::DEFAULT_PATH, 0) }
        .to raise_error(ArgumentError, /positive pixel height/)
    end
  end

  describe '.default' do
    it 'is the shipped font' do
      expect(face.text_width('Hello')).to eq(described_class.new(described_class::DEFAULT_PATH, 18).text_width('Hello'))
    end

    it 'opens each size once and hands back the same typeface after that' do
      expect(described_class.default(18)).to be(face)
    end

    it 'keeps sizes apart' do
      expect(described_class.default(24).height).to eq(24)
    end

    it 'defaults to the size the renderer draws at' do
      expect(described_class.default).to be(described_class.default(described_class::DEFAULT_SIZE))
    end
  end

  describe '#text_width' do
    it "is the real font's width, not an approximation" do
      expect(face.text_width('Systemsprache verwenden')).to be_within(0.005).of(194.33)
    end

    it 'measures nothing for an empty string' do
      expect(face.text_width('')).to eq(0.0)
    end

    it 'applies kerning' do
      expect(face.text_width('AV')).to be < face.text_width('A') + face.text_width('V')
    end

    it 'counts an accented character as one glyph, not two bytes' do
      expect(face.text_width('ü')).to be < face.text_width('uu')
    end

    it 'costs one replacement character for a malformed byte, not the rest of the string' do
      malformed = "a\xFFb".b

      expect(face.text_width(malformed)).to eq(face.text_width("a\u{FFFD}b"))
    end

    it 'scales with the size' do
      expect(described_class.default(36).text_width('Hello')).to be > face.text_width('Hello')
    end

    it 'refuses something that is not a String' do
      expect { face.text_width(42) }.to raise_error(TypeError)
    end
  end

  describe '#wrap' do
    let(:sentence) { 'The gate is shut for the night, traveller.' }

    it 'breaks at the last space that fits' do
      expect(face.wrap(sentence, 180)).to eq(['The gate is shut for the', 'night, traveller.'])
    end

    it 'returns one line for a string that fits' do
      expect(face.wrap(sentence, face.text_width(sentence))).to eq([sentence])
    end

    it 'returns no lines for an empty string' do
      expect(face.wrap('', 180)).to eq([])
    end

    it 'measures no line wider than the width it was given' do
      expect(face.wrap(sentence, 100).map { face.text_width(it) }).to all(be <= 100)
    end

    it 'hands back a word wider than the line whole, rather than cutting it' do
      expect(face.wrap('Systemsprache verwenden', 50)).to eq(%w[Systemsprache verwenden])
    end

    it 'gives back the string when the lines are joined with the spaces they replaced' do
      ['a  b', 'gate ', ' gate', sentence].each do |string|
        expect(face.wrap(string, 30).join(' ')).to eq(string)
      end
    end

    it 'keeps each line in the encoding of the string it came from' do
      expect(face.wrap('Tür für Tür', 30).map(&:encoding)).to all(eq(Encoding::UTF_8))
    end

    it 'breaks a German paragraph into more lines than its English source' do
      english = 'The gate is shut for the night, traveller. ' \
                'The road ahead is dark, but the dawn will come and the gate will open again. ' \
                'Rest here until then. Keep the fire burning and stay on the path, ' \
                'and the morning will find you safe.'
      german = 'Das Tor ist für die Nacht geschlossen, Wanderer. ' \
               'Die Straße davor ist dunkel, doch der Morgen wird kommen und das Tor wird wieder geöffnet. ' \
               'Ruhe dich bis dahin aus. Halte das Feuer am Brennen und bleib auf dem Weg, ' \
               'dann wird der Morgen dich wohlbehalten finden.'

      expect([face.wrap(english, 520).size, face.wrap(german, 520).size]).to eq([3, 4])
    end

    it 'refuses something that is not a String' do
      expect { face.wrap(42, 180) }.to raise_error(TypeError)
    end

    it 'refuses a width that is not a number' do
      expect { face.wrap(sentence, 'wide') }.to raise_error(TypeError)
    end
  end

  describe '#inspect' do
    it 'shows the size' do
      expect(face.inspect).to eq('#<RGame::Util::Typeface 18px>')
    end
  end
end
