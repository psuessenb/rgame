# frozen_string_literal: true

module RuboCop
  module Cop
    module Game
      # Shared by the two cops that police a layer boundary —
      # `NoCoreInEngineLayer` and `NoEngineInCoreLayer`. They are mirror images:
      # each forbids one namespace inside the other's files, and the only thing
      # that differs is which namespace and which message.
      #
      # Kept in one place because the interesting part is not the comparison but
      # the *walk*: `RGame::Core::Renderer` is three nested `const` nodes, and a
      # naive check reports the same reference three times. Getting that right
      # once beats getting it right twice and then fixing only one of them.
      module LayerBoundary
        private

        # The segments of a constant path, outermost first:
        # `RGame::Core::Renderer` => %w[RGame Core Renderer].
        def const_path(node)
          names = []
          current = node
          while current&.const_type?
            names.unshift(current.short_name.to_s)
            current = current.namespace
          end
          names
        end

        # Whether `node` is the *outermost* const of a path under one of
        # `prefixes` — so one written reference is one offence, however many
        # segments it has.
        #
        # Each prefix is an Array of leading segments, e.g. `%w[RGame Engine]`.
        def opens_namespace?(node, prefixes)
          return false unless under?(node, prefixes)

          !(node.parent&.const_type? && under?(node.parent, prefixes))
        end

        def under?(node, prefixes)
          return false unless node.const_type?

          path = const_path(node)
          prefixes.any? { |prefix| path.first(prefix.length) == prefix }
        end
      end
    end
  end
end
