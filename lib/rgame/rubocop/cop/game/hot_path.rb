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
      #
      # A cop's `EveryMethodIn` option names files where every method counts, tagged or
      # not. That is for a library a game calls into: rgame cannot know which of its
      # methods a game calls every frame, and `TileMap#frame_tile` runs for every
      # animated tile in view without being a lifecycle hook or tagged as one.
      module HotPath
        METHODS = %i[update control draw draw_children rgame_draw_content
                     _update _draw _control].freeze

        # True for a `def` that runs per frame: a lifecycle method by name, one tagged
        # `# hot-path` on the line directly above it, or any method in a file the
        # cop's `EveryMethodIn` names.
        def hot_path_def?(node)
          return false unless node&.type?(:def, :defs)
          return true if every_method_hot?
          return false unless node.def_type?

          METHODS.include?(node.method_name) || hot_path_tagged?(node)
        end

        # True in a file the cop's `EveryMethodIn` option names.
        def every_method_hot? = file_name_matches_any?(processed_source.file_path, 'EveryMethodIn', false)

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
