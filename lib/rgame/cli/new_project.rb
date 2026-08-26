# frozen_string_literal: true

require 'erb'
require 'fileutils'
require 'rubygems/version'

require_relative '../version'

module RGame
  module CLI
    # Writes a new game project: `rgame new tictactoe`.
    #
    # The layout it produces is the project's own architecture in miniature, and
    # the generated comments say so at each file:
    #
    #   - `game.rb` is the only file that requires `rgame/game`, so it is the
    #     only one that loads SDL and OpenGL. It is the game's glue class, the
    #     local counterpart of RGame::Game.
    #   - `nodes/` requires `rgame` and names only RGame::Engine, so every node
    #     runs with no window.
    #   - `spec/` therefore loads `rgame` too, and the whole suite runs headless.
    #
    # Getting a newcomer to that shape by default is most of the point: it is
    # the arrangement that keeps game logic spec-able, and it is not one anybody
    # would arrive at by guessing.
    class NewProject
      # Anything the caller did wrong: a bad name, a directory in the way.
      # RGame::CLI turns it into a message and a non-zero status.
      class Error < StandardError; end

      TEMPLATE_ROOT = File.expand_path('templates', __dir__)

      # Templates whose generated name starts with a dot, keyed by the name they
      # are stored under.
      #
      # They cannot simply *be* dotfiles in the template directory: rgame.gemspec
      # derives `spec.files` with `Dir.glob('lib/**/*')`, which does not match a
      # leading dot, so a template named `.gitignore` would be missing from the
      # gem and nothing local would notice. spec/packaging_spec.rb has a guard
      # that fails if one ever appears here.
      DOTFILES = {
        'gitignore' => '.gitignore',
        'rspec' => '.rspec',
        'rubocop.yml' => '.rubocop.yml'
      }.freeze

      # A directory the generated project needs but has no file to put in it.
      # Git cannot track an empty directory, hence the `.keep`.
      KEEP_DIRS = ['assets'].freeze

      NAME_PATTERN = /\A[a-z0-9][a-z0-9_-]*\z/i

      def initialize(name, out: $stdout, root: Dir.pwd)
        @name = name
        @out = out
        @target = File.expand_path(name, root)

        validate_name!
      end

      def generate
        check_target!

        templates.each { |source, destination| write(destination, render(source)) }
        KEEP_DIRS.each { |dir| write(File.join(dir, '.keep'), '') }

        report_next_steps
      end

      # `tic_tac_toe` and `tic-tac-toe` both give `TicTacToe`. Used for the
      # window caption and, with `Game` appended, for the game class.
      def caption = @name.split(/[_-]+/).map(&:capitalize).join

      def game_class = "#{caption}Game"

      def app_name = @name

      # "~> 0.2" for a 0.2.0 generator, so a project tracks whatever version
      # created it rather than a number frozen into a template.
      def rgame_requirement = Gem::Version.new(RGame::VERSION).approximate_recommendation

      private

      # Derived from the template tree rather than listed, so adding a template
      # file is the whole of adding it to a generated project. Returns pairs of
      # [source path relative to TEMPLATE_ROOT, destination relative to the
      # project root].
      def templates
        Dir.glob('**/*.tt', base: TEMPLATE_ROOT).sort.map do |source|
          [source, destination_for(source)]
        end
      end

      def destination_for(source)
        dir = File.dirname(source)
        base = File.basename(source, '.tt')
        base = DOTFILES.fetch(base, base)

        dir == '.' ? base : File.join(dir, base)
      end

      # ERB evaluates against this method's binding, which is why the values a
      # template names — `app_name`, `game_class`, `caption`,
      # `rgame_requirement` — are ordinary public methods of this class.
      def render(source)
        # `trim_mode: '-'` so a template can write `<%- ... -%>` and not leave a
        # blank line behind it.
        erb = ERB.new(File.read(File.join(TEMPLATE_ROOT, source)), trim_mode: '-')
        erb.filename = source
        erb.result(binding)
      end

      def write(destination, content)
        path = File.join(@target, destination)

        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)

        @out.puts("      create  #{File.join(@name, destination)}")
      end

      def validate_name!
        return if @name.is_a?(String) && @name.match?(NAME_PATTERN)

        raise Error, "#{@name.inspect} is not a valid project name — use letters, digits, " \
                     'underscores and dashes, starting with a letter or a digit'
      end

      def check_target!
        return unless File.exist?(@target)
        raise Error, "#{@name} exists and is not a directory" unless File.directory?(@target)
        return if (Dir.children(@target) - ['.', '..']).empty?

        raise Error, "#{@name} already exists and is not empty"
      end

      def report_next_steps
        @out.puts(<<~NEXT)

          Created #{@name}. Next:

            cd #{@name}
            bundle install
            bundle exec rspec     # the game logic, headless — no window needed
            ruby main.rb          # the game itself
        NEXT
      end
    end
  end
end
