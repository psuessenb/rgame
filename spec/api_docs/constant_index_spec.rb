# frozen_string_literal: true

require_relative '../support/api_docs'

# The index the references check resolves prose against. A module reachable by
# two paths, as `Util::Color` is also `Core::Renderer::Color`, must answer to
# both, whichever the walk meets first.
RSpec.describe 'ApiDocs.constant_index' do # rubocop:disable RSpec/DescribeClass -- a module function of the docs checks
  let(:index) do
    root = stub_const('IndexRoot', Module.new)
    first = root.const_set(:First, Module.new)
    second = root.const_set(:Second, Module.new)
    second.const_set(:VALUE, 1)
    first.const_set(:Alias, second)
    ApiDocs.constant_index(root)
  end

  it 'indexes a module under its own name when an alias of it is met first' do
    expect(index).to include('IndexRoot::Second' => IndexRoot::Second, 'IndexRoot::First::Alias' => IndexRoot::Second)
  end

  it 'indexes what the module holds under its own name' do
    expect(index).to include('IndexRoot::Second::VALUE' => 1)
  end
end
