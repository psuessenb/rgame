# frozen_string_literal: true

# The `rgame` command, specced from the headless suite on purpose.
#
# `spec_helper` loads only `rgame`, so `RGame::Core` is an undefined constant in
# this process. That is the guard on the CLI's one structural rule — it may
# require nothing but stdlib and `rgame/version` — and it works without anyone
# asserting it: a require that reached for the graphics half would raise here
# rather than quietly dragging SDL into a command that only writes files.

require 'rgame/cli'
require 'ripper'
require 'tmpdir'

RSpec.describe RGame::CLI do
  subject(:status) { described_class.run(argv, out: out, err: err) }

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }

  describe 'version' do
    let(:argv) { ['version'] }

    it 'prints the version and succeeds' do
      expect(status).to eq(0)
      expect(out.string).to eq("rgame #{RGame::VERSION}\n")
    end
  end

  describe 'help' do
    it 'prints usage for an explicit request' do
      expect(described_class.run(['help'], out: out, err: err)).to eq(0)
      expect(out.string).to include('rgame new tictactoe')
    end

    it 'prints usage when called with no arguments' do
      expect(described_class.run([], out: out, err: err)).to eq(0)
      expect(out.string).to include('Usage: rgame COMMAND')
    end
  end

  describe 'an unknown command' do
    let(:argv) { ['sprint'] }

    it 'fails and says so on stderr' do
      expect(status).to eq(1)
      expect(err.string).to include('unknown command "sprint"')
      expect(out.string).to be_empty
    end
  end

  describe 'new' do
    # A generated project, built once per example group into a temporary
    # directory that goes away with it.
    def generate(name, out: StringIO.new)
      RGame::CLI::NewProject.new(name, out: out, root: tmp).generate
      File.join(tmp, name)
    end

    around do |example|
      Dir.mktmpdir('rgame-cli-spec') do |dir|
        @tmp = dir
        example.run
      end
    end

    attr_reader :tmp

    # A file's Ruby source with every comment removed. Lexed rather than
    # regexed, so a `#` inside a string stays where it is.
    def code_of(path)
      Ripper.lex(File.read(path))
            .reject { |(_position, type, _token)| type == :on_comment }
            .map { |(_position, _type, token)| token }
            .join
    end

    it 'reports the name it needs when given none' do
      expect(described_class.run(['new'], out: out, err: err)).to eq(1)
      expect(err.string).to include('expected a project name')
    end

    describe 'the project it writes' do
      let(:project) { generate('tictactoe') }

      # Relative paths of everything written, dotfiles included.
      let(:written) do
        Dir.glob('**/*', File::FNM_DOTMATCH, base: project)
           .reject { |path| File.basename(path).start_with?('.', '..') && File.directory?(File.join(project, path)) }
           .select { |path| File.file?(File.join(project, path)) }
           .sort
      end

      it 'writes exactly the files a project needs' do
        expect(written).to eq(
          %w[
            .gitignore
            .rspec
            .rubocop.yml
            .ruby-version
            Gemfile
            README.md
            Rakefile
            assets/.keep
            game.rb
            main.rb
            nodes/root.rb
            spec/nodes/root_spec.rb
            spec/spec_helper.rb
          ]
        )
      end

      it 'writes Ruby that parses' do
        # Cheap, and it is what catches a template broken by an ERB tag rather
        # than by anything a reader would see in the diff.
        ruby = written.grep(/\.rb\z/) + %w[Rakefile]

        ruby.each do |path|
          expect { RubyVM::AbstractSyntaxTree.parse_file(File.join(project, path)) }
            .not_to raise_error, "#{path} does not parse"
        end
      end

      it 'substitutes the project name into the game class and its caption' do
        game = File.read(File.join(project, 'game.rb'))

        expect(game).to include('class TictactoeGame < RGame::Game')
        expect(game).to include("caption: 'Tictactoe'")
      end

      it 'boots the class it generated' do
        expect(File.read(File.join(project, 'main.rb'))).to include('TictactoeGame.new.start')
      end

      it 'pins the engine to the version that generated it' do
        requirement = Gem::Version.new(RGame::VERSION).approximate_recommendation

        expect(File.read(File.join(project, 'Gemfile'))).to include("gem 'rgame', '#{requirement}'")
      end

      it 'records the Ruby that generated it, and points the Gemfile at it' do
        # Written from RUBY_VERSION rather than baked into the template: the
        # Ruby that ran the generator is the one the project is known to work
        # on, and it is the only one this can honestly claim.
        expect(File.read(File.join(project, '.ruby-version'))).to eq("#{RUBY_VERSION}\n")
        expect(File.read(File.join(project, 'Gemfile'))).to include("ruby file: '.ruby-version'")
      end

      # The layering the generated project is *for*: game.rb is the only file
      # allowed to load the graphics half, and nothing under nodes/ or spec/ may
      # name it. A template edit that broke this would still generate a project
      # that runs — and would quietly cost it its headless spec suite.
      it 'loads the graphics half in game.rb and nowhere else' do
        expect(File.read(File.join(project, 'game.rb'))).to include("require 'rgame/game'")

        written.grep(%r{\A(nodes|spec)/}).each do |path|
          # Code only. Those files *talk about* RGame::Core at length in their
          # comments — explaining the line they sit on the headless side of is
          # most of why they are worth generating — so a plain text search would
          # fail on the very thing being asserted.
          code = code_of(File.join(project, path))

          expect(code).not_to include("require 'rgame/game'"), "#{path} loads the graphics half"
          expect(code).not_to include('RGame::Core'), "#{path} names the graphics half"
        end
      end
    end

    describe 'multi-word names' do
      it 'camelizes underscores and dashes into one class name' do
        expect(File.read(File.join(generate('tic_tac_toe'), 'game.rb')))
          .to include('class TicTacToeGame < RGame::Game')

        expect(File.read(File.join(generate('tic-tac-toe'), 'game.rb')))
          .to include('class TicTacToeGame < RGame::Game')
      end
    end

    describe 'refusals' do
      it 'refuses a name that would not make a constant' do
        expect(described_class.run(['new', '2 player/game'], out: out, err: err)).to eq(1)
        expect(err.string).to include('not a valid project name')
      end

      it 'refuses a directory that already has something in it' do
        FileUtils.mkdir_p(File.join(tmp, 'taken'))
        File.write(File.join(tmp, 'taken', 'notes.txt'), 'mine')

        expect { generate('taken') }
          .to raise_error(RGame::CLI::NewProject::Error, /already exists and is not empty/)

        expect(Dir.children(File.join(tmp, 'taken'))).to eq(['notes.txt'])
      end

      it 'writes into a directory that exists but is empty' do
        FileUtils.mkdir_p(File.join(tmp, 'empty'))

        expect { generate('empty') }.not_to raise_error
        expect(File).to exist(File.join(tmp, 'empty', 'main.rb'))
      end
    end
  end
end
