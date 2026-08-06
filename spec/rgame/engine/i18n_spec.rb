# frozen_string_literal: true

RSpec.describe RGame::Engine::I18n do
  # Global module: reset around every example so locales/generation don't leak.
  after { described_class.reset }

  before do
    described_class.reset
    described_class.load(:en,
                         greeting: 'Hello', score: 'Score: %{n}', menu: { title: 'Main Menu' },
                         lives: { zero: 'No lives', one: '%{count} life', other: '%{count} lives' })
    described_class.load(:de, greeting: 'Hallo', menu: { title: 'Hauptmenü' })
    described_class.default = :en
  end

  describe 't' do
    it 'looks up a key in the current locale' do
      described_class.locale = :de
      expect(described_class.t(:greeting)).to eq('Hallo')
    end

    it 'resolves dotted keys against nested tables' do
      described_class.locale = :de
      expect(described_class.t('menu.title')).to eq('Hauptmenü')
    end

    it 'interpolates %{vars}' do
      expect(described_class.t(:score, n: 42)).to eq('Score: 42')
    end

    it 'falls back to the default locale when the current one lacks the key' do
      described_class.locale = :de # :de has no :score
      expect(described_class.t(:score, n: 7)).to eq('Score: 7')
    end

    it 'returns the key itself when no locale has it' do
      expect(described_class.t(:missing)).to eq('missing')
    end
  end

  describe 'pluralisation (count:)' do
    it 'picks the one form and exposes count to interpolation' do
      expect(described_class.t(:lives, count: 1)).to eq('1 life')
    end

    it 'picks the other form for counts above one' do
      expect(described_class.t(:lives, count: 3)).to eq('3 lives')
    end

    it 'uses an explicit zero form when present' do
      expect(described_class.t(:lives, count: 0)).to eq('No lives')
    end

    it 'pluralizes through the fallback locale' do
      described_class.locale = :de # :de has no :lives → falls back to :en's forms
      expect(described_class.t(:lives, count: 2)).to eq('2 lives')
    end
  end

  describe 'locale switching' do
    it 'bumps the generation only when the locale actually changes' do
      start = described_class.generation
      described_class.locale = :de
      expect(described_class.generation).to eq(start + 1)
      described_class.locale = :de # same locale → no bump
      expect(described_class.generation).to eq(start + 1)
    end

    it 'reports the available locales' do
      expect(described_class.available).to contain_exactly(:en, :de)
    end
  end
end
