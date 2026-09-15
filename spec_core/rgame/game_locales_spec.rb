# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# `RGame::Game` loading translation tables and choosing the player's language.
#
# `Game` is the glue, so it names Engine, and this suite may not load Engine —
# see core_spec_helper.rb. Every example therefore builds its game in a child
# process that requires `rgame/game`, the way docs/api references are checked,
# and reads back what `I18n` ended up holding. The child is also what lets an
# example set `LANG` without changing it for the rest of the suite.
RSpec.describe 'RGame::Game locales' do # rubocop:disable RSpec/DescribeClass -- the subject is Game, which this suite may not load
  let(:media) { Dir.mktmpdir }

  after { FileUtils.remove_entry(media) }

  def write(path, content)
    full = File.join(media, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
  end

  # Builds a Game over `media`, runs `body` against it as `game` and `i18n`, and
  # returns what `body` returns, through JSON. `start: true` runs the loop for
  # one tick first, to show the game starts.
  def with_game(body, env: {}, options: '', start: false)
    script = <<~RUBY
      require 'rgame/game'
      require 'json'

      class Root < RGame::Engine::Node2D
        def on_update(_dt) = context.close
      end

      i18n = RGame::Engine::I18n
      game = RGame::Game.new(root: Root.new, width: 64, height: 48, caption: 'locales spec',
                             media_root: #{media.inspect}#{options})
      #{'game.start' if start}
      result = (#{body})
      game.close
      puts JSON.generate(result)
    RUBY
    LocaleEnvironment.run(script, env: env)
  end

  def write_tables
    write('locales/en.yml', "en:\n  title: Main Menu\n")
    write('locales/de.yml', "de:\n  title: Hauptmenü\n")
  end

  it 'loads every .yml under media_root/locales' do
    write_tables
    write('locales/menus/fr.yml', "fr:\n  title: Menu principal\n")
    write('locales/README.txt', 'not a table')

    expect(with_game('i18n.available.map(&:to_s)')).to contain_exactly('en', 'de', 'fr')
  end

  it 'merges two files that define one locale in sorted path order' do
    write('locales/b.yml', "en:\n  title: From b\n")
    write('locales/a.yml', "en:\n  title: From a\n  only_a: Kept\n")

    expect(with_game("[i18n.t('title'), i18n.t('only_a')]")).to eq(['From b', 'Kept'])
  end

  it 'starts with no tables when media_root has no locales directory' do
    expect(with_game('[i18n.available, i18n.locale.to_s]', start: true)).to eq([[], 'en'])
  end

  it 'reads the directory locales: names, relative to media_root' do
    write('lang/en.yml', "en:\n  title: Main Menu\n")

    expect(with_game('i18n.available.map(&:to_s)', options: ", locales: 'lang'")).to eq(['en'])
  end

  it 'reads an absolute locales: directory as it stands' do
    Dir.mktmpdir do |elsewhere|
      File.write(File.join(elsewhere, 'en.yml'), "en:\n  title: Main Menu\n")

      expect(with_game('i18n.available.map(&:to_s)', options: ", locales: #{elsewhere.inspect}")).to eq(['en'])
    end
  end

  it 'reads a file that starts with a byte order mark' do
    write('locales/en.yml', "\uFEFFen:\n  title: Main Menu\n")

    expect(with_game("i18n.t('title')")).to eq('Main Menu')
  end

  it 'reads a table as UTF-8 whatever the process encoding is' do
    write('locales/de.yml', "de:\n  title: Hauptmenü\n")

    expect(with_game("i18n.load_hash(en: {}); i18n.locale = :de; i18n.t('title')",
                     env: { 'LANG' => 'C', 'LC_ALL' => 'C' })).to eq('Hauptmenü')
  end

  it 'loads through the asset manager cache, so a second load of a file parses nothing' do
    write_tables

    expect(with_game("g = i18n.generation; game.assets.locale('locales/en.yml'); i18n.generation == g")).to be(true)
  end

  it 'chooses the locale from what the OS prefers, on every platform' do
    write_tables

    expect(with_game('i18n.locale == i18n.choose(RGame::Core.preferred_locales)')).to be(true)
  end

  describe 'on a platform whose SDL reads LANG', :needs_lang_locale do
    before { write_tables }

    it 'chooses the player locale when a table covers it, unshortened' do
      expect(with_game('[i18n.locale.to_s, i18n.t("title")]', env: { 'LANG' => 'de_DE.UTF-8' }))
        .to eq(%w[de-DE Hauptmenü])
    end

    it 'chooses the default under LANG=C' do
      expect(with_game('i18n.locale.to_s', env: { 'LANG' => 'C' })).to eq('en')
    end

    it 'chooses the default when no table covers the player locale' do
      expect(with_game('i18n.locale.to_s', env: { 'LANG' => 'ja_JP.UTF-8' })).to eq('en')
    end
  end
end
