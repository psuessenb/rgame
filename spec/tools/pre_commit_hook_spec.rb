# frozen_string_literal: true

RSpec.describe 'The pre-commit hook' do # rubocop:disable RSpec/DescribeClass -- it describes a repository file, not a class
  let(:root) { File.expand_path('../..', __dir__) }
  let(:hook) { File.join(root, '.githooks', 'pre-commit') }

  it 'runs the comment stripper on the index' do
    expect(File.read(hook)).to include('tools/strip_comments.rb --staged')
  end

  # Windows has no executable bit, so File.executable? is false there for any
  # extensionless file. The mode git records is what a clone on Linux or macOS
  # checks out, and git reports it identically on every platform.
  it 'is committed as executable' do
    skip 'not a git checkout' unless File.exist?(File.join(root, '.git'))

    mode = IO.popen(['git', '-C', root, 'ls-files', '--stage', '--', '.githooks/pre-commit'], &:read).split.first
    expect(mode).to eq('100755')
  end

  it 'is wired up in this checkout' do
    skip 'not a git checkout' unless File.exist?(File.join(root, '.git'))

    hooks_path = IO.popen(['git', '-C', root, 'config', '--get', 'core.hooksPath'], &:read).strip
    expect(hooks_path).to eq('.githooks'),
                          'run `rake` once in this checkout, or `git config core.hooksPath .githooks`'
  end
end
