# frozen_string_literal: true

# The `rgame` command: `rgame new NAME`, `rgame version`, `rgame help`.
#
# ## What this file may require
#
# Only stdlib and `rgame/version`. **Never `rgame`, `rgame/core` or
# `rgame/game`** — `lib/rgame/version.rb` is documented as loading nothing
# compiled, and that property is what this file rests on.
#
# Two things follow from it. `rgame new` works before either extension has been
# built, which matters on a machine where SDL is missing or the install is
# half-finished. And the CLI can be specced from `spec/`, the headless suite,
# where `RGame::Core` is an undefined constant — so a require that crept in here
# would fail loudly there rather than quietly dragging SDL into a process that
# has no window to put it in.

require_relative 'version'
require_relative 'cli/new_project'

module RGame
  # Argument parsing and dispatch. The work is in RGame::CLI::NewProject.
  module CLI
    USAGE = <<~USAGE
      Usage: rgame COMMAND [ARGS]

      Commands:
        new NAME     Create a new game project in the directory NAME
        version      Print the rgame version
        help         Print this message

      Example:
        rgame new tictactoe
    USAGE

    # Runs one command and returns the process exit status, rather than calling
    # `exit` itself — which is what lets a spec drive it in-process and assert on
    # what it wrote and what it printed.
    #
    # `out` and `err` are injectable for the same reason.
    def self.run(argv, out: $stdout, err: $stderr)
      command, *rest = argv

      case command
      when 'new' then new_project(rest, out: out, err: err)
      when 'version', '--version', '-v' then version(out: out)
      when 'help', '--help', '-h', nil then help(out: out)
      else
        err.puts("rgame: unknown command #{command.inspect}", '', USAGE)
        1
      end
    end

    def self.help(out:)
      out.puts(USAGE)
      0
    end

    def self.version(out:)
      out.puts("rgame #{RGame::VERSION}")
      0
    end

    def self.new_project(args, out:, err:)
      name = args.first

      if name.nil? || name.start_with?('-')
        err.puts('rgame new: expected a project name', '', USAGE)
        return 1
      end

      NewProject.new(name, out: out).generate
      0
    rescue NewProject::Error => e
      err.puts("rgame new: #{e.message}")
      1
    end

    private_class_method :help, :version, :new_project
  end
end
