# frozen_string_literal: true

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
      # `RGame::Util` is fine anywhere: those are shareable value types with no
      # OS handle behind them, which is exactly why they live in Util.
      #
      # @example
      #   # bad — names the class
      #   def draw(renderer)
      #     RGame::Core::Renderer.new
      #   end
      #
      #   # bad — a require pulls SDL into the process
      #   require 'rgame/core'
      #
      #   # good — duck-typed against whatever it is handed
      #   def draw(renderer)
      #     renderer.sprite(:hero, 0, 0, @abs_x, @abs_y)
      #   end
      #
      #   # good — Util types may be held as attributes
      #   @grid = RGame::Util::Tensor.new(w, h, d)
      class NoCoreInEngineLayer < RuboCop::Cop::Base
        MSG = 'The engine layer must not name `RGame::Core`; receive the object ' \
              'and call it by method name instead.'
        MSG_REQUIRE = 'The engine layer must not require `%{path}` — that loads ' \
                      'SDL/OpenGL and breaks headless specs.'

        RESTRICTED_REQUIRE = %r{\Argame/core(/|\z)|\Argame/core_ext\z}

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

        # Any constant path ending in RGame::Core, or nested under it.
        def on_const(node)
          return unless core_const?(node)
          # Only report the outermost const of a path like RGame::Core::Renderer,
          # so one reference is one offense.
          return if node.parent&.const_type? && core_const?(node.parent)

          add_offense(node)
        end

        private

        def core_const?(node)
          return false unless node.const_type?

          names = []
          current = node
          while current&.const_type?
            names.unshift(current.short_name.to_s)
            current = current.namespace
          end
          names.first(2) == %w[RGame Core]
        end
      end
    end
  end
end
