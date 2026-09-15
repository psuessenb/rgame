# frozen_string_literal: true

RSpec.describe RGame::Engine::I18n::PluralRules do
  # count => category, per language: CLDR's integer rules, checked at the
  # boundaries where a language's forms change.
  expected = {
    %i[en de nl sv da nb fi] => { 0 => :other, 1 => :one, 2 => :other, 21 => :other, 1_000_000 => :other },
    %i[it es] => { 0 => :other, 1 => :one, 2 => :other, 1_000_000 => :many, 2_000_000 => :many, 1_000_001 => :other },
    %i[fr pt] => { 0 => :one, 1 => :one, 2 => :other, 1_000_000 => :many },
    %i[ru uk] => { 0 => :many, 1 => :one, 2 => :few, 3 => :few, 4 => :few, 5 => :many, 11 => :many,
                   12 => :many, 14 => :many, 21 => :one, 22 => :few, 111 => :many, 101 => :one },
    %i[pl] => { 0 => :many, 1 => :one, 2 => :few, 5 => :many, 12 => :many, 21 => :many, 22 => :few, 25 => :many },
    %i[cs] => { 0 => :other, 1 => :one, 2 => :few, 3 => :few, 4 => :few, 5 => :other, 22 => :other },
    %i[ja zh ko] => { 0 => :other, 1 => :other, 2 => :other, 100 => :other },
    %i[ar] => { 0 => :zero, 1 => :one, 2 => :two, 3 => :few, 10 => :few, 11 => :many, 99 => :many,
                100 => :other, 102 => :other, 103 => :few, 111 => :many }
  }

  expected.each do |languages, table|
    languages.each do |language|
      describe language.inspect do
        table.each do |count, category|
          it "puts #{count} in #{category}" do
            expect(described_class::BUILT_IN.fetch(language).call(count)).to eq(category)
          end
        end
      end
    end
  end

  it 'reads a negative count by its size' do
    expect(described_class::BUILT_IN.fetch(:ru).call(-3)).to eq(:few)
  end

  it 'puts a count that is not an Integer in other, even one equal to 1' do
    expect(described_class::BUILT_IN.fetch(:en).call(1.0)).to eq(:other)
  end

  it 'answers only with CLDR categories' do
    counts = (0..200).to_a + [1_000_000]
    answers = described_class::BUILT_IN.values.flat_map { |rule| counts.map { |count| rule.call(count) } }
    expect(answers.uniq - RGame::Engine::I18n::Plural::CATEGORIES).to be_empty
  end

  describe 'through I18n.t' do
    let(:i18n) { RGame::Engine::I18n }

    it 'picks the form by the current language' do
      i18n.load_hash(ru: { apples: { one: '%{count} яблоко', few: '%{count} яблока', many: '%{count} яблок',
                                     other: '%{count} яблока' } })
      i18n.locale = :ru
      forms = [1, 3, 5, 21].map { |count| i18n.t('apples', count: count) }
      expect(forms).to eq(['1 яблоко', '3 яблока', '5 яблок', '21 яблоко'])
    end

    it 'lets an explicit zero: win for 0 in a language with no zero category' do
      i18n.load_hash(en: { apples: { zero: 'No apples', one: 'One apple', other: '%{count} apples' } })
      expect(i18n.t('apples', count: 0)).to eq('No apples')
    end

    it 'reads other for a category the table leaves out' do
      i18n.load_hash(pl: { apples: { one: 'jabłko', other: '%{count} jabłek' } })
      i18n.locale = :pl
      expect(i18n.t('apples', count: 22)).to eq('22 jabłek')
    end

    it 'pluralizes a key reached through a fallback by the fallback language, not the current one' do
      i18n.load_hash(en: { apples: { one: 'one', few: 'few', many: 'many', other: 'other' } }, pl: {})
      i18n.locale = :pl
      expect([i18n.t('apples', count: 22), i18n.t('apples', count: 25)]).to eq(%w[other other])
    end

    it 'uses the rule of the regional table that supplied the text before its language' do
      i18n.plural_rule('pt-PT') { |count| count == 1 ? :one : :other }
      i18n.load_hash('pt-PT': { apples: { one: 'uma maçã', other: '%{count} maçãs' } })
      i18n.locale = 'pt-PT'
      expect(i18n.t('apples', count: 0)).to eq('0 maçãs')
    end

    it 'counts like English in a language with no rule' do
      i18n.load_hash(eo: { apples: { one: 'unu pomo', other: '%{count} pomoj' } })
      i18n.locale = :eo
      expect([i18n.t('apples', count: 1), i18n.t('apples', count: 2)]).to eq(['unu pomo', '2 pomoj'])
    end

    it 'lets plural_rule replace a built-in rule until reset' do
      i18n.plural_rule(:en) { :other }
      i18n.load_hash(en: { apples: { one: 'one', other: 'other' } })
      expect(i18n.t('apples', count: 1)).to eq('other')
      i18n.reset
      i18n.load_hash(en: { apples: { one: 'one', other: 'other' } })
      expect(i18n.t('apples', count: 1)).to eq('one')
    end

    it 'applies a rule added after a key of its language was already counted' do
      i18n.load_hash(en: { apples: { one: 'one', other: 'other' } })
      i18n.t('apples', count: 1)
      i18n.plural_rule(:en) { :other }
      expect(i18n.t('apples', count: 1)).to eq('other')
    end

    it 'refuses plural_rule without a block' do
      expect { i18n.plural_rule(:en) }.to raise_error(ArgumentError, /needs a block/)
    end

    it 'raises ArgumentError for a pluralized key without count:' do
      i18n.load_hash(en: { apples: { one: 'one', other: 'other' } })
      expect { i18n.t('apples') }.to raise_error(ArgumentError, /apples is pluralized and needs count:/)
    end

    it 'reads a Hash of plural categories without other: as nesting' do
      i18n.load_hash(en: { numbers: { one: 'One', two: 'Two' } })
      expect(i18n.t('numbers.two')).to eq('Two')
    end

    it 'merges plural forms spread over two loads' do
      i18n.load_hash(en: { apples: { other: '%{count} apples' } })
      i18n.load_hash(en: { apples: { one: 'One apple' } })
      expect(i18n.t('apples', count: 1)).to eq('One apple')
    end
  end
end
