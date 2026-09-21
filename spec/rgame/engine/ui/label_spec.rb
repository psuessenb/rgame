# frozen_string_literal: true

RSpec.describe RGame::Engine::UI::Label do
  let(:renderer) { FakeRenderer.new }
  let(:root) { RGame::Engine::Node2D.new }
  let(:face) { RGame::Util::Typeface.default(24) }
  let(:i18n) { RGame::Engine::I18n }

  before do
    i18n.load_hash(
      en: {
        notice: 'The gate is shut for the night, traveller.',
        greeting: 'Well met, %{name}.',
        story: 'Long ago, before the roads had names, a lantern keeper lived at the edge of the world. ' \
               'Every night the keeper climbed the tower and lit the flame, so that travellers lost in ' \
               'the dark could find their way home. Nobody remembered who had lit it first, and nobody ' \
               'thought to ask. This is the story of the night the flame went out.'
      },
      de: {
        story: 'Vor langer Zeit, als die Straßen noch keine Namen hatten, lebte am Rand der Welt ein ' \
               'Laternenwärter. Jede Nacht stieg der Wärter auf den Turm und entzündete die Flamme, damit ' \
               'Reisende, die sich im Dunkeln verirrt hatten, den Weg nach Hause fanden. Niemand wusste ' \
               'mehr, wer sie zuerst entzündet hatte, und niemand dachte daran zu fragen. Dies ist die ' \
               'Geschichte der Nacht, in der die Flamme erlosch.'
      }
    )
  end

  def label(text: 'notice', width: 180, **)
    root.add_node(described_class.new(text: text, width: width, typeface: face, **)).tap { root.enter_tree }
  end

  def drawn
    renderer.clear
    root.draw(renderer, screen_view)
    renderer.calls_to(:text)
  end

  describe 'drawing' do
    it 'draws each line of the page, one line height apart, in its typeface' do
      label
      expect(drawn.map { [it.args, it.options[:font]] }).to eq(
        [[['The gate is shut', 0, 0], face], [['for the night,', 0, 24], face], [['traveller.', 0, 48], face]]
      )
    end

    it 'draws in the colour it was given' do
      label(color: [255, 0, 0])
      expect(drawn.first.options[:color]).to eq(RGame::Util::Color.new(255, 0, 0))
    end
  end

  describe 'align:' do
    def xs(align) = label(align: align).then { drawn.map { it.args[1] } }

    let(:widths) { ['The gate is shut', 'for the night,', 'traveller.'].map { face.text_width(it) } }

    it 'places each line at the left edge by default' do
      expect(xs(:left)).to eq([0, 0, 0])
    end

    it 'centres each line against the width' do
      expect(xs(:center)).to eq(widths.map { (180 - it) / 2 })
    end

    it 'places each line against the right edge' do
      expect(xs(:right)).to eq(widths.map { 180 - it })
    end

    it 'refuses anything else' do
      expect { label(align: :justify) }.to raise_error(ArgumentError, /align: must be one of/)
    end
  end

  describe 'pages' do
    let(:story) { label(text: 'story', width: 440, lines_per_page: 3) }

    # The reason a label exists: the same key fills a different number of
    # pages per language, and nothing tells the label the language changed.
    it 'fills a page more in German, with no call on the label' do
      english = story.page_count
      i18n.locale = :de
      expect([english, story.page_count]).to eq([3, 4])
    end

    it 'draws the lines of the page it is on' do
      story.page = 1
      paragraph = RGame::Engine::Paragraph.new('story', width: 440, typeface: face, lines_per_page: 3)
      expect(drawn.map { it.args.first }).to eq(paragraph.page(1))
    end

    it 'stays on the last page when turned past it' do
      story.page = 2
      story.page += 1
      expect([story.page, story.last_page?]).to eq([2, true])
    end

    it 'keeps the page it stopped on when a switch adds pages' do
      story.page = 9
      i18n.locale = :de
      expect([story.page, story.last_page?]).to eq([2, false])
    end

    it 'turns back no further than the first page' do
      story.page = -1
      expect([story.page, story.last_page?]).to eq([0, false])
    end

    it 'reads as the last page after a switch leaves fewer pages than the one set' do
      i18n.locale = :de
      story.page = 3
      i18n.locale = :en
      expect([story.page, story.last_page?]).to eq([2, true])
    end

    it 'is one page without lines_per_page' do
      expect([label.page_count, label.last_page?]).to eq([1, true])
    end
  end

  describe '#width=' do
    it 'breaks the text again at the new width, and sets the node width' do
      notice = label
      notice.width = 520
      expect([notice.width, drawn.map { it.args.first }]).to eq([520, ['The gate is shut for the night, traveller.']])
    end

    it 'refuses a width of zero or less, here and at construction' do
      expect { label.width = 0 }.to raise_error(ArgumentError, /positive width/)
      expect { label(width: -1) }.to raise_error(ArgumentError, /positive width/)
    end
  end

  describe '#with' do
    it 'gives the text its variables and returns the label' do
      greeting = label(text: RGame::Engine::Text.new('greeting', :name), width: 520)
      expect(greeting.with(name: 'Ada')).to be(greeting)
      expect(drawn.map { it.args.first }).to eq(['Well met, Ada.'])
    end
  end

  it 'refuses text that is neither a key nor a Text' do
    expect { label(text: 42) }.to raise_error(TypeError, /translation key or an Engine::Text/)
  end

  it 'allocates nothing on an unchanged draw' do
    story = label(text: 'story', width: 440, lines_per_page: 3, align: :center)
    quiet = QuietRenderer.new
    story.on_draw(quiet, nil)
    expect { story.on_draw(quiet, nil) }.to allocate_nothing.over(200_000)
  end
end
