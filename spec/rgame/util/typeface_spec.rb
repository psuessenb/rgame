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

  describe '#inspect' do
    it 'shows the size' do
      expect(face.inspect).to eq('#<RGame::Util::Typeface 18px>')
    end
  end
end
