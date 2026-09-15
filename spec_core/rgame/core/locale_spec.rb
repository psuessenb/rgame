# frozen_string_literal: true

RSpec.describe 'RGame::Core.preferred_locales' do # rubocop:disable RSpec/DescribeClass -- a module function, not a class
  it 'returns an Array of non-empty Strings' do
    locales = RGame::Core.preferred_locales
    RSpec.configuration.reporter.message("RGame::Core.preferred_locales on this machine: #{locales.inspect}")

    expect(locales).to be_an(Array).and(all(be_a(String).and(satisfy { !it.empty? })))
  end

  it 'needs no app' do
    expect(LocaleEnvironment.run("require 'rgame/core'; puts RGame::Core.preferred_locales.class.name.to_json"))
      .to eq('Array')
  end

  describe 'on a platform whose SDL reads LANG', :needs_lang_locale do
    it 'joins a language and its country with a hyphen' do
      expect(LocaleEnvironment.preferred_under('de_AT.UTF-8')).to eq(['de-AT'])
    end

    it 'returns a language without a country alone' do
      expect(LocaleEnvironment.preferred_under('de')).to eq(['de'])
    end

    it 'returns nothing under LANG=C' do
      expect(LocaleEnvironment.preferred_under('C')).to eq([])
    end

    it 'lists LANGUAGE after LANG, most preferred first' do
      locales = LocaleEnvironment.run(
        "require 'rgame/core'; require 'json'; puts JSON.generate(RGame::Core.preferred_locales)",
        env: { 'LANG' => 'de_AT.UTF-8', 'LANGUAGE' => 'fr_CA:en' }
      )

      expect(locales).to eq(%w[de-AT fr-CA en])
    end
  end
end
