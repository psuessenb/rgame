# frozen_string_literal: true

RSpec.describe RGame::Engine::Text do
  let(:i18n) { RGame::Engine::I18n }

  before do
    i18n.load_hash(
      en: {
        title: 'Main Menu',
        hud: { score: 'Score: %{score}', where: '%{name} on level %{level}', trio: '%{a}-%{b}-%{c}' },
        apples: { zero: 'No apples', one: '%{count} apple', other: '%{count} apples' },
        title_menu: { play: 'Play' },
        other_menu: { play: 'Start' }
      },
      de: { title: 'Hauptmenü', hud: { score: 'Punkte: %{score}' } }
    )
  end

  describe '#with' do
    it 'renders the translation with the keywords interpolated' do
      expect(described_class.new('hud.where', :name, :level).with(name: 'Ada', level: 3)).to eq('Ada on level 3')
    end

    it 'returns the identical frozen String while nothing has changed' do
      score = described_class.new('hud.score', :score)
      expect(score.with(score: 7)).to be(score.with(score: 7)).and be_frozen
    end

    it 'renders once for any number of unchanged reads' do
      score = described_class.new('hud.score', :score)
      allow(i18n).to receive(:render).and_call_original
      3.times { score.with(score: 7) }
      expect(i18n).to have_received(:render).once
    end

    describe 'allocating nothing on an unchanged read' do
      it 'with no names' do
        title = described_class.new('title')
        expect { title.to_s }.to allocate_nothing.over(200_000)
      end

      it 'with one name' do
        score = described_class.new('hud.score', :score)
        expect { score.with(score: 7) }.to allocate_nothing.over(200_000)
      end

      it 'with three names' do
        trio = described_class.new('hud.trio', :a, :b, :c)
        expect { trio.with(a: 1, b: 'two', c: :three) }.to allocate_nothing.over(200_000)
      end
    end

    it 're-renders when any one keyword changes' do
      where = described_class.new('hud.where', :name, :level)
      first = where.with(name: 'Ada', level: 3)
      expect(where.with(name: 'Ada', level: 4)).to eq('Ada on level 4').and(satisfy { !it.equal?(first) })
    end

    # A load always moves the generation, so this is the case showing the
    # identity assertions above could fail at all.
    it 're-renders after a load, with no keyword change' do
      score = described_class.new('hud.score', :score)
      first = score.with(score: 7)
      i18n.load_hash(fr: { title: 'Menu principal' })
      expect(score.with(score: 7)).to eq(first).and(satisfy { !it.equal?(first) })
    end

    it 'follows a locale switch on the next read, with no keyword change' do
      score = described_class.new('hud.score', :score)
      score.with(score: 7)
      i18n.locale = :de
      expect(score.with(score: 7)).to eq('Punkte: 7')
    end

    it 'raises ArgumentError naming a missing keyword' do
      expect { described_class.new('hud.where', :name, :level).with(name: 'Ada') }
        .to raise_error(ArgumentError, /level/)
    end

    it 'raises ArgumentError naming an unknown keyword' do
      expect { described_class.new('hud.score', :score).with(score: 1, bonus: 2) }
        .to raise_error(ArgumentError, /bonus/)
    end

    it 'pluralizes by count' do
      apples = described_class.new('apples', :count)
      expect([0, 1, 3].map { apples.with(count: it) }).to eq(['No apples', '1 apple', '3 apples'])
    end
  end

  describe '#to_s' do
    it 'is the translation of a Text with no names' do
      expect(described_class.new('title').to_s).to eq('Main Menu')
    end

    it 'follows a locale switch' do
      title = described_class.new(:title)
      title.to_s
      i18n.locale = :de
      expect(title.to_s).to eq('Hauptmenü')
    end

    describe 'on a Text that has names' do
      let(:score) { described_class.new('hud.score', :score) }

      it 'refuses before the first with, pointing at with' do
        expect { score.to_s }.to raise_error(ArgumentError, /"hud.score" needs score:.*with/)
      end

      it 'is what the last with rendered, the identical String' do
        shown = score.with(score: 7)
        expect(score.to_s).to be(shown)
      end

      it 'follows the last with' do
        score.with(score: 7)
        score.with(score: 8)
        expect(score.to_s).to eq('Score: 8')
      end

      it 'renders the last values again after a locale switch, with no with in between' do
        score.with(score: 7)
        i18n.locale = :de
        expect(score.to_s).to eq('Punkte: 7')
      end

      it 'renders the last values again after scope=' do
        i18n.load_hash(en: { arena: { score: 'Arena: %{score}' } })
        scoped = described_class.new('score', :score, scope: 'hud')
        scoped.with(score: 7)
        scoped.scope = 'arena'
        expect(scoped.to_s).to eq('Arena: 7')
      end

      it 'still refuses after a with that raised on a missing keyword' do
        expect { score.with }.to raise_error(ArgumentError)
        expect { score.to_s }.to raise_error(ArgumentError, /needs score:/)
      end

      it 'renders nothing on a read after with, while nothing has changed' do
        score.with(score: 7)
        allow(i18n).to receive(:render).and_call_original
        3.times { score.to_s }
        expect(i18n).not_to have_received(:render)
      end

      it 'allocates nothing on an unchanged read' do
        score.with(score: 7)
        expect { score.to_s }.to allocate_nothing.over(200_000)
      end

      it 'reads a computed Text the same way' do
        lives = described_class.computed(:lives) { |lives:| "Lives: #{lives}" }
        lives.with(lives: 3)
        expect(lives.to_s).to eq('Lives: 3')
      end
    end
  end

  describe 'the generated with' do
    it 'is shared by every Text with the same names, in any order' do
      one = described_class.new('hud.where', :name, :level)
      other = described_class.new('elsewhere', :level, :name)
      expect(one.method(:with).owner).to be(other.method(:with).owner)
    end

    it 'is not shared with a different name list' do
      one = described_class.new('hud.where', :name, :level)
      other = described_class.new('hud.score', :score)
      expect(one.method(:with).owner).not_to be(other.method(:with).owner)
    end

    it 'refuses a name that cannot be a keyword' do
      expect { described_class.new('x', :Name) }.to raise_error(ArgumentError, /:Name cannot be a variable name/)
    end

    it 'refuses a Ruby keyword as a name' do
      expect { described_class.new('x', :end) }.to raise_error(ArgumentError, /cannot all be variable names/)
    end

    it 'refuses a name declared twice' do
      expect { described_class.new('x', :a, :a) }.to raise_error(ArgumentError, /declares a variable twice/)
    end
  end

  describe 'before any table is loaded' do
    before do
      i18n.reset
      i18n.missing = :key
    end

    it 'shows the missing answer, then the translation once a table loads' do
      title = described_class.new('title')
      shown = [title.to_s]
      i18n.load_hash(en: { title: 'Main Menu' })
      expect(shown << title.to_s).to eq(['title', 'Main Menu'])
    end
  end

  describe 'scope' do
    it 'resolves the key under the scope' do
      expect(described_class.new('play', scope: 'title_menu').to_s).to eq('Play')
    end

    it 'keeps the key as given' do
      expect(described_class.new('play', scope: 'title_menu').key).to eq('play')
    end

    it 'resolves again when the scope changes' do
      play = described_class.new('play', scope: 'title_menu')
      play.to_s
      play.scope = 'other_menu'
      expect(play.to_s).to eq('Start')
    end
  end

  describe 'a translation whose variables differ from the declared names' do
    it 'raises VariableMismatch under :raise for a placeholder the Text does not declare' do
      expect { described_class.new('hud.score').to_s }
        .to raise_error(i18n::VariableMismatch, 'hud.score: uses %{score}, which the Text does not declare')
    end

    it 'raises VariableMismatch for a declared name the translation never uses' do
      expect { described_class.new('hud.score', :score, :bonus).with(score: 1, bonus: 2) }
        .to raise_error(i18n::VariableMismatch, /never uses :bonus/)
    end

    it 'raises VariableMismatch for a plural whose Text lacks count' do
      expect { described_class.new('apples').to_s }.to raise_error(i18n::VariableMismatch, /pluralized.*:count/)
    end

    it 'shows the key under :key' do
      i18n.missing = :key
      expect(described_class.new('hud.score').to_s).to eq('hud.score')
    end

    it 'shows what a callable policy returns' do
      i18n.missing = ->(key, chain) { "[#{key} @ #{chain.first}]" }
      expect(described_class.new('hud.score').to_s).to eq('[hud.score @ en]')
    end
  end

  it 'answers a missing key by the policy' do
    expect { described_class.new('nowhere').to_s }.to raise_error(i18n::MissingKey)
  end

  describe '.literal' do
    it 'shows its string through to_s and with' do
      ada = described_class.literal('Ada')
      expect([ada.to_s, ada.with]).to eq(%w[Ada Ada])
    end

    it 'is a Text' do
      expect(described_class.literal('Ada')).to be_a(described_class)
    end

    it 'never consults I18n' do
      allow(i18n).to receive(:render)
      described_class.literal('Ada').to_s
      expect(i18n).not_to have_received(:render)
    end

    it 'shows the same string in every locale and after a reset' do
      ada = described_class.literal('Ada')
      i18n.locale = :de
      i18n.reset
      expect(ada.to_s).to eq('Ada')
    end

    it 'ignores a scope' do
      ada = described_class.literal('Ada')
      ada.scope = 'title_menu'
      expect([ada.to_s, ada.scope]).to eq(['Ada', nil])
    end

    it 'allocates nothing on a read' do
      ada = described_class.literal(+'Ada')
      expect { ada.to_s }.to allocate_nothing.over(200_000)
    end
  end

  describe '.computed' do
    it 'shows what the block builds from the keywords' do
      clock = described_class.computed(:minutes, :seconds) { |minutes:, seconds:| format('%d:%02d', minutes, seconds) }
      expect(clock.with(minutes: 1, seconds: 5)).to eq('1:05')
    end

    it 'runs the block once per change, not once per read' do
      calls = 0
      lives = described_class.computed(:lives) do |lives:|
        calls += 1
        "Lives: #{lives}"
      end
      [3, 3, 3, 2, 2].each { lives.with(lives: it) }
      expect(calls).to eq(2)
    end

    it 'runs the block again when the generation moves, so I18n.t inside follows the language' do
      score = described_class.computed(:score) { |score:| i18n.t('hud.score', score: score) }
      score.with(score: 7)
      i18n.locale = :de
      expect(score.with(score: 7)).to eq('Punkte: 7')
    end

    it 'reads a block with no names through to_s' do
      title = described_class.computed { i18n.t('title') }
      expect([title.to_s, title.with]).to eq(['Main Menu', 'Main Menu'])
    end

    it 'shares the generated with of a Text with the same names' do
      computed = described_class.computed(:score) { |score:| score.to_s }
      expect(computed.method(:with).owner).to be(described_class.new('hud.score', :score).method(:with).owner)
    end

    it 'raises ArgumentError naming a missing keyword' do
      expect { described_class.computed(:lives) { |lives:| lives.to_s }.with }.to raise_error(ArgumentError, /lives/)
    end

    it 'requires a block' do
      expect { described_class.computed(:lives) }.to raise_error(ArgumentError, /needs a block/)
    end

    it 'allocates nothing on an unchanged read' do
      lives = described_class.computed(:lives) { |lives:| "Lives: #{lives}" }
      expect { lives.with(lives: 3) }.to allocate_nothing.over(200_000)
    end
  end
end
