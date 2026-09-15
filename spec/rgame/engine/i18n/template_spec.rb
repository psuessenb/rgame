# frozen_string_literal: true

RSpec.describe RGame::Engine::I18n::Template do
  def render(source, **vars) = described_class.compile(source).render(vars)

  describe '.compile' do
    it 'lists each variable once, in order of appearance' do
      expect(described_class.compile('%{b} %{a} %{b}').names).to eq(%i[b a])
    end

    it 'lists no variables for plain text' do
      expect(described_class.compile('Play').names).to be_empty
    end

    it 'does not take an escaped placeholder for a variable' do
      expect(described_class.compile('%%{name}').names).to be_empty
    end
  end

  describe '#render' do
    it 'interpolates %{name}' do
      expect(render('Hello, %{name}!', name: 'Ada')).to eq('Hello, Ada!')
    end

    it 'interpolates a variable at either end and one used twice' do
      expect(render('%{n} and %{n}', n: 3)).to eq('3 and 3')
    end

    it 'renders %%{name} as the literal %{name}' do
      expect(render('%%{name} is %{name}', name: 'Ada')).to eq('%{name} is Ada')
    end

    it 'leaves a lone % and an unclosed %{ as they are' do
      expect(render('100% %{done', done: 'x')).to eq('100% %{done')
    end

    it 'ignores variables the template does not use' do
      expect(render('Play', count: 3)).to eq('Play')
    end

    describe 'a template with no variables' do
      subject(:template) { described_class.compile('Main %%{menu}') }

      it 'returns the same frozen String every time' do
        first = template.render({})
        expect(template.render(name: 'x')).to be(first).and be_frozen
      end

      it 'applies escapes to that String' do
        expect(template.render({})).to eq('Main %{menu}')
      end
    end

    it 'raises KeyError for a variable it is not given' do
      expect { render('%{name}') }.to raise_error(KeyError)
    end
  end
end
