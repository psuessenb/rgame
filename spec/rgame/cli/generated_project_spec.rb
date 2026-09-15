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
    # No --no-server here, deliberately. RuboCop keys its server on the project
    # directory, and this one is a fresh temporary directory, so there is never
    # a server to pick up — and on Windows `--no-server` is not a no-op but an
    # error ("RuboCop server is not supported by this Ruby"), because the flag
    # is rejected wholesale wherever the server is unsupported.
    output, status = run_in_project('rubocop')

    expect(status).to be_success, "rubocop failed:\n#{output}"
    expect(output).to include('no offenses detected')
  end

  # The Game/ cops reach a generated project through the gem, not through this
  # repository's config. So this runs each against a node that breaks it, from
  # the generated .rubocop.yml alone.
  it "runs rgame's own cops on its nodes" do
    File.write(File.join(project, 'nodes', 'score.rb'), <<~RUBY)
      # frozen_string_literal: true

      require 'rgame/game'

      class Score < RGame::Engine::Node2D
        def on_draw(renderer, _view)
          renderer.text("Score: \#{@points}", x, 0)
          @size = [4, 4]
          RGame::Core::Image
        end
      end
    RUBY

    output, status = run_in_project('rubocop', 'nodes/score.rb')

    expect(status).not_to be_success
    expect(output).to include('Game/NoInterpolationInHotPath', 'Game/NoLiteralText', 'Game/DrawInLocalSpace',
                              'Game/NoNeedlessAllocation', 'Game/NoCoreInEngineLayer')
    expect(output).to include('must not require rgame/game')
  end

  # The translation setup the generator promises: specs read the tables in
  # assets/locales/, fail on a key a language lacks, and fail on a key no table
  # has. Each example edits the generated project and runs its suite.
  describe 'its translation tables' do
    def write(relative, content)
      File.write(File.join(project, relative), content)
    end

    def run_suite = run_in_project('rspec')

    # The pair to the example below: a second language is not a failure in
    # itself, so the failure below is about the key rather than about de.yml.
    it 'passes with a second locale that has every key' do
      write('assets/locales/de.yml', "de:\n  root:\n    greeting: Hallo!\n")

      output, status = run_suite

      expect(status).to be_success, "rspec failed:\n#{output}"
    end

    it 'fails, naming the locale and the key, when a second locale lacks a key' do
      write('assets/locales/de.yml', "de:\n  root:\n    farewell: Tschüss!\n")

      output, status = run_suite

      expect(status).not_to be_success
      expect(output).to include('de: ["root.greeting"]')
    end

    it 'fails, naming the key, when a key the game draws is in no table' do
      write('assets/locales/en.yml', "en:\n  root:\n    farewell: Bye!\n")

      output, status = run_suite

      expect(status).not_to be_success
      expect(output).to include('MissingKey').and include('root.greeting')
    end

    it 'gives every example the project tables in the default locale, whatever the one before did' do
      write('spec/leak_spec.rb', <<~RUBY)
        # frozen_string_literal: true

        RSpec.describe RGame::Engine::I18n do
          it 'loads a table and switches the locale' do
            described_class.load_hash(de: { root: { greeting: 'Hallo!' } })
            described_class.locale = :de

            expect(described_class.t('root.greeting')).to eq('Hallo!')
          end

          it 'starts from the tables on disk, in English' do
            expect([described_class.locale, described_class.available]).to eq([:en, [:en]])
          end
        end
      RUBY

      output, status = run_in_project('rspec', '--order', 'defined', 'spec/leak_spec.rb')

      expect(status).to be_success, "rspec failed:\n#{output}"
      expect(output).to include('2 examples, 0 failures')
    end
  end
end
