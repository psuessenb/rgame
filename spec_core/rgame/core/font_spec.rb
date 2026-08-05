# frozen_string_literal: true

RSpec.describe RGame::Core::Font do
  # Loading a font needs a GL context for its atlas pages, which is what this
  # suite is for. The metrics underneath — advances, kerning, UTF-8 — are pure C
  # and are covered without a display by test/test_font.c, against this same
  # shipped file.
  let(:app) { RGame::Core::App.new(width: 200, height: 100, caption: 'font spec') }

  describe '.new' do
    it 'loads the shipped font when given no path' do
      font = described_class.new(app, 18)

      expect(font.height).to eq(18)
    end

    it 'loads a font at whatever size it is asked for' do
      expect(described_class.new(app, 32).height).to eq(32)
    end

    it 'loads a font from a path' do
      font = described_class.new(app, 12, path: described_class::DEFAULT_PATH)

      expect(font.height).to eq(12)
    end

    it 'raises LoadError naming a file it cannot read' do
      expect { described_class.new(app, 18, path: '/no/such/font.ttf') }
        .to raise_error(described_class::LoadError, %r{/no/such/font\.ttf})
    end

    it 'raises LoadError for a file that is not a font' do
      expect { described_class.new(app, 18, path: 'README.md') }
        .to raise_error(described_class::LoadError, /not read README\.md as a TrueType font/)
    end

    it 'refuses a size that is not positive' do
      expect { described_class.new(app, 0) }.to raise_error(described_class::LoadError)
    end

    it 'refuses anything that is not an App' do
      expect { described_class.new(Object.new, 18) }.to raise_error(TypeError)
    end
  end

  describe 'the shipped default' do
    it 'is a real file inside the gem' do
      # The failure this guards is invisible locally and fatal remotely: a
      # default font missing from the packaged gem works in a checkout and dies
      # at the first Font.new on someone else's machine.
      expect(File.file?(described_class::DEFAULT_PATH)).to be(true)
    end

    it 'ships its licence alongside it' do
      licence = File.join(File.dirname(described_class::DEFAULT_PATH), 'OFL.txt')

      expect(File.file?(licence)).to be(true)
    end
  end

  describe '#text_width' do
    subject(:font) { described_class.new(app, 18) }

    it 'measures nothing for an empty string' do
      expect(font.text_width('')).to be_zero
    end

    it 'grows with the string' do
      expect(font.text_width('aa')).to be > font.text_width('a')
    end

    it 'measures a narrow letter as narrower than a wide one' do
      expect(font.text_width('i')).to be < font.text_width('W')
    end

    it 'works outside a frame' do
      # Laying out a menu happens while updating, not while drawing, so
      # measuring must not need an open frame the way drawing does.
      expect(font.text_width('Score')).to be_positive
    end

    it 'counts an accented character as one glyph, not two bytes' do
      # 'ü' is two bytes of UTF-8. A byte-wise measure would report it as two
      # replacement boxes and come out wider than the plain letter.
      expect(font.text_width('ü')).to be < font.text_width('uu')
    end

    it 'scales with the font size' do
      small = described_class.new(app, 12)
      large = described_class.new(app, 36)

      expect(large.text_width('Hello')).to be > small.text_width('Hello')
    end
  end

  describe '#inspect' do
    it 'shows the size' do
      expect(described_class.new(app, 18).inspect).to eq('#<RGame::Core::Font 18px>')
    end
  end

  describe 'atlas pages' do
    # The counter that makes a leaked GPU page visible; nothing else would say.
    def live_pages
      3.times { GC.start(full_mark: true, immediate_sweep: true) }
      described_class.debug_live_pages
    end

    it 'costs no video memory until something is drawn' do
      # A font that is only ever measured — a layout pass — should not have
      # allocated a page.
      before = live_pages

      font = described_class.new(app, 18)
      font.text_width('measured but never drawn')

      expect(live_pages).to eq(before)
    end

    it 'allocates a page the first time text is drawn' do
      before = live_pages
      font = nil

      RenderedFrame.capture(width: 64, height: 64) do |renderer, capture_app|
        font = described_class.new(capture_app, 18)
        renderer.text('hello', 0, 0, font: font)
      end

      expect(live_pages).to eq(before + 1)
      expect(font.height).to eq(18) # keeps `font` reachable for the count above
    end

    it 'keeps one page however many glyphs a Latin game draws' do
      before = live_pages
      font = nil

      RenderedFrame.capture(width: 64, height: 64) do |renderer, capture_app|
        font = described_class.new(capture_app, 18)
        renderer.text('abcdefghijklmnopqrstuvwxyz', 0, 0, font: font)
        renderer.text('ABCDEFGHIJKLMNOPQRSTUVWXYZ', 0, 20, font: font)
        renderer.text('0123456789 .,:;!?äöüßÄÖÜ€«»', 0, 40, font: font)
      end

      expect(live_pages).to eq(before + 1)
      expect(font.height).to eq(18)
    end

    it 'releases its pages when the font is collected' do
      before = live_pages

      RenderedFrame.capture(width: 64, height: 64) do |renderer, capture_app|
        renderer.text('hello', 0, 0, font: described_class.new(capture_app, 18))
      end

      expect(live_pages).to eq(before)
    end

    it 'survives its app being collected first' do
      # Same rule as images: a collector picks the order, so both work.
      before = live_pages
      fonts = []

      3.times do
        RenderedFrame.capture(width: 32, height: 32) do |renderer, capture_app|
          font = described_class.new(capture_app, 18)
          renderer.text('x', 0, 0, font: font)
          fonts << font
        end
      end

      expect(fonts.map(&:height)).to all(eq(18))
      fonts.clear
      expect(live_pages).to eq(before)
    end
  end

  describe 'a font from another App' do
    it 'raises rather than drawing blank quads' do
      other = RGame::Core::App.new(width: 8, height: 8, caption: 'elsewhere')
      foreign = described_class.new(other, 18)

      expect do
        RenderedFrame.capture(width: 32, height: 32) do |renderer, _app|
          renderer.text('hi', 0, 0, font: foreign)
        end
      end.to raise_error(ArgumentError, /different App/)
    end
  end
end
