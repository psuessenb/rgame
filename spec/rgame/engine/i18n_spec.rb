# frozen_string_literal: true

RSpec.describe RGame::Engine::I18n do
  before { described_class.reset }
  after { described_class.reset }

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
  end
end
