# frozen_string_literal: true

require_relative 'layer_boundary'

module RuboCop
  module Cop
    module Game
      # The engine layer must never name `RGame::Core`.
      #
      # `RGame::Engine` holds the game concepts — scene tree, signals, sprites,
      # tile maps — and its whole value is that it can be specified with no
      # window, no GPU and no clock. It reaches the platform only through
      # objects handed to it: a node's `draw` receives a `renderer` and calls
      # methods on it by name, never storing it and never asking its class.
      #
      # Engine specs enforce this at runtime by simply never loading
      # `rgame/core`, so a stray reference raises `NameError`. That only catches
      # code a test run actually executes, though — this cop covers the
      # branches it doesn't reach.
      #
      # A game has the same line: its nodes and specs run headless, and only its
      # glue class loads the window. So `require 'rgame/game'` is refused too,
      # since it loads everything `rgame/core` does.
      #
      # The short spelling `Core::Image` is flagged only inside `module RGame`,
      # the one place it resolves to `RGame::Core`. Anywhere else it names the
      # project's own `Core`.
      #
      # `RGame::Util` is fine anywhere: those are shareable value types with no
      # OS handle behind them, which is exactly why they live in Util.
      #
      # @example
      #   # bad — names the class
      #   def draw(renderer)
      #     RGame::Core::Renderer.new
      #   end
      #
      #   # bad — the same thing, resolved through the enclosing RGame
      #   module RGame
      #     Core::Image.new(app, path)
      #   end
      #
      #   # bad — a require pulls SDL into the process
      #   require 'rgame/core'
      #
      #   # good — duck-typed against whatever it is handed
      #   def draw(renderer, _view)
      #     renderer.sprite(:hero, 0, 0, 0, 0)
      #   end
      #
      #   # good — Util types may be held as attributes
      #   @grid = RGame::Util::Tensor.new(w, h, d)
      class NoCoreInEngineLayer < RuboCop::Cop::Base
        include LayerBoundary

        MSG = 'Headless code must not name `RGame::Core`; receive the object ' \
              'and call it by method name instead.'
        MSG_REQUIRE = 'Headless code must not require `%{path}` — that loads ' \
                      'SDL/OpenGL and breaks headless specs.'

        QUALIFIED = [%w[RGame Core]].freeze
        WITHIN_RGAME = [%w[RGame Core], %w[Core]].freeze
        RESTRICTED_REQUIRE = %r{\Argame/(core|game)(/|\z)|\Argame/core_ext\z}

        # `require "rgame/core"` and friends.
        # @!method core_require(node)
        def_node_matcher :core_require, <<~PATTERN
          (send nil? {:require :require_relative} (str $_))
        PATTERN

        def on_send(node)
          core_require(node) do |path|
            next unless RESTRICTED_REQUIRE.match?(path.to_s.delete_prefix('./'))

            add_offense(node, message: format(MSG_REQUIRE, path: path))
          end
        end

        # Any constant path under RGame::Core. The walk, and reporting one
        # offence per written reference rather than one per path segment, is in
        # LayerBoundary — shared with this cop's mirror.
        def on_const(node)
          add_offense(node) if opens_namespace?(node, prefixes_for(node))
        end

        private

        def prefixes_for(node)
          within_rgame?(node) ? WITHIN_RGAME : QUALIFIED
        end

        def within_rgame?(node)
          node.each_ancestor(:module, :class).any? do |scope|
            const_path(scope.identifier).first == 'RGame'
          end
        end
      end
    end
  end
end
