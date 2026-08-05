# frozen_string_literal: true

require_relative 'layer_boundary'

module RuboCop
  module Cop
    module Game
      # `RGame::Core` must never name `RGame::Engine`. The mirror of
      # `NoCoreInEngineLayer`, and the more easily broken of the two.
      #
      # Engine is built *on top of* Core, so Core should not know it exists.
      # Core owns windows, textures and sound devices; Engine owns scene
      # concepts. A Core class that reaches upward makes the lower layer
      # unusable without the higher one, and inverts a dependency that the whole
      # three-layer split exists to keep pointing one way.
      #
      # Where Core genuinely needs something Engine has — a tile map's grid, say
      # — it takes the object and calls it by method name, exactly as the engine
      # layer does with a renderer. The one place allowed to name both sides is
      # the glue class directly under `RGame`, which is what a glue class is
      # for.
      #
      # Unlike its mirror, nothing catches this at runtime: loading Engine into
      # a Core spec would work fine and the inversion would go unnoticed until
      # someone tried to use Core on its own. This cop is the only guard.
      #
      # Both spellings are flagged — `RGame::Engine` and the bare `Engine` the
      # layer still has before it is ported — because the interim is exactly
      # when the mistake gets made.
      #
      # @example
      #   # bad — Core parsing a file format Engine owns
      #   def self.load(app, path)
      #     map = Engine::TileMap.parse(File.read(path))
      #     new(app, map)
      #   end
      #
      #   # bad — a require, in either spelling
      #   require 'rgame/engine'
      #
      #   # good — hand Core the parsed thing and call it by name
      #   def initialize(map, tiles)
      #     @columns = map.width
      #   end
      class NoEngineInCoreLayer < RuboCop::Cop::Base
        include LayerBoundary

        MSG = 'RGame::Core must not name `%{name}`; take the object and call it ' \
              'by method name, and let the glue layer wire the two together.'
        MSG_REQUIRE = 'RGame::Core must not require `%{path}` — Engine is built on ' \
                      'top of Core, not the other way round.'

        PREFIXES = [%w[RGame Engine], %w[Engine]].freeze
        RESTRICTED_REQUIRE = %r{(\A|/)engine(/|\z)}

        # @!method engine_require(node)
        def_node_matcher :engine_require, <<~PATTERN
          (send nil? {:require :require_relative} (str $_))
        PATTERN

        def on_send(node)
          engine_require(node) do |path|
            next unless RESTRICTED_REQUIRE.match?(path.to_s.delete_prefix('./'))

            add_offense(node, message: format(MSG_REQUIRE, path: path))
          end
        end

        def on_const(node)
          return unless opens_namespace?(node, PREFIXES)

          add_offense(node, message: format(MSG, name: matched_prefix(node).join('::')))
        end

        private

        # The namespace that made this an offence — `Engine` or `RGame::Engine`
        # — rather than the whole path, so the message names the boundary that
        # was crossed and not the particular class that crossed it.
        def matched_prefix(node)
          path = const_path(node)
          PREFIXES.find { |prefix| path.first(prefix.length) == prefix }
        end
      end
    end
  end
end
