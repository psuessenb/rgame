# frozen_string_literal: true

RSpec.describe 'The pre-commit hook' do # rubocop:disable RSpec/DescribeClass -- it describes a repository file, not a class
  let(:root) { File.expand_path('../..', __dir__) }
  let(:hook) { File.join(root, '.githooks', 'pre-commit') }

  it 'is an executable that runs the comment stripper on the index' do
    expect(File.executable?(hook)).to be(true)
    expect(File.read(hook)).to include('tools/strip_comments.rb --staged')
  end

  it 'is wired up in this checkout' do
    skip 'not a git checkout' unless File.exist?(File.join(root, '.git'))

    hooks_path = IO.popen(['git', '-C', root, 'config', '--get', 'core.hooksPath'], &:read).strip
    expect(hooks_path).to eq('.githooks'),
                          'run `rake` once in this checkout, or `git config core.hooksPath .githooks`'
  end
end
