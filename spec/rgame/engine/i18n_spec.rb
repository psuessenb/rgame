# frozen_string_literal: true

RSpec.describe RGame::Engine::I18n do
  describe '.load' do
    it 'reads Rails format, where one document may hold two locales' do
      described_class.load(<<~YAML)
        en:
          menu:
            title: Main Menu
        de:
          menu:
            title: Hauptmenü
      YAML
      described_class.locale = :de
      expect(described_class.t('menu.title')).to eq('Hauptmenü')
    end

    it 'deep-merges a second load into a locale rather than replacing it' do
      described_class.load("en:\n  menu:\n    title: Main Menu\n")
      described_class.load("en:\n  menu:\n    quit: Quit\n")
      expect([described_class.t('menu.title'), described_class.t('menu.quit')]).to eq(['Main Menu', 'Quit'])
    end

    it 'lets a later load overwrite a key an earlier one set' do
      described_class.load("en:\n  play: Play\n")
      described_class.load("en:\n  play: Start\n")
      expect(described_class.t('play')).to eq('Start')
    end

    it 'follows YAML aliases' do
      described_class.load("en:\n  a: &word Play\n  b: *word\n")
      expect(described_class.t('b')).to eq('Play')
    end

    it 'refuses an object tag rather than instantiating it' do
      expect { described_class.load("en:\n  a: !ruby/object:Object {}\n") }.to raise_error(Psych::DisallowedClass)
    end

    it 'names the source file in a syntax error' do
      expect { described_class.load("en: [\n", source: 'locales/en.yml') }
        .to raise_error(Psych::SyntaxError, %r{locales/en\.yml})
    end

    it 'refuses an unquoted on/off key, which YAML reads as a boolean' do
      expect { described_class.load("en:\n  on: On\n", source: 'en.yml') }
        .to raise_error(ArgumentError, /en\.yml: en has the key true.*quote it/)
    end

    it 'refuses a boolean value, naming its key' do
      expect { described_class.load("en:\n  toggle:\n    state: off\n") }
        .to raise_error(ArgumentError, /en\.toggle\.state is false/)
    end

    it 'refuses a document that is not a Hash of locales' do
      expect { described_class.load('- en') }.to raise_error(ArgumentError, /expected a Hash of locales/)
    end

    it 'reads a number as its text' do
      described_class.load("en:\n  players: 4\n")
      expect(described_class.t('players')).to eq('4')
    end
  end

  describe '.load_hash' do
    it 'treats Symbol and String keys alike' do
      described_class.load_hash(en: { menu: { 'title' => 'Main Menu' } })
      expect(described_class.t('menu.title')).to eq('Main Menu')
    end

    it 'returns the module, so loads chain' do
      expect(described_class.load_hash(en: { a: 'A' })).to be(described_class)
    end
  end

  describe '.available' do
    it 'lists the locales that have a table' do
      described_class.load_hash(en: { a: 'A' }, de: { a: 'A' })
      expect(described_class.available).to eq(%i[en de])
    end
  end

  describe '.t' do
    before do
      described_class.load_hash(en: { greeting: 'Hello, %{name}', menu: { title: 'Main Menu', play: 'Play' } })
    end

    it 'resolves a dotted key' do
      expect(described_class.t('menu.title')).to eq('Main Menu')
    end

    it 'accepts a Symbol key' do
      expect(described_class.t(:'menu.title')).to eq('Main Menu')
    end

    it 'prefixes the key with scope:' do
      expect(described_class.t('play', scope: 'menu')).to eq('Play')
    end

    it 'interpolates keyword variables' do
      expect(described_class.t('greeting', name: 'Ada')).to eq('Hello, Ada')
    end

    it 'raises ArgumentError naming a variable the template needs and was not given' do
      expect { described_class.t('greeting') }.to raise_error(ArgumentError, /greeting needs %\{name\}/)
    end

    it 'returns the same frozen String every time for a key without variables' do
      expect(described_class.t('menu.title')).to be(described_class.t('menu.title')).and be_frozen
    end
  end

  describe '.normalize' do
    it 'reads de_AT, de-at and :"de-AT" as one locale' do
      expect(['de_AT', 'de-at', :'de-AT'].map { |id| described_class.normalize(id) }).to eq([:'de-AT'] * 3)
    end

    it 'lowercases a bare language' do
      expect(described_class.normalize('DE')).to eq(:de)
    end

    it 'capitalizes a script and uppercases a region' do
      expect(described_class.normalize('zh_hant_tw')).to eq(:'zh-Hant-TW')
    end

    it 'refuses an empty identifier' do
      expect { described_class.normalize('') }.to raise_error(ArgumentError, /not a locale/)
    end
  end

  describe '.chain' do
    it 'is the locale, each shorter prefix, then the default' do
      described_class.locale = 'de_AT'
      expect(described_class.chain).to eq(%i[de-AT de en])
    end

    it 'lists the default once when the locale is the default' do
      expect(described_class.chain).to eq(%i[en])
    end

    it 'follows a change of default' do
      described_class.locale = :de
      described_class.default = :fr
      expect(described_class.chain).to eq(%i[de fr])
    end
  end

  describe 'resolving through the chain' do
    before do
      described_class.load_hash(en: { play: 'Play', quit: 'Quit' }, de: { play: 'Spielen' }, 'de-AT': { quit: 'Aus' })
    end

    it 'takes a key from the locale itself first' do
      described_class.locale = :'de-AT'
      expect(described_class.t('quit')).to eq('Aus')
    end

    it 'takes a key the locale lacks from its language' do
      described_class.locale = :'de-AT'
      expect(described_class.t('play')).to eq('Spielen')
    end

    it 'falls back to the default last' do
      described_class.locale = :de
      expect(described_class.t('quit')).to eq('Quit')
    end

    it 'resolves a locale with no table of its own through its chain' do
      described_class.locale = :'de-CH'
      expect(described_class.t('play')).to eq('Spielen')
    end

    it 'files a table under its normalized locale' do
      described_class.load_hash(pt_br: { play: 'Jogar' })
      expect(described_class.available).to include(:'pt-BR')
    end
  end

  describe '.choose' do
    before { described_class.load_hash(en: { a: 'A' }, de: { a: 'A' }) }

    it 'returns the first preferred locale whose own chain meets a table, unshortened' do
      expect(described_class.choose(%w[fr-CA de-AT en])).to eq(:'de-AT')
    end

    it 'does not count the default as a match for a language without a table' do
      expect(described_class.choose(%w[fr-CA de])).to eq(:de)
    end

    it 'returns the default when nothing matches' do
      described_class.default = :de
      expect(described_class.choose(%w[fr ja])).to eq(:de)
    end

    it 'returns the default for an empty list' do
      expect(described_class.choose([])).to eq(:en)
    end
  end

  describe '.generation' do
    it 'moves on load' do
      expect { described_class.load_hash(en: { a: 'A' }) }.to(change(described_class, :generation))
    end

    it 'moves on a switch to a different locale' do
      expect { described_class.locale = :de }.to(change(described_class, :generation))
    end

    it 'does not move on a switch to the locale already current' do
      described_class.locale = :de
      expect { described_class.locale = :de }.not_to(change(described_class, :generation))
    end

    it 'moves on a change of default' do
      expect { described_class.default = :de }.to(change(described_class, :generation))
    end

    it 'moves on plural_rule, which changes the form a count reads' do
      expect { described_class.plural_rule(:en) { :other } }.to(change(described_class, :generation))
    end

    it 'moves on reset rather than starting again' do
      described_class.load_hash(en: { a: 'A' })
      expect { described_class.reset }.to(change(described_class, :generation).by_at_least(1))
    end
  end

  describe '.reset' do
    it 'forgets every table and restores :en' do
      described_class.load_hash(de: { a: 'A' })
      described_class.locale = :de
      described_class.reset
      expect([described_class.available, described_class.locale, described_class.default]).to eq([[], :en, :en])
    end

    it 'restores the :key missing policy' do
      described_class.reset
      expect(described_class.missing).to eq(:key)
    end
  end

  describe 'a missing key' do
    before do
      described_class.load_hash(en: { play: 'Play' })
      described_class.locale = :'de-AT'
    end

    it 'raises MissingKey under the policy this suite sets for every example' do
      expect { described_class.t('quit') }.to raise_error(described_class::MissingKey)
    end

    describe 'missing = :key' do
      before { described_class.missing = :key }

      it 'shows the key' do
        expect(described_class.t('quit')).to eq('quit')
      end

      it 'shows the scoped key' do
        expect(described_class.t('quit', scope: 'menu')).to eq('menu.quit')
      end
    end

    describe 'missing = :raise' do
      it 'names the key and the chain it looked in' do
        expect { described_class.t('quit') }
          .to raise_error(described_class::MissingKey, 'no translation for "quit" in de-AT, de, en')
      end

      it 'carries the key and the chain' do
        expect { described_class.t('quit') }.to raise_error(described_class::MissingKey) { |error|
          expect([error.key, error.chain]).to eq(['quit', %i[de-AT de en]])
        }
      end
    end

    describe 'missing = a callable' do
      it 'shows what it returns for the key and chain' do
        described_class.missing = ->(key, chain) { "[#{key} @ #{chain.first}]" }
        expect(described_class.t('quit')).to eq('[quit @ de-AT]')
      end
    end

    it 'refuses a policy that is none of those' do
      expect { described_class.missing = :silent }.to raise_error(ArgumentError, /:key, :raise or a callable/)
    end

    it 'is not missing when only the default has it' do
      expect(described_class.t('play')).to eq('Play')
    end
  end

  describe '.missing_keys' do
    before do
      described_class.load_hash(
        en: { play: 'Play', quit: 'Quit', menu: { title: 'Menu', back: 'Back' },
              apples: { one: 'apple', other: 'apples' } },
        de: { play: 'Spielen', menu: { title: 'Menü' }, apples: { one: 'Apfel', other: 'Äpfel' } },
        'de-AT': { quit: 'Aus' }
      )
    end

    it 'lists the keys the default has and the locale lacks, in the default table order' do
      expect(described_class.missing_keys(:de)).to eq(%w[quit menu.back])
    end

    it 'does not list a key the locale gets from a parent' do
      expect(described_class.missing_keys('de_AT')).to eq(%w[menu.back])
    end

    it 'lists every key for a locale with no table in its chain' do
      expect(described_class.missing_keys(:fr)).to eq(%w[play quit menu.title menu.back apples])
    end

    it 'lists nothing for the default itself' do
      expect(described_class.missing_keys(:en)).to be_empty
    end
  end
end
