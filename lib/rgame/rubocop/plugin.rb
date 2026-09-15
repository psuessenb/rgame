# frozen_string_literal: true

require_relative '../version'

module RuboCop
  module Game
    # Hands RuboCop the `Game/` cops' default configuration, in `default.yml`
    # beside this file.
    #
    # A project loads it by path and class, from `.rubocop.yml`:
    #
    #   plugins:
    #     - rgame/rubocop:
    #         plugin_class_name: RuboCop::Game::Plugin
    #
    # The bare gem name would make RuboCop `require 'rgame'` and load the whole
    # engine, compiled extension included, just to lint. `lint_roller` comes
    # with every RuboCop that supports plugins, so the gem needs no dependency.
    #
    # It lives under `RuboCop` rather than `RGame`, like every other RuboCop
    # extension, because RuboCop's process is the only one that loads it.
    class Plugin < LintRoller::Plugin
      def about
        LintRoller::About.new(
          name: 'rgame',
          version: RGame::VERSION,
          homepage: 'https://github.com/psuessenb/rgame',
          description: 'Per-frame allocation, draw-space, layering and translation rules for rgame games.'
        )
      end

      def supported?(context)
        context.engine == :rubocop
      end

      def rules(_context)
        LintRoller::Rules.new(
          type: :path,
          config_format: :rubocop,
          value: File.join(__dir__, 'default.yml')
        )
      end
    end
  end
end
