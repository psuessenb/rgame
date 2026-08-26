# frozen_string_literal: true

# The claim `rgame new` makes, run rather than described.
#
# cli_spec.rb checks what the generator writes. This checks that what it wrote
# *works*: the generated spec suite passes and the generated RuboCop config is
# green. Those are the two things a newcomer will try in their first minute, and
# they are exactly the kind of promise that rots silently — a cop enabled in a
# new RuboCop release, an RSpec default that changes, a template edited without
# running it. Nothing else in the suite would notice.
#
# ## Why the subprocesses borrow this repo's bundle
#
# A generated project's Gemfile names `rgame` from RubyGems, so resolving it
# would mean a network install of a *published* version — slow, and testing the
# wrong code. Instead both commands run against this checkout: BUNDLE_GEMFILE
# points at the repo's Gemfile (which already locks rspec, rubocop,
# rubocop-performance and rubocop-rspec) and RUBYOPT puts this lib/ on the load
# path, so `require 'rgame'` finds the working tree.
#
# The generated project is written to a temporary directory outside the repo,
# which is what keeps RuboCop from walking up into the engine's own config: it
# stops at the first .rubocop.yml it finds, and that is the generated one.

require 'rgame/cli'
require 'open3'
require 'tmpdir'

RSpec.describe 'a generated project' do # rubocop:disable RSpec/DescribeClass -- the subject is the project on disk, not a class
  let(:tmp) { Dir.mktmpdir('rgame-generated') }
  let(:repo) { File.expand_path('../../..', __dir__) }

  # Generated per example. That is a few milliseconds against the second each
  # subprocess below costs, so there is nothing to win by sharing one.
  let(:project) do
    RGame::CLI::NewProject.new('tictactoe', out: StringIO.new, root: tmp).generate
    File.join(tmp, 'tictactoe')
  end

  after { FileUtils.remove_entry(tmp) }

  def run_in_project(*command)
    env = {
      'BUNDLE_GEMFILE' => File.join(repo, 'Gemfile'),
      'RUBYOPT' => "-I#{File.join(repo, 'lib')}"
    }

    Open3.capture2e(env, 'bundle', 'exec', *command, chdir: project)
  end

  it 'passes its own spec suite' do
    output, status = run_in_project('rspec')

    expect(status).to be_success, "rspec failed:\n#{output}"
    expect(output).to include('0 failures')
  end

  it 'is clean under its own RuboCop configuration' do
    # --no-server so the run cannot pick up a server started elsewhere with a
    # different config.
    output, status = run_in_project('rubocop', '--no-server')

    expect(status).to be_success, "rubocop failed:\n#{output}"
    expect(output).to include('no offenses detected')
  end
end
