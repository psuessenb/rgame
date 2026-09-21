# frozen_string_literal: true

RSpec.describe RGame::Engine::Paragraph do
  let(:i18n) { RGame::Engine::I18n }
  let(:face) { RGame::Util::Typeface.default(18) }
  let(:text) { RGame::Engine::Text }

  before do
    i18n.load_hash(
      en: {
        notice: 'The gate is shut for the night, traveller.',
        greeting: 'Well met, %{name}. The gate is shut for the night.',
        story: 'The gate is shut for the night, traveller. ' \
               'The road ahead is dark, but the dawn will come and the gate will open again. ' \
               'Rest here until then. Keep the fire burning and stay on the path, ' \
               'and the morning will find you safe.'
      },
      de: {
        story: 'Das Tor ist für die Nacht geschlossen, Wanderer. ' \
               'Die Straße davor ist dunkel, doch der Morgen wird kommen und das Tor wird wieder geöffnet. ' \
               'Ruhe dich bis dahin aus. Halte das Feuer am Brennen und bleib auf dem Weg, ' \
               'dann wird der Morgen dich wohlbehalten finden.'
      }
    )
  end

  describe '#lines' do
    it 'breaks the translation into lines that fit the width' do
      notice = described_class.new('notice', width: 180, typeface: face)
      expect(notice.lines).to eq(['The gate is shut for the', 'night, traveller.'])
    end

    it 'returns the same frozen Array of frozen Strings while nothing moves' do
      notice = described_class.new('notice', width: 180)
      expect(notice.lines).to be(notice.lines).and be_frozen
      expect(notice.lines).to all(be_frozen)
    end

    it 'answers no lines for an empty translation' do
      i18n.load_hash(en: { blank: '' })
      expect(described_class.new('blank', width: 180).lines).to eq([])
    end

    it 'refuses before the first with, when its Text has variables' do
      greeting = described_class.new(text.new('greeting', :name), width: 520)
      expect { greeting.lines }.to raise_error(ArgumentError, /call with first/)
    end

    # The acceptance test for step 4 of the text-measurement plan.
    it 'breaks again after a language switch, with no call on the paragraph' do
      story = described_class.new('story', width: 520)
      english = story.lines.size
      i18n.locale = :de
      expect([english, story.lines.size]).to eq([3, 4])
    end
  end

  describe 'when it breaks the text' do
    it 'breaks once for any number of unchanged reads' do
      notice = described_class.new('notice', width: 180, typeface: face)
      allow(face).to receive(:text_lines).and_call_original
      3.times { notice.lines }
      expect(face).to have_received(:text_lines).once
    end

    it 'does not break again for width= given the width it already has' do
      notice = described_class.new('notice', width: 180, typeface: face)
      notice.lines
      allow(face).to receive(:text_lines).and_call_original
      notice.width = 180.0
      notice.lines
      expect(face).not_to have_received(:text_lines)
    end

    it 'breaks again at a new width' do
      notice = described_class.new('notice', width: 180, typeface: face)
      notice.lines
      notice.width = 520
      expect(notice.lines).to eq(['The gate is shut for the night, traveller.'])
    end

    it 'breaks again when a variable changes, and only then' do
      greeting = described_class.new(text.new('greeting', :name), width: 520, typeface: face)
      allow(face).to receive(:text_lines).and_call_original
      2.times { greeting.with(name: 'Ada').lines }
      2.times { greeting.with(name: 'Grace').lines }
      expect(face).to have_received(:text_lines).twice
    end
  end

  describe '#with' do
    it 'gives the Text its variables and returns the paragraph' do
      greeting = described_class.new(text.new('greeting', :name), width: 520)
      expect(greeting.with(name: 'Ada')).to be(greeting)
      expect(greeting.lines).to eq(['Well met, Ada. The gate is shut for the night.'])
    end

    it 'raises for a variable its Text does not have, as Text#with does' do
      greeting = described_class.new(text.new('greeting', :name), width: 520)
      expect { greeting.with(nam: 'Ada') }.to raise_error(ArgumentError)
    end
  end

  describe 'on an unchanged read' do
    it 'allocates nothing in lines' do
      notice = described_class.new('notice', width: 180)
      expect { notice.lines }.to allocate_nothing.over(200_000)
    end

    it 'allocates nothing in with given the same values, then lines' do
      greeting = described_class.new(text.new('greeting', :name), width: 180)
      expect { greeting.with(name: 'Ada').lines }.to allocate_nothing.over(200_000)
    end
  end

  describe 'pages' do
    let(:story) { described_class.new('story', width: 300, lines_per_page: 4) }

    it 'groups the lines into pages of lines_per_page' do
      expect(story.lines.size).to eq(6)
      expect([story.page_count, story.page(0), story.page(1)])
        .to eq([2, story.lines.first(4), story.lines.last(2)])
    end

    it 'is one page without lines_per_page' do
      whole = described_class.new('story', width: 300)
      expect([whole.page_count, whole.page(0)]).to eq([1, whole.lines])
    end

    it 'is one empty page for an empty text' do
      i18n.load_hash(en: { blank: '' })
      blank = described_class.new('blank', width: 300, lines_per_page: 3)
      expect([blank.page_count, blank.page(0)]).to eq([1, []])
    end

    it 'answers the nearest page for an index past either end' do
      expect([story.page(9), story.page(-1)]).to eq([story.page(1), story.page(0)])
    end

    it 'clamps to the pages there are after a language switch shortens the text' do
      i18n.load_hash(de: { story: 'Das Tor ist zu.' })
      last = story.page(1)
      i18n.locale = :de
      expect([last.size, story.page(1)]).to eq([2, ['Das Tor ist zu.']])
    end

    it 'returns the same frozen page on every unchanged read' do
      expect(story.page(1)).to be(story.page(1)).and be_frozen
    end

    it 'allocates nothing in page and page_count on an unchanged read' do
      expect { story.page(1) && story.page_count }.to allocate_nothing.over(200_000)
    end

    it 'refuses lines_per_page below 1' do
      expect { described_class.new('story', width: 300, lines_per_page: 0) }
        .to raise_error(ArgumentError, /at least 1 line/)
    end

    it 'refuses a lines_per_page that is not an Integer' do
      expect { described_class.new('story', width: 300, lines_per_page: 2.5) }.to raise_error(TypeError)
    end
  end

  describe '.new' do
    it 'takes a key as a Symbol' do
      expect(described_class.new(:notice, width: 520).lines).to eq(['The gate is shut for the night, traveller.'])
    end

    it 'takes an Engine::Text as it is' do
      notice = text.new('notice')
      expect(described_class.new(notice, width: 520).lines).to eq([notice.to_s])
    end

    it 'refuses anything that is neither a key nor a Text' do
      expect { described_class.new(42, width: 520) }.to raise_error(TypeError, /translation key or an Engine::Text/)
    end

    it 'refuses nil' do
      expect { described_class.new(nil, width: 520) }.to raise_error(TypeError)
    end

    it 'uses the default typeface unless given one' do
      expect(described_class.new('notice', width: 520).typeface).to be(RGame::Util::Typeface.default)
    end
  end

  describe '#width=' do
    it 'refuses a width of zero or less, here and at construction' do
      notice = described_class.new('notice', width: 180)
      expect { notice.width = 0 }.to raise_error(ArgumentError, /positive width/)
      expect { described_class.new('notice', width: -1) }.to raise_error(ArgumentError, /positive width/)
    end

    it 'refuses a width that is not a number' do
      expect { described_class.new('notice', width: '520') }.to raise_error(TypeError)
    end

    it 'keeps the width it had after a refusal' do
      notice = described_class.new('notice', width: 180)
      expect { notice.width = 0 }.to raise_error(ArgumentError)
      expect(notice.width).to eq(180)
    end
  end
end
