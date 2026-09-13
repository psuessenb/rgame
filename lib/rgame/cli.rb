# frozen_string_literal: true

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
