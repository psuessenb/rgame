# frozen_string_literal: true

module RuboCop
  module Cop
    module Game
      # Shared definition of the per-frame "hot path" for the allocation-guard cops.
      #
      # The hot path is the set of methods that run every frame: the engine's six
      # lifecycle hooks, plus any method an author opts into with a `# hot-path` magic
      # comment on the line directly above its `def`. The opt-in covers per-frame
      # *helpers* the lifecycle methods call, where an allocation is just as costly but
      # the method name alone can't reveal it.
      module HotPath
        METHODS = %i[update control draw on_update on_draw on_control].freeze

        # True for a `def` that runs per frame: a lifecycle method by name, or one tagged
        # `# hot-path` on the line directly above it.
        def hot_path_def?(node)
          return false unless node.def_type?

          METHODS.include?(node.method_name) || hot_path_tagged?(node)
        end

        private

        def hot_path_tagged?(node)
          line_above = node.source_range.first_line - 1
          processed_source.comments.any? do |comment|
            comment.location.line == line_above && comment.text.match?(/\A#\s*hot-path\b/)
          end
        end
      end
    end
  end
end
