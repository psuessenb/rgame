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
    #   - `<name>.rb` defines the game's module, where `Engine` and `Util` stand
    #     for RGame::Engine and RGame::Util, and requires only `rgame`.
    #   - `nodes/` requires that file and names only RGame::Engine, so every node
    #     runs with no window.
    #   - `spec/` therefore loads `rgame` too, and the whole suite runs headless.
    #   - `assets/<name>.tiled-project` is the Tiled project `rake tiled` writes
    #     the placeable node classes into, and `spec/tiled_project_spec.rb`
    #     fails when it falls behind them. `tiled: false` leaves out both.
    #
    # Getting a newcomer to that shape by default is most of the point: it is
    # the arrangement that keeps game logic spec-able, and it is not one anybody
    # would arrive at by guessing.
    #
    # @api private
    class NewProject
      # Anything the caller did wrong: a bad name, a directory in the way.
      # RGame::CLI turns it into a message and a non-zero status.
      class Error < StandardError; end

      TEMPLATE_ROOT = File.expand_path('templates', __dir__)

      DOTFILES = {
        'gitignore' => '.gitignore',
        'rspec' => '.rspec',
        'ruby-version' => '.ruby-version',
        'rubocop.yml' => '.rubocop.yml'
      }.freeze

      # The prefix of a template written under the game's own name: the module
      # in `<name>.rb`, and the Tiled project in `assets/<name>.tiled-project`.
      MODULE_TEMPLATE = 'game_module'

      # The templates a project without maps leaves out.
      TILED = %w[assets/game_module.tiled-project.tt spec/tiled_project_spec.rb.tt].freeze

      NAME_PATTERN = /\A[a-z][a-z0-9_-]*\z/i

      # `tiled: false` writes no Tiled project and no spec for it, for a game
      # without maps. The Rakefile's `tiled` task stays, and creates the
      # project if it runs.
      def initialize(name, out: $stdout, root: Dir.pwd, tiled: true)
        @name = name
        @out = out
        @target = File.expand_path(name, root)
        @tiled = tiled

        validate_name!
      end

      def generate
        check_target!

        templates.each { |source, destination| write(destination, render(source)) }

        report_next_steps
      end

      # `tic_tac_toe` and `tic-tac-toe` both give `TicTacToe`. Used for the
      # window caption and for the game's module.
      def caption = @name.split(/[_-]+/).map(&:capitalize).join

      def game_module = caption

      # `tic_tac_toe` for `tic-tac-toe` too: the file, less its `.rb`, that
      # defines the game's module and that every other Ruby file of the project
      # requires first.
      def module_file = @name.downcase.tr('-', '_')

      def app_name = @name

      # "~> 0.2" for a 0.2.0 generator, so a project tracks whatever version
      # created it rather than a number frozen into a template.
      def rgame_requirement = Gem::Version.new(RGame::VERSION).approximate_recommendation

      # The Ruby running `rgame new`, written to .ruby-version and pointed at
      # from the Gemfile. Whichever Ruby generated the project is the one it was
      # known to work on, which is the only version this can honestly claim.
      #
      # The bare `4.0.5` form rather than mise's `ruby 4.0.5`: every version
      # manager reads it, and so does Bundler's `ruby file:`.
      def ruby_version = RUBY_VERSION

      # Whether the project gets a Tiled project and the spec that keeps it
      # current.
      def tiled? = @tiled

      private

      def templates
        sources = Dir.glob('**/*.tt', base: TEMPLATE_ROOT).sort
        sources -= TILED unless @tiled
        sources.map { |source| [source, destination_for(source)] }
      end

      def destination_for(source)
        dir = File.dirname(source)
        base = File.basename(source, '.tt')
        base = if base.start_with?("#{MODULE_TEMPLATE}.") then base.sub(MODULE_TEMPLATE, module_file)
               else DOTFILES.fetch(base, base)
               end

        dir == '.' ? base : File.join(dir, base)
      end

      def render(source)
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
        unless @name.is_a?(String) && @name.match?(NAME_PATTERN)
          raise Error, "#{@name.inspect} is not a valid project name — use letters, digits, " \
                       'underscores and dashes, starting with a letter'
        end
        if Object.const_defined?(game_module)
          raise Error, "#{@name} would name the game's module #{game_module}, which Ruby already defines " \
                       '— choose another name'
        end
        return unless templates.count { |_source, destination| destination == "#{module_file}.rb" } > 1

        raise Error, "#{@name} would write the game's module to #{module_file}.rb, which the project uses " \
                     'for something else — choose another name'
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
